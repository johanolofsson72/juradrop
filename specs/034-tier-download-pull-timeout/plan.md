# Implementation Plan: Tier-download idle timeout (stalled pull self-recovery)

**Branch**: `main` (solo / direct-push, no feature branch) | **Date**: 2026-06-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/034-tier-download-pull-timeout/spec.md`

## Summary

`OllamaClient::pull` streams NDJSON progress from `POST /api/pull` via `bytes_stream()` with **no read/idle timeout** — its own comment falsely claims a stall "will surface via the `bytes_stream()` adapter". It will not. A half-open / silently-stalled registry connection blocks `stream.next().await` indefinitely, so the spec-027 tier download sits in `downloading` forever (only Avbryt escapes). This is spec 027's `/tla` GAP-1.

**Approach**: wrap each `stream.next().await` inside `pull` in a bounded `tokio::time::timeout` that **resets on every received chunk** (a true *idle* timeout, not a total-duration cap). On elapse, return `ClientError::Timeout`, which the existing error path already feeds into the tier caller's `categorise_failure` → `DownloadFailure::Network` → existing `error → Försök igen → RetryDownload` machinery. Net change: a handful of lines in `client.rs`, a truth-telling comment, one clarifying comment in `tier_download.rs`, the spec-027 `.allium` amendment (done), and tests. **Zero** new outbound endpoints, UI states, or Swedish strings. Because the idle guard lives in the shared `pull` method, the spec-008 bundled first-run pull also gains it (on top of its existing 300 s total cap — strictly safer).

## Technical Context

**Language/Version**: Rust (2021 edition, `src-tauri`). Backend-only change — no TypeScript/React touched.

**Primary Dependencies**: `reqwest` 0.12.28 (`stream` feature, already enabled), `tokio` (`time` feature — `tokio::time::timeout`), `futures` (`StreamExt`, already used). All already in the tree; **net new deps: 0**.

**Storage**: N/A.

**Testing**: `cargo test`. New idle-timeout coverage uses a hand-rolled `tokio::net::TcpListener` "stall server" helper (accept → flush HTTP 200 + chunked NDJSON → then go silent) because `wiremock` cannot simulate *mid-stream* silence (it sends a whole body or delays the whole response). Idle duration is **injected short** (~200 ms) in tests so the suite never waits 90 s.

**Target Platform**: macOS desktop (Tauri 2.x / WKWebView). Pull path is OS-agnostic Rust.

**Project Type**: Desktop app (Rust core + React frontend). This feature is entirely in the Rust core.

**Performance Goals**: Idle threshold = 90 s of stream silence in production (FR-007). Must never fire during a healthy slow download (FR-002 / SC-002). Test runtime impact: < 1 s (injected ~200 ms idle).

**Constraints**: Must not regress the bundled path's separate 300 s total timeout (FR-008 / SC-004). No new outbound destination (FR-006 / Principle I). No new UI state or Swedish copy (SC-006).

**Scale/Scope**: ~1 production method touched (`OllamaClient::pull`), 1 new const, 1 new injectable variant method, 1 comment correction, 1 clarifying comment, 1–2 new test files. No frontend, no fixtures, no new strings.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment |
|---|---|
| **I. Privacy by Architecture (NON-NEGOTIABLE)** | ✅ **Strengthened.** The idle timeout is a configuration change on an EXISTING localhost-only call (`POST 127.0.0.1:11434/api/pull`). It introduces no new endpoint, no telemetry, no upload. A stalled connection now *terminates faster*, which is strictly more private (no lingering open socket). FR-006 + invariants `LocalhostOnly` / `NoNewOutbound`. |
| **III. Local-Only Inference** | ✅ Unchanged. Same loopback pull endpoint; no remote-host capability added. |
| **VII. Bundled Sidecar — internal plumbing** | ✅ Reinforced. The user never sees the timer; a stall surfaces as the existing plain-Swedish network message, never "connection refused" or a hang. |
| **VIII. Honest Failure States** | ✅ **Strengthened.** Today a stall is a *dishonest* state — the row says "downloading" while nothing is happening. After this, the app honestly reports a network failure and offers retry. No silent forever-state. |
| **V. Swedish-First UI, English-First Code** | ✅ No new user-facing strings; reuses spec 027's network-failure copy. English code/comments. |
| **II / IV / VI / IX** | ✅ Not implicated (no install, service, native-UI, or licensing surface touched). |

**Result: PASS. Zero violations. The feature strengthens Principles I and VIII.** No Complexity Tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/034-tier-download-pull-timeout/
├── plan.md              # This file
├── research.md          # Phase 0 — mechanism + test-vehicle decisions
├── data-model.md        # Phase 1 — the (minimal) entities/constants
├── quickstart.md        # Phase 1 — manual + automated verification steps
├── contracts/
│   └── pull-idle-timeout.md   # Phase 1 — the pull-method behavioural contract
├── spec.md
├── spec.allium
└── checklists/requirements.md
```

### Source Code (repository root)

```text
src-tauri/src/sidecar/client.rs
  - NEW const PULL_STREAM_IDLE_TIMEOUT (Duration, 90 s) + doc justification.
  - NEW pub(crate) async fn pull_with_idle_timeout(&self, model, idle: Duration, on_event)
    containing the existing pull body, with each `stream.next().await` wrapped in
    `tokio::time::timeout(idle, …)`; on Elapsed → Err(ClientError::Timeout).
  - pull(&self, model, on_event) becomes a thin delegate passing PULL_STREAM_IDLE_TIMEOUT
    (production callers — commands.rs bundled + tier_download.rs — UNCHANGED).
  - REWRITE the lines 137–141 doc comment that currently lies about stall behaviour.

src-tauri/src/settings/tier_download.rs
  - ADD the FR-010 clarifying comment at the start-download lock re-check documenting
    that the at-most-one-download invariant holds under the lock (benign TOCTOU).
    NO behavioural change.

src-tauri/src/sidecar/client.rs (#[cfg(test)])  — and/or a new integration test file
src-tauri/tests/pull_idle_timeout.rs
  - Stall-server helper + tests: (1) silence settles to Err(Timeout) within ~idle window;
    (2) chunks RESET the idle clock (N timely chunks then stall → all N consumed, error only
    after final silence); (3) the Timeout maps to DownloadFailure::Network via categorise_failure.

specs/027-on-demand-tier-download/spec.allium
  - DONE in /allium step: added invariant DownloadingHasIdleBound (FR-011).
```

**Structure Decision**: Single-module backend change in the existing `sidecar` layer, mirroring how spec 008's bundled timeout and spec 026's connect/total timeouts already live on `OllamaClient`. No new module, no new layer — the smallest incision that satisfies the liveness requirement.

## Complexity Tracking

> No Constitution Check violations. Section intentionally empty.
