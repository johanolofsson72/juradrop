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

use super::docx_write::build_summary_doc;
use super::errors::ZoneFailure;
use super::extract::extract_text as extract_text_dispatch;
use super::input_format::InputFormat;
use super::job::DropJob;
use super::md_write::build_sidecar as build_md_sidecar;
use super::output_format::OutputFormat;
use super::sidecar_path::{resolve_target_format, write_atomically};
use super::snapshot::{JobOutcome, ZoneSnapshot, ZoneState};
use super::txt_write::build_sidecar as build_txt_sidecar;
use super::zone_id::ZoneId;

/// Auto-clear delays per FR-010 / FR-011.
const SUCCESS_AUTO_CLEAR: Duration = Duration::from_secs(2);
const ERROR_AUTO_CLEAR: Duration = Duration::from_secs(5);

#[derive(Default)]
struct ZoneInternalState {
    visible: ZoneState,
    current_job: Option<DropJob>,
}

pub struct DropZone {
    id: ZoneId,
    state: Arc<RwLock<ZoneInternalState>>,
}

/// Compat shim — spec 003 call sites still say `SammanfattaZone`.
/// Removed in T049 (Phase 7 cleanup).
pub type SammanfattaZone = DropZone;

impl DropZone {
    pub fn new(id: ZoneId) -> Arc<Self> {
        Arc::new(Self {
            id,
            state: Arc::new(RwLock::new(ZoneInternalState::default())),
        })
    }

    pub fn id(&self) -> ZoneId {
        self.id
    }

    /// Per-channel emit string `juradrop://zone/<slug>`.
    fn event_channel(&self) -> String {
        format!("juradrop://zone/{}", self.id.slug())
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
                let _ = app.emit(&self.event_channel(), self.snapshot_for_busy_toast());
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
            &self.event_channel(),
            ZoneSnapshot {
                state: ZoneState::Processing,
                disabled: false,
                failure: None,
                job_id: Some(job_id.to_string()),
                progress_hint: Some(self.id.processing_hint().into()),
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
        // Spec 005 — detect the input format from the lowercase extension.
        // None → InvalidFormat (FR-010). Resolves which extractor and
        // which writer run.
        let input_format = match InputFormat::detect_from_path(&source) {
            Some(f) => f,
            None => {
                self.finalize_with_failure(&app, job_id, ZoneFailure::InvalidFormat)
                    .await;
                return;
            }
        };
        let output_format = OutputFormat::mirror_from(input_format);

        // Step 1: extract text. Runs synchronously because the
        // extractors (docx-rs, pdf-extract, std::fs) don't expose
        // async APIs. The dispatcher routes to the right per-format
        // extractor and centralises the truncation cap + blank-line
        // collapse.
        let extracted = match tokio::task::spawn_blocking({
            let source = source.clone();
            move || extract_text_dispatch(&source, input_format)
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

        // Step 2: build the per-zone full prompt (system + user). The
        // system prompt comes from self.id.system_prompt() so each
        // zone fires its own Swedish instruction. Wrap in Redacted
        // immediately so logging stays safe end-to-end.
        let full_prompt = format!(
            "{}\n\n{}",
            self.id.system_prompt(),
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

        // Step 4: build the output sidecar + write atomically. Both
        // per-zone — the writer uses the zone's header template +
        // disclaimer, and the resolver uses the zone's sidecar suffix.
        // Spec 005 — the writer chosen per `output_format` mirrors the
        // input extension (with PDF → DOCX per FR-011).
        let bytes = match output_format {
            OutputFormat::Docx => build_summary_doc(
                self.id,
                &source,
                &response_text,
                extracted.was_truncated,
                extracted.was_partial,
            ),
            OutputFormat::Txt => {
                build_txt_sidecar(self.id, &source, &response_text, extracted.was_truncated)
            }
            OutputFormat::Md => build_md_sidecar(
                self.id,
                &source,
                &response_text,
                extracted.frontmatter.as_deref(),
                extracted.was_truncated,
            ),
        };
        let target = resolve_target_format(&source, self.id, output_format);

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
            &self.event_channel(),
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
            let _ = app.emit(&self.event_channel(), snap);
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
            &self.event_channel(),
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
            &self.event_channel(),
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
            &self.event_channel(),
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
        let _ = app.emit(&self.event_channel(), ZoneSnapshot::idle(false));
        true
    }

    // ----- Test-only accessors -----
    //
    // Mirrors the spec 002 `OllamaSidecar::pid()` pattern: plain `pub`
    // with a "test-only" doc note. `#[cfg(test)]` gating doesn't work
    // for integration tests under tests/ (each integration test is
    // its own crate; cfg(test) only fires on the lib's own test
    // target, not on a sibling test target).

    /// Test-only: force the visible state without going through a
    /// snapshot emit. Used by `auto_clear_to_idle` unit tests (T035).
    pub fn set_visible_for_test(&self, s: ZoneState) {
        self.state.write().visible = s;
    }

    /// Test-only: read the current visible state.
    pub fn visible_for_test(&self) -> ZoneState {
        self.state.read().visible
    }

    /// Spec 007 / FR-017 — public read of the current visible state.
    /// Used by the updater's per-zone-busy predicate to decide whether
    /// to defer a restart. Acquires a parking_lot read lock; never
    /// blocks for long because writes are short.
    pub fn visible_state(&self) -> ZoneState {
        self.state.read().visible
    }

    /// Test-only: cancel whatever job is currently in flight,
    /// regardless of its id. Production callers use `cancel(&str)`
    /// so they can't accidentally cancel jobs they didn't initiate.
    /// Used by the zone_cancel integration test (T053).
    pub fn cancel_in_flight_for_test(&self) {
        let st = self.state.read();
        if let Some(ref job) = st.current_job {
            job.cancel();
        }
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
        let zone = DropZone::new(ZoneId::Sammanfatta);
        let st = zone.state.read();
        assert!(matches!(st.visible, ZoneState::Idle));
        assert!(st.current_job.is_none());
    }

    #[test]
    fn cancel_with_stale_job_id_is_no_op() {
        let zone = DropZone::new(ZoneId::Sammanfatta);
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

        let zone = DropZone::new(ZoneId::Sammanfatta);

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
