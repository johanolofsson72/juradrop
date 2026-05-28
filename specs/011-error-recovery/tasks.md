# Tasks — Spec 011 Error Recovery

**Feature**: Error Recovery (sidecar crash → one-shot retry + Swedish-only failure surface + no-leakage + telemetry-free)
**Spec**: [spec.md](spec.md) • **Plan**: [plan.md](plan.md) • **Allium**: [spec.allium](spec.allium)
**Track**: Full pipeline (per `specs/INDEX.md` row 011)
**Date**: 2026-05-28

User stories from spec.md (priority order):
- **US1 — P1**: Transient crash auto-heals silently
- **US2 — P2**: Second crash holds polite Swedish error until quit
- **US3 — P3**: Crash during model pull → partial download discarded, wizard resumes

## Phase 1 — Setup

- [ ] T001 [P] Create `src-tauri/tests/fixtures/crash-recovery-strings.json` with the two pinned Swedish copy entries (`fel_ovantat` = `AI-motorn svarar inte. Starta om JuraDrop.`, `model_error` = `AI-motorn svarade inte — försök igen`) per `contracts/error-copy-fixture.md`
- [ ] T002 Read `src-tauri/src/main.rs` and verify no `panic::set_hook` call exists; document the finding in this task's commit message. Default Rust panic hook (stderr-only) is the contract (R-007). NO code change.

## Phase 2 — Foundational (verification, NO code change)

These tasks confirm the RATIFIED behavior is intact. Each is a read-only inspection that pins the contract; if any inspection fails, the spec scope expands (likely indicates an unrelated regression).

- [ ] T003 Inspect `src-tauri/src/sidecar/manager.rs:126` — confirm the drain task emits `juradrop://sidecar-crashed` with the exit code payload. Record line number + verbatim quote in this task's commit message.
- [ ] T004 Inspect `src-tauri/src/lib.rs:79-100` — confirm the listener gates on `retry_count_value() == 0`, calls `increment_retry()` only when entering the retry path, and invokes `after_sidecar_ready` on successful re-spawn. Record verbatim quotes.
- [ ] T005 Inspect `src-tauri/src/sidecar/status.rs:41-118` — confirm `UserVisibleStatus::FelOvantat` exists and its render path (in `src/components/WelcomeCard.tsx` or sibling) surfaces the pinned Swedish copy. Record the source-of-truth location.

## Phase 3 — User Story 1 (P1): Silent auto-heal

**Goal**: A single crash within an app session causes one auto-restart attempt; the user sees no FelOvantat.

**Independent test**: Rust integration test inside `crash_recovery_invariants.rs` that uses a mock or direct `OllamaSidecar` instance to verify the retry-counter monotonicity contract — no end-to-end Tauri app needed.

### Implementation + tests

- [ ] T006 [US1] [P] Create `src-tauri/tests/crash_recovery_invariants.rs` with these tests:
  - `retry_counter_starts_at_zero` — fresh `OllamaSidecar::new()`, assert `retry_count_value() == 0`.
  - `increment_retry_returns_post_increment_value` — call `increment_retry()`, assert it returns `1`, then assert `retry_count_value() == 1`.
  - `second_increment_returns_two_but_listener_path_gates_at_one` — call `increment_retry()` twice, assert second call returns `2`; document that the listener gate (`retry_count_value() == 0`) prevents the second call in practice.
  - `retry_counter_never_decrements_within_app_lifetime` — property-style: call any sequence of `increment_retry()` calls; assert subsequent `retry_count_value()` is always ≥ the previous value.
  - `crash_event_channel_name_pinned` — assert the constant string `juradrop://sidecar-crashed` is unique by scanning lib.rs + commands.rs + zones for any other `emit(...)` call with that string (only the manager.rs emit should reference it).
  - `fel_ovantat_copy_pinned` — load the fixture, assert `fel_ovantat` matches the constant `AI-motorn svarar inte. Starta om JuraDrop.` and length ≤ 80 chars.
  - `model_error_copy_pinned` — load the fixture, assert `model_error` matches the constant `AI-motorn svarade inte — försök igen` and length ≤ 80 chars.

## Phase 4 — User Story 2 (P2): Double-crash terminal

**Goal**: A second crash in the same session does NOT trigger a second retry; the welcome card surfaces FelOvantat until quit.

**Independent test**: Rust integration test that simulates two crash-event observations and counts the would-be spawn invocations.

### Implementation + tests

- [ ] T007 [US2] [P] Add to `src-tauri/tests/crash_recovery_invariants.rs`:
  - `listener_path_gates_second_spawn` — simulate the listener flow: first crash → `retry_count_value() == 0` so spawn-path runs; second crash → `retry_count_value() == 1 != 0` so spawn-path is skipped. Assert via a counter that the spawn-path is entered exactly once across two simulated crashes.
  - `exhausted_retry_path_yields_fel_ovantat` — after the simulated second crash, assert the test's mock `error_override` equals the pinned `fel_ovantat` string.

## Phase 5 — User Story 3 (P3): Mid-pull crash recovery

**Goal**: A crash during model pull discards the partial download and the wizard resumes from 0%.

**Independent test**: This is the hardest to test in pure Rust without a real Ollama child; the existing spec 008 wizard-state tests already cover the resume-on-network-drop flow. Spec 011 adds an integration-level assertion that the same code path is reachable from a crash.

### Implementation + tests

- [ ] T008 [US3] [P] Add to `src-tauri/tests/crash_recovery_invariants.rs`:
  - `pull_cancel_token_cancellable_via_crash_path` — construct an `AppState`-like fixture with a `pull_cancel` `CancellationToken`. Simulate the crash listener calling `state.pull_cancel.cancel()`. Assert `is_cancelled() == true`.
  - `after_sidecar_ready_retriggers_pull_when_model_missing_and_consent_granted` — this is a contract-level assertion: read the source of `after_sidecar_ready` and assert it contains the branch that calls `spawn_pull_task` when `model_status == NotPresent && consent.choice == Fortsatt`. (Static-string assertion is sufficient because the runtime path requires a real Tauri app — covered by manual hardware verification.)

## Phase 6 — Cross-cutting (the two NEW grep tests + drift)

These are the only genuinely-NEW code surface this spec adds. They enforce FR-013 (English-leakage denylist), FR-015 (telemetry-library denylist), and FR-016 (no custom panic hook).

### English-leakage denylist (FR-013)

- [ ] T009 [P] Create `src-tauri/tests/english_leakage_denylist.rs`:
  - Define the 14-entry `ENGLISH_LEAKAGE_DENYLIST` constant per `contracts/grep-test-denylists.md`.
  - Recursive walk of `src/**/*.{ts,tsx,json}` and `src-tauri/tests/fixtures/*.json` (excluding `node_modules`, `target`, `dist`, dotfiles, `package.json`, `package-lock.json`).
  - For each file, assert none of the 14 substrings appears (case-sensitive `str::contains`).
  - Additionally assert no file contains the path-prefix `src-tauri/src/` (FR-013 path component).
  - Failure shape: `assert!(violations.is_empty(), "english-leakage denylist hit:\n{}", violations.join("\n"))`.
  - **Self-exclusion**: skip the test file itself since the denylist patterns are intentionally present as constants in source.

### Telemetry-library denylist (FR-015)

- [ ] T010 [P] Create `src-tauri/tests/telemetry_denylist.rs`:
  - Define the 18-entry `TELEMETRY_DENYLIST` constant per `contracts/grep-test-denylists.md`.
  - Read the 4 dep manifests: `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, `package.json`, `package-lock.json`.
  - For each file, lowercase the contents then assert none of the 18 substrings appears.
  - Failure shape: `assert!(violations.is_empty(), "telemetry denylist hit in {file}: {needle}")`.
  - **Self-exclusion**: skip the test file itself (contains the denylist as code).

### No custom panic hook (FR-016)

- [ ] T011 [P] Add to `src-tauri/tests/crash_recovery_invariants.rs`:
  - `no_custom_panic_hook_registered` — recursive walk of `src-tauri/src/**/*.rs`; assert the substring `panic::set_hook` does NOT appear in any file. Documents R-008.

### No outbound HTTP from crash-handling code path (FR-017 + SC-007 — per analyze C1)

- [ ] T011a [P] Add to `src-tauri/tests/crash_recovery_invariants.rs`:
  - `no_outbound_from_crash_listener_closure` — read `src-tauri/src/lib.rs`, locate the closure passed to `.listen("juradrop://sidecar-crashed", ...)`, extract its body (between the matching braces), and assert none of `reqwest::Client`, `tauri::http::`, `tauri_plugin_http::`, `shell::open` appear within that scope. This is a structural assertion — if the listener closure is refactored into a named function, update the test to scan the named function's body instead. Documents the Allium `NoOutboundFromCrashHandlingCode` invariant.

### Cross-language drift (the fixture's TS-side mirror)

- [ ] T012 [P] Create `src/__tests__/crash-recovery-strings-drift.test.ts`:
  - Import the fixture as a JSON module.
  - Assert `fixture.fel_ovantat` equals the pinned constant.
  - Assert `fixture.model_error` equals the pinned constant.
  - Assert both are ≤ 80 chars (UTF-8 char count via spread).
  - Assert the fixture's `model_error` value matches the existing `zone-error-strings.json` `model_error` value byte-for-byte (cross-fixture drift check).

### Final quality gates

- [ ] T013 Run `cd src-tauri && cargo clippy --all-targets -- -D warnings` — fix any clippy diagnostics introduced by the three new test files; zero warnings.
- [ ] T014 Run `cd src-tauri && cargo fmt --check` and `npm run lint && npm run typecheck` — zero issues.
- [ ] T015 Run `cd src-tauri && cargo test` and `npm test -- --run` — all 666+ existing tests still green; new tests from T006-T012 added to the count.
- [ ] T016 Manual real-hardware verification (acknowledged-as-deferred per the spec-register convention): on a real M-series Mac, kill the Ollama PID via Activity Monitor during a Sammanfatta dispatch; observe (a) the zone surfaces ModelError + returns to idle, (b) the welcome card never displays FelOvantat after a single kill, (c) a second kill within the same app session DOES surface FelOvantat. Wall-clock observation of the 10s re-spawn budget is included.

---

## Dependency graph

```text
Phase 1 (T001-T002) ──┐
                      ├──▶ Phase 2 (T003-T005, read-only verification) ──┐
                      │                                                   ├──▶ Phase 3 / US1 (T006)
                      │                                                   ├──▶ Phase 4 / US2 (T007)
                      │                                                   └──▶ Phase 5 / US3 (T008)
                      │                                                                                    
                      └────────────────────────────────────────────────────────────────────────▶ Phase 6 (T009-T016)
```

**Story independence**: US1, US2, US3 share the same test file (`crash_recovery_invariants.rs`) so technically can be implemented in one PR. They're scoped here for clarity of intent.

**MVP scope**: T001 + T006 (fixture + the US1 retry-counter monotonicity tests) — proves the central contract.

## Parallel execution opportunities

- **Phase 1**: T001 + T002 (different files / different concerns)
- **Phase 6**: T009 + T010 + T011 + T012 (different files, no deps)

## Acknowledged-as-deferred

- T016 SC-001 / SC-002 wall-clock observation (manual real-hardware). The Rust tests cover the invariants; the user-perceptible 10s re-spawn budget needs a real M-series Mac to observe.
