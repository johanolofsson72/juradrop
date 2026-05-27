# Tauri commands contract — Spec 007

Four new Tauri commands registered via `tauri::generate_handler!` in `src-tauri/src/lib.rs`. All return `Result<(), String>` where the error string is for developer diagnostics only — never user-facing.

## `check_for_updates_now`

```rust
#[tauri::command]
pub async fn check_for_updates_now(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
) -> Result<(), String>;
```

**Behaviour** (per FR-005):
- Reads the current `Updater.state`.
- If state is `Unknown | UpToDate | Failed`, transitions to `Checking` and triggers the plugin's `app.updater()?.check().await`. Maps the result to `Available | UpToDate | Failed` per the resolution rules.
- If state is `Checking | Downloading | ReadyToInstall | Restarting | Available`, returns `Ok(())` immediately (silent no-op).
- Emits a fresh `juradrop://update-status` event for every state transition.

**Errors**: Returns `Err(message)` only if the plugin's `app.updater()` call itself fails (e.g. plugin not registered). The user-facing failure path goes through `UpdateStatus::Failed`, not the command's `Err`.

## `install_update_now`

```rust
#[tauri::command]
pub async fn install_update_now(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
) -> Result<(), String>;
```

**Behaviour** (per FR-006 + FR-008 + FR-009):
- Requires current `Updater.state == Available`. Returns `Err("state is not Available")` otherwise (a defensive error — the UI should never call this in another state because the button is hidden).
- Transitions `Available → Downloading`, calls `update.download(on_chunk, on_done)`, emits `juradrop://update-status` events with each new integer percent.
- On success, holds the downloaded bytes in `Updater.downloaded_bytes` and transitions `Downloading → ReadyToInstall`. Does NOT call `update.install` automatically — the user must click "Starta om" first.
- On failure, maps the plugin error to `UpdateFailure` and transitions to `Failed`.

## `confirm_restart_install`

```rust
#[tauri::command]
pub async fn confirm_restart_install(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
) -> Result<(), String>;
```

**Behaviour** (per FR-008 + FR-009):
- Requires current `Updater.state == ReadyToInstall`.
- Reads `any_zone_processing(&app_state)`:
  - If false: transitions `ReadyToInstall → Restarting`, calls `update.install(downloaded_bytes)` (the process exits inside).
  - If true: sets `pending_restart_consent = true`, emits a fresh `UpdateStatus::ReadyToInstall { deferred: true }`. The fire-on-idle logic in `deferral.rs` handles the eventual restart.

## `cancel_deferred_restart`

```rust
#[tauri::command]
pub fn cancel_deferred_restart(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
) -> Result<(), String>;
```

**Behaviour** (per FR-009):
- Requires `Updater.state == ReadyToInstall && pending_restart_consent == true`.
- Sets `pending_restart_consent = false`. Emits `UpdateStatus::ReadyToInstall { deferred: false }`. The user is back to "needs to click Starta om explicitly" mode.

## `dismiss_update_indicator`

```rust
#[tauri::command]
pub fn dismiss_update_indicator(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
) -> Result<(), String>;
```

**Behaviour** (per FR-018):
- Requires `Updater.state ∈ {Available, ReadyToInstall}` — dismissal is meaningful only when the badge is visible.
- Sets `indicator_dismissed = true`. Emits an `UpdateStatus` event so the React layer hides the badge.
- The badge re-appears on the next state transition into `Available | ReadyToInstall` (e.g. a fresh check finds a newer version, or the dismissed `Available` transitions to a different available version).
