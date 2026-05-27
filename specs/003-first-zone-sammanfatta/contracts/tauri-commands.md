# Tauri command contracts — spec 003

The WebView calls these via `@tauri-apps/api/core` `invoke()`. Each command is `#[tauri::command]` annotated in `src-tauri/src/sidecar/commands.rs` and registered in `lib.rs`'s `invoke_handler`.

## `cancel_summary`

```typescript
invoke<void>('cancel_summary', { jobId: string })
```

Rust side:

```rust
#[tauri::command]
pub async fn cancel_summary(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    job_id: String,
) -> Result<(), String> { ... }
```

**Behavior**:
- If the in-flight DropJob's id matches `job_id`, call `cancel_token.cancel()` and return `Ok(())`.
- If the zone is idle or the in-flight job has a different id (stale UI), return `Ok(())` silently — idempotent.
- The cancel propagation triggers the `JobOutcome::Cancelled` transition via the existing rule chain; the WebView observes the result through the next `juradrop://sammanfatta` event.

**Why a separate command rather than a "stop" event**: Tauri events are fire-and-forget; commands return acknowledgements. Cancel is a user action that warrants explicit acknowledgement before the UI updates the cancel button's pressed-state.

## (Existing — referenced for context, no spec 003 changes)

- `get_status` — spec 002, unchanged.
- `give_consent`, `cancel_consent` — spec 002, unchanged.
- `run_roundtrip_dev` — spec 002, unchanged. (Spec 003's summary flow does NOT use this command; it has its own path.)

## Notes

- The drop event itself is NOT a command — it arrives via `WindowEvent::DragDrop` at the Rust layer and is processed there. The WebView never sees a "drop" command. This keeps the privacy boundary clean: the WebView can't poke the summarization pipeline with arbitrary paths (its drop handler is a passive subscriber).
