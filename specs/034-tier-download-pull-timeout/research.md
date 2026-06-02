# Research: Tier-download idle timeout

Phase 0 — resolve the two open mechanism questions. No `NEEDS CLARIFICATION` markers remained from the spec (the two soft decisions were locked in `/clarify`: 90 s threshold, shared `OllamaClient::pull` placement). These are the HOW decisions deferred from the spec.

## R-001 — Idle-timeout mechanism: `tokio::time::timeout` per-chunk wrapper vs reqwest `.read_timeout()`

**Decision**: Wrap each `stream.next().await` inside `pull` in `tokio::time::timeout(idle, …)`. On `Err(Elapsed)`, return `ClientError::Timeout`. The wrap is re-entered for every chunk, so the idle window **resets on every received byte chunk** — a true inter-chunk silence bound, with no cap on total download duration.

**Rationale**:
- **Legible reset semantics (FR-002).** The reset-per-chunk behaviour is the whole point of an *idle* (not total) timeout. Wrapping each `.next()` makes that reset structurally obvious at the call site, instead of relying on a library's internal read-chunking granularity.
- **Deterministic, decoupled testability (SC-001/SC-002).** The wrapper's behaviour does not depend on whether reqwest's `read_timeout` interacts correctly with `bytes_stream()` across versions (that pairing has had quirks historically). The timeout is plain `tokio` and is provable with a hand-rolled stall server (R-002).
- **Direct mapping into the existing error path.** `ClientError::Timeout` already exists and `categorise_failure` already maps it to `DownloadFailure::Network` (`tier_download.rs`). And `From<reqwest::Error>` already turns any genuine reqwest timeout into `ClientError::Timeout` too — so even a connect-timeout and an idle-timeout converge on the same category. Zero new error variants, zero new categorisation arms.
- **Shared placement = both callers fixed (FR-008, Clarifications Q2).** Living inside `pull`, the guard covers spec 027's tier pull AND spec 008's bundled pull. The bundled path keeps its outer 300 s `tokio::time::timeout` total cap (`commands.rs` `MODEL_PULL_TIMEOUT_SECONDS`) and gains the inner 90 s idle guard — strictly safer, never weaker.

**Alternatives considered**:
- **reqwest `ClientBuilder::read_timeout(Duration)`** (available in 0.12.28). A genuine per-read idle timeout, one declarative line on the pull client. *Rejected* as the primary mechanism because: (a) its firing is coupled to reqwest's internal body-read chunking, making the per-chunk reset less explicit; (b) proving it fires requires the same stall-server test vehicle anyway, so it buys no test simplicity; (c) the explicit `tokio::time::timeout` wrapper is self-evidently correct on read of the loop. *Note*: read_timeout could be added later as cheap defense-in-depth, but YAGNI — one mechanism, clearly tested, is enough.
- **A single total-duration `.timeout(90s)` on the pull client** (mirroring spec 026's `with_base_url` 180 s, or the bundled 300 s). *Rejected outright* — this is exactly the wrong tool the spec warns against (FR-002): it would strangle a legitimately-slow-but-progressing 8–12 GB `gemma3:12b` pull over a slow link. The bug is *silence*, not *slowness*.

## R-002 — Test vehicle: how to simulate a mid-stream stall

**Decision**: A hand-rolled async "stall server" on `tokio::net::TcpListener`:
1. Bind `127.0.0.1:0` (ephemeral port), hand the URL to `OllamaClient::with_base_url`.
2. Accept one connection, read+discard the request bytes.
3. Write a valid `HTTP/1.1 200 OK` with `Transfer-Encoding: chunked`, flush.
4. Optionally write N NDJSON progress chunks (each a valid chunked frame), flushing between them with a delay **shorter** than the injected idle — to prove the clock resets (SC-002).
5. Then **go silent** — hold the socket open, send nothing more (the half-open / stalled condition).

The test calls `pull_with_idle_timeout(model, Duration::from_millis(~200), cb)` and asserts:
- it returns `Err(ClientError::Timeout)` (SC-001),
- within a small multiple of 200 ms (bounded, not "eventually"),
- after consuming the N timely chunks (callback saw them — proves reset, SC-002),
- and `categorise_failure(&err) == DownloadFailure::Network` (SC-003 linkage).

**Rationale**: `wiremock` (the project's existing HTTP mock, used in zone-pipeline + sidecar tests) sends a complete body or delays the *entire* response via `set_delay` — it cannot hold a connection open mid-body. Only a raw socket can reproduce true mid-stream silence. The helper is ~40 lines, lives in the test module, and needs no new dependency (`tokio` `net` + `io` are already available to the test target).

**Alternatives considered**:
- **wiremock `ResponseTemplate::set_delay`** — delays the whole response, exercising connect/overall latency, not body-stream idle. *Rejected*: does not test the actual code path (the wrapper around `bytes_stream().next()`).
- **Refactor `pull` to accept an injectable `impl Stream`** and unit-test with a hand-made stalling stream (`futures::stream` + `pending()`). *Rejected*: larger refactor of a working method for marginal gain; the stall server tests the real reqwest body path end-to-end, which is more honest.

## R-003 — Injecting a short idle for tests without changing production call sites (FR-007)

**Decision**: Extract the pull body into `pub(crate) async fn pull_with_idle_timeout(&self, model: &str, idle: Duration, on_event: …)`. Keep the public `pull(&self, model, on_event)` as a one-line delegate that passes `PULL_STREAM_IDLE_TIMEOUT` (90 s). Production callers (`commands.rs`, `tier_download.rs`) keep calling `pull` unchanged; tests call `pull_with_idle_timeout` with ~200 ms.

**Rationale**: Smallest possible blast radius — no signature change to either production caller, no plumbing of a timeout through the tier/bundled layers, and the 90 s constant lives in exactly one place (FR-007). `pub(crate)` keeps the injectable variant internal to the crate (tests are in-crate or integration tests within the same crate target).

**Alternatives considered**:
- **Add a `Duration` param to `pull`** and thread the production constant through both callers. *Rejected*: touches two unrelated production call sites for no behavioural benefit; the delegate keeps the change local.
- **An env-var / cfg seam** for the idle value. *Rejected*: over-engineered for a value only tests need to shorten; a `pub(crate)` method arg is cleaner and compile-checked.

## R-004 — Confirm `ClientError::Timeout → DownloadFailure::Network` and the retry path are already wired

**Decision**: No change needed in `tier_download.rs` for the failure→error→retry flow. `categorise_failure` already has `ClientError::Timeout => DownloadFailure::Network`; `spawn_pull_task`'s `Err(e)` select arm already sets `phase = Error, failure = categorise_failure(&e)` and emits the `error` frame; spec 027's `RetryDownload` already restarts from `error`. The idle timeout is just one more upstream way `pull` returns `Err` — it rides the existing rails.

**Rationale**: Verified by reading `tier_download.rs::categorise_failure` and `spawn_pull_task`. This is what makes the feature a few-line change rather than a new state machine — exactly the spec's intent (FR-003/FR-005, no new state/copy).

## R-005 — Threshold value justification (locks Clarifications Q1 = 90 s)

**Decision**: `PULL_STREAM_IDLE_TIMEOUT = Duration::from_secs(90)`.

**Rationale**: A live `/api/pull` against a reachable registry emits NDJSON status/progress lines sub-second while bytes flow; the longest legitimate *silent* phases are registry-side `verifying sha256 digest` / `writing manifest` pauses, which are seconds, not minutes. 90 s sits an order of magnitude above any realistic inter-chunk gap yet well below user-give-up, and is the same order of magnitude as the bundled path's 300 s total cap — but it governs *silence*, so it cannot fire on a slow-but-progressing large pull. Lower (e.g. 15–30 s) risks false positives on a slow disk flush after a big layer; higher (e.g. 5 min) needlessly extends the dishonest "downloading" window the GAP is about.
