# Contract: `OllamaClient::pull` idle-timeout behaviour

The behavioural contract of the pull method after this feature. This is the internal Rust API contract (the only "interface" this backend feature exposes); there is no new Tauri command, no new IPC surface, no new HTTP endpoint.

## Method surface

```rust
// Production entry point — UNCHANGED signature. Callers in commands.rs (bundled
// first-run pull) and settings/tier_download.rs (on-demand tier pull) keep calling this.
pub async fn pull(
    &self,
    model: &str,
    on_event: impl FnMut(PullEvent) + Send,
) -> Result<(), ClientError>;

// NEW — injectable idle duration for tests. `pull` delegates to this with
// PULL_STREAM_IDLE_TIMEOUT (90 s). pub(crate): in-crate tests only.
pub(crate) async fn pull_with_idle_timeout(
    &self,
    model: &str,
    idle: Duration,
    on_event: impl FnMut(PullEvent) + Send,
) -> Result<(), ClientError>;
```

## Contract clauses

### C-1 — Bounded idle (FR-001)
GIVEN the response stream has been opened
WHEN no body chunk is received for longer than `idle`
THEN the method MUST return `Err(ClientError::Timeout)`
AND MUST NOT block beyond approximately `idle` past the last received chunk.

### C-2 — Per-chunk reset, not total cap (FR-002)
GIVEN body chunks keep arriving with inter-chunk gaps each shorter than `idle`
WHEN total elapsed time exceeds `idle` (or any multiple of it)
THEN the method MUST NOT time out — the idle clock resets on every received chunk.
AND every received progress chunk MUST still invoke `on_event` as before.

### C-3 — Timeout maps to the network failure category (FR-003)
GIVEN `pull` returned `Err(ClientError::Timeout)` from an idle stall
WHEN the tier caller runs `categorise_failure(&err)`
THEN the result MUST be `DownloadFailure::Network`
AND the tier-download row MUST show the EXISTING network-failure Swedish message and `Försök igen` (no new copy, no new state).

### C-4 — Self-recovery without user action (FR-004, liveness)
GIVEN a tier download is `downloading` and its stream goes permanently silent
WHEN `idle` elapses
THEN the tier download MUST settle to `DownloadPhase::Error` (failure = Network) with NO user action
AND the `downloading` state MUST NOT be reachable forever.

### C-5 — Retry path unchanged (FR-005)
GIVEN a tier download in `error` (failure = Network) caused by an idle timeout
WHEN the user invokes `Försök igen` (RetryDownload)
THEN a fresh pull MUST start (status → `downloading`) via the existing retry code, indistinguishable from any other network-failure retry.

### C-6 — Bundled path not regressed (FR-008)
GIVEN the bundled first-run pull (spec 008) calling `pull`
THEN it MUST retain its outer 300 s total-duration timeout (`MODEL_PULL_TIMEOUT_SECONDS`)
AND additionally benefit from the inner 90 s idle guard (strictly safer).
The existing bundled total-timeout test MUST stay green.

### C-7 — Cancel wins a simultaneous race (FR-009)
GIVEN a tier download is `downloading`
WHEN `Avbryt` (cancel token) and the idle timeout fire at nearly the same time
THEN exactly ONE terminal outcome MUST result (cancelled → `not_pulled`, OR error → `error`), never both, never a stuck row.
(Enforced by the existing `tokio::select!{ biased; cancel.cancelled(); pull_future }` arbitration in `spawn_pull_task`.)

### C-8 — No new outbound (FR-006, Principle I)
THE change MUST add no new network destination. The only target remains `127.0.0.1:11434/api/pull`. Existing no-outbound audit/grep tests MUST stay green.

## Test mapping

| Clause | Test (see quickstart.md) |
|---|---|
| C-1 | `idle_stall_returns_timeout` — stall server, ~200 ms idle, asserts `Err(Timeout)` within bound |
| C-2 | `timely_chunks_reset_idle_clock` — N chunks under idle, then stall; asserts all N seen + error only after final silence |
| C-3 | `idle_timeout_categorises_as_network` — `categorise_failure(Timeout) == Network` |
| C-4 | covered by C-1 (the `pull` Err is what drives `spawn_pull_task` → Error with no user action) |
| C-5 | existing spec-027 retry test stays green against a Network failure |
| C-6 | existing bundled `pull_timeout` test stays green; (optional) bundled-path stall settles |
| C-7 | existing spec-027 cancel test stays green; select arbitration unchanged |
| C-8 | existing Principle-I no-outbound audit tests stay green |
