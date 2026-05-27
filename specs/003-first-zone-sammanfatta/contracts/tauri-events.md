# Tauri event contracts — spec 003

Events flow Rust → WebView via `app.emit(...)`. The WebView subscribes via `@tauri-apps/api/event` `listen()`.

## `juradrop://sammanfatta`

Payload type: `ZoneSnapshot` (see `data-model.md`).

```typescript
{
  state: 'idle' | 'dragover' | 'processing' | 'success' | 'error',
  disabled: boolean,
  failure: ZoneFailure | null,
  job_id: string | null,
  progress_hint: string | null,
}
```

**Emitted on every visible state transition** per FR-009 (within 100 ms). Specifically:

| Transition trigger | Snapshot fields |
|---|---|
| Drag-enter (valid) | `state=dragover, disabled=false, failure=null, progress_hint=null` |
| Drag-leave | `state=idle` |
| Drop accepted | `state=processing, job_id=<uuid>, progress_hint="Sammanfattar…"` |
| Inference completes | `state=success, progress_hint="Klar — öppnar fil…"` |
| Auto-clear from success (after 2 s) | `state=idle, job_id=null` |
| Inference fails | `state=error, failure=<variant>, progress_hint=null` |
| Auto-clear from error (after 5 s) | `state=idle, failure=null` |
| Cancel acknowledged | `state=success, progress_hint="Sammanfattning avbruten"` then auto-clears |
| Sidecar status changes to non-Klar | `state=idle, disabled=true` |
| Sidecar status changes to Klar | `state=idle, disabled=false` |

**Throttling**: not throttled — state transitions are rare events (sub-Hz under all realistic load). Spec 002's progress-stream throttling does NOT apply to spec 003.

## `juradrop://status` (existing, unchanged)

Spec 002 contract. Spec 003 reads it (via the existing store wiring) to decide `disabled`. No new emitters.

## Events the Rust core LISTENS to (not emitted to the WebView)

These are internal to Rust — the WebView never sees them — but documented here so the contract is complete:

- `WindowEvent::DragDrop` (Tauri 2 built-in) — fired by the windowing layer when the user drags files over the window. The Rust core consumes these directly in `lib.rs`'s `on_window_event` handler, validates the file count and extension, and either rejects (emitting a `juradrop://sammanfatta` snapshot with `state=error`) or starts a `DropJob`.

## Privacy boundary

No event payload may carry document content. The `progress_hint` strings are pre-defined Swedish phrases; they never include the source path, the extracted text, or the model response. `Redacted<String>` never crosses this boundary — the WebView is on the wrong side of the privacy line for document text.
