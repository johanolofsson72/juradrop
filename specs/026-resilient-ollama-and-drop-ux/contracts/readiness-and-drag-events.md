# Contracts — Spec 026 (Tauri event + status surface)

## Startup readiness (Rust → frontend, existing `juradrop://status` channel)

`AppStatus` (emitted on `juradrop://status`) gains the port-conflict state. The frontend `AppStatus` type + `status-store.ts` mirror it; `statusMessage()` maps it to the humanizer'd Swedish copy.

- `visible: 'klar'` ⟺ `SidecarReadiness.is_ready` ⟺ every zone enabled. (Invariant: these three never disagree.)
- `visible: <port-conflict>` ⟹ honest Swedish message, zones disabled, no crash.

**Reuse contract**: when an external Ollama answers `GET 127.0.0.1:11434/api/tags` with `2xx` at startup, the sidecar reports `SidecarStatus::Ready` with `ownership = reused_external`; no bundled process is spawned; on shutdown no process is killed.

## Drag events (Rust → frontend) — already implemented, formalized here

| Event | Payload | Emitted when |
|---|---|---|
| `juradrop://file-dragover` | `{ x: f64, y: f64 }` (logical px) | `DragDropEvent::Over` |
| `juradrop://file-dragleave` | `()` | `DragDropEvent::Leave` |
| `juradrop://file-dropped` | `{ paths: string[], position: {x,y} }` | `DragDropEvent::Drop` (existing) |

Frontend `createDragHoverTracker` consumes dragover/leave: hit-tests `document.elementFromPoint` → `[data-zone-id]`, sets that zone `dragover` (one at a time), reverts on leave/drop. Gated on `!disabled` (i.e. on `is_ready`).

## Picker (existing)

`pickFileForZone(zoneId)` opens the native dialog; the `DropZone` "Välj fil" button is operable iff `!disabled` (i.e. `is_ready`).

## Window (config)

`tauri.conf.json` `app.windows[0]`: `width=1160`, `height=760`; `minWidth=700`, `minHeight=500` unchanged.

## Invariants exposed to tests

- IR-1: ∀ zone, `zone.disabled == !is_ready` (no drift).
- IR-2: `ownership == reused_external ⟹ no stop request issued`.
- IR-3: at most one zone in `dragover`.
- IR-4: a zone in `dragover` ⟹ `is_ready`.
- IR-5: AI host is loopback only (denylist/privacy guard).
