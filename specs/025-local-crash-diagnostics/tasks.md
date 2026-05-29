# Tasks: Opt-in local crash diagnostics (Spec 025)

- [ ] T001 `src-tauri/src/diagnostics/mod.rs`: `DiagnosticEvent` enum + `Diagnostics` struct (is_enabled/set_enabled/log_event/log_path) + global OnceLock wrapper + consent.json load/persist + 64KB size cap. Wire `pub mod diagnostics;` in lib.rs.
- [ ] T002 [P] Unit tests in mod.rs: disabled→no write; enabled→content-free line (category+timestamp+version); consent persist+reload; size cap trims; failed write (bad dir) no-ops; log_path shape.
- [ ] T003 `ZoneFailure::tag(&self) -> &'static str` in errors.rs (content-free serde tags) + test.
- [ ] T004 `diagnostics/commands.rs`: `set_diagnostics_enabled` + `get_diagnostics_status`; register in lib.rs invoke_handler; call `diagnostics::init(app_data_dir/diagnostics)` at startup.
- [ ] T005 Wire `log_event`: `finalize_with_failure` (sammanfatta.rs) → ZoneFailureLogged{tag}; sidecar restart path (manager) → SidecarRestart{attempt}.
- [ ] T006 [frontend-design + humanizer FIRST] `SettingsPanelDiagnostics` section: toggle (default OFF) + Swedish explanation (local-only, content-free, off by default) + log path; mount in SettingsPanel; strings in settings-panel-strings.ts + zone... settings fixture (drift); a diagnostics bridge/hook.
- [ ] T007 [P] vitest: toggle renders OFF by default, flips via command, shows path; strings drift parity.
- [ ] T008 Gate: full `cargo test` (incl. settings_invariants GREEN + telemetry denylist + no-outbound) + clippy + fmt; full vitest + typecheck + lint.
- [ ] T009 `/tla` (distill + drift vs spec.allium + invariant coverage). Surface findings.
- [ ] T010 Commit + push; tick 025 in `specs/INDEX.md`.

## Dependencies
T001→T002/T004/T005. T003→T005. T006→T007. T008/T009/T010 last.
