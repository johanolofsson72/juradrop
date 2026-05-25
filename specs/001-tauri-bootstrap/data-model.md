# Phase 1 — Data Model: Tauri Bootstrap

This spec introduces no domain entities. Drop-zone entities, prompt entities, sidecar process entities, settings entities all arrive in later specs (see `deferred` block in `spec.allium`).

What this spec **does** introduce is a minimal runtime state machine for the application + its single window, formalised in `spec.allium` and re-summarised here for the implementer's convenience.

## Runtime entities

### Application

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `status` | `not_running \| running` | Process state | `not_running → running` on launch; `running → not_running` on window close |
| `profile` | `dev \| release` | Build profile | Determined at compile time |
| `capabilities` | `Set<String>` | `src-tauri/capabilities/*.json` | MUST be empty at this spec (FR-019) |
| `window` | `Window?` | Single window | Present iff `status = running` |

**Invariant**: `capabilities.count = 0` at this spec.

### Window

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `title` | `String` | `tauri.conf.json` | Constant `"JuraDrop"` |
| `width` | `Integer` | Initial 900; min 700 | Per FR-015, R-003 |
| `height` | `Integer` | Initial 650; min 500 | Per FR-015 |
| `visibility` | `hidden \| visible \| fullscreen` | OS window state | Visible after launch |
| `appearance` | `light \| dark` | `prefers-color-scheme` media query | Reactive via Tailwind dark variant (R-001) |

**Transitions**: `hidden → visible → fullscreen → visible → hidden` (and `fullscreen → hidden` directly via cmd-Q while in fullscreen). Terminal state: `hidden` (the process exits).

**Invariants**:
- `title = "JuraDrop"` always.
- `width >= 700` and `height >= 500` always (enforced by `tauri.conf.json` `minWidth` / `minHeight`).

## Lifecycle rules (from `spec.allium`)

1. **LaunchDevWindow** — `npm run tauri dev` transitions `Application.status` from `not_running` to `running`, opens the window at 900×650, visibility = visible, appearance = current OS appearance.
2. **LaunchProductionApp** — Same, triggered by Finder double-click of `JuraDrop.app`.
3. **CloseWindowTerminatesApp** — When `Window.visibility transitions_to hidden`, `Application.status = not_running`. Implementation: handle the close-requested event in Tauri and call `app.exit(0)`.
4. **SystemAppearanceChanged** — When the OS appearance flips, all running windows update their `appearance` field. Implementation: zero code needed at this spec — the `prefers-color-scheme` media query is reactive natively (R-001).
5. **ResizeBelowMinimumClamps** — Resize requests below 700×500 clamp at 700×500. Implementation: `minWidth` / `minHeight` in `tauri.conf.json`.
6. **EnterFullscreen** / **ExitFullscreen** — Standard macOS fullscreen via the green stoplight button. Implementation: no code needed; Tauri's default window config permits it.
7. **DeniedCapabilityCallFails** — Any frontend `invoke()` call to a capability not in the allowlist raises a Tauri capability error. Implementation: the empty `permissions: []` array enforces this automatically (R-002).

## Storage

None. No persistence at this spec.

## Network

None outbound, beyond the Vite dev-server loopback at `127.0.0.1:1420` (dev profile only, explicitly excluded from "outbound" by amended FR-016).
