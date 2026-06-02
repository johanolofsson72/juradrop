# Data Model: Tier-download idle timeout

This is a liveness-hardening change. It introduces **no new domain entity, no new enum variant, and no new persisted state**. The "data" is one constant and the reuse of existing types. Captured here for completeness and to make the no-new-state claim auditable.

## Constants (new)

| Name | Type | Value | Location | Requirement |
|---|---|---|---|---|
| `PULL_STREAM_IDLE_TIMEOUT` | `Duration` | `Duration::from_secs(90)` | `src-tauri/src/sidecar/client.rs` | FR-001, FR-007, Clarifications Q1 |

Justification for 90 s: see research.md R-005. Production-only default; tests inject a shorter value via the new method parameter (R-003).

## Constants (existing — referenced, unchanged)

| Name | Value | Location | Relationship |
|---|---|---|---|
| `MODEL_PULL_TIMEOUT_SECONDS` | `300` | `src-tauri/src/sidecar/commands.rs` | The bundled (spec 008) pull's **total-duration** cap. UNCHANGED. The new idle guard is an *inner* bound; the bundled path keeps this *outer* total cap AND gains the idle guard (FR-008). |
| connect timeout | `5 s` | `client.rs` pull client | UNCHANGED. Covers the connect phase; the idle guard covers the streaming body phase. |

## Types (existing — reused, unchanged)

| Type | Location | Role in this feature |
|---|---|---|
| `ClientError::Timeout` | `client.rs` | The idle timeout returns this variant. Already exists; no new variant. |
| `From<reqwest::Error> for ClientError` | `client.rs` | Maps `is_timeout()` reqwest errors to `ClientError::Timeout`. Unchanged; the new path constructs `ClientError::Timeout` directly on `Elapsed`. |
| `DownloadFailure::Network` | `settings/tier_download.rs` | The category an idle timeout lands in. `categorise_failure(ClientError::Timeout) => Network` already exists. No new category. |
| `DownloadPhase::Error` | `settings/tier_download.rs` | The terminal-ish state the tier download settles into. Reached via the existing `spawn_pull_task` `Err(e)` arm. No new phase. |
| `PullEvent` | `client.rs` | Progress/Completed/Failed events from the stream. Unchanged — an idle timeout produces NO `PullEvent`; it short-circuits the loop with `Err`. |

## State machine (existing — one edge gains a new cause)

The spec-027 `TierDownload.status` machine is **unchanged in shape**. The idle timeout adds a new *cause* for the existing `downloading -> error` edge:

```
not_pulled --StartDownload-->        downloading
downloading --DownloadCompleted-->   pulled        (terminal)
downloading --DownloadFailed-->      error         ← idle timeout is a NEW way to take this edge
downloading --CancelDownload-->      not_pulled
error       --RetryDownload-->       downloading
```

The new internal stream lifecycle that drives it (modeled in spec.allium as `PullStream.outcome`):

```
streaming --chunk received--> (idle clock reset to 0, stays streaming)
streaming --success line-->   completed
streaming --error envelope/transport--> failed
streaming --silent > 90s-->   silent_too_long  → ClientError::Timeout → DownloadFailure::Network
```

## Invariants (enforced by code + tests)

| Invariant | Source | How enforced |
|---|---|---|
| `downloading` is not a terminal sink (liveness) | spec.allium `DownloadingEventuallyLeaves`, spec-027 `DownloadingHasIdleBound` | The idle timeout guarantees the stream loop exits on silence; test SC-001. |
| Idle bound is per-chunk silence, not total duration | spec.allium `IdleBoundIsSilenceNotTotal` / `NoUnboundedSilence`; FR-002 | The timeout wraps each `.next()` and resets; test SC-002. |
| Idle timeout ⇒ network category (no new state/copy) | FR-003; `categorise_failure` | `ClientError::Timeout => DownloadFailure::Network`; test SC-003. |
| Cancel vs timeout ⇒ exactly one terminal outcome | spec.allium `SingleTerminalOutcome`; FR-009 | `spawn_pull_task`'s `tokio::select!{ biased; cancel; pull }` — cancel wins the race; pull's `Err` only acts if cancel didn't fire. |
| At most one download (preserved) | spec-027 `AtMostOneDownloading`; FR-010 | Unchanged; the idle timeout only removes a download from `downloading`. The lock re-check comment documents the benign TOCTOU. |
| No new outbound endpoint | FR-006, Principle I | Diff touches only timeout config on the existing localhost pull; existing no-outbound audit tests stay green. |
