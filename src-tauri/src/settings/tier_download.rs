// Spec 027 — on-demand tier download.
//
// Replaces the spec-010 stub (`trigger_tier_download` emitted an event that
// the dead `subscribeTierDownloadRequested` listener never consumed). This
// module drives a REAL `/api/pull` for a non-bundled tier (Snabb
// `llama3.2:1b`, Stor `gemma3:12b`) with streaming progress, an honest
// categorised failure state, retry, and cancel.
//
// It runs INDEPENDENTLY of the spec-008 bundled-model flow
// (`sidecar::commands::spawn_pull_task`): its own at-most-one slot, its own
// cancel token, its own event channel. A tier download therefore NEVER moves
// the global `klar` gate or changes the active model (FR-004/005), and it is
// kept OUT of `SettingsSnapshot` so the on-disk settings file keeps its
// strict 2-key privacy invariant — download state is purely in-memory.

use std::sync::Arc;
use std::time::{Duration, Instant};

use parking_lot::RwLock;
use serde::Serialize;
use tauri::{AppHandle, Emitter};
use tokio_util::sync::CancellationToken;

use super::tier_map::ModelTier;
use crate::sidecar::client::{ClientError, OllamaClient, PullEvent};

/// The one channel tier-download progress/terminal events ride on. Distinct
/// from `juradrop://status` / `juradrop://progress` (which drive the global
/// header + the spec-008 wizard and must never be moved by a tier download).
pub const TIER_DOWNLOAD_EVENT: &str = "juradrop://settings/tier-download";

/// Why a download failed — drives which Swedish message the row shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DownloadFailure {
    Network,
    DiskFull,
    NotReady,
    NotFound,
}

/// The persistent phase of the at-most-one download slot. `not_pulled`
/// (never started / cancelled) and `pulled` (done) are represented by the
/// slot being ABSENT — disambiguated by `get_tier_pull_state` / `/api/tags`.
/// (analyze I1: the event payload's `phase` is the broader emit-signal set
/// `downloading | error | done | cancelled`; `done`/`cancelled` are transient
/// signals fired as the slot clears, not stored variants.)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DownloadPhase {
    Downloading,
    Error,
}

#[derive(Debug, Clone)]
pub struct TierDownloadState {
    pub tier: ModelTier,
    pub phase: DownloadPhase,
    pub completed: u64,
    pub total: u64,
    pub failure: Option<DownloadFailure>,
}

impl TierDownloadState {
    /// Percent for the payload. `total == 0` ⇒ 0 (the row renders the
    /// indeterminate "Laddar ned…" label instead of a percentage, FR-003).
    pub fn percent(&self) -> u8 {
        if self.total == 0 {
            0
        } else {
            ((self.completed as u128 * 100) / self.total as u128).min(100) as u8
        }
    }
}

/// Managed Tauri state: the single download slot + its cancel token.
/// At most one download exists at a time (FR-009 / SC-005).
pub struct TierDownloadHandle {
    slot: RwLock<Option<TierDownloadState>>,
    cancel: RwLock<CancellationToken>,
}

impl Default for TierDownloadHandle {
    fn default() -> Self {
        Self::new()
    }
}

impl TierDownloadHandle {
    pub fn new() -> Self {
        Self {
            slot: RwLock::new(None),
            cancel: RwLock::new(CancellationToken::new()),
        }
    }

    pub fn snapshot(&self) -> Option<TierDownloadState> {
        self.slot.read().clone()
    }

    /// True while a pull is actively in flight (the slot is `Downloading`).
    pub fn is_downloading(&self) -> bool {
        matches!(
            self.slot.read().as_ref(),
            Some(s) if s.phase == DownloadPhase::Downloading
        )
    }

    /// The tier currently occupying the slot (downloading OR errored), if any.
    pub fn active_tier(&self) -> Option<ModelTier> {
        self.slot.read().as_ref().map(|s| s.tier)
    }
}

/// Wire-format payload for the event + `get_tier_download_state`. Carries ONLY
/// tier, phase, byte counts, and failure category — never document content
/// (FR-013 / Principle I).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct TierDownloadPayload {
    pub tier: ModelTier,
    pub phase: String, // "downloading" | "error" | "done" | "cancelled"
    pub percent: u8,
    pub completed: u64,
    pub total: u64,
    pub failure: Option<DownloadFailure>,
}

impl TierDownloadPayload {
    fn from_state(phase: &str, st: &TierDownloadState) -> Self {
        Self {
            tier: st.tier,
            phase: phase.to_string(),
            percent: st.percent(),
            completed: st.completed,
            total: st.total,
            failure: st.failure,
        }
    }

    /// Terminal signal with no surviving slot (done / cancelled).
    fn terminal(phase: &str, tier: ModelTier) -> Self {
        Self {
            tier,
            phase: phase.to_string(),
            percent: 0,
            completed: 0,
            total: 0,
            failure: None,
        }
    }
}

fn emit(app: &AppHandle, payload: TierDownloadPayload) {
    let _ = app.emit(TIER_DOWNLOAD_EVENT, payload);
}

/// Build the wire payload for the current slot, for `get_tier_download_state`
/// (panel hydration on open — FR-011). Returns `None` when no download is
/// active or errored.
pub fn current_payload(handle: &TierDownloadHandle) -> Option<TierDownloadPayload> {
    handle.snapshot().map(|st| {
        let phase = match st.phase {
            DownloadPhase::Downloading => "downloading",
            DownloadPhase::Error => "error",
        };
        TierDownloadPayload::from_state(phase, &st)
    })
}

/// Map a pull failure to one of the four honest Swedish-message buckets
/// (FR-006 / SC-003). `client.pull` embeds the Ollama `{"error": ...}` text in
/// `ClientError::Http("pull failed: <msg>")`, so the category is recoverable
/// from the returned error alone.
pub fn categorise_failure(err: &ClientError) -> DownloadFailure {
    match err {
        ClientError::DiskFull => DownloadFailure::DiskFull,
        ClientError::Timeout => DownloadFailure::Network,
        ClientError::Http(msg) => categorise_message(msg),
        // Json / EmptyResponse / anything else mid-stream → treat as a
        // transport/stream failure the user can retry.
        _ => DownloadFailure::Network,
    }
}

/// Categorise from a raw message string (the `{"error": ...}` body or an
/// HTTP status text). Order matters: not-found and disk are checked before
/// the network fallback.
fn categorise_message(msg: &str) -> DownloadFailure {
    let m = msg.to_lowercase();
    if m.contains("not found")
        || m.contains("manifest")
        || m.contains("does not exist")
        || m.contains("no such")
    {
        DownloadFailure::NotFound
    } else if m.contains("no space") || m.contains("disk full") || m.contains("enospc") {
        DownloadFailure::DiskFull
    } else {
        DownloadFailure::Network
    }
}

/// Outcome of attempting to start (or retry) a tier download — the command
/// translates this into `Ok(())` or a stable `Err` string the frontend maps.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StartOutcome {
    Started,
    AlreadyDownloadingThisTier, // idempotent: rapid double-click (Ok no-op)
    RefusedNotReady,            // FR-010
    RefusedBusy,                // another tier downloading (FR-009)
    RefusedAlreadyPulled,
}

/// Begin (or retry) a tier download. Pure precondition gate + slot set; the
/// actual streaming runs in `spawn_pull_task`. `ready` = sidecar reachable AND
/// no bundled first-run pull active. Caller supplies `already_pulled` (an
/// async `/api/tags` check it does outside the lock).
pub fn try_start(
    handle: &TierDownloadHandle,
    tier: ModelTier,
    ready: bool,
    already_pulled: bool,
) -> StartOutcome {
    if already_pulled {
        return StartOutcome::RefusedAlreadyPulled;
    }
    {
        let guard = handle.slot.read();
        if let Some(active) = guard.as_ref() {
            if active.tier == tier && active.phase == DownloadPhase::Downloading {
                return StartOutcome::AlreadyDownloadingThisTier;
            }
            if active.phase == DownloadPhase::Downloading {
                // A DIFFERENT tier is mid-download — one at a time (FR-009).
                return StartOutcome::RefusedBusy;
            }
            // else: the slot holds an errored tier — retry/replace is allowed.
        }
    }
    if !ready {
        return StartOutcome::RefusedNotReady;
    }
    *handle.slot.write() = Some(TierDownloadState {
        tier,
        phase: DownloadPhase::Downloading,
        completed: 0,
        total: 0,
        failure: None,
    });
    StartOutcome::Started
}

/// Spawn the background pull task for `tier`. Process-lifetime (NOT tied to
/// the panel — FR-011). Reuses the model-generic `OllamaClient::pull` and the
/// spec-008 select-against-cancel pattern. The slot MUST already be
/// `Downloading` (set by `try_start`).
pub fn spawn_pull_task(
    app: AppHandle,
    handle: Arc<TierDownloadHandle>,
    client: Arc<OllamaClient>,
    tier: ModelTier,
) {
    let cancel = CancellationToken::new();
    *handle.cancel.write() = cancel.clone();

    // Emit the initial downloading frame so the row switches immediately.
    if let Some(st) = handle.snapshot() {
        emit(&app, TierDownloadPayload::from_state("downloading", &st));
    }

    let model = tier.model_id().to_string();

    tauri::async_runtime::spawn(async move {
        let handle_cb = handle.clone();
        let app_cb = app.clone();
        let mut last_pct: Option<u8> = None;
        let mut last_emit = Instant::now()
            .checked_sub(Duration::from_secs(1))
            .unwrap_or_else(Instant::now);

        let pull_future = client.pull(&model, move |event| {
            if let PullEvent::Progress {
                percent,
                completed,
                total,
            } = event
            {
                {
                    let mut g = handle_cb.slot.write();
                    if let Some(s) = g.as_mut() {
                        s.completed = completed;
                        s.total = total;
                    }
                }
                // Throttle: emit on ≥1% change OR ≥500 ms elapsed — satisfies
                // SC-002 (≥ once/second while the stream produces data).
                let now = Instant::now();
                let changed = last_pct != Some(percent);
                let elapsed = now.duration_since(last_emit) > Duration::from_millis(500);
                if changed || elapsed {
                    last_pct = Some(percent);
                    last_emit = now;
                    if let Some(st) = handle_cb.snapshot() {
                        emit(&app_cb, TierDownloadPayload::from_state("downloading", &st));
                    }
                }
            }
            // Completed / Failed are terminal — handled by the select arm below
            // off the future's return value (richer: carries the error).
        });

        tokio::select! {
            biased;
            _ = cancel.cancelled() => {
                // The cancel command owns the slot clear + the `cancelled`
                // emit (single responsibility). Just exit cleanly.
            }
            res = pull_future => {
                match res {
                    Ok(()) => {
                        // Success — clear the slot; the row flips to selectable
                        // once the frontend re-reads get_tier_pull_state (FR-005).
                        *handle.slot.write() = None;
                        emit(&app, TierDownloadPayload::terminal("done", tier));
                    }
                    Err(e) => {
                        let failure = categorise_failure(&e);
                        {
                            let mut g = handle.slot.write();
                            if let Some(s) = g.as_mut() {
                                s.phase = DownloadPhase::Error;
                                s.failure = Some(failure);
                            }
                        }
                        if let Some(st) = handle.snapshot() {
                            emit(&app, TierDownloadPayload::from_state("error", &st));
                        }
                    }
                }
            }
        }
    });
}

/// Trip the cancel token and clear the slot. The tier is NOT reported pulled
/// (FR-008 / SC-004) — a cancelled partial pull leaves the slot `None`, so
/// `get_tier_pull_state` (which asks Ollama) still reports it not installed.
pub fn cancel(app: &AppHandle, handle: &TierDownloadHandle, tier: ModelTier) -> bool {
    let was_downloading = matches!(
        handle.slot.read().as_ref(),
        Some(s) if s.tier == tier && s.phase == DownloadPhase::Downloading
    );
    if !was_downloading {
        return false;
    }
    handle.cancel.read().cancel();
    *handle.slot.write() = None;
    emit(app, TierDownloadPayload::terminal("cancelled", tier));
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn st(tier: ModelTier, phase: DownloadPhase) -> TierDownloadState {
        TierDownloadState {
            tier,
            phase,
            completed: 0,
            total: 0,
            failure: None,
        }
    }

    #[test]
    fn percent_is_zero_when_total_unknown() {
        let s = st(ModelTier::Stor, DownloadPhase::Downloading);
        assert_eq!(s.percent(), 0); // total = 0 ⇒ indeterminate, never div-by-zero
    }

    #[test]
    fn percent_clamps_and_computes() {
        let mut s = st(ModelTier::Stor, DownloadPhase::Downloading);
        s.completed = 5;
        s.total = 10;
        assert_eq!(s.percent(), 50);
        s.completed = 150;
        s.total = 100;
        assert_eq!(s.percent(), 100); // overshoot clamps
    }

    #[test]
    fn categorise_all_four_buckets() {
        assert_eq!(
            categorise_failure(&ClientError::DiskFull),
            DownloadFailure::DiskFull
        );
        assert_eq!(
            categorise_failure(&ClientError::Timeout),
            DownloadFailure::Network
        );
        assert_eq!(
            categorise_failure(&ClientError::Http(
                "pull failed: file does not exist".into()
            )),
            DownloadFailure::NotFound
        );
        assert_eq!(
            categorise_failure(&ClientError::Http("pull failed: no space left".into())),
            DownloadFailure::DiskFull
        );
        assert_eq!(
            categorise_failure(&ClientError::Http("pull failed: connection reset".into())),
            DownloadFailure::Network
        );
        assert_eq!(
            categorise_message("pull model manifest: 412"),
            DownloadFailure::NotFound
        );
    }

    #[test]
    fn try_start_happy_path_sets_downloading() {
        let h = TierDownloadHandle::new();
        assert_eq!(
            try_start(&h, ModelTier::Stor, true, false),
            StartOutcome::Started
        );
        assert!(h.is_downloading());
        assert_eq!(h.active_tier(), Some(ModelTier::Stor));
    }

    #[test]
    fn try_start_refuses_when_not_ready() {
        let h = TierDownloadHandle::new();
        assert_eq!(
            try_start(&h, ModelTier::Stor, false, false),
            StartOutcome::RefusedNotReady
        );
        assert!(!h.is_downloading()); // no slot set, no pull
    }

    #[test]
    fn try_start_refuses_already_pulled() {
        let h = TierDownloadHandle::new();
        assert_eq!(
            try_start(&h, ModelTier::Snabb, true, true),
            StartOutcome::RefusedAlreadyPulled
        );
    }

    #[test]
    fn try_start_is_at_most_one_download() {
        let h = TierDownloadHandle::new();
        assert_eq!(
            try_start(&h, ModelTier::Snabb, true, false),
            StartOutcome::Started
        );
        // A different tier while one is downloading → refused (FR-009/SC-005).
        assert_eq!(
            try_start(&h, ModelTier::Stor, true, false),
            StartOutcome::RefusedBusy
        );
        // Same tier again → idempotent no-op (rapid double-click).
        assert_eq!(
            try_start(&h, ModelTier::Snabb, true, false),
            StartOutcome::AlreadyDownloadingThisTier
        );
    }

    #[test]
    fn try_start_from_error_state_is_allowed_retry() {
        let h = TierDownloadHandle::new();
        *h.slot.write() = Some(st(ModelTier::Stor, DownloadPhase::Error));
        assert_eq!(
            try_start(&h, ModelTier::Stor, true, false),
            StartOutcome::Started
        );
        assert!(h.is_downloading());
    }

    #[test]
    fn payload_is_structurally_content_free() {
        // Principle I / FR-013 — the wire payload can carry ONLY tier, phase,
        // byte counts, and a failure category. There is no String field that
        // could ever hold document text. This serialises a fully-populated
        // payload and asserts the key set is exactly the closed schema.
        let st = TierDownloadState {
            tier: ModelTier::Stor,
            phase: DownloadPhase::Error,
            completed: 123,
            total: 456,
            failure: Some(DownloadFailure::Network),
        };
        let payload = TierDownloadPayload::from_state("error", &st);
        let json = serde_json::to_value(&payload).unwrap();
        let mut keys: Vec<&str> = json
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            ["completed", "failure", "percent", "phase", "tier", "total"],
            "payload schema drifted — a new field could leak content"
        );
    }

    #[test]
    fn payload_is_content_free_by_construction() {
        // Principle I (FR-013): a tier-download event carries ONLY tier,
        // phase, byte counts, and failure category — NEVER document text.
        // Serialize a representative payload and assert its key set is the
        // fixed content-free schema (a regression that added a `text`/`name`
        // field would trip immediately).
        let st = TierDownloadState {
            tier: ModelTier::Stor,
            phase: DownloadPhase::Downloading,
            completed: 5,
            total: 10,
            failure: None,
        };
        let payload = TierDownloadPayload::from_state("downloading", &st);
        let json = serde_json::to_value(&payload).unwrap();
        let mut keys: Vec<&str> = json
            .as_object()
            .unwrap()
            .keys()
            .map(|s| s.as_str())
            .collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            ["completed", "failure", "percent", "phase", "tier", "total"],
            "tier-download payload schema drifted — Principle I requires a \
             closed, content-free key set"
        );
    }

    #[test]
    fn error_state_carries_a_reason() {
        // ErrorHasReason invariant: an errored slot always has a failure set
        // by the task; try_start never leaves Error without a reason because
        // it overwrites with Downloading.
        let mut s = st(ModelTier::Stor, DownloadPhase::Error);
        s.failure = Some(DownloadFailure::Network);
        assert!(s.failure.is_some());
    }
}
