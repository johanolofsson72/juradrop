# Research: On-demand tier download (Phase 0)

All decisions resolve against existing code — no NEEDS CLARIFICATION remained after `/clarify`.

## R-001 — Separate tier-download path vs. generalising `spawn_pull_task`

- **Decision**: New `settings/tier_download.rs` module with its own state + channel. Reuse only `OllamaClient::pull(model, on_event)` (already model-generic, `client.rs:134`).
- **Rationale**: `sidecar/commands.rs::spawn_pull_task` (line 179) is hardwired to `DEFAULT_MODEL` and writes the global `model_status` / `progress` / `error_override`, which drive the global `klar` gate and the spec-008 wizard. A tier download must NOT move the global gate or change the active model (FR-004/005, Assumptions: auto-select out of scope). Generalising that function would entangle two flows with different ownership of the global state — high regression risk on the just-shipped spec-026 readiness work.
- **Alternatives rejected**: (a) parameterise `spawn_pull_task` by model + target-state — rejected: couples the bundled `klar` gate to tier pulls; (b) shell out to `ollama pull` — rejected: violates Principle VII (CLI exposure) and bypasses the HTTP seam the tests mock.

## R-002 — Byte-level progress (`PullEvent::Progress`)

- **Decision**: Extend `PullEvent::Progress { percent: u8 }` → `Progress { percent: u8, completed: u64, total: u64 }`. `PullLine` already parses `total`/`completed` (`client.rs:227,229`) and discards them in `into_event` (line 247) — thread them through.
- **Rationale**: FR-003 requires "62 % · 5,0 / 8,1 GB". Percent alone cannot render the byte figures. The bytes are free (already parsed).
- **Impact**: the one bundled callsite (`commands.rs:194` `PullEvent::Progress { percent }`) becomes `Progress { percent, .. }`. No behavioural change to the bundled flow.
- **Alternatives rejected**: new `ProgressBytes` variant — rejected: two progress variants complicate every match for no gain.

## R-003 — Failure categorisation → `DownloadFailure`

- **Decision**: Map to four buckets at the boundary:
  - `not_ready` — refused before starting when sidecar not ready / bundled pull active (checked in the command, never starts a pull).
  - `disk_full` — reuse `has_sufficient_disk_for_pull` (`commands.rs:45`) as a pre-check before spawning; the large `gemma3:12b` (~8 GB) needs the existing 4 GB-min guard raised contextually (see R-007).
  - `not_found` — `PullEvent::Failed(msg)` whose message indicates an unknown model/manifest (e.g. contains "not found"/"manifest").
  - `network` — any other `ClientError` (connect/stream/HTTP) or `Failed(msg)` that is not disk/not-found.
- **Rationale**: FR-006 / SC-003 require four *distinct* Swedish messages. The signals already exist (disk pre-check, sidecar status, the `Failed(String)` payload, `ClientError` variants).
- **Alternatives rejected**: a single generic "nedladdning misslyckades" — rejected: SC-003 demands distinct categories.

## R-004 — At-most-one download state (FR-009)

- **Decision**: `Arc<RwLock<Option<TierDownloadState>>>` held in `SettingsState` (one slot). `start_tier_download` refuses (returns the active state unchanged) if the slot is `Some(downloading)`. The slot identifies which tier + phase + progress + failure.
- **Rationale**: At-most-one (FR-009, SC-005) means a single optional slot is the simplest correct representation; the other tier's button is disabled in the UI by reading "is any download active".
- **Alternatives rejected**: a per-tier map of independent tasks — rejected: allows concurrent pulls, contradicts FR-009.

## R-005 — Survives panel close (FR-011)

- **Decision**: The pull runs on `tauri::async_runtime::spawn` (a process-lifetime task, like `spawn_pull_task`), writing the `SettingsState` slot. The frontend store subscribes to `juradrop://settings/tier-download` AND calls `get_tier_download_state()` on panel mount to hydrate current state.
- **Rationale**: The task is owned by the backend, not the panel/component. Closing the panel only unmounts React; the task and the slot persist. Reopening re-reads the slot.
- **Alternatives rejected**: driving the pull from a React effect — rejected: unmounting the panel would drop the stream (FR-011 violation).

## R-006 — Cancel (FR-008)

- **Decision**: Per-download `CancellationToken` stored alongside the slot; `cancel_tier_download` trips it. The pull task races `client.pull` against `token.cancelled()` via `tokio::select!` (the exact pattern in `spawn_pull_task` lines 225+). On cancel the command clears the slot to `None` (→ row returns to `not_pulled`); the partial Ollama pull is abandoned (Ollama keeps already-fetched layers, so a later retry resumes cheaply — Assumptions).
- **Rationale**: Reuses the proven spec-008 cancellation pattern; keeps status-flip ownership in the command (single responsibility), matching the existing `cancel_model_pull` design.

## R-007 — Disk pre-check threshold

- **Decision**: Keep the existing `has_sufficient_disk_for_pull` (4 GB min) as the pre-check but treat it as a floor; if the pull fails mid-stream with a write/space error, categorise as `disk_full` too. (Exact per-tier size gating — 1.3 GB vs 8.1 GB — is NOT pre-validated beyond the 4 GB floor; over-engineering for v1.)
- **Rationale**: The 4 GB floor already exists and is the conservative guard; Ollama's own pull surfaces space errors mid-stream which we map to `disk_full`. SC-003 only requires the category to be distinguishable, not a perfect pre-flight size computation.

## R-008 — Concurrency with inference (FR-015)

- **Decision**: No gate between a tier download and document processing. The download path and the `generate` path are independent Ollama endpoints; neither blocks the other in our code.
- **Rationale**: Ollama serves `/api/pull` and `/api/generate` concurrently. FR-009's "one at a time" is download-vs-download only. Adding a cross-gate would be over-restrictive and is explicitly out of scope per the clarification.

## R-009 — Progress event channel + throttle

- **Decision**: New channel `juradrop://settings/tier-download`, payload `{ tier, phase, percent, completed, total, failure? }`. Throttle progress emits to the existing rule: emit when percent changed by ≥1 OR ≥500 ms elapsed (mirrors `spawn_pull_task` lines 197–199), which satisfies "≥ once/second" (SC-002).
- **Rationale**: A dedicated channel keeps tier-download progress off the global `juradrop://status` / `juradrop://progress` channels that drive the `klar` header and the wizard.

## R-010 — Byte formatting (sv-SE)

- **Decision**: Frontend formats bytes → GB with a Swedish decimal comma (e.g. `5,0 GB`). The backend ships raw `completed`/`total` u64; the row composes "{percent} % · {done} / {total} GB", or "Laddar ned…" when `total == 0`.
- **Rationale**: Formatting is a presentation concern; keeping raw bytes in the payload keeps the contract simple and testable.

## R-011 — Reconciling the spec-010 stub (FR-012)

- **Decision**: Remove the emit-only `trigger_tier_download` event path and the dead `subscribeTierDownloadRequested` listener. Replace with three real commands (`start_tier_download`, `cancel_tier_download`, `get_tier_download_state`) + the new subscribe helper for `juradrop://settings/tier-download`. Update `SettingsPanelModelTier.tsx`'s `onDownload` to call `start_tier_download`.
- **Rationale**: FR-012 forbids a dead event path remaining. A direct command + a real progress channel is clearer than wiring the old fire-and-forget event into the wizard.
- **Note**: the `TierDownloadRequest` type and `juradrop://settings/tier-download-requested` event are deleted; any test referencing them is updated.
