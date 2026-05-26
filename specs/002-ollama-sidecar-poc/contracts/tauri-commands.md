# Contract: Tauri commands

Four `#[tauri::command]` functions are exposed to the WebView. This is the entire WebView→Rust surface introduced at spec 002.

| Command | Args | Returns | Purpose |
|---------|------|---------|---------|
| `get_status` | — | `AppStatus` | One-shot snapshot of current status. Used on mount + as fallback if event subscription drops. |
| `give_consent` | — | `Result<(), String>` | User clicked "Fortsätt" on the FR-019 modal. Persists choice + triggers model pull. |
| `cancel_consent` | — | `Result<(), String>` | User clicked "Avbryt". Persists choice + transitions to `ModellSaknasAvbruten` status. |
| `run_roundtrip_dev` | — | `Result<u64, String>` | **Dev profile only.** Sends a hardcoded prompt and returns the response length (never the content). Returns `Err("not available in release build")` in release. |

## Type signatures

```rust
#[tauri::command]
async fn get_status(state: tauri::State<'_, AppStateHandle>) -> AppStatus;

#[tauri::command]
async fn give_consent(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppStateHandle>,
) -> Result<(), String>;

#[tauri::command]
async fn cancel_consent(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppStateHandle>,
) -> Result<(), String>;

#[tauri::command]
async fn run_roundtrip_dev(
    state: tauri::State<'_, AppStateHandle>,
) -> Result<u64, String>;
```

## Error semantics

`String` error type is used for the `Result<_, String>` returns so the WebView gets a stable display string. The Rust side maps `SidecarError` and `ClientError` to Swedish-key strings the WebView already knows how to render — same set as `UserVisibleStatus` variants. The Rust side does NOT include English error text or stack traces in these strings.

## Authorization

All four commands target capability `core:app:default` in `capabilities/default.json`. No remote-origin invocation is possible (the WebView is local file:// + Tauri's IPC origin).
