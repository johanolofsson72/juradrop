# Tasks: Hel-rads-adress — Whole-Line Address Collapse + Bracket Fix

**Feature**: 047-hel-rads-adress | **Track**: light | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Rust-only. Zero dispatch changes. Both address patterns share `Category::Adress` (no width change).
Tests MANDATORY.

## Phase 1: Setup
- [x] T001 Baseline: `cd src-tauri && cargo test pii_scrub pii_sweep prompts::anonymisera` green before edits.

## Phase 2: Foundational (the whole-line pattern source)
- [x] T002 In `pii_sweep.rs`: extract the spec-046 street body into `const STREET_BODY: &str` and rebuild `RE_ADRESS` as `Regex::new(&(String::from(r"\b") + STREET_BODY + r"\b"))` (behaviour unchanged — pinned by the existing 046 tests).
- [x] T003 In `pii_sweep.rs`: add `pub(crate) static RE_ADRESS_FULL: LazyLock<Regex>` = `\b{STREET_BODY}\s*,?\s+[1-9]\d{2}[\x{00A0} ]?\d{2}\s+[A-ZÅÄÖ][a-zåäö]+\b` (built via string concat to avoid `format!` brace escaping), with a comment: scrub-only superset; unspaced postnummer accepted only in the street/city context (FR-001/FR-002).

## Phase 3: User Story 1 — Whole line collapses to one placeholder (P1)
- [x] T004 [US1] In `pii_scrub.rs`: add `(&*RE_ADRESS_FULL, Category::Adress)` to the candidate loop, placed BEFORE `(&*RE_ADRESS, Category::Adress)` (import RE_ADRESS_FULL). No registry-width change. Comment that leftmost-longest collapses the full line and discards the street/postnummer sub-spans.
- [x] T005 [P] [US1] Unit tests in `pii_scrub.rs`: `Storgatan 5, 114 35 Stockholm` → `[Adress 1]` (and `out.adress==1`, `out.postnummer==0`, scan clean); `Lökgatan 1, 32456 Stockholm` (unspaced) → `[Adress 1]`; NBSP `Lillgatan 12B, 412 96 Göteborg` → `[Adress 1]`; comma-less `Vasagatan 1 111 20 Stockholm` → `[Adress 1]`; same full line twice → same index (SC-001/SC-003).
- [x] T006 [P] [US1] Unit test in `pii_scrub.rs`: the 4-line field-doc shape → 4 distinct `[Adress 1..4]`, zero raw streets/cities/postnummer, `scan_residual_pii` clean.
- [x] T007 [P] [US1] Unit test in `pii_scrub.rs`: UTF-8 city adjacency — `...Köpmangatan 3, 211 22 Malmö och...` → `[Adress 1] och...` with Swedish neighbours intact (FR-009).

## Phase 4: User Story 2 — Partials + standalones unchanged (P1)
- [x] T008 [P] [US2] Unit tests in `pii_scrub.rs` (regression): street-only `Storgatan 5 (kontoret)` → `[Adress 1]`; standalone `postnr 114 35 ensamt` → `[Postnr 1]` (`out.adress==0`); bare `11435` / `15 000 kr` / `T 4521-25` unchanged (SC-002).

## Phase 5: User Story 3 — Clean brackets via prompt deletion (P2)
- [x] T009 [US3] In `prompts/anonymisera.rs`: DELETE the free-text "Ersätt varje adress … med \"Adress 1\", \"Adress 2\"." sentence; keep `[Adress N]` in the preserve list; update the comment (spec 047, bracket-strip cause removed).
- [x] T010 [P] [US3] Update the prompt pinning tests: assert the prompt does NOT contain `"Adress 1"` (free-text) AND still contains `[Adress 1]` (placeholder). Update the 046 `prompt_keeps_free_text_address_fallback` test — it now asserts the OPPOSITE (instruction removed).

## Phase 6: Integration + polish
- [x] T011 [US1] Integration test in `tests/zone_pipeline_scrub.rs`: the field-doc shape echo-mock → prompt contains `[Adress 1]`–`[Adress 4]`, zero raw street/city/postnummer; sidecar no banner (SC-001).
- [x] T012 [P] [US1] Integration test: multi-chunk same full address line in two chunks → one `[Adress N]` index (SC-003); other-zone (Sammanfatta) gets the RAW line (SC-005/FR-007).
- [x] T013 Full gates: `cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check`; `npm test && npm run lint && npm run typecheck && npm run test:e2e`. FR-008: chunked_path_privacy no-log test still green.
- [~] T014 Manual real-model re-test (app live in tauri dev — Johan re-drops; deterministic path proven by echo-mock integration tests): re-drop the field doc in `tauri dev` — each address line is now ONE `[Adress N]` with brackets kept, city + unspaced postnummer gone.

## Dependencies
- T002 (STREET_BODY) → T003 (RE_ADRESS_FULL) → T004 (candidate). US2 regression after T004. US3 (T009→T010) independent. Polish last.

## MVP
US1 (T002–T007): whole-line collapse. US2 (regression guard) + US3 (clean brackets) complete it.
