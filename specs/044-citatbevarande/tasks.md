# Tasks: Citatbevarande (spec 044)

- [ ] T001 Create `src-tauri/src/zones/quote_mask.rs` (pii_scrub template): `is_triggered(zone, instruction)`, `mask_quotes(text) -> MaskOutcome`, `restore_quotes(output, &spans)`; balanced-pair scan for `”…”`/`“…”`/`"…"`/`»…«|»`, 1000-char cap with abandoned-opener rescan, collision-safe numbering above pre-existing `[CITAT k]`; NO log macros. Unit tests: round-trip, multi-span, unbalanced left untouched, cap abandonment, collision (FR-009), destroyed-placeholder no-op (FR-005), empty quote, adjacent quotes, trigger-phrase matrix incl. "översätt även citaten"-negative + non-translation zone
- [ ] T002 Add `ZoneId::is_translation()` helper + register module in `zones/mod.rs`
- [ ] T003 Wire dispatch (`sammanfatta.rs`): mask after the 039 scrub / before `split_into_chunks`; restore after combine+disclaimer section / before sidecar build; spans live on the stack only
- [ ] T004 [P] Append the `[CITAT N]`-verbatim guard sentence to `TILLENGELSKA_SYSTEM_PROMPT` + `TILLSVENSKA_SYSTEM_PROMPT` (model-facing Swedish); prompt-const tests; combine.rs budget test recomputes (expected green)
- [ ] T005 Integration `src-tauri/tests/zone_pipeline_quotes.rs` (wiremock): (a) triggered single-pass → prompt has placeholders, lacks originals; sidecar restores verbatim; (b) dormant trio (no instruction / wrong zone / negative phrase) → byte-identical prompts; (c) chunked: quotes across chunk boundaries, global numbering, all restored (SC-003); (d) hostile doc with literal `[CITAT 1]`
- [ ] T006 [P] Static privacy invariant: quote_mask has no log macros (chunked_path_privacy extension, FR-006)
- [ ] T007 Real-model: extend `manus_validation_real_model` with steg 2b — Johan's exact case (quote-rich Swedish doc + "behåll citaten på svenska" på TillEngelska → all quoted spans verbatim in English output, SC-005)
- [ ] T008 [P] Help: extend INSTRUCTION_HELP body with the documented phrase (humanizer pass; 3-way mirror + drift tests); update TESTMANUS step 2 (re-promote keep-quotes to PASS criterion) + LÄS-MIG
- [ ] T009 Gates: full sweep (cargo ×, vitest, e2e, native smoke unaffected expected) with HONEST failure counting; real-model gated suite green; register tick + history

Order: T001→T002→T003; T004 ∥ after T001; T005 after T003; T006/T008 ∥; T007 after T003; T009 last.
