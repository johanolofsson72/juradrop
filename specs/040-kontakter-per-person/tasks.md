# Tasks: Kontakter grouped per person

**Input**: Design documents from `/specs/040-kontakter-per-person/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/kontakter-output.md, quickstart.md

**Tests**: Included — project mandate (CLAUDE.md: 100% functional coverage; tests.md rules).

**Organization**: Tasks grouped by user story. US1 = per-person grouping (prompt), US2 = Övriga uppgifter safety, US3 = multi-part merge, US4 = help copy.

## Phase 1: Setup

No setup tasks — no new files, deps, or infrastructure. Existing module layout reused.

## Phase 2: Foundational (blocking prerequisites)

- [ ] T001 Define the shared catch-all heading const `OVRIGA_HEADING: &str = "## Övriga uppgifter"` in src-tauri/src/zones/chunking.rs (pub(crate)), with a doc comment naming it the single source of truth for both the merge and the prompt-agreement test (contract §1 note; pattern from spec 039's shared PII regexes)

**Checkpoint**: const exists; both halves below key on it.

## Phase 3: User Story 1 — Contact details grouped under their owner (P1) 🎯 MVP

**Goal**: The model is instructed to emit per-person sections with category-labeled bullets; the zone's single-part output shape changes accordingly.

**Independent Test**: Prompt-contract unit test inspects the const; pipeline test drives a canned per-person model output end-to-end.

- [ ] T002 [US1] Rewrite `KONTAKTER_SYSTEM_PROMPT` in src-tauri/src/prompts/kontakter.rs: one `## ` heading per person; bullets labeled `Adress:` / `Personnummer:` / `Telefon:` / `E-post:`; unattributable details under a final `## Övriga uppgifter` with an explicit no-guessing instruction ("gissa aldrig vem en uppgift tillhör"); omit empty sections (incl. Övriga when everything is attributed); keep the "skriv bara" no-greeting guardrail; extraction scope unchanged (names + the four categories, no roles/titles/orgs); include a one-line shape example; update the module doc comment (per-category description is stale)
- [ ] T003 [US1] Add prompt-contract unit tests (contract §1 I-1…I-6) in src-tauri/src/prompts/kontakter.rs `#[cfg(test)]`: prompt contains `OVRIGA_HEADING` (agreement with the merge const), contains "skriv bara", contains the four category labels, demands per-person headings, forbids guessing, does NOT mention the five old category headings as output grouping
- [ ] T004 [US1] Update src-tauri/tests/zone_pipeline_kontakter.rs: canned model output becomes a per-person fixture (≥2 persons with mixed labeled details), expected tokens become person headings + category labels; assert NO `## Namn`/`## Adresser` style category headings in the sidecar

**Checkpoint**: US1 independently green — per-person shape proven end-to-end with canned output.

## Phase 4: User Story 2 — Unattributable details never force-paired (P2)

**Goal**: Orphan details land under `## Övriga uppgifter`, last, instead of being guessed onto a person or dropped.

**Independent Test**: Canned output with an Övriga section round-trips; merge-level guarantees covered in US3 tests.

- [ ] T005 [US2] Extend src-tauri/tests/zone_pipeline_kontakter.rs with a second canned fixture where `## Övriga uppgifter` is deliberately NOT last (model disobedience); assert the sidecar preserves the model's section order exactly — pinning FR-012: the single-part path is a pass-through with NO reordering/normalization (the deterministic Övriga-last guarantee is multi-part-only, US3). Also assert the orphan detail survives verbatim (analyze G1 remediation)

**Checkpoint**: Övriga section round-trips end-to-end.

## Phase 5: User Story 3 — Long documents merge per person (P3)

**Goal**: The deterministic combine step merges person sections across parts per contract §2 (M-1…M-9).

**Independent Test**: `merge_aggregate(ZoneId::Kontakter, …)` unit tests with fixed parts; chunked pipeline integration test.

- [ ] T006 [US3] Rewrite `merge_kontakter` in src-tauri/src/zones/chunking.rs per contract §2: remove the `CANONICAL` category array (M-2/FR-010); key sections by exact trimmed heading (M-1); person sections first-seen order (M-2); `OVRIGA_HEADING` section pinned LAST regardless of first-seen position (M-3); lines before any heading in a part — including whole heading-less parts — fold into the Övriga section (M-4, replaces the headingless leading block); per-section exact-trim dedup only, first-seen line order (M-5); person sections with zero lines render as bare heading (M-6); empty Övriga omitted (M-7); output joined as heading + blank + lines (M-8); stays a pure function (M-9); rewrite the function's doc comment
- [ ] T007 [US3] Update existing g7 unit tests in src-tauri/src/zones/chunking.rs: `g7_kontakter_merges_headings_and_dedups` → per-person fixtures, first-seen order assertion replaces canonical-order assertion; `g7_kontakter_handles_missing_headings_and_empty_parts` → headingless line now asserted INSIDE the Övriga section and Övriga asserted last; keep `g7_kontakter_dedup_ignores_surrounding_whitespace` (shape-agnostic)
- [ ] T008 [US3] Add new merge unit tests in src-tauri/src/zones/chunking.rs: (a) Övriga first-seen in part 1 still renders last after persons from part 2 (M-3); (b) same person heading in two parts → one section with union of details (SC-003); (c) cross-person duplicate line preserved under both headings (M-5 clarified); (d) bare person heading with no lines preserved (M-6); (e) whole part with no headings folds entirely into Övriga (M-4); (f) parts that are Övriga-only produce a single Övriga section; (g) no empty Övriga section when nothing is unattributed (M-7)
- [ ] T009 [US3] Update src-tauri/tests/zone_pipeline_chunked.rs `kontakter_multi_chunk_aggregates_with_exactly_once_dedup`: per-person part fixtures (same person across both chunks with overlapping + distinct details, plus an Övriga detail in the FIRST chunk); keep exactly-once assertions; add assertions: one section for the cross-chunk person, `## Övriga uppgifter` is the last heading in the sidecar
- [ ] T010 [US3] Update src-tauri/tests/real_ollama_zones.rs Kontakter expectations (ignored hardware suite): replace per-category heading expectations with per-person-tolerant assertions (labels present, no category-heading grouping demanded of the model output)

**Checkpoint**: deterministic merge fully pinned; chunked path proven end-to-end.

## Phase 6: User Story 4 — Help text describes the new shape (P4)

**Goal**: The three-way mirrored Swedish help copy describes per-person grouping.

**Independent Test**: both drift tests (Rust↔JSON, TS↔JSON) green with the new text.

- [ ] T011 [US4] Run the humanizer skill on the replacement Swedish long help text for Kontakter (replacing "…listar namn, adresser, personnummer, telefonnummer och e-post var för sig…" with per-person wording), then apply the IDENTICAL string to all three mirrors: src-tauri/src/help/zone_help.rs, src-tauri/tests/fixtures/zone-help-strings.json, src/lib/help-strings.ts; `short` stays unchanged (still accurate); verify help_strings_drift.rs + src/__tests__/help-strings-drift.test.ts pass

**Checkpoint**: help copy accurate, mirrors identical, drift guards green.

## Phase 7: Polish & cross-cutting

- [ ] T012 [P] Sweep remaining references to the per-category output shape: src-tauri/tests/concurrency_stress.rs (kontakter canned outputs, if heading-asserting), any fixture/docs mentioning the five category headings as Kontakter output (README zone description if present); update or confirm untouched
- [ ] T013 Full gate sweep: `cd src-tauri && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check`; `npm test`; `npm run lint && npm run typecheck`; `npm run test:e2e` (Playwright zone smoke — no kontakter-output assertions expected, confirm)
- [ ] T014 Manual real-model verification per quickstart.md (short doc single-part + long doc multi-part + help copy) — DEFERRED to the user (no Mac GUI/model in the agent environment), as specs 036/038 did

## Dependencies

- T001 → T002/T003 (shared const) and T006 (merge pin)
- US1 (T002–T004) independent of US3 (T006–T010) after T001 — parallelizable
- T005 depends on T004 (same fixture file)
- T011 (US4) independent of everything — parallelizable any time
- T012–T014 after all stories

## Implementation strategy

MVP = US1 (prompt + single-part shape). US3 is the deterministic half and ships in the same run (light pipeline, one commit). Suggested order: T001 → T002–T005 → T006–T010 → T011 → T012–T013 (T014 deferred to user).
