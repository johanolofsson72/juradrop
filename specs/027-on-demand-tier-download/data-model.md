# Data Model: On-demand tier download (Phase 1)

## Entities

### TierDownload (new, in-memory, at most one)

The in-progress / failed download of one non-bundled tier. Exactly zero or one exists at a time (FR-009).

| Field | Type | Notes |
|---|---|---|
| `tier` | `ModelTier` (Snabb \| Stor) | Smart is bundled — never a tier-download target |
| `model_id` | `String` | derived: Snabb→`llama3.2:1b`, Stor→`gemma3:12b` (existing spec-010 map) |
| `phase` | `Downloading \| Error` | the slot only exists while downloading or errored; success/cancel clear it to `None` |
| `completed` | `u64` | bytes pulled so far (0 until first progress line) |
| `total` | `u64` | total bytes; `0` ⇒ indeterminate ("Laddar ned…") |
| `failure` | `DownloadFailure?` | present iff `phase = Error` |

**Rust shape** (`settings/tier_download.rs`):

```rust
pub enum DownloadPhase { Downloading, Error }

pub enum DownloadFailure { Network, DiskFull, NotReady, NotFound }

pub struct TierDownloadState {
    pub tier: ModelTier,
    pub phase: DownloadPhase,
    pub completed: u64,
    pub total: u64,                 // 0 = indeterminate
    pub failure: Option<DownloadFailure>,
}
// Held as: Arc<RwLock<Option<TierDownloadState>>> + Arc<RwLock<CancellationToken>>
```

**Serialised payload** (to the WebView, snake_case serde):

```jsonc
{ "tier": "Stor", "phase": "downloading", "completed": 5300000000,
  "total": 8100000000, "percent": 65, "failure": null }
```

### ModelTier (existing, spec 010)

`Snabb` / `Smart` / `Stor`. Unchanged. `model_id()` already maps each tier. This feature only adds the on-demand acquisition for Snabb + Stor.

### TierPullState (existing, spec 010)

`{ snabb_pulled, smart_pulled, stor_pulled }`, derived live from `/api/tags`. On `DownloadCompleted` the panel re-reads it (`get_tier_pull_state`) so the row flips to `radio_selectable` (FR-005).

## State machine (per tier, frontend row view)

The **row** combines the existing spec-010 pull-state with the new TierDownload slot:

```
                        Ladda ned clicked (ready, no other download)
   not_pulled  ───────────────────────────────────────────────►  downloading
      ▲   ▲                                                          │  │  │
      │   │  cancel (Avbryt)                                         │  │  │ stream done
      │   └──────────────────────────────────────────────────────── │  │  ▼
      │                                                              │  │  pulled ──► (radio_selectable; selecting is spec-010)
      │  retry (Försök igen, ready, no other download)               │  │  [terminal]
      └───────────────────────── error ◄──────────────────────────── │  │
                                   ▲   stream error (categorised)      │  │
                                   └──────────────────────────────────┘  │
   (refused: Ladda ned while not ready / bundled pull active →           │
    stays not_pulled + "AI inte redo ännu" message, no transition) ◄─────┘
```

- **Terminal**: `pulled` (download concern done; selection governed by spec 010).
- **not_pulled** is the resting state for an uninstalled tier AND the post-cancel state.
- **error** is exited only by user-initiated retry (FR-007) — no auto-retry.

Maps directly to the `spec.allium` `TierDownload.status { not_pulled | downloading | pulled | error }` transitions.

## Validation rules / invariants

- **At most one downloading** (FR-009 / SC-005 / invariant `AtMostOneDownloading`): the slot is a single `Option`; `start`/`retry` refuse when it is `Some` and downloading.
- **Error ⇒ failure present** (invariant `ErrorHasReason`): `phase = Error ⟺ failure.is_some()`.
- **Not pulled ⇒ not selectable** (FR-008 / SC-004 / invariant `NotPulledIsNotSelectable`): a cancelled or errored tier is never reported pulled — the slot clears, `get_tier_pull_state` still reports false.
- **Selectable ⇒ pulled** (FR-005 / invariant `SelectableImpliesPulled`): the radio appears only after `/api/tags` confirms the model.
- **Localhost only** (Principle I+III / invariant `LocalhostOnly`): `model_id` ∈ {`llama3.2:1b`, `gemma3:12b`}; pull URL host fixed to `127.0.0.1`.
- **No content on path** (FR-013): the payload carries only tier, phase, byte counts, failure category — never document text.

## New Swedish strings (mirrored: TS `settings-panel-strings.ts` ↔ fixture `settings-panel-strings.json` ↔ Rust drift test)

| Key | Swedish (draft — humanizer pass at impl) |
|---|---|
| `tier_downloading_label` | `Laddar ned…` |
| `tier_download_cancel` | `Avbryt` |
| `tier_download_retry` | `Försök igen` |
| `tier_download_err_network` | `Nedladdningen avbröts. Kolla din uppkoppling och försök igen.` |
| `tier_download_err_disk_full` | `Det finns inte tillräckligt med plats på disken.` |
| `tier_download_err_not_ready` | `AI:n är inte redo ännu. Vänta tills den startat.` |
| `tier_download_err_not_found` | `Modellen kunde inte hittas.` |

Final wording is set during implementation via the humanizer skill (FR-014); the keys are fixed here so the drift test can be written against them.
