# Feature Specification: Click-to-browse file picker fallback

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: Draft
**Track**: Light (UI feature, single actor, no concurrency; new surface/rule → `.allium`; trivial state → skip `/tla`).

**Input**: Today the only way to feed a zone is OS drag-drop. That is mouse-only — hostile to keyboard and VoiceOver users — and not obviously discoverable. Add a focusable "Välj fil"-affordance per zone that opens the native macOS file picker (filtered to the supported formats) and dispatches the chosen file to that zone through the existing `dispatch_to_zone` path. Drag-drop stays; this is an additional, accessible entry point.

## Why this spec exists

Accessibility + discoverability. A 19-year-old who doesn't realise they can drag a file, or a keyboard/VoiceOver user who can't, currently can't use the app at all. A native file picker is the standard macOS affordance and routes through the same pipeline — zero new processing logic, just a second door into it.

## What's IN scope

| Item | Type |
|---|---|
| `tauri-plugin-dialog` (Rust + JS) + a scoped `dialog` capability | Dep |
| Bridge `pickFileForZone(zoneId)` → native `open()` filtered to supported formats → `dispatchToZone` | Code |
| Per-zone "Välj fil"-affordance: focusable button, Enter/Space activatable, Swedish label | Code (UI) |
| Affordance disabled while the zone is disabled (same gate as drop) | Code |
| vitest: click → open() called with the format filter → dispatch on selection; cancel = no dispatch; disabled = no-op | Test |

## What's OUT of scope

| Item | Reason |
|---|---|
| Multi-file selection | Zones process one file; multi-file already → MultipleFiles failure on drop. Picker is single-select to match. |
| Removing/replacing drag-drop | Additive — drag-drop stays the primary path |
| A global "open file" menu | Per-zone is clearer (the zone IS the choice of operation) |

## Clarifications

### Session 2026-05-29 (auto-picked)

- Q: JS dialog API or a Rust command? → A: **JS `@tauri-apps/plugin-dialog` `open()`** from the bridge, then `dispatchToZone` — matches the existing frontend-drives-dispatch pattern; no new Rust command needed.
- Q: Affordance shape — whole-card click or explicit element? → A: **Explicit "Välj fil" text-button** inside the card. A whole-dashed-area click is surprising and collides with selection; an explicit, focusable affordance is clearer and keyboard-reachable.
- Q: Single or multi select? → A: **Single.** Matches the one-file-per-zone contract; multi-file drops already yield `MultipleFiles`.
- Q: Format filter? → A: **The zone's accepted formats.** Generera → `txt, md`; every other zone → `docx, pdf, txt, md, rtf, pages, odt`. Same set the hint copy advertises.
- Q: Behaviour while the zone is disabled (model not ready / job in flight)? → A: **Affordance disabled too** — same gate as drop; no picker, no dispatch.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Keyboard user opens a file without dragging (Priority: P1)

A student tabs to a zone's "Välj fil"-button, presses Enter, the native picker opens filtered to supported files, they choose one, and the zone processes it exactly as a drop would.

**Independent Test**: vitest — clicking the affordance calls the dialog `open()` with the zone's format filter; resolving with a path calls `dispatchToZone(zoneId, [path])`; resolving with `null` (cancel) calls nothing.

**Acceptance Scenarios**:
1. **Given** a klar Generera zone, **When** the affordance is activated, **Then** `open()` is called with a `txt, md` filter.
2. **Given** any other klar zone, **When** activated, **Then** `open()` is called with the 7-format filter.
3. **Given** the picker is cancelled, **When** it resolves null, **Then** no dispatch happens.
4. **Given** a disabled zone, **When** the affordance is present, **Then** it is disabled and activating it is a no-op.

### Edge Cases

- Enter AND Space activate the button (native `<button>` gives this for free).
- The affordance is in the tab order; `aria-label` is Swedish and names the zone.
- Cancelling the picker leaves the zone idle (no error flash).

## Requirements

- **FR-001**: Add `tauri-plugin-dialog` (Rust) + `@tauri-apps/plugin-dialog` (JS) + register the plugin in `lib.rs` + a scoped `dialog` permission in `capabilities/default.json`.
- **FR-002**: Bridge `pickFileForZone(zoneId: ZoneId): Promise<void>` MUST call the dialog `open({ multiple: false, filters: [...] })` with the zone's accepted extensions, and on a non-null result call `dispatchToZone(zoneId, [path])`.
- **FR-003**: Each `DropZone` card MUST render a focusable "Välj fil"-button (native `<button>`), Swedish `aria-label` naming the zone, activatable by click/Enter/Space.
- **FR-004**: The button MUST be disabled exactly when the zone's drop is disabled (`zoneSnap.disabled || status.visible !== 'klar'`).
- **FR-005**: Generera's filter MUST be `txt, md`; all other zones `docx, pdf, txt, md, rtf, pages, odt`. The filter set MUST mirror the hint-copy formats (single source where practical).
- **FR-006**: Cancelling the picker (null result) MUST NOT dispatch and MUST NOT change zone state.
- **FR-007**: The dialog plugin adds NO outbound network surface (native OS picker only) — Principle I unaffected. Capability scoped to file-open only (no save, no arbitrary fs read beyond the chosen file the user explicitly selects).

## Success Criteria

- **SC-001**: Activating the affordance on a klar zone opens the picker with the correct filter + dispatches the chosen file. Verified by vitest (dialog mocked).
- **SC-002**: Cancel → no dispatch. Verified by vitest.
- **SC-003**: Disabled zone → affordance disabled + no-op. Verified by vitest.
- **SC-004**: Keyboard reachable (button in tab order, Enter/Space). Verified by vitest (role/tabindex + activation).
- **SC-005**: Net new deps: +1 intentional (`tauri-plugin-dialog`); no new outbound traffic. Telemetry denylist green.

## Assumptions

- The native picker itself can't be driven headless; SC-001's *native dialog open* is manual-verify on real hardware. The wiring (filter passed, dispatch on result, no-op on cancel/disabled) is fully covered by vitest with the dialog mocked.
- The dialog plugin is a standard Tauri-org plugin (MIT), no telemetry, no network.
