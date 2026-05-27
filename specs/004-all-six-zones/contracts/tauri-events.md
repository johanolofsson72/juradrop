# Tauri event contracts — spec 004

## `juradrop://file-dropped` (NEW)

The OS-level `WindowEvent::DragDrop::Drop` event is captured Rust-side and re-emitted to the WebView so the WebView can resolve which zone was targeted via `document.elementFromPoint`.

Payload shape:

```typescript
interface FileDroppedPayload {
  paths: string[];
  position: { x: number; y: number };  // CSS pixels (Rust converts from physical)
}
```

Rust emits the event from `lib.rs::handle_drag_drop_event` on every `DragDropEvent::Drop`. JS subscribes via `subscribeFileDropped(cb)` (in `tauri-bridge.ts`).

Resolution flow on the JS side:

```typescript
subscribeFileDropped(({ paths, position }) => {
  const el = document.elementFromPoint(position.x, position.y);
  const zoneEl = el?.closest<HTMLElement>('[data-zone-id]');
  if (!zoneEl) return; // drop outside any zone — silently ignore
  const zoneId = zoneEl.dataset.zoneId as ZoneId;
  dispatchToZone(zoneId, paths);
});
```

**Privacy note**: paths flow through the Rust event payload, NOT the HTML5 drag-drop API. The WebView never reads file bytes; it only learns the OS path strings for the purpose of forwarding them back into Rust dispatch via `dispatch_to_zone`.

## `juradrop://zone/<slug>` (NEW — six channels)

One channel per `ZoneId`. The payload shape (`ZoneSnapshot`) is unchanged from spec 003.

Channels:
- `juradrop://zone/sammanfatta`
- `juradrop://zone/tillengelska`
- `juradrop://zone/tillsvenska`
- `juradrop://zone/punktlista`
- `juradrop://zone/anonymisera`
- `juradrop://zone/forenkla`

Each `DropZone` instance emits ONLY to its own channel. The React layer subscribes per-channel (one `listen()` per component mount).

## `juradrop://sammanfatta` (DEPRECATED — kept for compatibility during refactor)

Spec 003's single-zone channel is migrated to `juradrop://zone/sammanfatta`. During Phase 3 of spec 004, a short compatibility window may keep both names emitting; final implementation drops the old name.

## Spec 002 events carried forward

- `juradrop://status` — unchanged. The Rust status listener (T038 spec 003) still calls `refresh_disabled` on every zone when this fires.
- `juradrop://progress` — unchanged.

## Privacy boundary (unchanged from spec 003)

No event payload carries document content. `progress_hint` strings are pre-defined Swedish phrases. `Redacted<String>` never crosses to the WebView.
