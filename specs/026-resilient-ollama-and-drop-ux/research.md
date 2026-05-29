# Research — Spec 026

## R-001 — How to decide "usable Ollama present" vs "port occupied by other"

**Decision**: On startup, before spawning the bundled sidecar, issue the existing readiness probe `GET http://127.0.0.1:11434/api/tags` with a ~2 s timeout (the same check `OllamaSidecar::wait_ready` already polls).
- `2xx` → a usable Ollama is already serving → **reuse**.
- Connection refused (nothing bound) → port free → **spawn bundled** as today.
- Bound but no `2xx` (connect succeeds / times out / non-2xx, i.e. a non-Ollama listener) → **port-conflict** error state.

**Rationale**: Reuses the exact reachability signal the app already trusts; no new health-check surface, no new dependency, loopback-only (Principle I/III).
**Alternatives**: Parsing `lsof`/port tables (fragile, needs entitlements); attempting bind-and-fallback (races, leaves a half-spawned process). Rejected.

## R-002 — Ownership tracking & shutdown

**Decision**: Add an `ownership` notion to the sidecar (`none | reused_external | we_started`). `stop()` terminates the process **only** when `ownership = we_started`. A reused external Ollama is left running.
**Rationale**: FR-006 / SC-007 — killing a process we did not start would disrupt the user's other work and surprise them.
**Alternatives**: Always kill whatever is on the port (rejected — destructive); never kill (rejected — leaks our own spawned sidecar).

## R-003 — The single readiness truth (the actual bug)

**Decision**: Make the reused-external path set the sidecar's internal `SidecarStatus::Ready`. Both consumers already key off `SidecarStatus::Ready`:
- Global `UserVisibleStatus::Klar` is computed in `sidecar/status.rs` from `(SidecarStatus::Ready, ModelStatus::Ready, _)`.
- Per-zone `refresh_disabled(sidecar_ready)` in `lib.rs` passes `sidecar.status() == Ready`.

So once the reused-external case genuinely sets `SidecarStatus::Ready`, the global header and the per-zone gate converge on the same value and **cannot drift** (FR-004 / SC-002).
**Implementation note (verify in code)**: trace why the live dev session showed global `Klar` while zones stayed `disabled` — candidate cause is the `commands.rs` visible-override path setting `Klar` without `SidecarStatus::Ready`, or `refresh_disabled` not firing on the reuse transition. The fix must ensure there is exactly one readiness source feeding both, and add a regression test asserting they agree in every state.
**Alternatives**: Derive `disabled` purely from the frontend `status.visible === 'klar'` and drop the per-zone `disabled` term (simpler frontend, but leaves the backend signals divergent). Kept as fallback; the backend-alignment approach is preferred because it fixes the root, not the symptom.

## R-004 — Port-conflict copy (Principle VII gate)

**Decision**: The port-conflict user message MUST NOT contain a port number, the word "Ollama", or any errno/"EADDRINUSE". It is a calm Swedish status in the `fel_*` family explaining that another program is blocking the AI engine and to close it and restart. Final wording produced via the `humanizer` skill before ship.
**Rationale**: Principle VII (Ollama is invisible plumbing) + VIII (honest, no internals).

## R-005 — macOS drop cursor ("forbidden" icon)

**Decision**: The forbidden cursor in the dev session was a **downstream symptom** of zones being disabled (the readiness bug) and the drop being rejected, not an independent defect. Tauri's OS-level drag-drop (`dragDropEnabled` defaults true) makes the window a valid drop target and shows the copy cursor; once R-003 makes zones genuinely ready and drops are accepted, the cursor resolves. No separate Tauri config change is required. Verified during quickstart hardware testing (the cursor is OS-owned and not directly settable from app code).
**Alternatives**: Setting `dragDropEnabled` explicitly / custom NSView drag handling — unnecessary and out of scope.

## R-006 — Drag-over highlight wiring (already built)

**Decision**: Reconcile the uncommitted work: Rust forwards `DragDropEvent::Over`/`Leave` as `juradrop://file-dragover` / `file-dragleave`; the frontend `createDragHoverTracker` flips the hovered zone to `dragover` and reverts it, gated on readiness. Unit-tested in `drag-hover.test.ts` (8 cases). No redesign — reuses the existing `data-[state=dragover]` styling.

## R-007 — Startup window size (already built)

**Decision**: `tauri.conf.json` default `1160×760` (≥ the 1024 `lg` three-column breakpoint); `minWidth/minHeight` and responsive reflow unchanged.
