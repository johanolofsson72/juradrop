# Implementation Plan: Opt-in local crash diagnostics (Spec 025)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: full

## Summary

A `diagnostics` module with an enum-only, content-safe `log_event` API; opt-in consent (default OFF) persisted in its own file (SettingsSnapshot untouched); a settings-panel toggle + log-path display; wiring into the zone-failure + sidecar-restart sites. No new outbound, no new deps.

## Constitution Check (Principle I is the whole point)

- **I. Privacy:** PASS — default OFF; local-only (own file in app_data_dir); NEVER auto-sent (no network added); content-free BY CONSTRUCTION (enum API, no String content param); consent stored outside SettingsSnapshot so its 2-field invariant is untouched. Reviewed in spec.md § Principle I review.
- **VIII. Honest failure:** PASS — failed diagnostics write no-ops, never crashes.
- **V. Swedish-first:** PASS — settings copy Swedish, humanizer.
- Gate: PASS. The deliberate `settings_invariants.rs` 2-field guard stays GREEN (we don't touch SettingsSnapshot).

## Approach

- `src-tauri/src/diagnostics/mod.rs`:
  - `pub enum DiagnosticEvent { SidecarCrash, SidecarRestart { attempt: u8 }, ZoneFailureLogged { category: &'static str } }` — `category_token()` renders a fixed content-free string.
  - `struct Diagnostics { enabled: AtomicBool, dir: PathBuf, write_lock: Mutex<()> }` with methods `is_enabled/set_enabled/log_event/log_path` — fully testable with a tempdir (no global needed).
  - Global `static DIAG: OnceLock<Diagnostics>` + free fns `init(dir)/is_enabled()/set_enabled()/log_event()/log_status()` delegating to it — used by runtime call sites.
  - Consent in `<dir>/consent.json` (`{"enabled":bool}`, default false, malformed→false). Log in `<dir>/diagnostics.log`. Size cap 64 KB (trim oldest lines on append). Timestamp via chrono (already a dep); version `env!("CARGO_PKG_VERSION")`; OS `std::env::consts::OS`.
- `ZoneFailure::tag(&self) -> &'static str` (errors.rs) — content-free serde tag for the zone-failure category.
- Commands `set_diagnostics_enabled(bool)` + `get_diagnostics_status() -> {enabled, log_path}` in `diagnostics/commands.rs`; registered in lib.rs; `diagnostics::init` called at startup from the resolved app_data_dir.
- Wiring: `finalize_with_failure` (sammanfatta.rs) → `ZoneFailureLogged`; sidecar restart path (manager increment_retry caller) → `SidecarRestart`/`SidecarCrash`.
- UI: a `SettingsPanelDiagnostics` section (toggle default OFF + Swedish explanation + log path), mounted in SettingsPanel; strings in settings-panel-strings + fixture (drift); a small diagnostics store hook calling the commands. frontend-design + humanizer FIRST.
- Tests: Rust unit (enabled→write, disabled→noop, content-free, size cap, consent persist/load, failed-write noop) + a no-outbound/structural content-free test; vitest for the toggle + drift; settings_invariants.rs stays green.

## Phases
1. diagnostics module (methods + global) + ZoneFailure::tag + unit tests.
2. Commands + startup init + register.
3. Wire log_event into the 2 sites.
4. UI section (frontend-design + humanizer) + strings + drift.
5. Gate: cargo test + clippy + fmt + vitest + typecheck + lint; /tla.
