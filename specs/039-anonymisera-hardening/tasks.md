# Tasks: Anonymisera Hardening — Deterministic Structured-PII Replacement

**Input**: plan.md + spec.md + spec.allium (light track)
**Note**: No UI surface change (frontend-design gate not triggered); no new user-facing
Swedish copy (humanizer gate not triggered — prompt text is model-facing).

## Phase 1: Foundational

- [ ] T001 Widen `RE_EMAIL` in `src-tauri/src/zones/pii_sweep.rs` to match å/ä/ö (upper+lower) in the local part (FR-009); add å-email sweep test; expose the three patterns `pub(crate)` as the single pattern source (DetectAndReplaceAgree)
- [ ] T002 Create `src-tauri/src/zones/pii_scrub.rs`: `ScrubOutcome` + `scrub_structured_pii(&str)` — email→phone→personnummer pass order, back-to-front byte-range splicing, per-category value→index registry (first-occurrence, same value same index), placeholders `[Personnr N]`/`[Telefon N]`/`[E-post N]`; register in `zones/mod.rs` (deny-ratchet tree)
- [ ] T003 Unit tests in pii_scrub.rs: all three categories + shape variants; same-value-same-index; sequential first-occurrence indices; å-email full replacement; UTF-8 adjacency (åäö hugging matches); phone/personnummer overlap precedence; no-match identity; idempotence on scrubbed text; placeholders never re-matched. Plus (analyze A1): extend `src-tauri/tests/chunked_path_privacy.rs` with a pii_scrub.rs no-log-macro static invariant (FR-007 — matched values must never reach a log sink)

## Phase 2: Integration (US1+US2)

- [ ] T004 [US1] Wire the scrub into `DropZone::dispatch` (src-tauri/src/zones/sammanfatta.rs): Anonymisera-only, on the whole extracted text BEFORE `split_into_chunks` (FR-003/FR-005); scrubbed text re-wrapped in `Redacted` immediately
- [ ] T005 [US2] Rewrite `ANONYMISERA_SYSTEM_PROMPT` (src-tauri/src/prompts/anonymisera.rs): keep Person A/Företag X/Adress 1 + same-identity rule; drop the personnummer instruction (pre-replaced); add preserve-bracketed-placeholders-verbatim instruction; update any prompt-pinning tests

## Phase 3: Tests (US1-US3)

- [ ] T006 [US1] Integration: echo-mock anonymisera run with personnummer + phone + email planted in the document → sidecar contains `[Personnr 1]`/`[Telefon 1]`/`[E-post 1]`, ZERO raw values, NO warning banner (SC-001)
- [ ] T007 [US3] Integration: scrubbed input but mock response fabricates `08-555 12 34` → warning banner names 1 telefonnummer (SC-003)
- [ ] T008 [US1] Integration: multi-chunk doc with the same phone in chunk 1 and chunk 3 → both prompts carry the same `[Telefon 1]` (global pre-chunk numbering, SC-002); a second distinct number gets `[Telefon 2]`
- [ ] T009 [US1] Integration: non-anonymisera zone (sammanfatta) with the same PII-laden doc → the model REQUEST prompt contains the raw values (byte-identical input, SC-004)
- [ ] T010 Destructive sweep: hostile shapes — document consisting ONLY of PII; PII adjacent to markers (`--- DOKUMENT SLUTAR ---070-123 45 67`); 1000 distinct personnummer (index growth); PII inside the injection-guard text echoed by a hostile doc; personnummer at exact chunk-boundary positions in a long doc
- [ ] T011 Full gates: cargo test + clippy -D warnings + fmt + vitest + eslint + typecheck + Playwright; /tla triviality statement (pure transformation, no new states); register tick + commit + push

## Dependencies

T001 → T002 → T003 → (T004, T005) → T006-T010 → T011
