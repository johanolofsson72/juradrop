# Tasks: Gatuadress Anonymisering — Deterministic Street-Address Scrub (+ phone-tail fix)

**Feature**: 046-gatuadress-anonymisering | **Track**: light | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Rust-only. Zero dispatch changes (both call sites already route through `pii_scrub`/`pii_sweep`).
`RE_PLACEHOLDER` already masks `Adress` (the model emitted "Adress 1/2" pre-046) — `[Adress N]`
is masked for free. Tests MANDATORY (CLAUDE.md: 100% functional coverage).

## Phase 1: Setup

- [x] T001 Baseline: `cd src-tauri && cargo test pii_scrub pii_sweep` green on `main` before edits (anchors the byte-identity assertions).

## Phase 2: Foundational (the two pattern sources — BLOCK US1/US2/US4)

- [x] T002 In `src-tauri/src/zones/pii_sweep.rs`: add `pub(crate) static RE_ADRESS: LazyLock<Regex>` = the verified street pattern `\b[A-ZÅÄÖ][a-zåäöA-ZÅÄÖ]*(?:gatan|gata|vägen|väg|gränden|gränd|stigen|stig|torget|torg|allén|allé|backen|backe|liden|lid|kajen|kaj|stranden|strand|brinken|brink|hamnen|hamn|esplanaden|esplanad|promenaden|promenad|gången|gång)\s+\d{1,3}(?:\s?[A-Za-zÅÄÖåäö])?\b`, beside the other `RE_*`, with the `#[allow(clippy::expect_used)]` + `.expect("adress regex")` discipline and a comment explaining the capital gate, the excluded ambiguous suffixes (plan/led/ring/park/plats), and the required house number. FR-001/FR-002/FR-006 single source.
- [x] T003 In `pii_sweep.rs`: widen `RE_PHONE`'s national branch to add an optional third trailing group `(?:[\s-]? \d{2,4})?` before the closing `\b`, so `0NN-NNN NN NN` is captured in full. Comment that it fixes the spec-039 three-group ceiling (FR-009). Existing `+46` branch + two-group forms unchanged.

## Phase 3: User Story 1 — Streets can no longer survive anonymization (P1)

**Goal**: every Capital+suffix+number street → `[Adress N]` before the model.
**Independent test**: the spec-045 field doc echo-mock; four streets → `[Adress 1..4]`, zero raw.

- [x] T004 [US1] In `src-tauri/src/zones/pii_scrub.rs`: add `Adress = 4` to `Category` + `Category::Adress => "Adress"` in `label()`.
- [x] T005 [US1] In `pii_scrub.rs`: add `(&*RE_ADRESS, Category::Adress)` to the candidate-collection loop (import from `super::pii_sweep`), widen registries `[Vec<&str>; 4] → [Vec<&str>; 5]`, add `pub adress: usize` to `ScrubOutcome`.
- [x] T006 [P] [US1] Unit tests in `pii_scrub.rs`: `Storgatan 5` → `[Adress 1]`; `Lillgatan 12B` + `Köpmangatan 3 A` letter forms captured; same street twice → same index, distinct → next; `out.adress` count correct.
- [x] T007 [P] [US1] Unit test in `pii_scrub.rs`: all-five-categories document (personnummer, telefon, e-post, postnummer, gatuadress) → all five placeholder families present, zero raw values, `scan_residual_pii` clean (DetectAndReplaceAgree for adress).
- [x] T008 [US1] Integration test in `src-tauri/tests/zone_pipeline_scrub.rs` (echo-mock, the real field doc shape): input `Storgatan 5, 114 35 Stockholm` (+ the other three streets) → prompt contains `[Adress 1]`/`[Postnr 1]`, zero raw street strings; sidecar has no banner (SC-001).

## Phase 4: User Story 2 — Precision: no false-positive street redactions (P1)

**Goal**: only Capital+included-suffix+number triads move; everything else byte-identical.
**Independent test**: `plan 3`, `Storgatan är avstängd`, `vägen 3 meter`, `motorled 4` unchanged.

- [x] T009 [P] [US2] Unit tests in `pii_scrub.rs` (negatives): `plan 3`, `Plan 3`, `Storgatan är avstängd`, `vägen 3 meter bort`, `motorled 4`, `park 5`, `Plats 7` → `out.adress == 0` AND `out.text == input`. Plus the tail case: `Storgatan 5 och Lillgatan` → only `Storgatan 5` replaced, `och Lillgatan` (no number) untouched (SC-002).
- [x] T010 [P] [US2] Unit test in `pii_scrub.rs`: UTF-8 adjacency — `ångrenseröd Köpmangatan 3 åäö` → street replaced, Swedish neighbors intact (FR-012); idempotence on `[Adress N]`.

## Phase 5: User Story 4 — Phone captured in full (P2)

**Goal**: `070-123 45 67` → `[Telefon 1]` with no tail; existing forms unchanged.
**Independent test**: scrub the field phone, assert no residual `67`.

- [x] T011 [P] [US4] Unit tests in `pii_scrub.rs`: `070-123 45 67` → `[Telefon 1]`, `!out.text.contains("67")`-style assertion (no tail); `031-22 33 44` → `[Telefon 1]` full; `08-555 12 34` unchanged from pre-046; `+46 70 123 45 67` full (SC-004). Mirror in `pii_sweep.rs` detection if a sweep phone test exists.

## Phase 6: User Story 3 — Prompt preserves [Adress N] + keeps fallback (P2)

- [x] T012 [US3] In `src-tauri/src/prompts/anonymisera.rs`: add `[Adress N]` to the preserve-verbatim bracket list; KEEP the existing "Ersätt varje adress med Adress 1/2" sentence as the fallback (FR-007). Update the comment (spec 046).
- [x] T013 [P] [US3] Update the prompt pinning test (anonymisera.rs): assert the prompt names `[Adress` in the preserve list AND still contains the free-text "Adress" fallback instruction.

## Phase 7: Sweep warning + polish

- [x] T014 [US1] In `pii_sweep.rs`: add `pub adress: usize` to `PiiFindings` (+ `total()`/`is_clean()`); count `RE_ADRESS` in `scan_residual_pii`; add a `"{n} adress"/"{n} adresser"` part to `warning_paragraph` when `f.adress > 0` (sv plural differs: 1 adress / N adresser). Confirm `RE_PLACEHOLDER` already masks `Adress` (it does — no change).
- [x] T015 [P] [US1] Unit tests in `pii_sweep.rs`: RE_ADRESS detect (`Storgatan 5`) + negatives (`plan 3`, no-number); `[Adress 1]` masked (clean); widened-phone detect (`070-123 45 67` one match, no fragment); `warning_paragraph` with `adress==1` says "1 adress", `adress==2` says "2 adresser".
- [x] T016 Run the residual-street warning fragment through the `humanizer` skill (Swedish copy gate, FR-013); record wording.
- [x] T017 Integration test in `zone_pipeline_scrub.rs`: multi-chunk same street in two chunks → one `[Adress N]` index (SC-003); and a non-Anonymisera zone (Sammanfatta) with a street + `070-123 45 67` → prompt contains the RAW street AND raw phone (SC-005/FR-010).
- [x] T018 Full gates: `cd src-tauri && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check`; `npm test && npm run lint && npm run typecheck && npm run test:e2e`. Verify FR-011: no log macro touches a street value (the existing chunked_path_privacy no-log test over pii_scrub still passes, now transitively covering Adress).
- [~] T019 Manual real-model re-test (app is live in tauri dev — Johan re-drops the same file; deterministic path proven by the echo-mock integration tests): re-drop `juradrop-test/03-kantfall/postnummer-adresser-kantfall.docx` in `tauri dev` — the four streets must now be `[Adress N]` and `070-123 45 67` fully scrubbed (the exact live-test that surfaced this).

## Dependencies

- T002 (RE_ADRESS) + T003 (RE_PHONE) foundational → BLOCK T005, T011, T014, T015.
- US1 (T004→T005→T006/T007→T008→T014/T015); US2 (T009/T010) after T005; US4 (T011) after T003; US3 (T012→T013) independent once the module compiles.
- T016 finalizes T014's warning string; polish (T016–T019) last.

## MVP

US1 + US2 (T002, T004–T010) — streets deterministically scrubbed with zero collateral corruption. US4 (phone fix), US3 (prompt), and the sweep warning layer on top.
