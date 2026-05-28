# Contract — Tauri commands

Tauri `#[command]` functions exposed by `src-tauri/src/settings/commands.rs`. All registered in `lib.rs`'s `invoke_handler`.

## `get_settings`

```rust
#[tauri::command]
pub async fn get_settings(state: tauri::State<'_, SettingsState>) -> Result<SettingsSnapshot, String>
```

**Purpose**: React reads the current snapshot. Cheap — returns the in-memory mirror, no file IO.

**Returns**: The current `SettingsSnapshot` (always valid — defaults apply on missing/malformed).

**Errors**: Never — this command cannot fail. The signature uses `Result` only because Tauri's `#[command]` macro requires it for async functions.

**Frontend caller**: `src/lib/settings.ts`'s `getSettings()` wrapper.

## `set_model_tier`

```rust
#[tauri::command]
pub async fn set_model_tier(
    state: tauri::State<'_, SettingsState>,
    app: tauri::AppHandle,
    tier: ModelTier,
) -> Result<(), SetModelTierError>
```

**Purpose**: Commit a new tier choice. Updates the in-memory snapshot AND persists to disk synchronously (atomic temp-file + rename).

**Errors** (`SetModelTierError`):

| Variant         | When                                                | UI surface                                 |
|-----------------|-----------------------------------------------------|--------------------------------------------|
| `TierNotPulled` | Requested tier's model is not on disk               | The React layer MUST prevent this by reading `TierRowMode` first; this error is a belt-and-braces guard against a buggy UI bypassing the radio gate. Surfaces as a console error in dev, silent in release. |
| `WriteFailed`   | Atomic disk write failed (full disk, permission)    | Snapshot is rolled back to pre-call value; the UI re-reads via `get_settings`. Console error in dev. No Swedish UI error — settings being un-persistable is rare enough that we don't burn UX on it. |

**Frontend caller**: `src/lib/settings.ts`'s `setModelTier(tier)` wrapper. The wrapper does NOT catch the error and propagates to the calling component; the component logs and re-reads.

## `get_tier_pull_state`

```rust
#[tauri::command]
pub async fn get_tier_pull_state(
    app: tauri::AppHandle,
) -> Result<TierPullState, String>
```

**Purpose**: React reads which tiers are pulled. The result drives `TierRowMode` per tier.

**Returns**:

```rust
pub struct TierPullState {
    pub snabb_pulled: bool,
    pub smart_pulled: bool,
    pub stor_pulled:  bool,
}
```

**Implementation**: Delegates to the existing Ollama client used by spec 008 — checks the locally-installed model list via the sidecar's `/api/tags` endpoint (or a cached version of same to avoid hammering the sidecar). Cache TTL: 30 s, invalidated on every `settings://tier_pulled` event.

**Errors**: Wraps any sidecar reachability failure into a String error. React surfaces as "tier pull state unknown — try again after the sidecar finishes booting".

## `trigger_tier_download`

```rust
#[tauri::command]
pub async fn trigger_tier_download(
    app: tauri::AppHandle,
    tier: ModelTier,
) -> Result<(), String>
```

**Purpose**: Click handler for the `Ladda ned` button. Fires the spec 008 first-run-wizard download flow with `source = panel_triggered` and `target_model_id = tier.model_id()`.

**Behaviour**:
1. Calls the spec 008 wizard's internal `start_model_pull(model_id, source: PanelTriggered { target_tier: tier })`.
2. The wizard's existing progress UI takes over the screen (same UI as first-run).
3. On success: wizard emits `settings://tier_pulled` with payload `{ "tier": "<TierName>" }`. The settings store's listener auto-selects that tier (calls `set_model_tier(tier)` internally, which succeeds because the model is now pulled).
4. On failure / cancel: wizard emits its own existing failure / cancel event. The settings store does NOT auto-select. Previously-selected tier remains active.

**Errors**: Returns the wizard's existing error variants (sidecar dead, network failure, etc.) as String. React surfaces via the wizard's existing Swedish error UI — no NEW error category in this command.

**Frontend caller**: `TierRow.tsx`'s `Ladda ned` button onClick.

## Command registration in `lib.rs`

```rust
.invoke_handler(tauri::generate_handler![
    // ... existing commands ...
    settings::commands::get_settings,
    settings::commands::set_model_tier,
    settings::commands::get_tier_pull_state,
    settings::commands::trigger_tier_download,
])
```

## `SettingsState`

Tauri's app-managed state. Wraps a `tokio::sync::RwLock<SettingsSnapshot>`.

```rust
pub struct SettingsState {
    inner: RwLock<SettingsSnapshot>,
}
```

Initialised in the Tauri `setup` callback by calling `settings::file_io::load_or_default()` and inserting the result via `app.manage(SettingsState { inner: RwLock::new(snapshot) })`.

Used by:
- `get_settings`: read lock.
- `set_model_tier`: write lock, then disk write, then drop lock.
- `dispatch_to_zone` (in `sidecar/commands.rs`): read lock at every dispatch — replaces the current `DEFAULT_MODEL` constant read.
