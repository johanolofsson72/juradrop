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
    /// Spec 003 — first drop zone owning its single-flight job slot
    /// and visible state machine.
    pub sammanfatta: Arc<crate::zones::sammanfatta::SammanfattaZone>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            sidecar: OllamaSidecar::new(),
            client: Arc::new(OllamaClient::new()),
            model_status: Arc::new(RwLock::new(ModelStatus::NotPresent)),
            progress: Arc::new(RwLock::new(None)),
            consent: Arc::new(RwLock::new(ConsentRecord::default())),
            error_override: Arc::new(RwLock::new(None)),
            sammanfatta: crate::zones::sammanfatta::DropZone::new(ZoneId::Sammanfatta),
        }
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
    tauri::async_runtime::spawn(async move {
        let app_inner = app.clone();
        let state_inner = state.clone();
        let mut last_pct: Option<u8> = None;
        let mut last_emit: Instant = Instant::now()
            .checked_sub(Duration::from_secs(1))
            .unwrap_or_else(Instant::now);

        let pull_future = state.client.pull(DEFAULT_MODEL, |event| match event {
            PullEvent::Progress { percent } => {
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

        // F1: enforce the spec.allium `model_pull_timeout_seconds: 300` ceiling.
        let timed =
            tokio::time::timeout(Duration::from_secs(MODEL_PULL_TIMEOUT_SECONDS), pull_future)
                .await;

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
/// Idempotent: silent no-op when `job_id` doesn't match the current
/// in-flight job (per `contracts/tauri-commands.md`).
#[tauri::command]
pub async fn cancel_summary(
    state: tauri::State<'_, AppState>,
    job_id: String,
) -> Result<(), String> {
    state.sammanfatta.cancel(&job_id);
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
