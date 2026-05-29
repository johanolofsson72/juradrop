# Tasks — Spec 026 (resilient-ollama-and-drop-ux)

Dependency-ordered. [x] = done (some pre-existing, reconciled).

## Phase 0 — Investigation (foundation)

- [ ] T001 Trace the readiness drift: read `sidecar/status.rs` (UserVisibleStatus computation + any visible-override), `sidecar/manager.rs` (SidecarStatus lifecycle, spawn, stop, wait_ready), `lib.rs` (startup sequence + `refresh_disabled` wiring). Confirm exactly why global=`klar` while per-zone=`disabled`. Record the one signal both will be driven from.

## Phase 1 — Readiness coexistence (Rust, the core)

- [ ] T002 Add `ownership` (`none|reused_external|we_started`) to `OllamaSidecar` (manager.rs).
- [ ] T003 Probe-before-spawn in startup (`lib.rs`): probe `127.0.0.1:11434/api/tags` (~2s) → reuse (status Ready, ownership reused_external) | spawn bundled (we_started) | port_conflict.
- [ ] T004 `stop()` honors ownership: terminate only when `we_started`; never kill a reused external Ollama.
- [ ] T005 Single readiness truth: ensure both `UserVisibleStatus::Klar` and `refresh_disabled` derive from the same `SidecarStatus::Ready`; the reuse path sets it. Add the port-conflict variant to `UserVisibleStatus`.
- [ ] T006 Emit port-conflict as an honest `fel_*` status (no port/Ollama/errno per Principle VII).

## Phase 2 — Frontend surface

- [ ] T007 `tauri-bridge.ts` + `status-store.ts`: add the port-conflict `AppStatus` variant; `statusMessage()` maps it.
- [ ] T008 Humanizer'd Swedish port-conflict copy (no port number / "Ollama" / errno).
- [ ] T009 Verify `DropZone` disabled gate mirrors the single truth (no independent signal); drag-over tracker + Välj fil gate on it.

## Phase 3 — Reconcile already-built work

- [x] T010 Rust `DragDropEvent::Over/Leave` → `juradrop://file-dragover|leave` (lib.rs).
- [x] T011 `createDragHoverTracker` + wiring in App.tsx; `tauri-bridge` subs.
- [x] T012 Window 1160×760 (tauri.conf.json).

## Phase 4 — Tests (functional first, then destructive)

- [x] T013 `drag-hover.test.ts` — 8 cases (DONE).
- [ ] T014 Rust: reuse / spawn / port-conflict readiness resolution unit tests.
- [ ] T015 Rust: shutdown-honors-ownership test (reused → no stop; we_started → stop).
- [ ] T016 Rust/vitest: single-truth regression — header-ready == all-zones-enabled in every state.
- [ ] T017 vitest: Välj fil clickable iff ready; port-conflict status renders Swedish copy.
- [ ] T018 Destructive (≥8 across 6 categories) per quickstart.md.
- [ ] T019 Privacy guard: no new outbound destination; AI host loopback only (denylist).

## Phase 5 — Verify

- [ ] T020 Full `cargo test` + `vitest` + lint + clippy + fmt green.
- [ ] T021 `/tla` on the readiness state machine (drift + invariants IR-1..IR-5).
- [ ] T022 Commit + push; tick register 026.
