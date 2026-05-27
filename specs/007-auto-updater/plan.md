# Implementation Plan: Auto-updater (Swedish UI, per-zone-aware)

**Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`) | **Date**: 2026-05-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-auto-updater/spec.md` plus the formal contract in [spec.allium](spec.allium).

## Summary

Replace Tauri's built-in modal updater dialog with a non-modal Swedish in-app surface. Build a 7-state `UpdateState` machine in Rust (`Unknown → Checking → UpToDate | Available → Downloading → ReadyToInstall → Restarting | Failed`) owned by the existing `AppState`, mirrored to React via a new Zustand slice. Add a tokio background task that re-checks every 4 hours. Wire the deferral gate so an explicit "Starta om" click while any zone is `Processing` stores consent and auto-fires the install when the last zone returns to non-`Processing`. Six new Swedish-localized `UpdateFailure` variants. End-to-end Rust integration test stubs the manifest endpoint via `wiremock` and drives the state machine through `Unknown → Checking → Available → Downloading → ReadyToInstall`, asserting Swedish copy at every step. The plugin's signature verification stays intact.

## Technical Context

**Language/Version**: Rust 1.95+, TypeScript 5.x. Same toolchain as spec 006.

**Primary Dependencies**: Existing — `tauri`, `tauri-plugin-shell`, `tauri-plugin-updater` (added in spec 006), `tokio`, `parking_lot`, `serde`, `serde_json`, `chrono`, `wiremock` (dev-dep). **No new external deps** — spec 007 is pure UI + state machine + background task built on what's already in the tree.

**Storage**: Filesystem (existing `~/Library/Application Support/JuraDrop/` paths from spec 001). Spec 007 adds NO new persisted state — the `Updater` entity lives entirely in memory and is reset on every app launch. The 4-hour tick's `last_fired_at` is in-memory only.

**Testing**:
- Rust: `cargo test` + new integration test `tests/update_lifecycle.rs` (stubs the manifest endpoint via `wiremock` and drives Unknown → Checking → Available → Downloading → ReadyToInstall; signature-check path is mocked because the plugin's binary-replacement step would require write access to the running .app).
- Vitest: `src/__tests__/UpdateIndicator.test.tsx` for the React component + `src/__tests__/UpdateStore.test.tsx` for the Zustand slice transitions.
- Playwright: 1 new smoke test driving the indicator badge appearance against a built app (best-effort — see spec 003's note about Tauri + Playwright).
- TLA+: state machine has 7 distinct states + 2 actors (Updater + per-zone DropZones) + async transitions = not trivial. `/tla` MUST run after browser tests per the full-track pipeline.

**Target Platform**: macOS 12+ on Apple Silicon. Unchanged.

**Project Type**: Desktop app (Tauri 2.x). Unchanged.

**Performance Goals**:
- SC-001 — `Installera nu` click → new process live ≤ 90 s on broadband.
- SC-003 — Rust integration test drives Unknown → Checking → Available → Downloading → ReadyToInstall in ≤ 5 s wall-clock.
- SC-005 — 4-hour tick within ±5 minutes of every 4-hour anniversary.
- SC-006 — Launch-time check completes within 10 s (normal network), 30 s (slow), and transitions to `Failed { NoNetwork }` within 30 s on unreachable network (DNS timeout dominates).

**Constraints**:
- Principle I (privacy): zero new outbound endpoints. The updater uses ONLY the existing GitHub Releases manifest URL + the DMG URL it references. Logs MUST NOT include release notes content, IP, username, document content, or any user-identifying info.
- Principle V (Swedish-first UI): every user-visible string in Swedish, humanizer-reviewed.
- Principle VIII (Honest failure states): six distinct `UpdateFailure` variants each with specific Swedish copy.
- Per-zone single-flight invariant (spec 003/004): the updater MUST NEVER interrupt a `Processing` zone. The two state machines are independent except for the deferral gate.
- The Tauri plugin's signature verification stays intact — FR-012 codifies that no code path can transition to `ReadyToInstall` without a passing signature check.

**Scale/Scope**: Single user, single window. ~50 lines of new Rust for the state machine + ~30 lines for the background task. ~80 lines of new React for the indicator badge + expandable panel + the bottom-right "Senast kollat" footnote. ~10 new Tauri commands + 1 new event channel.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Privacy by Architecture | Zero new outbound endpoints. Local-logs-only invariant. No telemetry of update install/failure. | ✅ |
| II. Zero-CLI Install | No new external deps. The signed DMG flow from spec 006 stays unchanged. | ✅ |
| III. Local-Only Inference | Updater is independent of the Ollama path; no change to `OllamaClient`. | ✅ |
| IV. Single-User Desktop App | Single in-memory `Updater` entity per running app. No backend, no daemon, no accounts. | ✅ |
| V. Swedish-First UI, English-First Code | All 6 UpdateFailure variants + 7 UI strings in Swedish; humanizer-reviewed. Code/comments/commits English. | ✅ |
| VI. Native macOS Feel | Non-modal indicator badge in the top-right of the main window — matches macOS menu-bar update-indicator conventions. SF Pro typography inherited. No new UI vocabulary. | ✅ |
| VII. Bundled Sidecar Internal | Updater is for the app binary itself, not the Ollama sidecar. Sidecar handling unchanged. | ✅ |
| VIII. Honest Failure States | Six specific `UpdateFailure` variants each with explicit Swedish copy; no generic fallback path (SC-004 enforces 100% coverage). | ✅ |
| IX. Open Source, Free, No Lock-In | Tauri's updater plugin is MIT; the GitHub Releases endpoint is the project's own; no third-party update service. | ✅ |

**All gates pass.** No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/007-auto-updater/
├── spec.md                       # written + 3 auto-picked clarifications
├── spec.allium                   # written + 0 errors
├── plan.md                       # this file
├── research.md                   # Phase 0 — Tauri updater 2.x API, state-machine ownership, wiremock stubbing
├── data-model.md                 # Phase 1 — UpdateState enum, Updater entity, UpdateFailure variants, mirrored types
├── quickstart.md                 # Phase 1 — 7 smoke flows (4 happy + 3 failure)
├── contracts/                    # Phase 1
│   ├── tauri-commands.md         # check_for_updates_now, install_update_now, cancel_deferred_restart, dismiss_update_indicator
│   ├── tauri-events.md           # juradrop://update-status payload schema
│   └── update-failure-vocabulary.md  # 6 variants × Swedish copy + UI mapping
├── checklists/
│   └── requirements.md           # already passing
└── tasks.md                      # Phase 2 — produced by /speckit-tasks
```

### Source Code (repository root)

```text
src-tauri/
├── Cargo.toml                                       # MODIFIED — no new deps; document the spec 007 use of existing crates
├── src/
│   ├── lib.rs                                       # MODIFIED — register check_for_updates_now / install_update_now / cancel_deferred_restart / dismiss_update_indicator commands; spawn the 4h background tick on app startup
│   ├── updater/                                     # NEW MODULE
│   │   ├── mod.rs                                   # NEW — re-exports
│   │   ├── state.rs                                 # NEW — UpdateState enum + Updater entity + transitions
│   │   ├── status.rs                                # NEW — UpdateStatus value (mirrored to React)
│   │   ├── errors.rs                                # NEW — UpdateFailure enum + 6 Swedish strings
│   │   ├── commands.rs                              # NEW — 4 Tauri commands
│   │   ├── tick.rs                                  # NEW — 4-hour background task
│   │   └── deferral.rs                              # NEW — per-zone-busy predicate + deferred-restart logic
│   └── (existing modules unchanged)
└── tests/
    ├── update_lifecycle.rs                          # NEW — integration test via wiremock
    └── (existing tests unchanged)

src/
├── components/
│   ├── UpdateIndicator.tsx                          # NEW — top-right badge + expandable panel
│   └── UpdateRetryFootnote.tsx                      # NEW — bottom-right "Senast kollat" affordance
├── lib/
│   ├── tauri-bridge.ts                              # MODIFIED — add UpdateState type, UpdateFailure type, 4 new command wrappers, juradrop://update-status subscription
│   └── update-store.ts                              # NEW — Zustand slice mirroring UpdateStatus
├── __tests__/
│   ├── UpdateIndicator.test.tsx                     # NEW — render + state-driven copy tests
│   └── UpdateStore.test.tsx                         # NEW — Zustand transition tests
└── App.tsx                                          # MODIFIED — mount UpdateIndicator in the top-right; mount UpdateRetryFootnote in the bottom-right
```

**Structure Decision**: New self-contained `src-tauri/src/updater/` module — six small files, one concern each. The existing `zones/` module is untouched (no spec 003/004 file changes). The React layer adds two new components + one new Zustand slice; the existing zones UI is untouched. Spec 006's `tauri.conf.json` plugins.updater block flips `dialog: true → dialog: false` (one-line edit). The tauri-plugin-updater crate stays at the same version.
