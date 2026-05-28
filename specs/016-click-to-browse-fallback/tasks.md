# Tasks: Click-to-browse file picker (Spec 016)

- [ ] T001 Add `tauri-plugin-dialog` to `src-tauri/Cargo.toml`; register `.plugin(tauri_plugin_dialog::init())` in `lib.rs`; add scoped `dialog:allow-open` to `capabilities/default.json`.
- [ ] T002 Add `@tauri-apps/plugin-dialog` to `package.json` deps.
- [ ] T003 Bridge: `pickFileForZone(zoneId)` + a `formatFilterFor(zoneId)` map in `src/lib/tauri-bridge.ts` (Generera=txt/md, others=7); calls dialog `open({multiple:false, filters})` then `dispatchToZone` on non-null.
- [ ] T004 [frontend-design FIRST] Add a "Välj fil" `<button>` to `src/components/DropZone.tsx`, disabled with the drop predicate, Swedish aria-label (humanizer the label).
- [ ] T005 vitest `src/__tests__/DropZone.picker.test.tsx`: click → open() with correct filter → dispatch; cancel(null) → no dispatch; disabled → no-op + button disabled; keyboard (button role, Enter).
- [ ] T006 Gate: typecheck + lint + vitest; `cargo build` + clippy -D warnings + fmt. Telemetry denylist green (SC-005).
- [ ] T007 Commit + push; tick 016 in `specs/INDEX.md`. (Manual: native dialog on real hardware — deferred.)

## Dependencies
T001/T002→T003→T004→T005. T006/T007 last.
