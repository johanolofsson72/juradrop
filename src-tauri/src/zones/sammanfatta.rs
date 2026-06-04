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

use super::chunking::{self, CombineStrategy, CHUNK_CHAR_TARGET};
use super::docx_write::build_summary_doc;
use super::errors::ZoneFailure;
use super::extract::extract_text as extract_text_dispatch;
use super::input_format::InputFormat;
use super::job::DropJob;
use super::md_write::build_sidecar as build_md_sidecar;
use super::output_format::OutputFormat;
use super::pii_sweep;
use super::sidecar_path::{resolve_target_format, write_atomically};
use super::snapshot::{JobOutcome, ZoneSnapshot, ZoneState};
use super::txt_write::build_sidecar as build_txt_sidecar;
use super::zone_id::ZoneId;

/// Auto-clear delays per FR-010 / FR-011.
const SUCCESS_AUTO_CLEAR: Duration = Duration::from_secs(2);
const ERROR_AUTO_CLEAR: Duration = Duration::from_secs(5);

/// Spec 038 FR-014 — honest disclosure on multi-chunk Anonymisera output:
/// chunks are anonymized independently, so the same person can carry
/// different placeholder labels in different document sections. Prepended
/// as the first body paragraph (after the spec-014 sweep warning, if any).
/// User-facing Swedish — humanizer-reviewed (T016).
const ANONYMISERA_CHUNK_DISCLAIMER: &str = "Dokumentet anonymiserades i flera delar — samma person kan därför heta \"Person A\" i en del och \"Person B\" i en annan. Granska innan du delar.";

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
        model_id: &'static str,
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

        // Spec 005 FR-010 + spec 028 — extension routing.
        //   1. Any `.pages` (modern zip-form OR legacy directory bundle,
        //      any letter case) routes to the actionable PagesUnsupported
        //      message BEFORE the generic fallthrough. Spec 028 removed
        //      .pages: modern Pages stores text in undecodable `.iwa` blobs,
        //      so we tell the user to export to Word/PDF first instead of
        //      faking a parse attempt that always failed.
        //   2. Any extension outside the 6-format supported set surfaces
        //      InvalidFormat (FR-010).
        let lower_ext = source
            .extension()
            .and_then(|s| s.to_str())
            .map(|s| s.to_lowercase());
        if lower_ext.as_deref() == Some("pages") {
            self.emit_failure(&app, ZoneFailure::PagesUnsupported);
            self.schedule_error_clear(&app);
            return;
        }
        if InputFormat::detect_from_path(&source).is_none() {
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
        // DragDrop event handler) returns promptly. Spec 010 / FR-010 —
        // the model_id is pinned at dispatch entry; in-flight runs are
        // immune to tier switches that happen mid-flight.
        let zone = self.clone();
        let app_clone = app.clone();
        tauri::async_runtime::spawn(async move {
            zone.dispatch(app_clone, client, source, model_id, job_id, cancel_token)
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
        model_id: &'static str,
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
        // Spec 013 FR-003 — zone-aware: Generera always writes .docx
        // (generates a document, not a transform of the input).
        let output_format = OutputFormat::for_zone(self.id, input_format);

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

        // Step 2 (spec 038): build the chunk plan. Documents that fit one
        // model pass take exactly the pre-038 path (one framed generate);
        // longer documents run one pass per chunk with per-part Swedish
        // progress, then combine per the zone's strategy.
        let plan = chunking::split_into_chunks(extracted.raw.as_inner());
        let strategy = self.id.combine_strategy();

        // Generera is exempt: its input is user instructions, never a
        // document — keep the pre-038 behavior (first chunk + disclaimer).
        let (chunks, was_capped) = if strategy == CombineStrategy::Exempt && !plan.is_single_pass()
        {
            let first = plan.chunks.into_iter().next();
            (first.into_iter().collect::<Vec<_>>(), true)
        } else {
            let capped = plan.was_capped;
            (plan.chunks, capped)
        };
        // Analyze F1 — the disclaimer fires iff content was genuinely
        // skipped at EITHER layer: the extraction memory bound (288k) or
        // the 12-chunk cap (or the Generera exemption above).
        let content_skipped = extracted.was_truncated || was_capped;

        let Some(first_chunk) = chunks.first() else {
            // Defensive: extraction already rejects whitespace-only text,
            // so an empty plan cannot occur in practice.
            self.finalize_with_failure(&app, job_id, ZoneFailure::EmptyText)
                .await;
            return;
        };

        let multi = chunks.len() > 1;
        let response_text = if !multi {
            // Single-pass path — byte-identical to pre-038 (SC-004): one
            // framed generate, no extra snapshots, no combine.
            // Spec 022 — frame the untrusted document so it can't hijack
            // the system prompt (Generera is framed as instructions).
            let full_prompt =
                crate::prompts::frame_prompt(self.id, self.id.system_prompt(), first_chunk);
            match self
                .generate_raced(&app, &client, model_id, full_prompt, job_id, &cancel_token)
                .await
            {
                Some(text) => text,
                None => return, // finalized (failure or cancel) inside
            }
        } else {
            // Multi-chunk loop (FR-003/FR-008): sequential passes, one
            // Swedish progress snapshot per part, cancel raced per pass.
            let n = chunks.len();
            let per_chunk_instruction = match strategy {
                // Condense-then-structure: chunks are condensed first; the
                // zone's own IRAC prompt runs once over the condensate.
                CombineStrategy::CondenseThenStructure => {
                    crate::prompts::STRUKTURERA_CONDENSE_PROMPT
                }
                _ => self.id.system_prompt(),
            };

            let mut partials: Vec<String> = Vec::with_capacity(n);
            for (i, chunk) in chunks.iter().enumerate() {
                self.emit_progress(&app, job_id, format!("Bearbetar del {} av {n}…", i + 1));
                let full_prompt =
                    crate::prompts::frame_prompt(self.id, per_chunk_instruction, chunk);
                match self
                    .generate_raced(&app, &client, model_id, full_prompt, job_id, &cancel_token)
                    .await
                {
                    Some(text) => partials.push(text),
                    None => return,
                }
            }

            // Combine per strategy (FR-004). Deterministic strategies need
            // no model pass; reduce/condense run framed combine passes.
            self.emit_progress(&app, job_id, "Sammanställer…".to_string());
            match strategy {
                CombineStrategy::Concat => chunking::merge_concat(&partials),
                CombineStrategy::Aggregate => chunking::merge_aggregate(self.id, &partials),
                CombineStrategy::Reduce => {
                    let combine_instruction = match self.id {
                        ZoneId::Punktlista => crate::prompts::PUNKTLISTA_COMBINE_PROMPT,
                        _ => crate::prompts::SAMMANFATTA_COMBINE_PROMPT,
                    };
                    match self
                        .reduce_partials(
                            &app,
                            &client,
                            model_id,
                            combine_instruction,
                            combine_instruction,
                            partials,
                            job_id,
                            &cancel_token,
                        )
                        .await
                    {
                        Some(text) => text,
                        None => return,
                    }
                }
                CombineStrategy::CondenseThenStructure => {
                    // Re-condense recursively if needed (analyze F2), then
                    // the zone's own prompt structures the condensate.
                    match self
                        .reduce_partials(
                            &app,
                            &client,
                            model_id,
                            crate::prompts::STRUKTURERA_CONDENSE_PROMPT,
                            self.id.system_prompt(),
                            partials,
                            job_id,
                            &cancel_token,
                        )
                        .await
                    {
                        Some(text) => text,
                        None => return,
                    }
                }
                // Exempt never reaches multi (forced single above); the
                // defensive arm keeps the match exhaustive without a panic.
                CombineStrategy::Exempt => chunking::merge_concat(&partials),
            }
        };

        // Spec 038 FR-014 — multi-chunk Anonymisera output carries an honest
        // Swedish review disclaimer: chunks are anonymized independently, so
        // placeholder labels can differ between document sections. Prepended
        // BEFORE the PII sweep so the sweep warning (if any) stays first.
        let response_text = if self.id == ZoneId::Anonymisera && multi {
            format!("{ANONYMISERA_CHUNK_DISCLAIMER}\n\n{response_text}")
        } else {
            response_text
        };

        // Spec 014 — Anonymisera output-side PII-residue sweep. Scan the
        // model OUTPUT (never the input) for personnummer / e-post / telefon
        // the model failed to redact; when found, prepend a Swedish warning
        // as the first body paragraph. Detection only — the model text is
        // never edited. Runs for Anonymisera only (spec 038: on the FULL
        // combined output); every other zone keeps its output byte-identical.
        let response_text = if self.id == ZoneId::Anonymisera {
            let findings = pii_sweep::scan_residual_pii(&response_text);
            match pii_sweep::warning_paragraph(&findings) {
                Some(warning) => format!("{warning}\n\n{response_text}"),
                None => response_text,
            }
        } else {
            response_text
        };

        // Step 4: build the output sidecar + write atomically. Both
        // per-zone — the writer uses the zone's header template +
        // disclaimer, and the resolver uses the zone's sidecar suffix.
        // Spec 005 — the writer chosen per `output_format` mirrors the
        // input extension (with PDF → DOCX per FR-011).
        let bytes = match output_format {
            OutputFormat::Docx => match build_summary_doc(
                self.id,
                &source,
                &response_text,
                content_skipped,
                extracted.was_partial,
            ) {
                Ok(b) => b,
                Err(failure) => {
                    // Spec 035 — a docx pack failure is an honest SaveError, not a panic.
                    self.finalize_with_failure(&app, job_id, failure).await;
                    return;
                }
            },
            OutputFormat::Txt => {
                build_txt_sidecar(self.id, &source, &response_text, content_skipped)
            }
            OutputFormat::Md => build_md_sidecar(
                self.id,
                &source,
                &response_text,
                extracted.frontmatter.as_deref(),
                content_skipped,
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
                job.truncated = content_skipped;
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

    /// Spec 038 — one framed model pass raced against the job's cancel
    /// token, with the late-cancel re-check (Allium
    /// DiscardLateModelResponseAfterCancel). Returns `None` after
    /// finalizing (failure or cancellation) — the caller just returns.
    #[allow(clippy::too_many_arguments)]
    async fn generate_raced<R: Runtime>(
        self: &Arc<Self>,
        app: &AppHandle<R>,
        client: &Arc<OllamaClient>,
        model_id: &str,
        full_prompt: String,
        job_id: Uuid,
        cancel_token: &tokio_util::sync::CancellationToken,
    ) -> Option<String> {
        // Wrap in Redacted immediately so logging stays safe end-to-end.
        let prompt = Redacted::new(full_prompt);
        let response = tokio::select! {
            r = client.generate(model_id, prompt) => r,
            _ = cancel_token.cancelled() => {
                self.finalize_with_cancellation(app, job_id).await;
                return None;
            }
        };
        let text = match response {
            Ok(r) => r.into_inner(),
            Err(_) => {
                self.finalize_with_failure(app, job_id, ZoneFailure::ModelError)
                    .await;
                return None;
            }
        };
        if cancel_token.is_cancelled() {
            self.finalize_with_cancellation(app, job_id).await;
            return None;
        }
        Some(text)
    }

    /// Spec 038 — bound-and-combine: batch `parts` until the labeled input
    /// fits one model pass, combining each batch with `instruction`; the
    /// final pass runs `final_instruction` over the fitting input. For
    /// Reduce both instructions are the zone's combine prompt; for
    /// CondenseThenStructure the batches re-condense and the final pass is
    /// the zone's own (IRAC) prompt (analyze F2). Deterministic
    /// termination: an oversized single part is hard-truncated, and a
    /// no-progress round falls through to a final truncated pass.
    #[allow(clippy::too_many_arguments)]
    async fn reduce_partials<R: Runtime>(
        self: &Arc<Self>,
        app: &AppHandle<R>,
        client: &Arc<OllamaClient>,
        model_id: &str,
        instruction: &str,
        final_instruction: &str,
        mut parts: Vec<String>,
        job_id: Uuid,
        cancel_token: &tokio_util::sync::CancellationToken,
    ) -> Option<String> {
        // Defensive bound: a single partial larger than the chunk target
        // (model ignored its instruction) is truncated on a char boundary
        // so batching always makes progress.
        for p in parts.iter_mut() {
            if p.chars().nth(CHUNK_CHAR_TARGET).is_some() {
                *p = p.chars().take(CHUNK_CHAR_TARGET / 2).collect();
            }
        }

        loop {
            let labeled = label_parts(&parts);
            if labeled.chars().nth(CHUNK_CHAR_TARGET).is_none() {
                // Fits one pass — run the final combine/structure pass.
                let full = crate::prompts::frame_prompt(self.id, final_instruction, &labeled);
                return self
                    .generate_raced(app, client, model_id, full, job_id, cancel_token)
                    .await;
            }

            // Greedy batches whose labeled size fits the target.
            let batches = batch_parts(&parts);
            if batches.len() >= parts.len() {
                // No progress possible — truncate the labeled input and
                // run the final pass (deterministic termination; in
                // practice unreachable because each part is bounded above).
                let truncated: String = labeled.chars().take(CHUNK_CHAR_TARGET).collect();
                let full = crate::prompts::frame_prompt(self.id, final_instruction, &truncated);
                return self
                    .generate_raced(app, client, model_id, full, job_id, cancel_token)
                    .await;
            }

            let mut next: Vec<String> = Vec::with_capacity(batches.len());
            for batch in &batches {
                let full = crate::prompts::frame_prompt(self.id, instruction, &label_parts(batch));
                match self
                    .generate_raced(app, client, model_id, full, job_id, cancel_token)
                    .await
                {
                    Some(text) => next.push(text),
                    None => return None,
                }
            }
            parts = next;
        }
    }

    /// Spec 038 FR-008 — per-part Swedish progress on the existing zone
    /// channel. The hint is a pre-defined phrase with integers only —
    /// never document content (snapshot.rs privacy contract).
    fn emit_progress<R: Runtime>(&self, app: &AppHandle<R>, job_id: Uuid, hint: String) {
        let _ = app.emit(
            &self.event_channel(),
            ZoneSnapshot {
                state: ZoneState::Processing,
                disabled: false,
                failure: None,
                job_id: Some(job_id.to_string()),
                progress_hint: Some(hint),
            },
        );
    }

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
        // Spec 025 — content-free failure category (no-op unless the user
        // opted in to local diagnostics). Logs the ZoneFailure serde tag,
        // never any document content.
        crate::diagnostics::log_event(crate::diagnostics::DiagnosticEvent::ZoneFailureLogged {
            category: failure.tag(),
        });
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

/// Spec 038 — label partial results in document order for a combine pass:
/// "Del 1:\n…\n\nDel 2:\n…".
fn label_parts(parts: &[String]) -> String {
    parts
        .iter()
        .enumerate()
        .map(|(i, p)| format!("Del {}:\n{p}", i + 1))
        .collect::<Vec<_>>()
        .join("\n\n")
}

/// Spec 038 — greedy in-order grouping of parts into batches whose labeled
/// size fits one model pass. Every part is bounded above by the caller, so
/// each batch holds at least one part and the batch count strictly shrinks
/// whenever any two parts fit together.
fn batch_parts(parts: &[String]) -> Vec<Vec<String>> {
    let mut batches: Vec<Vec<String>> = Vec::new();
    let mut current: Vec<String> = Vec::new();
    let mut current_chars = 0usize;
    // Per-part overhead: "Del NN:\n" + the "\n\n" joiner (≤ 10 chars).
    const LABEL_OVERHEAD: usize = 10;
    for part in parts {
        let part_chars = part.chars().count() + LABEL_OVERHEAD;
        if !current.is_empty() && current_chars + part_chars > CHUNK_CHAR_TARGET {
            batches.push(std::mem::take(&mut current));
            current_chars = 0;
        }
        current_chars += part_chars;
        current.push(part.clone());
    }
    if !current.is_empty() {
        batches.push(current);
    }
    batches
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
