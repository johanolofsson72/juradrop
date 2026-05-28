# Feature Specification: Concurrency stress tests

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: Draft
**Track**: Spec-only (test-only hardening; no behavior change, no new entities/state → no `.allium`, no `/tla`).

**Input**: Each zone's `handle_drop` spawns its own tokio task. Nine zones can be fed at once (drag onto several, or future automation). The per-zone state + auto-clear timer races are guarded individually, but cross-zone behaviour under simultaneous load has never been tested. Add integration tests that fire many drops concurrently and assert: every job completes correctly, no cross-zone contamination (each sidecar gets its own zone's suffix + content), every source stays byte-identical, and the suite finishes in bounded time.

## Why this spec exists

Recommendation #8 from the codebase review. Concurrency bugs (shared-state races, cross-task contamination, deadlocks) are exactly what single-threaded happy-path tests miss. A deterministic concurrent-load test converts "probably fine — zones are independent" into "verified independent under load."

## What's IN scope

| Item | Type |
|---|---|
| `tests/concurrency_stress.rs` | Test |
| All 9 zones dispatched concurrently (per-zone mock), joined, all asserted | Test |
| Repeat over several rounds to shake out races | Test |
| Assert no cross-zone contamination (suffix + content isolation) | Test |
| Assert all sources byte-identical after concurrent load | Test |

## What's OUT of scope

| Item | Reason |
|---|---|
| Changing the dispatch architecture | Tests are read-only on behaviour; if they find a race, that's a follow-up fix |
| Same-zone rapid double-drop semantics | The single-slot + auto-clear race is already unit-tested (spec 003 `auto_clear_to_idle_only_fires_when_state_still_matches`); this spec targets the untested CROSS-zone axis |
| Real-Ollama concurrency | Mocked Ollama (deterministic) isolates the concurrency concern from model latency |

## Clarifications

### Session 2026-05-29 (auto-picked)

- Q: Concurrent across zones or rapid within one zone? → A: **Across zones.** The within-zone slot/timer race is already covered by a spec-003 unit test; the untested axis is many zones at once.
- Q: How many concurrent + how many rounds? → A: **All 9 zones × 3 rounds.** Enough to interleave without ballooning runtime; deterministic mocks keep it reproducible.
- Q: Parallel (spawn) or concurrent (join)? → A: **Concurrent via `join_all`.** Each `handle_drop` already spawns its own internal tokio task, so `join_all` initiating all 9 at once exercises real parallelism inside the dispatch while keeping the test free of Send bounds on the Tauri mock app.

## Requirements

- **FR-001**: `src-tauri/tests/concurrency_stress.rs` MUST dispatch all 9 zones concurrently (each with its own wiremock + mock app + fixture copy) via `futures::future::join_all`, and assert every one produces its correct sidecar.
- **FR-002**: The concurrent batch MUST run ≥ 3 rounds; every round must pass.
- **FR-003**: Each sidecar MUST contain ONLY its own zone's suffix + markers (no cross-zone contamination).
- **FR-004**: Every source file MUST be byte-identical (SHA-256) after the concurrent load.
- **FR-005**: The test MUST complete in bounded time (< 30s) and never deadlock.
- **FR-006**: If a race/contamination/deadlock is found, the offending code MUST be fixed as part of this spec.

## Success Criteria

- **SC-001**: `cargo test --test concurrency_stress` passes — 9 zones × 3 rounds, all sidecars correct.
- **SC-002**: Zero cross-zone contamination across all rounds.
- **SC-003**: All sources byte-identical after concurrent load.
- **SC-004**: Runtime < 30s; no deadlock.
- **SC-005**: Net new deps: 0 (`futures` + `wiremock` + `tauri test` already present).
