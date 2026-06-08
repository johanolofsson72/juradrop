# Tasks: Postnummer Anonymisering — Deterministic Postcode Scrub + Address Anchor

**Feature**: 045-postnummer-anonymisering | **Track**: light | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Rust-only hardening. Zero dispatch changes — both call sites (`sammanfatta.rs:244` scrub,
`:432` sweep) already route through `pii_scrub` / `pii_sweep`. Postnummer is additive inside
those two modules + the prompt. Tests are MANDATORY (CLAUDE.md: 100% functional coverage).

## Phase 1: Setup

- [x] T001 Confirm baseline green before touching code: `cd src-tauri && cargo test pii_scrub pii_sweep` passes on `main` (captures pre-045 behavior for the byte-identity assertions in US2).

## Phase 2: Foundational (the single pattern source — BLOCKS US1/US2/US4)

- [x] T002 Add `pub(crate) static RE_POSTNUMMER: LazyLock<Regex>` = `r"\b[1-9]\d{2}[\x{00A0} ]\d{2}\b"` in `src-tauri/src/zones/pii_sweep.rs`, beside the existing `RE_*`, with the same `#[allow(clippy::expect_used)]` + `.expect("postnummer regex")` discipline and a comment explaining the `1-9` first digit (real-postnummer domain + phone-0-band reservation) and the space|NBSP separator (Word `.docx` exports). This is FR-005's single source consumed by both scrub and sweep.

## Phase 3: User Story 1 — Canonical postnummer can never survive anonymization (P1)

**Goal**: every canonical spaced postnummer is replaced with `[Postnr N]` before the model.
**Independent test**: echo-mock anonymisera pipeline; input `114 35` → output `[Postnr 1]`, zero raw, no banner.

- [x] T003 [US1] In `src-tauri/src/zones/pii_scrub.rs`: add `Postnr = 3` to the `Category` enum and `Category::Postnr => "Postnr"` to `label()`.
- [x] T004 [US1] In `pii_scrub.rs`: add `(&*RE_POSTNUMMER, Category::Postnr)` to the candidate-collection loop (import it from `super::pii_sweep`), widen the registries array `[Vec<&str>; 3] → [Vec<&str>; 4]`, and add `pub postnummer: usize` to `ScrubOutcome` (set from `registries[Category::Postnr as usize].len()`).
- [x] T005 [P] [US1] Unit tests in `pii_scrub.rs`: `114 35` → `[Postnr 1]`; NBSP form `114\u{00A0}35` → `[Postnr 1]`; same postnummer twice → same index, a distinct one → `[Postnr 2]` (first-occurrence order); `out.postnummer` count correct.
- [x] T006 [P] [US1] Unit test in `pii_scrub.rs`: an all-four-categories document (`19850312-1234`, `070-123 45 67`, `a@b.se`, `114 35`) → all four placeholder families present, zero raw values, `scan_residual_pii` clean (DetectAndReplaceAgree for postnummer too).
- [x] T007 [US1] Integration test in `src-tauri/tests/zone_pipeline_anonymisera.rs` (echo-mock): input `Storgatan 5, 114 35 Stockholm` on Anonymisera → sidecar contains `[Postnr 1]`, zero `114 35`, NO warning banner (SC-001).

## Phase 4: User Story 2 — The scrub does NOT corrupt non-postcode numbers (P1)

**Goal**: only the canonical spaced `[1-9]NN NN` grouping moves; everything else byte-identical.
**Independent test**: scrub a doc with amount/case-number/year-range/unspaced/leading-0 → those tokens unchanged.

- [x] T008 [P] [US2] Unit tests in `pii_scrub.rs` (negative/precision): `15 000` (amount `NN NNN`) unchanged; `T 4521-25` unchanged; `2015–2020` unchanged; `11435` (unspaced) unchanged; `012 34` (leading 0) NOT taken as postnummer; `114  35` (double space) unchanged. Assert `out.postnummer == 0` and `out.text == input` for each (SC-002).
- [x] T009 [P] [US2] Unit test in `pii_scrub.rs`: UTF-8 adjacency — `ångrenseröd 114 35 åäö` → `ångrenseröd [Postnr 1] åäö` (no boundary corruption, FR-011); plus idempotence — scrubbing scrubbed text is a no-op for `[Postnr N]`.

## Phase 5: User Story 3 — The model is told to preserve [Postnr N] (P2)

**Goal**: the prompt's preserve-verbatim list names `[Postnr N]`.
**Independent test**: assert prompt string lists `[Postnr`; echo-mock pipeline shows `[Postnr 1]` passes through.

- [x] T010 [US3] In `src-tauri/src/prompts/anonymisera.rs`: extend the `ANONYMISERA_SYSTEM_PROMPT` placeholder example list (`[Personnr 1], [Telefon 2] och [E-post 1]`) to also name `[Postnr 1]`. Update the leading comment to mention postnummer (spec 045). Model-facing Swedish.
- [x] T011 [P] [US3] Unit test (in `anonymisera.rs` or the prompts pinning test): assert `ANONYMISERA_SYSTEM_PROMPT` contains `[Postnr`. Update any existing prompt-snapshot/pinning test that would now drift.

## Phase 6: User Story 4 — A leaked address line is flagged via its surviving postnummer (P2)

**Goal**: residual postnummer counted + framed as a possible address line in the warning.
**Independent test**: mock output containing `114 35` → banner present, counts postnummer, address framing.

- [x] T012 [US4] In `pii_sweep.rs`: add `pub postnummer: usize` to `PiiFindings`; include it in `total()` and `is_clean()`; count `RE_POSTNUMMER.find_iter(&masked)` in `scan_residual_pii`; add `Postnr` to `RE_PLACEHOLDER` (`\[(?:Person|Personnr|Adress|Telefon|E-post|Postnr)[^\]]*\]`) so `[Postnr N]` never counts as residue (FR-007).
- [x] T013 [US4] In `pii_sweep.rs` `warning_paragraph`: add a `"{n} postnummer"` part (identical sv singular/plural) to the list join, and when `f.postnummer > 0` append the humanizer-reviewed address-anchor sentence after the existing "Granska och ta bort manuellt." sentence (FR-008/FR-012). Final copy comes from T016.
- [x] T014 [P] [US4] Unit tests in `pii_sweep.rs`: detects `114 35` (space) and `114\u{00A0}35` (NBSP); does NOT detect `11435` / `012 34` / `15 000` / `T 4521-25`; `[Postnr 1]` masked (clean); `warning_paragraph` with `postnummer > 0` contains the count AND the address-anchor sentence; with `postnummer == 0` the postnummer fragment + anchor are both absent; multi-category warning lists postnummer in the Swedish join.
- [x] T015 [US4] Integration test in `zone_pipeline_anonymisera.rs` (fabricated-output mock): model output containing raw `114 35` → sidecar warning banner present, reports the postnummer, carries the address framing (SC-004). And a multi-chunk test: same postnummer in chunk 1 + chunk 3 → single `[Postnr N]` index (SC-003).

## Phase 7: Polish & cross-cutting

- [x] T016 Run the address-anchor warning sentence through the `humanizer` skill (Swedish copy gate, FR-012) BEFORE finalizing T013; record the chosen wording.
- [x] T017 Integration test (byte-identity): a non-Anonymisera zone (e.g. Sammanfatta) with a postnummer-laden doc → the prompt/model input contains the RAW `114 35`, proving no scrub leaks outside Anonymisera (SC-005/FR-009).
- [x] T018 Full gates: `cd src-tauri && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check`; `npm test && npm run lint && npm run typecheck && npm run test:e2e` (vitest/Playwright unaffected, run for regression proof, SC-006). Also verify FR-010 holds: postnummer values flow only through the existing stack-bound scrub registry and `ScrubOutcome` carries counts only — confirm no new `println!`/`eprintln!`/log macro touches a postnummer value (the existing no-log invariant test over `pii_scrub`/`pii_sweep` must still pass and now transitively covers the Postnr category).
- [~] T019 Manual real-model verification (deferred to Johan — needs `npm run tauri dev` + real Ollama + file drop; logic deterministically proven by the echo-mock integration tests) per `quickstart.md` (drop a `.docx` with `Storgatan 5, 114 35 Stockholm`; confirm `[Postnr 1]`, precision on `15 000`/`T 4521-25`, address-anchor banner on a fabricated case).

## Dependencies

- T002 (Foundational, the shared `RE_POSTNUMMER`) BLOCKS T004, T012, T014.
- US1 (T003→T004→T005/T006→T007): T004 depends on T003; tests after.
- US2 (T008/T009) depends on US1 implementation (T004) being present.
- US3 (T010→T011) is independent of US1/US2/US4 except the shared module compiling.
- US4 (T012→T013→T014/T015) depends on T002; T013 wording finalized by T016.
- Polish (T016–T019) last; T016 feeds T013's final string.

## Parallel opportunities

- After T004: T005, T006 run in parallel (same file, distinct test fns — sequential commits fine, logically independent).
- After T012: T014 parallel with US1/US3 test authoring.
- T008, T009 parallel with each other.

## MVP

US1 + US2 (T002–T009) is the MVP: postnummer deterministically scrubbed with zero collateral corruption. US3 (prompt) and US4 (sweep anchor) are defense-in-depth layered on top.
