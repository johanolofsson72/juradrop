# Contract: Tier-download commands + events (Phase 1)

Replaces the spec-010 stub (`trigger_tier_download` + `juradrop://settings/tier-download-requested` + `subscribeTierDownloadRequested`), all of which are deleted (FR-012).

## Tauri commands (WebView → Rust)

### `start_tier_download(tier: ModelTier) -> Result<(), String>`

Starts a real `/api/pull` for the tier's model.

- **Preconditions**: sidecar ready AND no bundled first-run pull active AND no other tier download in progress AND the tier is not already pulled.
- **On accept**: sets the slot to `Some(TierDownloadState { tier, phase: Downloading, completed: 0, total: 0, failure: None })`, spawns the process-lifetime pull task, emits the first `juradrop://settings/tier-download` event. Returns `Ok(())`.
- **On refuse (not ready / bundled pull active)**: does NOT start a pull; returns `Err("not_ready")` (the frontend shows the `tier_download_err_not_ready` message; the row stays `not_pulled`). FR-010.
- **On refuse (another download active)**: returns `Err("busy")`; UI already disables the button so this is belt-and-braces (FR-009).
- **Idempotent**: a second call while the same tier is downloading is a no-op `Ok(())` (FR rapid-click edge case).

### `cancel_tier_download(tier: ModelTier) -> Result<(), String>`

- **Precondition**: the slot is `Some` and downloading the given tier.
- **Effect**: trips the cancellation token; the pull task exits; the command clears the slot to `None`; emits a terminal event with phase reflecting `not_pulled` (slot cleared). The tier is NOT reported pulled (FR-008).

### `get_tier_download_state() -> Option<TierDownloadStatePayload>`

- Returns the current slot (or `null`). Called by the store on panel mount to hydrate (FR-011 — survives close/reopen).

### `get_tier_pull_state() -> TierPullState` (existing, spec 010)

- Unchanged. Re-queried by the store after a `phase: done`/completion signal so the row flips to `radio_selectable` (FR-005).

## Events (Rust → WebView)

### `juradrop://settings/tier-download`

Payload:

```jsonc
{
  "tier": "Snabb" | "Stor",
  "phase": "downloading" | "error" | "done" | "cancelled",
  "percent": 0..=100,        // present while downloading; derived from completed/total
  "completed": <u64 bytes>,  // 0 until first progress line
  "total": <u64 bytes>,      // 0 ⇒ indeterminate ("Laddar ned…")
  "failure": null | "network" | "disk_full" | "not_ready" | "not_found"
}
```

- **Throttle**: progress events emit when `percent` changed by ≥1 OR ≥500 ms since the last emit (mirrors `spawn_pull_task`), satisfying SC-002 (≥ once/second).
- **Terminal phases**: `done` (→ store re-queries pull-state, row becomes radio), `error` (→ row shows the failure message + Försök igen), `cancelled` (→ row returns to Ladda ned).
- **Channel isolation**: distinct from `juradrop://status` and `juradrop://progress` (those drive the global `klar` header + the spec-008 wizard and MUST NOT be moved by a tier download).

## Frontend bridge (`tauri-bridge.ts`)

| Old (deleted) | New |
|---|---|
| `triggerTierDownload(tier)` | `startTierDownload(tier)` → `invoke('start_tier_download', { tier })` |
| `subscribeTierDownloadRequested(cb)` | `subscribeTierDownload(cb)` → `listen('juradrop://settings/tier-download', …)` |
| `TierDownloadRequest` type | `TierDownloadEvent` type (the payload above) |
| — | `cancelTierDownload(tier)` → `invoke('cancel_tier_download', { tier })` |
| — | `getTierDownloadState()` → `invoke('get_tier_download_state')` |

## Invariants enforced at the boundary

- `start_tier_download` rejects a non-localhost target by construction (model id only; host fixed) — Principle I+III.
- The payload never contains document text — Principle I (FR-013).
- At most one slot ⇒ at most one concurrent download — FR-009 / SC-005.
