# Tauri command contracts — spec 004

Two zone-aware commands extend spec 003's surface. The drop event itself is still NOT a command — `WindowEvent::DragDrop` arrives Rust-side and is emitted to the WebView as `juradrop://file-dropped` (see `tauri-events.md`).

## `dispatch_to_zone` (NEW)

```typescript
invoke<void>('dispatch_to_zone', { zoneId: ZoneId, paths: string[] })
```

Rust side:

```rust
#[tauri::command]
pub async fn dispatch_to_zone(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    zone_id: ZoneId,
    paths: Vec<PathBuf>,
) -> Result<(), String> {
    let zone = state.zones.get(&zone_id).ok_or("unknown zone")?.clone();
    let client = state.client.clone();
    let sidecar_ready = matches!(state.sidecar.status(), SidecarStatus::Ready);
    zone.handle_drop(app, client, sidecar_ready, paths).await;
    Ok(())
}
```

**Behavior**:
- The WebView calls this *after* resolving `document.elementFromPoint(x, y)` from the `juradrop://file-dropped` payload. The Rust handler routes to the right zone instance.
- Argument validation: an unknown `zone_id` (shouldn't happen from a trusted WebView) returns `Err`; mismatched `paths` length is the zone's own `handle_drop` concern.
- Privacy boundary: the paths flow through the Rust event payload + this command — they never enter the HTML5 drag-drop blob world.

## `cancel_summary` (MODIFIED from spec 003)

```typescript
invoke<void>('cancel_summary', { zoneId: ZoneId, jobId: string })
```

Rust side:

```rust
#[tauri::command]
pub async fn cancel_summary(
    state: tauri::State<'_, AppState>,
    zone_id: ZoneId,
    job_id: String,
) -> Result<(), String> {
    if let Some(zone) = state.zones.get(&zone_id) {
        zone.cancel(&job_id);
    }
    Ok(())
}
```

**Behavior**:
- Idempotent (matches spec 003 spec). Unknown `zone_id` or mismatched `job_id` is a silent no-op.
- The zone parameter scopes the cancel — SC-006 — so cancelling on zone A never touches zone B.

## Spec 003 commands carried forward

- `get_status`, `give_consent`, `cancel_consent`, `run_roundtrip_dev` — unchanged.
