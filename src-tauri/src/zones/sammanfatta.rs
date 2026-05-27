// Spec 003 / T016 + T017 — Sammanfatta zone state machine + dispatch.
//
// Owns the single-flight `current_job` slot for the Sammanfatta zone,
// orchestrates the extract → model → write → open pipeline, and emits
// `juradrop://sammanfatta` snapshots on every visible state transition.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use parking_lot::RwLock;
use tauri::{AppHandle, Emitter, Runtime};
use uuid::Uuid;

use crate::sidecar::client::OllamaClient;
use crate::sidecar::log_safe::Redacted;
use crate::sidecar::status::SidecarStatus;

use super::docx_extract::extract_text;
use super::docx_write::build_summary_doc;
use super::errors::ZoneFailure;
use super::job::DropJob;
use super::prompts::SAMMANFATTA_SYSTEM_PROMPT;
use super::sidecar_path::{resolve_target, write_atomically};
use super::snapshot::{JobOutcome, ZoneSnapshot, ZoneState};

/// Auto-clear delays per FR-010 / FR-011.
const SUCCESS_AUTO_CLEAR: Duration = Duration::from_secs(2);
const ERROR_AUTO_CLEAR: Duration = Duration::from_secs(5);

#[derive(Default)]
struct ZoneInternalState {
    visible: ZoneState,
    current_job: Option<DropJob>,
}

impl Default for ZoneState {
    fn default() -> Self {
        ZoneState::Idle
    }
}

pub struct SammanfattaZone {
    state: Arc<RwLock<ZoneInternalState>>,
}

impl SammanfattaZone {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            state: Arc::new(RwLock::new(ZoneInternalState::default())),
        })
    }

    /// Validate a Drop and either start the dispatch pipeline or
    /// surface the matching `ZoneFailure` snapshot.
    pub async fn handle_drop<R: Runtime>(
        self: Arc<Self>,
        app: AppHandle<R>,
        client: Arc<OllamaClient>,
        sidecar_ready: bool,
        paths: Vec<PathBuf>,
    ) {
        // FR-012 — refuse drops on disabled zone (defense in depth).
        if !sidecar_ready {
            self.emit_failure(&app, ZoneFailure::ZoneDisabled);
            self.schedule_error_clear(&app);
            return;
        }

        // FR-014 — multi-file.
        if paths.len() >= 2 {
            self.emit_failure(&app, ZoneFailure::MultipleFiles);
            self.schedule_error_clear(&app);
            return;
        }

        let Some(source) = paths.into_iter().next() else {
            return; // empty drop — defensive, shouldn't happen
        };

        // FR-013 — non-.docx.
        if !source
            .extension()
            .and_then(|s| s.to_str())
            .map(|s| s.eq_ignore_ascii_case("docx"))
            .unwrap_or(false)
        {
            self.emit_failure(&app, ZoneFailure::InvalidFormat);
            self.schedule_error_clear(&app);
            return;
        }

        // FR-015 — single-flight. Reject the drop without disturbing the
        // in-flight job's UI state.
        {
            let st = self.state.read();
            if matches!(st.visible, ZoneState::Processing) {
                let _ = app.emit("juradrop://sammanfatta", self.snapshot_for_busy_toast());
                return;
            }
        }

        // All gates passed — start the job.
        let job = DropJob::new(source.clone());
        let job_id = job.id;
        let cancel_token = job.cancel_token.clone();

        {
            let mut st = self.state.write();
            st.visible = ZoneState::Processing;
            st.current_job = Some(job);
        }
        let _ = app.emit(
            "juradrop://sammanfatta",
            ZoneSnapshot {
                state: ZoneState::Processing,
                disabled: false,
                failure: None,
                job_id: Some(job_id.to_string()),
                progress_hint: Some("Sammanfattar…".into()),
            },
        );

        // Run the dispatch in a tokio task so the caller (the
        // DragDrop event handler) returns promptly.
        let zone = self.clone();
        let app_clone = app.clone();
        tauri::async_runtime::spawn(async move {
            zone.dispatch(app_clone, client, source, job_id, cancel_token)
                .await;
        });
    }

    /// The full pipeline. Runs in a background task so the
    /// DragDrop event handler doesn't block.
    async fn dispatch<R: Runtime>(
        self: Arc<Self>,
        app: AppHandle<R>,
        client: Arc<OllamaClient>,
        source: PathBuf,
        job_id: Uuid,
        cancel_token: tokio_util::sync::CancellationToken,
    ) {
        // Step 1: extract text. Runs synchronously because docx-rs
        // and our zip layer don't expose async APIs.
        let extracted = match tokio::task::spawn_blocking({
            let source = source.clone();
            move || extract_text(&source)
        })
        .await
        {
            Ok(Ok(e)) => e,
            Ok(Err(failure)) => {
                self.finalize_with_failure(&app, job_id, failure).await;
                return;
            }
            Err(_) => {
                self.finalize_with_failure(&app, job_id, ZoneFailure::ParseError)
                    .await;
                return;
            }
        };

        // Step 2: build the full prompt (system + user). Re-wrap in
        // Redacted immediately so logging stays safe end-to-end.
        let full_prompt = format!(
            "{SAMMANFATTA_SYSTEM_PROMPT}\n\n{}",
            extracted.raw.as_inner()
        );
        let prompt = Redacted::new(full_prompt);

        // Step 3: call the model, racing the cancel token.
        let response = tokio::select! {
            r = client.generate("gemma3:4b", prompt) => r,
            _ = cancel_token.cancelled() => {
                self.finalize_with_cancellation(&app, job_id).await;
                return;
            }
        };

        let response_text = match response {
            Ok(r) => r.into_inner(),
            Err(_) => {
                self.finalize_with_failure(&app, job_id, ZoneFailure::ModelError)
                    .await;
                return;
            }
        };

        // If the cancel landed AFTER the model returned, honor it
        // (Allium DiscardLateModelResponseAfterCancel rule).
        if cancel_token.is_cancelled() {
            self.finalize_with_cancellation(&app, job_id).await;
            return;
        }

        // Step 4: build the output .docx + write atomically.
        let bytes = build_summary_doc(&source, &response_text, extracted.was_truncated);
        let target = resolve_target(&source);

        if let Err(failure) = write_atomically(&target, &bytes).await {
            self.finalize_with_failure(&app, job_id, failure).await;
            return;
        }

        // Step 5: open via OS default handler (best-effort — open
        // failure does not flip success to error per FR-007).
        if let Err(e) = open::that_detached(&target) {
            eprintln!("[juradrop] OS open failed (file saved): {e}");
        }

        // Step 6: success snapshot + auto-clear.
        {
            let mut st = self.state.write();
            if let Some(ref mut job) = st.current_job {
                job.truncated = extracted.was_truncated;
                job.complete(JobOutcome::Success);
            }
            st.visible = ZoneState::Success;
        }
        let _ = app.emit(
            "juradrop://sammanfatta",
            ZoneSnapshot {
                state: ZoneState::Success,
                disabled: false,
                failure: None,
                job_id: Some(job_id.to_string()),
                progress_hint: Some("Klar — öppnar fil…".into()),
            },
        );
        self.schedule_success_clear(&app);
    }

    /// Cancellation entry point — called by the `cancel_summary`
    /// tauri::command. Idempotent: a stale `job_id` is a no-op.
    pub fn cancel(&self, job_id: &str) {
        let st = self.state.read();
        if let Some(ref job) = st.current_job {
            if job.id.to_string() == job_id {
                job.cancel();
            }
        }
    }

    /// Re-emit a snapshot reflecting the current spec 002 sidecar
    /// status. Called from `lib.rs` when `juradrop://status` arrives
    /// so the zone tracks the disabled gate reactively.
    pub fn refresh_disabled<R: Runtime>(&self, app: &AppHandle<R>, sidecar_ready: bool) {
        let st = self.state.read();
        if matches!(st.visible, ZoneState::Idle | ZoneState::Error) {
            let snap = ZoneSnapshot {
                state: st.visible,
                disabled: !sidecar_ready,
                failure: None,
                job_id: None,
                progress_hint: None,
            };
            drop(st);
            let _ = app.emit("juradrop://sammanfatta", snap);
        }
    }

    // --- private helpers ---------------------------------------------

    fn emit_failure<R: Runtime>(&self, app: &AppHandle<R>, failure: ZoneFailure) {
        {
            let mut st = self.state.write();
            st.visible = ZoneState::Error;
            st.current_job = None;
        }
        let _ = app.emit(
            "juradrop://sammanfatta",
            ZoneSnapshot {
                state: ZoneState::Error,
                disabled: false,
                failure: Some(failure),
                job_id: None,
                progress_hint: None,
            },
        );
    }

    fn snapshot_for_busy_toast(&self) -> ZoneSnapshot {
        // FR-015 bounce — emit the "vänta" copy as an error snapshot
        // but keep visible_state = processing internally.
        ZoneSnapshot {
            state: ZoneState::Processing,
            disabled: false,
            failure: Some(ZoneFailure::ZoneBusy),
            job_id: None,
            progress_hint: None,
        }
    }

    async fn finalize_with_failure<R: Runtime>(
        self: &Arc<Self>,
        app: &AppHandle<R>,
        job_id: Uuid,
        failure: ZoneFailure,
    ) {
        {
            let mut st = self.state.write();
            if let Some(ref mut job) = st.current_job {
                if job.id == job_id {
                    job.complete(JobOutcome::Failure);
                }
            }
            st.visible = ZoneState::Error;
        }
        let _ = app.emit(
            "juradrop://sammanfatta",
            ZoneSnapshot {
                state: ZoneState::Error,
                disabled: false,
                failure: Some(failure),
                job_id: Some(job_id.to_string()),
                progress_hint: None,
            },
        );
        self.schedule_error_clear(app);
    }

    async fn finalize_with_cancellation<R: Runtime>(
        self: &Arc<Self>,
        app: &AppHandle<R>,
        job_id: Uuid,
    ) {
        {
            let mut st = self.state.write();
            if let Some(ref mut job) = st.current_job {
                if job.id == job_id {
                    job.complete(JobOutcome::Cancelled);
                }
            }
            // Per spec.md US5: visible_state goes to Success so the
            // "Sammanfattning avbruten" flash uses the success
            // pathway (then auto-clears within 2 s).
            st.visible = ZoneState::Success;
        }
        let _ = app.emit(
            "juradrop://sammanfatta",
            ZoneSnapshot {
                state: ZoneState::Success,
                disabled: false,
                failure: None,
                job_id: Some(job_id.to_string()),
                progress_hint: Some("Sammanfattning avbruten".into()),
            },
        );
        self.schedule_success_clear(app);
    }

    fn schedule_success_clear<R: Runtime>(self: &Arc<Self>, app: &AppHandle<R>) {
        let zone = self.clone();
        let app_clone = app.clone();
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(SUCCESS_AUTO_CLEAR).await;
            zone.auto_clear_to_idle(&app_clone, ZoneState::Success);
        });
    }

    fn schedule_error_clear<R: Runtime>(self: &Arc<Self>, app: &AppHandle<R>) {
        let zone = self.clone();
        let app_clone = app.clone();
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(ERROR_AUTO_CLEAR).await;
            zone.auto_clear_to_idle(&app_clone, ZoneState::Error);
        });
    }

    /// Transition from `expected` → `Idle`. No-op if a new drop arrived
    /// during the sleep and the visible_state has already moved on.
    /// Auto-clear transition: only fires if the visible state is still
    /// `expected`. If a new drop or status change moved the zone on,
    /// this is a no-op — that's the Allium ProcessingHasJob /
    /// IdleHasNoJob safety net for the timer race.
    ///
    /// Returns `true` if the transition fired, `false` if it was a
    /// no-op. Exposed for the unit test below; the production callers
    /// (schedule_success_clear / schedule_error_clear) discard the
    /// return value.
    fn auto_clear_to_idle<R: Runtime>(&self, app: &AppHandle<R>, expected: ZoneState) -> bool {
        {
            let mut st = self.state.write();
            if st.visible != expected {
                return false;
            }
            st.visible = ZoneState::Idle;
            st.current_job = None;
        }
        let _ = app.emit("juradrop://sammanfatta", ZoneSnapshot::idle(false));
        true
    }

    // ----- Test-only accessors for the auto-clear unit tests (T035) ----

    #[cfg(test)]
    pub(crate) fn set_visible_for_test(&self, s: ZoneState) {
        self.state.write().visible = s;
    }

    #[cfg(test)]
    pub(crate) fn visible_for_test(&self) -> ZoneState {
        self.state.read().visible
    }
}

/// Convenience: spec 002's `OllamaSidecar::status()` returns `Ready`
/// when the sidecar is up; this maps it to the zone's `disabled` gate.
pub fn sidecar_is_ready(status: SidecarStatus) -> bool {
    matches!(status, SidecarStatus::Ready)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Most of the dispatch path is integration-tested in
    // tests/zone_sammanfatta_lifecycle.rs (T023). The unit tests here
    // cover state-machine invariants that don't need a Tauri app
    // around them.

    #[test]
    fn new_zone_starts_idle_with_no_job() {
        let zone = SammanfattaZone::new();
        let st = zone.state.read();
        assert!(matches!(st.visible, ZoneState::Idle));
        assert!(st.current_job.is_none());
    }

    #[test]
    fn cancel_with_stale_job_id_is_no_op() {
        let zone = SammanfattaZone::new();
        // No job in flight — cancel should be silent (no panic).
        zone.cancel("00000000-0000-0000-0000-000000000000");
        let st = zone.state.read();
        assert!(st.current_job.is_none());
    }

    #[test]
    fn sidecar_is_ready_only_for_ready_status() {
        assert!(sidecar_is_ready(SidecarStatus::Ready));
        assert!(!sidecar_is_ready(SidecarStatus::NotStarted));
        assert!(!sidecar_is_ready(SidecarStatus::Starting));
        assert!(!sidecar_is_ready(SidecarStatus::Crashed));
        assert!(!sidecar_is_ready(SidecarStatus::Stopping));
        assert!(!sidecar_is_ready(SidecarStatus::Stopped));
    }

    /// T035 — auto-clear must fire when the visible state still matches
    /// `expected`, and must NO-OP when the state has moved on (e.g. a
    /// new drop arrived during the 2 s / 5 s sleep). Without this
    /// guard, the timer would clobber an in-flight Processing state
    /// after a success → processing transition.
    #[test]
    fn auto_clear_to_idle_only_fires_when_state_still_matches() {
        use tauri::test::{mock_builder, mock_context, noop_assets};

        let app = mock_builder()
            .build(mock_context(noop_assets()))
            .expect("build mock app");
        let handle = app.handle().clone();

        let zone = SammanfattaZone::new();

        // Case 1 — expected matches actual. Clear should fire.
        zone.set_visible_for_test(ZoneState::Success);
        assert!(
            zone.auto_clear_to_idle(&handle, ZoneState::Success),
            "auto-clear should fire when state matches"
        );
        assert_eq!(zone.visible_for_test(), ZoneState::Idle);

        // Case 2 — state has moved on. Clear should NOT fire.
        zone.set_visible_for_test(ZoneState::Processing);
        assert!(
            !zone.auto_clear_to_idle(&handle, ZoneState::Success),
            "auto-clear must be a no-op when visible state has moved on"
        );
        assert_eq!(
            zone.visible_for_test(),
            ZoneState::Processing,
            "stale auto-clear must not clobber a new processing state"
        );

        // Case 3 — error → idle when state still matches.
        zone.set_visible_for_test(ZoneState::Error);
        assert!(zone.auto_clear_to_idle(&handle, ZoneState::Error));
        assert_eq!(zone.visible_for_test(), ZoneState::Idle);

        // Case 4 — error path with state moved on (a recover-and-redrop
        // arrived) must also no-op.
        zone.set_visible_for_test(ZoneState::Processing);
        assert!(!zone.auto_clear_to_idle(&handle, ZoneState::Error));
        assert_eq!(zone.visible_for_test(), ZoneState::Processing);
    }
}
