// Tauri command surface exposed to the WebView.
// Per spec 002 contracts/tauri-commands.md.

use std::sync::Arc;
use std::time::{Duration, Instant};

use chrono::Utc;
use parking_lot::RwLock;
use tauri::{AppHandle, Emitter, Manager};

use super::client::{OllamaClient, PullEvent};
use super::consent::{self, ConsentRecord};
use super::disk_space;
use super::log_safe::Redacted;
use super::manager::OllamaSidecar;
use super::status::{AppStatus, ConsentChoice, ModelStatus, SidecarStatus, UserVisibleStatus};
use crate::updater::state::{SharedUpdater, Updater};
use crate::zones::ZoneId;

/// Default model the PoC bundles. Spec 002 contracts/ollama-api-usage.md +
/// spec.allium `ModelArtifact::TagIsDefault` invariant.
pub(crate) const DEFAULT_MODEL: &str = "gemma3:4b";

/// GAP-8: extract the PullOnlyAfterConsent gate into a named, testable
/// function. The runtime path in `after_sidecar_ready` calls this rather
/// than inlining the condition — keeps the invariant easy to audit and
/// catches consent-gate regressions at unit-test time.
pub fn should_trigger_pull(model_present: bool, consent: ConsentChoice) -> bool {
    !model_present && consent == ConsentChoice::Fortsatt
}

/// Total pull-stream ceiling — F1 / spec.allium `model_pull_timeout_seconds: 300`.
/// Wraps the whole `OllamaClient::pull` call; on elapse, the in-flight HTTP
/// stream is dropped (cancellation cascades through reqwest's `bytes_stream`)
/// and the user-visible status flips to `fel_modellnedladdning_avbroten`.
const MODEL_PULL_TIMEOUT_SECONDS: u64 = 300;

/// Disk-space pre-check threshold — F2/F3, T047, spec.allium
/// `minimum_disk_free_gb: 4`. Pull is refused if `statvfs` reports fewer
/// available GiB at the app data root.
const MIN_FREE_GB_FOR_PULL: u64 = 4;

/// Returns true if the app data root has at least `MIN_FREE_GB_FOR_PULL`
/// GiB free. statvfs failures fail-open (returns true) — see disk_space.rs.
pub fn has_sufficient_disk_for_pull(app: &AppHandle) -> bool {
    let path = match app.path().app_data_dir() {
        Ok(p) => p,
        Err(_) => return true, // Path resolution failed → fail open.
    };
    let free_gb = disk_space::available_gb(&path);
    free_gb >= MIN_FREE_GB_FOR_PULL
}

/// Post-sidecar-ready bootstrap sequence — GAP-4 helper called by both the
/// initial setup task AND the retry listener after a successful re-spawn.
/// 1. Clear any stale `error_override` (GAP-1).
/// 2. List models and flip `ModelStatus` accordingly.
/// 3. If the model is missing and consent was previously granted, do the
///    disk-space pre-check (T047/F2/F3) and kick the pull task.
pub async fn after_sidecar_ready(app: AppHandle, state: AppState) {
    // GAP-1: sidecar is reachable; whatever stale error we showed before
    // (e.g. FelOvantat from a crash, FelKundeInteStarta from a failed
    // initial spawn) is no longer the truth. Reset.
    *state.error_override.write() = None;

    match state.client.list_tags().await {
        Ok(tags) => {
            let present = tags.iter().any(|t| t == DEFAULT_MODEL);
            *state.model_status.write() = if present {
                ModelStatus::Ready
            } else {
                ModelStatus::NotPresent
            };
            let _ = app.emit("juradrop://status", state.snapshot());

            if should_trigger_pull(present, state.consent.read().choice) {
                if !has_sufficient_disk_for_pull(&app) {
                    *state.error_override.write() = Some(UserVisibleStatus::FelDiskFull);
                    let _ = app.emit("juradrop://status", state.snapshot());
                } else {
                    *state.model_status.write() = ModelStatus::Downloading;
                    *state.progress.write() = Some(0);
                    let _ = app.emit("juradrop://status", state.snapshot());
                    spawn_pull_task(app, state);
                }
            }
        }
        Err(e) => {
            eprintln!("[juradrop] /api/tags failed: {e}");
        }
    }
}

#[derive(Clone)]
pub struct AppState {
    pub sidecar: Arc<OllamaSidecar>,
    pub client: Arc<OllamaClient>,
    pub model_status: Arc<RwLock<ModelStatus>>,
    pub progress: Arc<RwLock<Option<u8>>>,
    pub consent: Arc<RwLock<ConsentRecord>>,
    // T046: explicit error override. When Some, snapshot()'s derive result
    // is replaced with this — used for sidecar errors (PortBusy,
    // BundledBinaryMissing, …) whose distinction is otherwise lost in the
    // (sidecar, model, consent) tuple.
    pub error_override: Arc<RwLock<Option<UserVisibleStatus>>>,
    /// Spec 004 — six drop zones, one per ZoneId. Each owns its own
    /// single-flight job slot, visible state machine, and event channel
    /// (`juradrop://zone/<slug>`). Constructed at AppState::new and
    /// never mutated afterwards.
    pub zones: std::collections::HashMap<ZoneId, Arc<crate::zones::sammanfatta::DropZone>>,
    /// Spec 007 — shared updater state machine. Wrapped in
    /// `Arc<RwLock<Updater>>` so commands + the 4-hour tick task both
    /// mutate it under the same lock. See `crate::updater::state`.
    pub updater: SharedUpdater,
    /// Spec 008 — cancellation token for the in-flight model pull.
    /// Tripped by `cancel_model_pull` (FR-013). Reset to a fresh
    /// token at the start of every `spawn_pull_task` invocation so
    /// each pull has its own cancellation surface.
    pub pull_cancel: Arc<RwLock<tokio_util::sync::CancellationToken>>,
}

impl AppState {
    pub fn new() -> Self {
        use crate::zones::sammanfatta::DropZone;
        let mut zones = std::collections::HashMap::with_capacity(ZoneId::ALL.len());
        for id in ZoneId::ALL {
            zones.insert(id, DropZone::new(id));
        }
        Self {
            sidecar: OllamaSidecar::new(),
            client: Arc::new(OllamaClient::new()),
            model_status: Arc::new(RwLock::new(ModelStatus::NotPresent)),
            progress: Arc::new(RwLock::new(None)),
            consent: Arc::new(RwLock::new(ConsentRecord::default())),
            error_override: Arc::new(RwLock::new(None)),
            zones,
            updater: Arc::new(RwLock::new(Updater::new())),
            pull_cancel: Arc::new(RwLock::new(tokio_util::sync::CancellationToken::new())),
        }
    }

    /// Spec 004 — convenience accessor for a single zone by id.
    pub fn zone(&self, id: ZoneId) -> Option<&Arc<crate::zones::sammanfatta::DropZone>> {
        self.zones.get(&id)
    }

    pub fn snapshot(&self) -> AppStatus {
        let mut s = AppStatus::derive(
            self.sidecar.status(),
            *self.model_status.read(),
            *self.progress.read(),
            self.consent.read().choice,
        );
        if let Some(override_) = *self.error_override.read() {
            s.visible = override_;
        }
        s
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

fn emit_status(app: &AppHandle, snapshot: &AppStatus) {
    let _ = app.emit("juradrop://status", snapshot);
}

/// Spawn a background task that drives `/api/pull` for the bundled model and
/// reflects every step into shared state + Tauri events. Idempotent in the
/// sense that the caller is responsible for not starting a second pull while
/// one is in flight (current state: `ModelStatus::Downloading`).
///
/// Throttling per `contracts/tauri-events.md`: emit `juradrop://progress` only
/// when the percent has changed by ≥ 1 OR more than 500 ms have passed since
/// the last emit. Status events always fire on terminal transitions.
pub fn spawn_pull_task(app: AppHandle, state: AppState) {
    // Spec 008 — replace the cancellation token with a fresh one at
    // the start of every pull. Each pull owns its own cancel surface.
    let cancel = tokio_util::sync::CancellationToken::new();
    *state.pull_cancel.write() = cancel.clone();

    tauri::async_runtime::spawn(async move {
        let app_inner = app.clone();
        let state_inner = state.clone();
        let mut last_pct: Option<u8> = None;
        let mut last_emit: Instant = Instant::now()
            .checked_sub(Duration::from_secs(1))
            .unwrap_or_else(Instant::now);

        let pull_future = state.client.pull(DEFAULT_MODEL, |event| match event {
            PullEvent::Progress { percent, .. } => {
                *state_inner.progress.write() = Some(percent);
                let now = Instant::now();
                let changed = last_pct != Some(percent);
                let elapsed = now.duration_since(last_emit) > Duration::from_millis(500);
                if changed || elapsed {
                    last_pct = Some(percent);
                    last_emit = now;
                    #[derive(serde::Serialize, Clone)]
                    struct ProgressPayload {
                        percent: u8,
                    }
                    let _ = app_inner.emit("juradrop://progress", ProgressPayload { percent });
                }
            }
            PullEvent::Completed => {
                *state_inner.model_status.write() = ModelStatus::Ready;
                *state_inner.progress.write() = None;
                emit_status(&app_inner, &state_inner.snapshot());
            }
            PullEvent::Failed(_) => {
                *state_inner.model_status.write() = ModelStatus::DownloadFailed;
                *state_inner.progress.write() = None;
                emit_status(&app_inner, &state_inner.snapshot());
            }
        });

        // F1 + Spec 008 — race the pull against the timeout AND the
        // cancellation token. The cancel_model_pull command trips the
        // token; we then exit early WITHOUT touching model_status
        // because the command owns the status flip (single-responsibility).
        tokio::select! {
            biased;
            _ = cancel.cancelled() => {
                eprintln!("[juradrop] pull cancelled by user");
                // Status flip is owned by the cancel_model_pull command.
                // We just exit cleanly.
            }
            timed = tokio::time::timeout(Duration::from_secs(MODEL_PULL_TIMEOUT_SECONDS), pull_future) => {
                match timed {
                    Ok(Ok(())) => {} // Success — events already emitted by the callback.
                    Ok(Err(err)) => {
                        eprintln!("[juradrop] pull failed: {err}");
                        *state.model_status.write() = ModelStatus::DownloadFailed;
                        *state.progress.write() = None;
                        emit_status(&app, &state.snapshot());
                    }
                    Err(_elapsed) => {
                        eprintln!("[juradrop] pull timed out after {MODEL_PULL_TIMEOUT_SECONDS}s");
                        *state.model_status.write() = ModelStatus::DownloadFailed;
                        *state.progress.write() = None;
                        emit_status(&app, &state.snapshot());
                    }
                }
            }
        }
    });
}

#[tauri::command]
pub fn get_status(state: tauri::State<'_, AppState>) -> AppStatus {
    state.snapshot()
}

#[tauri::command]
pub async fn give_consent(app: AppHandle, state: tauri::State<'_, AppState>) -> Result<(), String> {
    // GAP-3: idempotency guard. Tauri `invoke()` is async; rapid double-click
    // on Fortsätt could fire two concurrent give_consent calls before the
    // modal closes. If a pull is already in flight, the second call is a
    // no-op.
    if *state.model_status.read() == ModelStatus::Downloading {
        return Ok(());
    }
    let mut consent = state.consent.write().clone();
    consent.choice = ConsentChoice::Fortsatt;
    consent.asked_at = Some(Utc::now());
    consent.schema_version = 1;
    consent::save(&app, &consent)
        .await
        .map_err(|e| e.to_string())?;
    *state.consent.write() = consent;

    // F2/F3 (T047): refuse the pull early if there isn't enough disk to
    // hold the model. The consent record was just persisted — the user did
    // opt in — but acting on it requires space.
    if !has_sufficient_disk_for_pull(&app) {
        *state.error_override.write() = Some(UserVisibleStatus::FelDiskFull);
        emit_status(&app, &state.snapshot());
        return Ok(());
    }

    *state.model_status.write() = ModelStatus::Downloading;
    *state.progress.write() = Some(0);
    let snapshot = state.snapshot();
    emit_status(&app, &snapshot);
    spawn_pull_task(app.clone(), state.inner().clone());
    Ok(())
}

#[tauri::command]
pub async fn cancel_consent(
    app: AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<(), String> {
    // GAP-3: idempotency — if consent is already decided (either choice),
    // a second click is a no-op rather than re-persisting and re-emitting.
    if state.consent.read().choice != ConsentChoice::NotAsked {
        return Ok(());
    }
    let mut consent = state.consent.write().clone();
    consent.choice = ConsentChoice::Avbryt;
    consent.asked_at = Some(Utc::now());
    consent.schema_version = 1;
    consent::save(&app, &consent)
        .await
        .map_err(|e| e.to_string())?;
    *state.consent.write() = consent;
    let snapshot = state.snapshot();
    emit_status(&app, &snapshot);
    Ok(())
}

/// Spec 008 / T016 — cancel the in-flight model pull.
///
/// Behaviour per `specs/008-first-run-wizard/contracts/tauri-commands.md`:
///   1. Acquires the model_status write-lock.
///   2. If model_status == Ready → silent no-op (the race was won by
///      completion; the wizard never "uncompletes" a finished download).
///   3. If model_status != Downloading → silent no-op (idempotent).
///   4. Else trips state.pull_cancel, flips status to NotPresent,
///      sets error_override = ModellSaknasAvbruten, emits status event.
/// Does NOT touch the consent record (see FR-013).
#[tauri::command]
pub async fn cancel_model_pull(
    app: AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<(), String> {
    // Two-phase to release the lock before the emit() call.
    let should_emit = {
        let mut status = state.model_status.write();
        match *status {
            ModelStatus::Ready => false,
            ModelStatus::Downloading => {
                state.pull_cancel.read().cancel();
                *status = ModelStatus::NotPresent;
                drop(status);
                *state.progress.write() = None;
                *state.error_override.write() = Some(UserVisibleStatus::ModellSaknasAvbruten);
                true
            }
            ModelStatus::NotPresent | ModelStatus::DownloadFailed => false,
        }
    };
    if should_emit {
        emit_status(&app, &state.snapshot());
    }
    Ok(())
}

#[tauri::command]
#[cfg(debug_assertions)]
pub async fn run_roundtrip_dev(state: tauri::State<'_, AppState>) -> Result<u64, String> {
    if state.sidecar.status() != SidecarStatus::Ready {
        return Err("sidecar not ready".into());
    }
    if *state.model_status.read() != ModelStatus::Ready {
        return Err("model not ready".into());
    }
    let prompt = Redacted::new(String::from("Säg hej."));
    let response = state
        .client
        .generate("gemma3:4b", prompt)
        .await
        .map_err(|e| e.to_string())?;
    Ok(response.len() as u64)
}

#[tauri::command]
#[cfg(not(debug_assertions))]
pub async fn run_roundtrip_dev(_state: tauri::State<'_, AppState>) -> Result<u64, String> {
    Err("not available in release build".into())
}

/// Spec 003 / T020 — cancel an in-flight Sammanfatta summarization.
/// Idempotent: silent no-op when `zone_id`/`job_id` doesn't match the
/// current in-flight job for that zone (per
/// `specs/004-all-six-zones/contracts/tauri-commands.md`).
#[tauri::command]
pub async fn cancel_summary(
    state: tauri::State<'_, AppState>,
    zone_id: ZoneId,
    job_id: String,
) -> Result<(), String> {
    if let Some(zone) = state.zones.get(&zone_id) {
        zone.cancel(&job_id);
    }
    Ok(())
}

/// Spec 004 / T021 — route a file drop to the right zone. The WebView
/// resolves the zone via `document.elementFromPoint(x, y)` after
/// receiving the `juradrop://file-dropped` event and invokes this
/// command. The path(s) flow through the Rust event payload + this
/// command — never through the HTML5 drag-drop blob (privacy
/// boundary).
#[tauri::command]
pub async fn dispatch_to_zone(
    app: AppHandle,
    state: tauri::State<'_, AppState>,
    settings: tauri::State<'_, crate::settings::snapshot::SettingsState>,
    zone_id: ZoneId,
    paths: Vec<std::path::PathBuf>,
) -> Result<(), String> {
    let zone = state
        .zones
        .get(&zone_id)
        .cloned()
        .ok_or_else(|| format!("unknown zone_id: {zone_id:?}"))?;
    let client = state.client.clone();
    let sidecar_ready = matches!(state.sidecar.status(), SidecarStatus::Ready);
    // Spec 010 / T011 — pin the active model_id at dispatch time so
    // in-flight runs are immune to tier switches (FR-010 +
    // InFlightRunsImmuneToTierSwitch invariant).
    let model_id = settings.active_model_id();
    tauri::async_runtime::spawn(async move {
        zone.handle_drop(app, client, sidecar_ready, model_id, paths)
            .await;
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // GAP-7: `TagIsDefault` invariant — DEFAULT_MODEL must equal the
    // spec.allium value `gemma3:4b`. Catches a typo'd constant at PR time.
    #[test]
    fn default_model_matches_spec_allium() {
        assert_eq!(
            DEFAULT_MODEL, "gemma3:4b",
            "DEFAULT_MODEL must equal spec.allium ModelArtifact.TagIsDefault"
        );
    }

    // GAP-8: `PullOnlyAfterConsent` invariant — every (model_present, consent)
    // combination produces the right pull-trigger decision. The pull MUST
    // fire iff the model is missing AND consent was explicitly granted.
    #[test]
    fn pull_only_triggers_when_model_missing_and_consent_fortsatt() {
        assert!(should_trigger_pull(false, ConsentChoice::Fortsatt));
    }

    #[test]
    fn pull_does_not_trigger_when_model_present() {
        // No matter the consent state, present means no pull.
        for c in [
            ConsentChoice::NotAsked,
            ConsentChoice::Fortsatt,
            ConsentChoice::Avbryt,
        ] {
            assert!(!should_trigger_pull(true, c), "{c:?} + present");
        }
    }

    #[test]
    fn pull_does_not_trigger_without_explicit_consent() {
        // The whole reason this gate exists — no outbound network call
        // before explicit user opt-in.
        assert!(!should_trigger_pull(false, ConsentChoice::NotAsked));
        assert!(!should_trigger_pull(false, ConsentChoice::Avbryt));
    }
}
