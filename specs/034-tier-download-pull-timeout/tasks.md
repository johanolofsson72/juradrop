# Tasks: Tier-download idle timeout (stalled pull self-recovery)

**Feature**: 034-tier-download-pull-timeout | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

**Track**: light (hardening/liveness). `/tla` IS in scope (liveness invariant + amends spec 027 `.allium`). No new UI → no destructive *UI* test category (mirrors spec 033's disposition); the functional tests exercise the actual new failure path.

**Tests**: REQUESTED (the spec's whole value is a testable liveness guarantee — SC-001..SC-003 + no-regression SC-004..SC-006). Test tasks are first-class.

## Phase 1: Setup & grounding (read before touching code)

- [X] T001 Read `src-tauri/src/sidecar/client.rs` lines ~13–190 — confirm exact shapes of `ClientError` (esp. `Timeout`), `From<reqwest::Error>` (`is_timeout() → Timeout`), the `pull` body, the `bytes_stream()` loop, and the misleading doc comment at ~137–141.
- [X] T002 Read `src-tauri/src/settings/tier_download.rs` — confirm `categorise_failure` maps `ClientError::Timeout => DownloadFailure::Network`, that `spawn_pull_task`'s `Err(e)` select arm sets `phase = Error, failure = categorise_failure(&e)`, and locate the start-download lock re-check site that needs the FR-010 clarifying comment.
- [X] T003 Read `src-tauri/src/sidecar/commands.rs` around `MODEL_PULL_TIMEOUT_SECONDS` (~50, ~250) — confirm the bundled path wraps `pull` in an outer 300 s `tokio::time::timeout` and therefore needs NO change (it inherits the inner idle guard for free, FR-008).

## Phase 2: Foundational — the production change (BLOCKS the tests)

- [X] T004 In `src-tauri/src/sidecar/client.rs`, add `const PULL_STREAM_IDLE_TIMEOUT: Duration = Duration::from_secs(90);` near the other timeout constants, with a doc comment justifying 90 s as a *silence* bound (per research.md R-005) and explicitly distinguishing it from a total-duration cap.
- [X] T005 In `src-tauri/src/sidecar/client.rs`, add `pub(crate) async fn pull_with_idle_timeout(&self, model: &str, idle: Duration, mut on_event: impl FnMut(PullEvent) + Send) -> Result<(), ClientError>` containing the current `pull` body, but wrap each `stream.next().await` in `tokio::time::timeout(idle, …)`; on `Err(Elapsed)` return `Err(ClientError::Timeout)`. Preserve all existing behaviour (connect timeout, status check, NDJSON line parsing, `on_event` calls, `Completed`/`Failed`/`EmptyResponse` outcomes).
- [X] T006 In `src-tauri/src/sidecar/client.rs`, reduce `pull(&self, model, on_event)` to a thin delegate: `self.pull_with_idle_timeout(model, PULL_STREAM_IDLE_TIMEOUT, on_event).await`. Verify the public signature is byte-for-byte unchanged so `commands.rs` and `tier_download.rs` callers compile untouched.
- [X] T007 In `src-tauri/src/sidecar/client.rs`, REWRITE the doc comment at ~137–141 that falsely claims a stall "will surface via the `bytes_stream()` adapter rather than a hard timer". State the truth: a per-chunk `tokio::time::timeout` idle guard (`PULL_STREAM_IDLE_TIMEOUT`) resets on every received chunk and yields `ClientError::Timeout` on silence; the 5 s connect timeout still covers the connect phase.
- [X] T008 In `src-tauri/src/settings/tier_download.rs`, add the FR-010 clarifying comment at the start-download lock re-check: document that the at-most-one-download slot is claimed AND re-checked under the same lock, so the TOCTOU-looking re-check is benign (`AtMostOneDownloading` holds; TLC-confirmed in spec 027 `/tla`). NO behavioural change.

## Phase 3: User Story 1 — a stalled download settles to error on its own (Priority: P1)

**Goal**: Prove the liveness guarantee — silence settles to `Err(Timeout)` → network category → existing retry path, with the idle clock resetting per chunk.

**Independent test**: Drive `pull_with_idle_timeout` against a stall server; assert bounded `Err(Timeout)`, reset-on-chunk, and network categorisation. Fully covers US1's acceptance scenarios without the real 90 s wait.

- [X] T009 [US1] Add an async stall-server test helper (`spawn_stall_server(chunks, gap)`) using `tokio::net::TcpListener` bound to `127.0.0.1:0`: accept one connection, drain the request, write `HTTP/1.1 200 OK` + `Transfer-Encoding: chunked` headers, flush N timely NDJSON chunks (gap < idle), then `std::future::pending().await` to hold the socket silent. Place in a new `src-tauri/tests/pull_idle_timeout.rs` (or a `#[cfg(test)] mod` in `client.rs` — match where existing pull/client tests live, discovered in T001).
- [X] T010 [P] [US1] Test `idle_stall_returns_timeout` (contract C-1 / SC-001): stall server with zero (or one) chunk then silence; `pull_with_idle_timeout("stor", 200ms, …)` returns `Err(ClientError::Timeout)` and resolves within a small bounded multiple of 200 ms (e.g. assert it completes well under 2 s).
- [X] T011 [P] [US1] Test `timely_chunks_reset_idle_clock` (contract C-2 / SC-002): pick `idle = 150 ms` and `gap = 60 ms` (gap < idle), stall server sends 3 chunks at 60 ms gaps (cumulative ~180 ms, which EXCEEDS `idle` — proving the bound is per-chunk silence, not a total cap) then goes silent. Assert the callback saw all 3 progress events (clock reset on each chunk) and the call returns `Err(Timeout)` only AFTER the final silence, never mid-stream.
- [X] T012 [P] [US1] Test `idle_timeout_categorises_as_network` (contract C-3 / SC-003): assert `categorise_failure(&ClientError::Timeout) == DownloadFailure::Network` (call the real `tier_download::categorise_failure`), closing the loop from idle timeout to the existing network message + `Försök igen`.

## Phase 4: Polish & cross-cutting (regression gates + no-new-surface proof)

- [X] T013 Run the FULL Rust suite `cd src-tauri && cargo test` and confirm green, paying explicit attention to: the bundled pull total-timeout test (SC-004 / C-6), spec-027 tier_download cancel + retry tests (C-5 / C-7), the Principle-I no-outbound / localhost audit tests (SC-005 / C-8), and cross-language string-drift tests with NO new keys (SC-006).
- [X] T014 [P] Run `cd src-tauri && cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` — both clean.
- [X] T015 [P] Run `npm test` (vitest) and `npm run typecheck` — confirm unaffected/green (the diff touches zero `src/` TS, but the privacy-scan Rust tests walk `../src`, so run the full Rust suite in T013 regardless).
- [X] T016 Run `graphify update .` to keep the knowledge graph current after the Rust change (per CLAUDE.md graphify rule).

## Dependencies & ordering

- **Phase 1 (T001–T003)** before everything — grounding reads.
- **Phase 2 (T004–T008)** before Phase 3 — the tests call `pull_with_idle_timeout`, which T005 creates. T004 → T005 → T006 are sequential (same file, same method). T007 (comment) and T008 (other file) are independent of each other but T008 is a different file `[P]`-able with T004–T007.
- **Phase 3 (T009–T012)**: T009 (helper) before T010–T012. T010/T011/T012 are `[P]` (independent test fns; T012 doesn't even need the server).
- **Phase 4 (T013–T016)** last. T014/T015 `[P]` with each other; T013 first within the phase; T016 after all code/test edits.

## Parallel execution example

```
After T009 (helper exists), run in parallel:
  T010 idle_stall_returns_timeout
  T011 timely_chunks_reset_idle_clock
  T012 idle_timeout_categorises_as_network
```

## Implementation strategy

MVP = US1 (the whole feature). There is exactly one user story; finishing Phase 2 + Phase 3 delivers the complete liveness guarantee. Phase 4 is the no-regression / no-new-surface proof.

**After tasks complete**: run `/tla` (in scope — liveness invariant; verifies `DownloadingEventuallyLeaves` / `NoUnboundedSilence` and re-distills against the amended spec 027 `.allium`), then tick the register and push.

## Notes

- Net new dependencies: **0** (`tokio` `net`/`time`, `reqwest` `stream`, `futures` all present).
- Net new outbound endpoints: **0**. Net new Swedish strings: **0**. Net new UI states: **0**.
- The 90 s production constant is never waited on in tests — `pull_with_idle_timeout` takes an injected short `idle` (FR-007 / R-003).
- **FR-011 is already satisfied** (completed during the `/allium` phase): `specs/027-on-demand-tier-download/spec.allium` gained the `DownloadingHasIdleBound` liveness invariant. No task row — recorded here so coverage is explicit, not a silent gap. `/tla` will re-distill against the amended 027 `.allium`.
