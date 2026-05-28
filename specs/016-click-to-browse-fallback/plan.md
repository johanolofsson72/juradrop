# Implementation Plan: Click-to-browse file picker (Spec 016)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: light

## Summary

A focusable "Välj fil"-button per zone opens the native picker (filtered to the zone's formats) and dispatches the chosen file through the existing `dispatch_to_zone`. Additive to drag-drop. New dep: `tauri-plugin-dialog` (+1, justified). State machine trivial → skip `/tla`.

## Constitution Check

- **I. Privacy:** PASS — native OS picker, no network; capability scoped to file-open; only surfaces a user-chosen path.
- **II. Zero-CLI / accessibility:** PASS — this is the accessible, discoverable entry point for non-drag users.
- **V. Swedish-first:** PASS — "Välj fil" + Swedish aria-label, via humanizer.
- **VI. Native feel:** PASS — the standard macOS file dialog.
- Gate: PASS. New dep is a standard Tauri-org plugin (MIT, no telemetry).

## Approach

- Rust: add `tauri-plugin-dialog` to Cargo.toml; `.plugin(tauri_plugin_dialog::init())` in lib.rs builder chain; `dialog:allow-open` (scoped) in capabilities/default.json.
- JS: add `@tauri-apps/plugin-dialog`; bridge `pickFileForZone(zoneId)` in tauri-bridge.ts using `open({ multiple:false, filters })` then `dispatchToZone`.
- Format filter: derive from a single map (Generera = txt/md; others = 7). Reuse/centralise with the hint-copy formats where practical.
- UI: `DropZone.tsx` — add a "Välj fil" `<button>` below the hint, disabled with the same predicate as the drop, Swedish aria-label. `frontend-design` BLOCKING; match the existing cancel-link styling (subtle text button).
- vitest: mock `@tauri-apps/plugin-dialog` + the bridge; assert filter, dispatch-on-result, no-op on cancel/disabled, keyboard activation.

## Project structure

```
src-tauri/Cargo.toml, src/lib.rs, capabilities/default.json   # dialog plugin + cap
package.json                                                  # @tauri-apps/plugin-dialog
src/lib/tauri-bridge.ts                                       # pickFileForZone + format map
src/components/DropZone.tsx                                   # Välj fil button
src/__tests__/DropZone.picker.test.tsx                       # NEW
```

## Phases

1. Dep + plugin registration + capability.
2. Bridge `pickFileForZone` + format map.
3. UI affordance (frontend-design first) + humanizer the label.
4. vitest coverage.
5. Gate (typecheck/lint/vitest + cargo build/clippy/fmt). Manual: native dialog on real hardware (deferred).
