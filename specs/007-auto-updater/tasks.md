# Tasks: Auto-updater (Swedish UI, per-zone-aware, v0.1 → v0.2 path)

**Spec**: [spec.md](spec.md) · **Allium**: [spec.allium](spec.allium) · **Plan**: [plan.md](plan.md)

**Input**: Spec 007 replaces Tauri's built-in modal updater dialog with a non-modal Swedish in-app surface. 7-state machine in Rust, mirrored to React via Zustand. Per-zone-aware deferral. 4-hour background tick. Six Swedish `UpdateFailure` variants. End-to-end Rust integration test via wiremock.

Total tasks: 43 across 7 phases. Track: **full** (Allium done; /tla still pending after browser tests).

---

## Phase 1 — Setup

- [x] T001 Flip `plugins.updater.dialog` from `true` to `false` in `src-tauri/tauri.conf.json`. Verify the change by running `cd src-tauri && cargo build` — the plugin still compiles because `dialog` is a runtime flag, not a feature flag.
- [x] T002 Create skeleton files (each with `// Spec 007 — placeholder` + module declaration): `src-tauri/src/updater/mod.rs`, `src-tauri/src/updater/state.rs`, `src-tauri/src/updater/status.rs`, `src-tauri/src/updater/errors.rs`, `src-tauri/src/updater/commands.rs`, `src-tauri/src/updater/tick.rs`, `src-tauri/src/updater/deferral.rs`. Add `pub mod updater;` to `src-tauri/src/lib.rs` so the project still compiles.

---

## Phase 2 — Foundational (blocking for every user story)

- [x] T003 [P] Implement the `UpdateState` enum + the `Updater` struct (all fields from data-model.md) + `Updater::new()` + the transition graph as a `transitions(self, new_state: UpdateState) -> bool` method that returns false for illegal transitions, all in `src-tauri/src/updater/state.rs`. Add 8+ unit tests covering: Unknown→Checking legal; Checking→Restarting illegal; ReadyToInstall→Restarting legal; consent flag cleared on transition out of ReadyToInstall; downloaded_bytes cleared on transition back to Failed.
- [x] T004 [P] Implement the `UpdateFailure` enum with `#[error("...")]` Swedish strings (per data-model.md). All six variants. Add unit tests: NoEnglishPrefix (no variant starts with "Error:"), LengthBounded (every variant ≤ 80 chars), NonEmpty, round-trip through serde with snake_case wire form.
- [x] T005 [P] Implement `UpdateStatus` tagged-union (per data-model.md) + `UpdateStatus::from_updater(&Updater) -> Self` in `src-tauri/src/updater/status.rs`. Add unit tests asserting the From impl produces the right tag + payload for each of the 8 states.
- [x] T006 [P] Create `src-tauri/tests/fixtures/update-failure-strings.json` (the 6 Swedish strings keyed by snake_case variant name, plus a `_comment`). Create `src-tauri/tests/update_failure_strings.rs` integration test that asserts every Rust `UpdateFailure::to_string()` matches the fixture byte-for-byte + the fixture has exactly 7 keys (6 variants + `_comment`).
- [x] T007 [P] Update `src/lib/tauri-bridge.ts` to export `UpdateStateTag`, `UpdateFailureVariant`, and `UpdateStatus` types (per data-model.md). Add `subscribeUpdateStatus(callback)` listener wrapper. Add four command wrappers: `checkForUpdatesNow`, `installUpdateNow`, `confirmRestartInstall`, `cancelDeferredRestart`, `dismissUpdateIndicator`.
- [ ] T008 [P] Create `src/components/DropZone.update-errors.ts` mirroring the six Swedish strings (TS-side cross-language mirror, same pattern as `DropZone.errors.ts`). Create vitest `src/__tests__/UpdateFailure.errors.test.tsx` that reads the same JSON fixture and asserts byte-for-byte match.
- [x] T009 Implement `impl From<tauri_plugin_updater::Error> for UpdateFailure` in `src-tauri/src/updater/errors.rs` per the mapping table in `contracts/update-failure-vocabulary.md`. Add 6 unit tests, one per variant, using stub `tauri_plugin_updater::Error` values where the variant is reachable.
- [ ] T010 Add `pub updater: Arc<parking_lot::RwLock<Updater>>` field to the existing `AppState` struct in `src-tauri/src/sidecar/commands.rs` (or wherever AppState lives). Initialise to `Updater::new()` in `AppState::new()`. Run `cargo build` — every test must still compile.
- [x] T011 Register the five new Tauri commands (`check_for_updates_now`, `install_update_now`, `confirm_restart_install`, `cancel_deferred_restart`, `dismiss_update_indicator`) in `src-tauri/src/lib.rs` `tauri::generate_handler!` macro. Stub bodies for each (return `Ok(())`) so the project compiles before Phase 3 implementations land.
- [x] T012 Create `src/lib/update-store.ts` — Zustand slice mirroring `UpdateStatus`. Subscribes to `juradrop://update-status` in the bridge layer; exposes `useUpdateStore()` hook for components.
- [x] T013 Wire the `juradrop://update-status` subscription in `src/lib/tauri-bridge.ts`'s app-startup initialiser so the store gets the first event whenever the React tree mounts. **SC-007 assertion**: grep all existing Tauri event channels (`grep -RInE "juradrop://" src/ src-tauri/src/`) and confirm `juradrop://update-status` does not collide with any existing channel name. Document the result inline in the bridge layer comment.

---

## Phase 3 — US1: Happy-path update on idle app (P1)

**Story goal**: User has v0.1.0 installed, v0.2.0 is published, the indicator badge appears in the top-right without a modal, the user clicks "Installera nu" → "Starta om" and the app relaunches as v0.2.0. Per-zone single-flight invariant holds throughout.

**Independent test**: With JuraDrop running and zones idle, publish a fresh manifest pointing at v0.2.0. Confirm: (a) indicator badge appears within 4h (or via manual check, immediately); (b) clicking opens a non-modal panel with release notes; (c) "Installera nu" downloads + verifies signature; (d) "Starta om" replaces the .app and relaunches as v0.2.0.

- [ ] T014 [US1] Implement `check_for_updates_now` command in `src-tauri/src/updater/commands.rs`. Behaviour per `contracts/tauri-commands.md`: read state guard, call `app.updater()?.check().await`, transition to `Available | UpToDate | Failed` based on result. Emit `juradrop://update-status` after every transition. **FR-015 logging**: on every transition, emit one line via `eprintln!("update_status: {old:?} → {new:?} (version: {version})")` — NEVER log notes content, IP, username, or document content. Add a unit test asserting that the eprintln! string format contains only state names + the version string.
- [ ] T015 [US1] Implement `install_update_now` command (same file). Calls `update.download(on_chunk, on_done)` with the `on_chunk` callback emitting `juradrop://update-status` per FR-007 debounce (one event per integer percent). On success, hold the downloaded bytes in `Updater.downloaded_bytes` and transition to `ReadyToInstall`. Plugin errors map to `UpdateFailure` via the `From` impl from T009.
- [ ] T016 [US1] Implement `confirm_restart_install` command (same file). Reads the `any_zone_processing` predicate. If false → transitions to `Restarting`, calls `update.install(downloaded_bytes)` (process exits inside). If true → sets `pending_restart_consent = true`, emits the deferred status, returns immediately.
- [x] T017 [US1] Implement `src-tauri/src/updater/deferral.rs` with two functions: `any_zone_processing(state: &AppState) -> bool` (reads each zone's visible_state) and `try_fire_deferred_restart(state: &AppState)` (called from the zone-state-change listener; checks consent flag + predicate; calls `update.install` if both align).
- [x] T018 [US1] Implement `src-tauri/src/updater/tick.rs` — single tokio task with `loop { sleep(4h); fire_tick(...).await; }`. The first sleep is `launch_check_delay_secs` (5 s) instead of 4 h. The tick checks `Updater.state in {Unknown, UpToDate, Failed} and not cancelled` before triggering `check_for_updates_now`. Cancellation token wired so app shutdown stops the task cleanly.
- [ ] T019 [US1] In `src-tauri/src/lib.rs`'s `setup()` callback, spawn the background task from T018 via `tauri::async_runtime::spawn(tick::run(app_handle.clone()))`. Store the task handle on `AppState` so shutdown can `.abort()` it.
- [x] T020 [US1] Implement `src/components/UpdateIndicator.tsx` — top-right badge + expandable panel. State-driven copy: hidden for Unknown/Checking/UpToDate/Failed (FR-010); "Uppdatering tillgänglig" for Available; "Hämtar uppdatering… N%" for Downloading; "Klar att installera — starta om?" for ReadyToInstall (deferred:false); "Väntar tills jobben är klara…" + an "Avbryt" button wired to `cancelDeferredRestart()` via the Tauri bridge for ReadyToInstall (deferred:true); "Startar om…" for Restarting. Expanded panel for Available: "Nyheter i version X.Y.Z" header + the release-notes body rendered as plain text (no Markdown parsing per FR-019). When the notes field is empty, render the literal string `Inga noteringar för denna version.` instead of an empty body. "Installera nu" button wires to `installUpdateNow()`. Use Tailwind primitives + shadcn/ui per design-system/MASTER.md.
- [x] T021 [US1] Mount `<UpdateIndicator />` in `src/App.tsx` in the top-right region of the main window's chrome. Verify with `npm run tauri dev` that the indicator renders + that drag-drop on the zones still works (the indicator is a non-blocking sibling).
- [ ] T022 [P] [US1] vitest `src/__tests__/UpdateIndicator.test.tsx`: render the component for each of the 8 UpdateStatus variants and assert (a) badge visible/hidden per state, (b) Swedish copy matches the indicator's rendered text, (c) button click invokes the right Tauri command. 12+ assertions.
- [ ] T023 [P] [US1] vitest `src/__tests__/UpdateStore.test.tsx`: drive the Zustand store through each state transition (Unknown→Checking→Available, etc.); assert the store correctly reflects the payload after each event.
- [ ] T024 [US1] End-to-end Rust integration test `src-tauri/tests/update_lifecycle.rs`. **Concrete strategy**: spin up a `wiremock` server bound to a random localhost port; configure the manifest endpoint to point at `<server>/latest.json` via a `cfg(test)`-only override on the Updater (a `pub(crate) fn override_endpoint_for_test(url: String)`). For the signature path, prefer mocking the entire `tauri_plugin_updater::Updater::check` + `Update::download` calls behind a trait abstraction (`UpdaterClient`) that the production code uses with the real plugin and the test uses with a fake. The fake returns `Available` for `check()` + drives `download()` through a few in-memory progress emissions + emits a fake `ReadyToInstall` outcome WITHOUT going through real minisign verification. This avoids generating a real test keypair while still exercising the entire state machine + Swedish copy assertions. Drive the state machine through Unknown → Checking → Available → Downloading → ReadyToInstall; assert the mirrored UpdateStatus payload's Swedish copy at every step. Stop at ReadyToInstall — do NOT invoke real install. **Required asserts**: each state's UpdateStatus payload contains the expected Swedish-copy substring (e.g. `"Hämtar uppdatering"` when state is `downloading`).

---

## Phase 4 — US2: Offline → silent failure → recovery (P2)

**Story goal**: User opens app offline; check fails; NO indicator badge appears; bottom-right footnote silently records the failure; on network return the next check succeeds.

**Independent test**: Disable network → launch JuraDrop → confirm no indicator + no toast/modal → enable network → manual check → state transitions to UpToDate or Available.

- [ ] T025 [US2] Verify the T009 `From<tauri_plugin_updater::Error>` mapping correctly produces `NoNetwork` for connect/timeout errors. Add a focused unit test stubbing a `reqwest::Error` with `.is_connect() == true` and asserting the variant maps to `NoNetwork`.
- [x] T026 [US2] Implement `src/components/UpdateRetryFootnote.tsx` — bottom-right "Senast kollat: <time>" affordance. When state is `Failed`, expanding the footnote reveals the Swedish failure copy + a "Sök efter uppdateringar igen" button. When state is non-Failed, expanding just shows the timestamp.
- [x] T027 [US2] Mount `<UpdateRetryFootnote />` in `src/App.tsx` in the bottom-right corner of the window chrome (subtle, low-contrast — not competing with the top-right indicator badge for attention).
- [ ] T028 [P] [US2] vitest `src/__tests__/UpdateRetryFootnote.test.tsx`: render the footnote for each of the 6 UpdateFailure variants + the non-Failed states; assert the rendered copy matches the cross-language fixture. 8+ assertions.
- [x] T029 [US2] Confirm `UpdateIndicator` returns null (badge hidden) when state is `Failed` (per FR-010). Add a vitest assertion in `UpdateIndicator.test.tsx`: `render(<UpdateIndicator />)` with a `Failed` status → `container.firstChild` is null.

---

## Phase 5 — US3: Manual check + dismissal (P3)

**Story goal**: User can manually trigger a re-check via the bottom-right footnote ("Sök efter uppdateringar igen") + can dismiss the indicator without losing the state.

**Independent test**: Set state to UpToDate → click "Sök efter uppdateringar igen" → confirm state transitions to Checking then to Available within 5s. Set state to Available → click X on the indicator badge → confirm badge hides but state stays Available → trigger another check → confirm badge reappears.

- [ ] T030 [US3] Wire the "Sök efter uppdateringar igen" button in `UpdateRetryFootnote.tsx` to invoke `checkForUpdatesNow()` via the Tauri bridge. Add a guard: the button is disabled while state is `Checking` (prevent double-fires).
- [ ] T031 [US3] Implement `cancel_deferred_restart` + `dismiss_update_indicator` commands in `src-tauri/src/updater/commands.rs` per `contracts/tauri-commands.md`. Both are simple flag-set + event-emit commands.
- [ ] T032 [US3] Implement dismissal + re-show logic in `UpdateIndicator.tsx`: clicking the X chevron invokes `dismissUpdateIndicator()`; the component reads `indicator_dismissed` from the store and renders null when true. The store reset of that flag on the next `Available | ReadyToInstall` transition happens server-side (Rust); the component just listens.
- [ ] T033 [P] [US3] vitest `src/__tests__/UpdateDismissal.test.tsx`: assert dismiss → hide → state-transition → re-show sequence works correctly via the store.

---

## Phase 6 — Cross-cutting polish

- [ ] T034 [P] Source-immutability extension test: extend the existing spec 005 `source_immutability.rs` test with a "mid-update" scenario — start a docx job on Sammanfatta, fire a manifest check that returns Available, assert the source file's SHA-256 is unchanged after the check completes (no incidental writes from the updater).
- [ ] T035 [P] Run the `humanizer` skill on every new Swedish string introduced in spec 007: the 6 `UpdateFailure` variants + the 7 UI strings (badge labels, buttons, expanded panel copy, deferred copy). Adjust any AI-tinged phrasing. BLOCKING per CLAUDE.md.
- [x] T036 [P] Static network audit: `grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/` — every match must remain in spec 002's `manager.rs` + `client.rs`. Spec 007 introduces ZERO new outbound surface (the tauri-plugin-updater calls live inside the plugin, not in the app's grep surface).
- [ ] T037 [P] Update `README.md`: replace the "v0.1 är under utveckling" section with a "Auto-updater" section describing the in-app indicator + the user-controlled install flow.
- [ ] T038 Run the full regression suite: `npm run lint && npm run typecheck && npm test`, then `cd src-tauri && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`, then `npm run test:e2e`. All MUST exit 0. Spec 007's additions must not regress spec 001–006.
- [ ] T039 [P] Playwright smoke extension `tests/e2e/update-indicator.spec.ts` (best-effort — see spec 003's note about Tauri + Playwright). At minimum, the existing placeholder test stays green.

---

## Phase 7 — TLA+ verification + manual close + commit

- [ ] T040 Run `/tla` for spec 007. Full track; 7-state machine + per-zone deferral + async transitions = non-trivial. Expect TLA+ to surface invariants like `UpdaterNeverInterruptsZoneProcessing` + `SignatureVerificationNotBypassable` + `ConsentRequiredForFirstRestart`. Address any findings per `.claude/rules/validation-followup.md`.
- [ ] T041 Execute `quickstart.md` flows 1–7 against `npm run tauri dev` on real hardware. SC-001 (≤ 90 s update wall-clock), SC-002 (zero restart during processing), SC-005 (4h tick within ±5 min), SC-006 (NoNetwork detection ≤ 30 s) need real-hardware verification. **Needs user verification on real Mac.**
- [ ] T042 Tick spec 007 in `specs/INDEX.md` to `[x]` and append a Register history entry dated today with task count, test count delta, deferrals, and the spec 008 next-up note.
- [ ] T043 Stage + commit + push to `origin/main` per the direct-push workflow. Commit message: `feat(spec-007): auto-updater state machine + Swedish in-app surface + v0.1→v0.2 e2e test`. Then emit the per-spec stop summary per `.claude/rules/spec-register.md`.

---

## Dependencies & ordering

- **Phase 1 (Setup)** blocks every later phase — the new module files + the dialog flip must exist before any extractor compiles.
- **Phase 2 (Foundational)** blocks Phases 3–5 — the state machine + the error vocabulary + the bridge types + the store must all be in place before the React components or commands can reference them.
- **Phase 3 (US1)** is the load-bearing implementation. Its sub-steps have internal dependencies: T014→T015→T016 (command chain); T017 (deferral) is independent and can be done in parallel with T020 (React indicator); T024 (integration test) requires T014–T019.
- **Phase 4 (US2)** depends on Phase 2's T009 (error mapping) being correct — otherwise NoNetwork detection is broken.
- **Phase 5 (US3)** is independent of Phase 4 — both layer on Phase 3 without touching each other.
- **Phase 6 (Polish)** depends on all user stories being complete — humanizer + regression sweep need the final strings + tests.
- **Phase 7 (TLA+ + close)** runs last per the full-track pipeline.

## Parallel execution opportunities

Phase 2: T003, T004, T005, T006, T007, T008 are all `[P]` — six different files, no shared state. T009 depends on T004 (UpdateFailure variants exist).

Phase 3 (within US1): T017 (deferral) + T020 (React indicator) + T022 (vitest tests) + T023 (Zustand tests) are all `[P]` while T014–T016 are in progress. T024 (e2e) runs after T014–T019.

Phase 4 + Phase 5: independent of each other. Could run in parallel.

Phase 6: T034, T035, T036, T037, T039 are all `[P]`.

## MVP scope

Minimum shippable slice: **Phase 1 + Phase 2 + Phase 3 (US1)**. With those three phases, the user has the full happy-path: indicator badge, "Installera nu", deferred restart, signed install, relaunch as new version. US2 (silent offline) and US3 (manual dismissal) layer on without touching US1's code paths.

## Format validation

Every task above starts with `- [ ]` + `T###` ID + optional `[P]` marker + optional `[US#]` label + concrete description + explicit file path. No task references "the codebase" or "appropriate files" without naming them.
