# Tasks: Study-method drop zones (9 → 12)

**Feature**: 036-study-method-zones | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

**Track**: light. `/tla` OUT OF SCOPE (reuses the existing per-zone state machine — triviality gate). Browser tests = vitest functional/drift + Playwright smoke; no NEW interactive surface → destructive battery covered by the existing DropZone tests.

**Coupling note**: the `ZoneId` enum's 8 exhaustive matches mean all three variants + all arms must land together to compile — so the shared additive change is Foundational; each User Story phase is that zone's independently-testable pipeline test.

## Phase 1: Setup & gates

- [X] T001 **BLOCKING (humanizer)**: run the `humanizer` skill over ALL new Swedish copy drafted in research.md R-003 — 3 titles, 3 hint_copy, 3 processing_hint, 3 disclaimers, 6 help short/long, 3 system prompts. Record the final approved strings (used verbatim by T003–T008). Voice must match the existing nine zones.
- [X] T002 Read the exact existing patterns to mirror: `zone_id.rs` (the 8 per-zone methods + the `ALL`/`spec_013_has_exactly_nine_zones` test), `prompts/mod.rs`, `tests/fixtures/zone-identity.json`, `tests/fixtures/zone-help-strings.json`, `examples/generate_fixtures.rs`, one `tests/zone_pipeline_*.rs`, and `tests/common/mod.rs::run_zone_pipeline`.

## Phase 2: Foundational — the shared additive change (must all land to compile)

- [X] T003 `src-tauri/src/zones/zone_id.rs`: add 3 `ZoneId` variants `Identifiera`/`Strukturera`/`Forklara` with serde `rename` = `identifiera`/`strukturera`/`forklara`; change `ALL: [ZoneId; 9]` → `[ZoneId; 12]` appending the 3 in that order.
- [X] T004 `src-tauri/src/zones/zone_id.rs`: add the 3 arms to EACH exhaustive match using the data-model.md values + T001 strings: `slug()`, `title()`, `hint_copy()`, `processing_hint()`, `sidecar_suffix()` (`rattsfragor`/`irac`/`begrepp`), `header_paragraph_template()`, `system_prompt()` (→ the new consts), `disclaimer_paragraph()` (`Some(...)` for all three).
- [X] T005 [P] Create `src-tauri/src/prompts/identifiera.rs`, `strukturera.rs`, `forklara.rs` (one Swedish system-prompt const each — T001 approved; MUST contain a "skriv bara …" no-preamble guard + an explicit "hitta inte på lagrum/paragrafer/rättsfall" anti-fabrication clause, FR-003); add the 3 `mod` + re-export lines to `src-tauri/src/prompts/mod.rs`.
- [X] T006 [P] `src-tauri/src/help/zone_help.rs`: `ZONE_HELP_STRINGS [;9]→[;12]` + 3 entries in `ALL` order (T001 short ≤80 / long ≤300).
- [X] T007 [P] `src/components/DropZone.identity.ts`: add 3 `ZONE_IDENTITIES` entries (`slug`/`title`/`hintCopy`/`sidecarSuffix`/`processingHint`/`hasDisclaimer: true`, mirroring Rust exactly) + append the 3 slugs to `ZONE_ORDER` (indices 9/10/11).
- [X] T008 [P] `src-tauri/tests/fixtures/zone-identity.json` (+3 objects, `_comment` 9→12) and `zone-help-strings.json` (+3 objects, `_comment` 9→12) — values byte-identical to the Rust/TS sources.
- [X] T009 `src-tauri/examples/generate_fixtures.rs`: add 3 generators for `identifiera-input.docx`/`strukturera-input.docx`/`forklara-input.docx` (realistic Swedish source content per zone); run `cargo run --example generate_fixtures` to write them under `tests/fixtures/documents/`.
- [X] T010 [P] `src-tauri/tauri.conf.json`: window `height` 760 → **1000** (width 1160, minHeight 500, minWidth 700 unchanged) — the frontend-design decision.
- [X] T011 [P] `.specify/memory/constitution.md`: bump 1.1.0 → 1.2.0; change "nine drop zones in a 3×3 grid" → "twelve drop zones in a 3×4 grid" (lines ~3 + ~40); add a Sync Impact entry (dated 2026-06-03, spec 036, MINOR, no principle weakened — all zones share the local-only pipeline).

## Phase 3: User Story 1 — Identifiera rättsfrågorna (Priority: P1)

- [X] T012 [US1] Create `src-tauri/tests/zone_pipeline_identifiera.rs` via `run_zone_pipeline(ZoneId::Identifiera, "identifiera-input.docx", <Swedish issue-list mock>, &["Rättsfråga", "1."])`. The mock output is citation-free; ALSO assert the produced sidecar contains no `SFS`/`NJA`/`§`/`kap.` token (SC-002) and mirrors the input format + suffix.

## Phase 4: User Story 2 — Strukturera (IRAC) (Priority: P2)

- [X] T013 [US2] Create `src-tauri/tests/zone_pipeline_strukturera.rs` via `run_zone_pipeline(ZoneId::Strukturera, "strukturera-input.docx", <IRAC-headed Swedish mock>, &["Rättsfråga", "Gällande rätt", "Subsumtion", "Slutsats"])`; assert the four headings appear in order (FR-005) + citation-free (SC-002).

## Phase 5: User Story 3 — Förklara begreppen (Priority: P3)

- [X] T014 [US3] Create `src-tauri/tests/zone_pipeline_forklara.rs` via `run_zone_pipeline(ZoneId::Forklara, "forklara-input.docx", <term→definition Swedish mock>, &[<a term>, <an explanation cue>])`; assert term/explanation pairing + citation-free (SC-002).

## Phase 6: Polish — drift tests, count assertions, gates, visual

- [X] T015 `src-tauri/src/zones/zone_id.rs`: update the `spec_013_has_exactly_nine_zones` test → twelve (rename if apt), assert `ALL.len()==12` + `ALL[9..12]` == the 3 new variants.
- [X] T016 [P] Update TS drift tests: `src/__tests__/DropZone.identity.test.tsx` — `EXPECTED_ZONE_IDS` +3 and the alphabetised fixture-key assertion 9→12; `src/__tests__/help-strings-drift.test.ts` — the `covers all 9 zones` comment/label → 12 (logic auto-parameterised).
- [X] T017 Run `cd src-tauri && cargo test` (zone-count, drift, 3 pipeline tests all green), `cargo clippy --all-targets -- -D warnings` (zone_id.rs is under spec-035's deny — no new unwrap/expect; arms return consts), `cargo fmt --check`.
- [X] T018 [P] Run `npm test` (DropZone.identity + help-strings-drift at 12), `npm run typecheck && npm run lint`, `npm run test:e2e` (Playwright smoke asserts twelve `data-zone-id` tiles render).
- [X] T019 Manual visual (`npm run tauri dev`): 12 zones in 3×4, all visible at 1160×1000 without scrolling, the 3 new tiles show their Swedish titles/hints; drag a real file onto one new zone → sidecar appears + opens. If headless (no Mac GUI/model), document as a deferral — the pipeline + smoke tests are the substitute.
- [X] T020 Run `graphify update .` to refresh the knowledge graph after the change.

## Dependencies & ordering

- Phase 1 first; **T001 (humanizer) BLOCKS T003–T008** (they consume the approved strings).
- Phase 2: T003 → T004 (same file, enum before matches); T005 before T004's `system_prompt()` arms (the consts must exist). T006/T007/T008/T010/T011 are `[P]` (different files). T009 after T003 (needs the variants? no — fixtures are docx content, independent; but run after T002). Everything in Phase 2 must compile together.
- Phase 3–5 (T012/T013/T014) after Phase 2 (need the variants + fixtures + prompts); independently testable per zone.
- Phase 6 after Phases 2–5. T017/T018 are the gate; T019 visual; T020 last.

## Parallel execution example

```
After T004+T005 land, in parallel: T006 (help) · T007 (TS identity) · T008 (fixtures) · T010 (window) · T011 (constitution)
After Phase 2: T012 · T013 · T014 (the three pipeline tests)
```

## Implementation strategy

MVP = US1 (Identifiera) once Foundational lands — but Foundational is shared (all three compile together), so the practical increment is "Foundational + all three pipeline tests". Each zone's behaviour is independently asserted by its own pipeline test.

## Notes

- Net new deps: **0**. Net new outbound: **0** (same local Ollama). New Swedish strings: 3 titles + 3 hints + 3 processing + 3 disclaimers + 6 help + 3 prompts — ALL humanizer-reviewed (T001).
- `framing.rs` + `output_format.rs` need NO change — the 3 zones fall through the `_` (DATA / mirror) arms; a quiet confirmation they are ordinary transform zones (FR-007/FR-008).
- Constitution bump 1.1.0→1.2.0 is part of the deliverable (FR-012), mirroring spec 013's 6→9 bump.
