# Tasks — Spec 010 Settings Panel

**Feature**: Settings Panel (gear-icon slide-in)
**Spec**: [spec.md](spec.md) • **Plan**: [plan.md](plan.md) • **Allium**: [spec.allium](spec.allium)
**Track**: Light pipeline (per `specs/INDEX.md` row 010)
**Date**: 2026-05-28

User stories from spec.md (priority order):
- **US1 — P1**: Pick a model tier and have the next zone run use it
- **US2 — P2**: Confirm the app respects the OS appearance
- **US3 — P3**: Find the version, source, and license

## Phase 1 — Setup

- [ ] T001 Add `settings` module skeleton — create `src-tauri/src/settings/mod.rs` exporting `pub mod tier_map; pub mod snapshot; pub mod file_io; pub mod commands; pub mod strings;` (empty stubs, just the module wiring)
- [ ] T002 Add `SettingsState` Tauri-managed-state type in `src-tauri/src/settings/snapshot.rs` and register it in `src-tauri/src/lib.rs` via `app.manage(...)` in the Tauri `setup` callback
- [ ] T003 Add `shell.open` URL scope `https://github.com/johanolofsson72/juradrop/releases` to `src-tauri/capabilities/main.json` under the `shell:default` permission
- [ ] T004 [P] Extend `fixtures/zone-error-strings.json` with a new top-level `settings_panel` object containing the 22 panel-string keys defined in `data-model.md` § SettingsPanelStrings
- [ ] T005 [P] Create `src/types/settings.ts` with `ModelTier` type union, `MODEL_TIERS` const array, `SettingsSnapshot` type, `PanelVisibility` type, `TierRowMode` type
- [ ] T006 [P] Create `src/lib/tier-strings.ts` exporting `SETTINGS_PANEL_STRINGS` constant that reads from the fixture (compile-time JSON import)

## Phase 2 — Foundational (BLOCKS all user stories)

These must complete before any user-story phase. They establish the central tier-map and the dispatch-reads-snapshot wiring that every flow depends on.

- [ ] T007 Implement `ModelTier` enum + `TierMapping` constants + `model_id()` and `size_badge()` const methods in `src-tauri/src/settings/tier_map.rs` (Snabb→`llama3.2:1b`, Smart→`gemma3:4b`, Stor→`gemma3:12b`; size badges `~1.3 GB`, `~3.3 GB`, `~8.1 GB`)
- [ ] T008 Implement `SchemaVersion` enum (V1=1) with `serde(into = "u32", try_from = "u32")` in `src-tauri/src/settings/snapshot.rs`
- [ ] T009 Implement `SettingsSnapshot` struct with `Default` impl returning `(V1, ModelTier::Smart)` in `src-tauri/src/settings/snapshot.rs`
- [ ] T010 Implement `load_or_default(path) -> SettingsSnapshot` and `save(path, snapshot) -> Result<(), WriteFailed>` in `src-tauri/src/settings/file_io.rs` — atomic temp-file + rename per `contracts/settings-file-schema.md` § Save
- [ ] T011 Modify `src-tauri/src/sidecar/commands.rs` dispatch path to read `SettingsState`'s snapshot at dispatch time instead of `DEFAULT_MODEL` constant (replace `DEFAULT_MODEL` reads with `tier_map::TierMapping` lookups from `snapshot.model_tier`). Keep `DEFAULT_MODEL` as a fallback constant for the test seam, but production dispatch reads the snapshot.
- [ ] T012 Add `useSettingsStore` Zustand store in `src/store/useSettingsStore.ts` with `snapshot`, `tierPullState`, `setSnapshot`, `setTierPullState`, `init()` (registers Tauri event listeners + calls `get_settings` and `get_tier_pull_state` on mount)
- [ ] T013 Add `useSettingsPanel` hook in `src/hooks/useSettingsPanel.ts` implementing the 4-state visibility machine (closed/opening/open/closing) with 6 transitions per `data-model.md` § PanelVisibility, plus the `gearIconEnabled` derived predicate

---

## Phase 3 — User Story 1 (P1): Pick model tier, next dispatch uses it

**Goal**: A student opens the panel, picks `Stor`, closes the panel, drops a file — the run uses `gemma3:12b`. No restart, no UI other than the existing zone result.

**Independent test**: Playwright + vitest: open panel → click `Stor` radio (assume already pulled in test mock) → close panel → invoke dispatch → assert sidecar called with `gemma3:12b`.

### Implementation

- [ ] T014 [US1] Implement `get_settings`, `set_model_tier`, `get_tier_pull_state`, `trigger_tier_download` Tauri commands in `src-tauri/src/settings/commands.rs` per `contracts/settings-commands.md`
- [ ] T015 [US1] Register all four `settings::commands::*` in `src-tauri/src/lib.rs`'s `invoke_handler!` macro
- [ ] T016 [US1] Implement `get_tier_pull_state` body — call the Ollama `/api/tags` endpoint via the existing sidecar client, check for each of the 3 model IDs, cache result with 30s TTL, invalidate on `settings://tier_pulled` event
- [ ] T017 [US1] Implement `trigger_tier_download` — delegate to the spec 008 wizard's `start_model_pull(model_id, source: PanelTriggered { target_tier })`. Requires a one-field extension to the wizard's `start_model_pull` signature: add the `source: WizardSource` parameter with variants `FirstRun`, `PanelTriggered { target_tier: ModelTier }`, `DispatchTriggered`. Implement `impl Default for WizardSource { fn default() -> Self { FirstRun } }` so all existing spec 008 callers compile without modification. **Exit criterion** (per analyze X1): re-run the full spec 008 test suite (`src-tauri/tests/wizard_*.rs` + `src/__tests__/Welcome*.test.tsx` + `src/__tests__/FirstRun*.test.tsx`) and confirm zero regressions before marking T017 done.
- [ ] T018 [US1] Modify spec 008 wizard's success / failure / cancel callbacks to emit, respectively, `settings://tier_pulled`, `settings://tier_pull_failed`, `settings://tier_pull_cancelled` with payload `{ "tier": "<TierName>" }`, gated on `source == PanelTriggered { target_tier }`. When `source == FirstRun` or `DispatchTriggered`, no settings events are emitted (preserves spec 008 behaviour exactly). **Exit criterion** (per analyze X1): same spec 008 regression run as T017.
- [ ] T019 [US1] [P] Create `src/lib/settings.ts` Tauri command wrappers: `getSettings()`, `setModelTier(tier)`, `getTierPullState()`, `triggerTierDownload(tier)` — each one a thin `invoke()` call with typed return
- [ ] T020 [US1] [P] Create `src/components/SettingsPanel/SettingsPanel.tsx` — slide-in container, scrim, focus trap; uses `useSettingsPanel` for visibility; mounts conditionally based on `visibility != 'closed'`; calls `closePanel()` on scrim click + Esc keydown
- [ ] T021 [US1] [P] Create `src/components/SettingsPanel/SettingsPanelHeader.tsx` — title `Inställningar` + close-X button with `aria-label="Stäng"`
- [ ] T022 [US1] [P] Create `src/components/SettingsPanel/TierRow.tsx` — props `{ tier, mode, isSelected, onSelect, onDownload, helper, sizeBadge }` — renders radio + label + helper when `mode === 'radio_selectable'`, renders `Ladda ned` button + size badge + helper when `mode === 'download_button'`
- [ ] T023 [US1] Create `src/components/SettingsPanel/ModelTierSection.tsx` — composes 3 `TierRow`s from `MODEL_TIERS`, computes per-row `mode` from `useSettingsStore`'s `tierPullState`, wires `onSelect` to `setModelTier` and `onDownload` to `triggerTierDownload`
- [ ] T024 [US1] [P] Create `src/components/GearIcon.tsx` — top-right chrome gear button, calls `useSettingsPanel.openPanel()`, sets `aria-disabled` from `gearIconEnabled`, suppresses click when disabled
- [ ] T025 [US1] [P] Create `src/hooks/useCmdComma.ts` — registers global keydown listener for Cmd+, on App.tsx mount, calls `togglePanel()` if `gearIconEnabled`
- [ ] T026 [US1] Modify `src/App.tsx` — mount `<GearIcon />` in the top-right chrome bar (LEFT of the existing spec 007 update indicator per Clarification Q5), mount `<SettingsPanel />`, wire `useCmdComma()` once
- [ ] T027 [US1] Wire `useSettingsStore.init()` from App.tsx mount — subscribes to `settings://tier_pulled` (auto-select target tier), `settings://tier_pull_failed` (no-op, keep previous), `settings://tier_pull_cancelled` (no-op, keep previous)

### Tests (functional coverage + invariants for US1)

- [ ] T028 [US1] [P] Vitest `src/__tests__/useSettingsStore.test.ts` — store mutations (setSnapshot, setTierPullState), persistence-call shape, event listener registration (uses Tauri event mock)
- [ ] T029 [US1] [P] Vitest `src/__tests__/useSettingsPanel.test.tsx` — all 4 states × 6 transitions, repeated-open coalescing (rapid Cmd+, presses do NOT stack panels), `gearIconEnabled` derivation from spec 007/008 stores
- [ ] T030 [US1] [P] Vitest `src/__tests__/ModelTierSection.test.tsx` — radio mode renders when pulled, download_button mode renders when not pulled, clicking radio fires `setModelTier`, clicking `Ladda ned` fires `triggerTierDownload`, helper sentence + size badge render with correct fixture strings. **Plus (per analyze C2 / FR-012a)**: with the spec 008 first-run-completed mock returning `smart_pulled: true`, assert at least one tier row renders as `radio_selectable` regardless of the Snabb/Stor pull state — "the panel is never in an all-disabled state after first run".
- [ ] T031 [US1] [P] Rust `src-tauri/tests/settings_tier_map.rs` — `ModelTier::model_id()` returns the three pinned IDs, `ModelTier::size_badge()` returns the three pinned size strings, `ModelTier::ALL.len() == 3`
- [ ] T032 [US1] [P] Rust `src-tauri/tests/settings_file_io.rs` — round-trip (every variant of `SettingsSnapshot` serialises and deserialises to itself), missing-file fallback returns `default()`, malformed-file fallback returns `default()`, schema-shape strict assertion (exactly 2 top-level keys per `contracts/settings-file-schema.md`), atomic-rename behaviour (kill mid-write does not corrupt prior version)
- [ ] T032a [US1] [P] Rust `src-tauri/tests/settings_persistence_across_restart.rs` (per analyze C3 / SC-002) — for each of the 3 `ModelTier` variants: call `save(path, snapshot)`, drop the snapshot, call `load_or_default(path)` (simulating an app restart), assert the returned snapshot equals the saved one byte-for-byte. Covers SC-002's "100% of clean app restarts" assertion that round-trip alone does not.
- [ ] T033 [US1] [P] Rust `src-tauri/tests/settings_invariants.rs` — `SettingsFileHasExactlyTwoFields` (grep serialised form), `SettingsFileNeverContainsUserContent` (denylist scan), `ModelIdStringsNeverHardCodedInFrontend` (grep `src/**/*.{ts,tsx}` for `llama3.2:1b` / `gemma3:4b` / `gemma3:12b` → must be empty), `SettingsFilePathFromTauriApi` (grep `src-tauri/src/**/*.rs` for `/Library/Application Support` literal → must be empty)
- [ ] T034 [US1] [P] Rust `src-tauri/tests/dispatch_reads_snapshot.rs` — `DispatchUsesSnapshotNotConstant` (mock snapshot with `Stor`, invoke dispatch, assert HTTP call to Ollama uses `gemma3:12b`), `InFlightRunsImmuneToTierSwitch` (start dispatch with `Smart`, mutate snapshot to `Snabb` mid-flight, assert in-flight job still completes against `gemma3:4b`)
- [ ] T035 [US1] Playwright `tests/playwright/settings_panel_smoke.spec.ts` — open panel via gear click, switch from Smart to (mocked-pulled) Snabb, close panel, drop fixture `.docx` on Sammanfatta, assert sidecar called with `llama3.2:1b` (uses the existing test seam)

---

## Phase 4 — User Story 2 (P2): Appearance row reflects OS without action

**Goal**: A student opens the panel in dark mode, sees `Mörkt läge (följer systemet)`, switches macOS to light mode, sees the row update within 500 ms without re-opening.

**Independent test**: Vitest with fake timers — render `AppearanceSection`, dispatch synthetic `change` event on the dark MediaQueryList, assert the text changes within 500 ms.

### Implementation

- [ ] T036 [US2] Create `src/hooks/useSystemAppearance.ts` — `useSyncExternalStore` wrapping `(prefers-color-scheme: dark)` MediaQueryList, returns `'light' | 'dark'`
- [ ] T037 [US2] Create `src/components/SettingsPanel/AppearanceSection.tsx` — section title from fixture, single read-only row that renders `appearance_light` or `appearance_dark` string based on `useSystemAppearance()` return; ZERO interactive descendants
- [ ] T038 [US2] Mount `<AppearanceSection />` in `SettingsPanel.tsx` between `<ModelTierSection />` and `<AboutSection />`

### Tests

- [ ] T039 [US2] [P] Vitest `src/__tests__/useSystemAppearance.test.tsx` — initial value matches `matchMedia('(prefers-color-scheme: dark)').matches`, change event re-renders within 500 ms (fake timer assertion for SC-004), no event listener leak on unmount
- [ ] T040 [US2] [P] Vitest `src/__tests__/AppearanceSection.test.tsx` — dark-mode mock → text is `Mörkt läge (följer systemet)`, light-mode mock → text is `Ljust läge (följer systemet)`, DOM has zero descendants matching `input, button, select, [role="switch"]` (FR-014 invariant)

---

## Phase 5 — User Story 3 (P3): About section with version + license + GitHub link

**Goal**: A student opens the panel, scrolls to About, sees app name + version + MIT license short-line + `Visa utgåvor på GitHub` button; clicking the button opens the default browser at the Releases URL.

**Independent test**: Vitest renders `AboutSection`, version string matches the build's version constant; clicking GitHub button calls `shell.open` with the pinned URL.

### Implementation

- [ ] T041 [US3] Expose build version to React — extend the existing version-pinning helper from spec 006 to also expose to TS (e.g. a generated `src/lib/build-version.ts` written by the release-prep script, OR a Tauri command `get_app_version` reading `tauri::app::AppHandle::package_info().version`). Pick the Tauri-command approach to avoid touching the release-prep script for one constant.
- [ ] T042 [US3] Add `get_app_version` Tauri command to `src-tauri/src/settings/commands.rs` returning `String` (semver from `package_info`)
- [ ] T043 [US3] Create `src/components/SettingsPanel/AboutSection.tsx` — three static rows (app_name, version from `get_app_version`, license fixture string) + `Visa utgåvor på GitHub` button that calls Tauri's `shell.open` with the pinned URL from a single `GITHUB_RELEASES_URL` constant in `src/lib/settings.ts`
- [ ] T044 [US3] Mount `<AboutSection />` in `SettingsPanel.tsx` below `<AppearanceSection />`

### Tests

- [ ] T045 [US3] [P] Vitest `src/__tests__/AboutSection.test.tsx` — version string matches the mocked `get_app_version` return value, license text matches fixture, clicking GitHub button calls `shell.open` mock exactly once with `https://github.com/johanolofsson72/juradrop/releases`, no in-app navigation occurs
- [ ] T046 [US3] [P] Rust `src-tauri/tests/about_command.rs` — `get_app_version` returns a non-empty string matching the semver pattern `^[0-9]+\.[0-9]+\.[0-9]+`

---

## Phase 6 — Cross-cutting & destructive coverage (BLOCKS finish)

These extend the functional coverage with the 8+ destructive scenarios mandated by `specs.md` § Destructive tests, and the cross-language drift test mandated by FR-026 / SC-007. They are NOT story-scoped — they assert invariants across the whole panel.

### Cross-language drift

- [ ] T047 Vitest `src/__tests__/settings-strings-drift.test.ts` — every key in `SETTINGS_PANEL_STRINGS` (TS) matches the fixture's `settings_panel.<key>`; adding a string on one side without the other fails CI (SC-007)
- [ ] T048 Rust `src-tauri/tests/settings_strings_drift.rs` — every entry in `SettingsPanelStrings` (Rust) matches the fixture; same drift detection in Rust direction

### Destructive scenarios (8 across 6 attack categories per spec-testing-checklist.md)

- [ ] T049 [P] Vitest destructive — **invalid input**: corrupt `settings.json` (truncated mid-string, non-UTF8 bytes, JSON with deeply nested objects, extra fields, schema_version=999) — assert all five cases route to silent default with debug warning, no UI error surfaced (FR-020)
- [ ] T050 [P] Vitest destructive — **wrong order**: open panel → drop file BEFORE closing → panel still open while zone processes (FR-005, SC-006); assert byte-identical sidecar output regardless of panel visibility
- [ ] T051 [P] Vitest destructive — **skip steps**: invoke `set_model_tier("Stor")` via `invoke()` WITHOUT opening the panel; assert Rust returns `TierNotPulled` error when Stor's model isn't pulled (cannot bypass the radio gate via the command surface — Principle III enforcement)
- [ ] T052 [P] Vitest destructive — **boundary values**: rapid 50-Cmd+, presses in 1 second (repeated open intents) → assert at most one panel instance; rapid 10-tier-radio-clicks across all 3 tiers in 1 second → assert final state matches the last click only, snapshot writes are coalesced (no write storm)
- [ ] T053 [P] Vitest destructive — **timing/race**: click `Ladda ned` for Stor → during the mocked download, switch macOS appearance → after download completes, assert auto-select fired AND appearance row updated correctly (no interleaving corruption)
- [ ] T054 [P] Vitest destructive — **accessibility**: panel keyboard navigation (Tab walks gear → close-X → tier radios → GitHub link → wraps back to gear), Enter activates the focused control, Escape closes from any focused element, focus is trapped inside the panel while open (FR-025)
- [ ] T055 [P] Vitest destructive — **state mutation during animation**: trigger close-X click DURING `opening` state → assert visibility transitions opening → closing (reverse), eventually settles at closed; trigger Cmd+, DURING `closing` → assert visibility transitions closing → opening
- [ ] T056 [P] Vitest destructive — **disabled-gate bypass attempt**: with spec 008 wizard mocked-visible, simulate gear click + Cmd+, + manual `openPanel()` call from devtools-equivalent → assert visibility stays closed, panel never mounts (FR-005a)
- [ ] T056a [P] Vitest invariant (per analyze C1 / FR-022) — `src/__tests__/no-outbound-from-panel.test.tsx`. Stub `globalThis.fetch`, `XMLHttpRequest`, and `WebSocket` to throw if called. Then simulate every panel interaction: open via gear, open via Cmd+,, switch tier (radio mode), click Ladda ned (download_button mode — assert delegation goes through Tauri `invoke`, NOT through fetch/XHR), click GitHub link (assert goes through Tauri `shell.open` mock, NOT through fetch), close via X / Esc / scrim. Assert the stubs were called ZERO times across the entire test. Belt-and-braces invariant covering Principle I at the frontend boundary.

### Humanizer review

- [ ] T057 Invoke the `humanizer` skill against the 12 new user-facing Swedish strings (panel_title, close_label, section_*_title, tier_*_helper, tier_not_downloaded_badge, appearance_light, appearance_dark, about_license, about_github_button, tier_ladda_ned_button) — fix any AI tells (inflated symbolism, rule of three, em-dash overuse, promotional language)

### Final quality gates

- [ ] T058 Run `cargo clippy --workspace -- -D warnings` in `src-tauri/` — fix every clippy diagnostic introduced by this spec; zero warnings
- [ ] T059 Run `cargo fmt --check` in `src-tauri/` and `npm run lint && npm run typecheck` at repo root — zero issues
- [ ] T060 Run `npm test` (vitest) and `cd src-tauri && cargo test` — all 600+ existing tests still green; new tests from T028–T056 added to count
- [ ] T061 `npm run tauri dev` — manually verify all 5 Flow paths from `quickstart.md` on the running app (gear click → tier switch, appearance toggle, About GitHub link, disabled gate during first-run, Ladda ned auto-select). Document any wall-clock measurements that need real hardware (SC-001 ≤ 2 s, SC-003 animation budget, SC-004 ≤ 500 ms) — these may be acknowledged-as-deferred in the status summary if mocked-time tests already cover the invariants.

---

## Dependency graph

```text
Phase 1 (T001-T006) ──┐
                      ├──▶ Phase 2 (T007-T013) ──┐
                      │                          ├──▶ Phase 3 / US1 (T014-T035) ──┐
                      │                          ├──▶ Phase 4 / US2 (T036-T040) ──┤
                      │                          └──▶ Phase 5 / US3 (T041-T046) ──┤
                      │                                                            │
                      └────────────────────────────────────────────────────────────┴──▶ Phase 6 (T047-T061)
```

**Story independence**: US1, US2, US3 can be implemented in parallel once Phase 2 completes (US2 and US3 only need a minimal `<SettingsPanel />` shell that US1 provides). For sequential execution, US1 must land first (it provides the panel container).

**MVP scope**: US1 only — gives a working tier selector and validates the dispatch-reads-snapshot core change. US2 and US3 are pure additive sections inside the panel container.

## Parallel execution opportunities

Within each phase, tasks marked `[P]` operate on different files and can be executed concurrently. Notable parallel pools:

- **Phase 1**: T004 + T005 + T006 (different files, no deps)
- **US1 implementation**: T019 + T020 + T021 + T022 + T024 + T025 (different files, no deps on each other once Phase 2 done)
- **US1 tests**: T028 + T029 + T030 + T031 + T032 + T033 + T034 (different files)
- **Phase 6 destructive**: T047 + T048 + T049 + T050 + T051 + T052 + T053 + T054 + T055 + T056 (different test files, all parallelizable)

## Independent test criteria (per story)

| Story | Independent test |
|---|---|
| **US1** | Playwright + 8 vitest tests (T028-T035) — covers tier switch, dispatch lookup, persistence, in-flight immunity |
| **US2** | 2 vitest tests (T039-T040) — appearance projection + FR-014 zero-control assertion |
| **US3** | 1 vitest + 1 cargo test (T045-T046) — version pin, GitHub link, license string |

## Implementation strategy

1. **Phase 1 + 2 in one go**: shared infrastructure for all three stories, must land together.
2. **US1 next**: highest priority, exercises the whole pipeline (commands + events + components + dispatch swap). Once US1 ships, the panel is open and the tier is switchable.
3. **US2 and US3 in parallel**: both are pure additive sections inside the panel container. They share no files with each other and only touch `SettingsPanel.tsx` for mounting.
4. **Phase 6 at the end**: destructive coverage and the humanizer pass require the full panel to exist. Cross-language drift tests (T047, T048) ALSO require all panel strings present.

## Acknowledged-as-deferred (manual real-hardware verification)

These tasks need a real M-series Mac and a clean app launch; CI mocks cover the invariants but the wall-clock requires hand-testing:

- T061 SC-001 — tier change → effective in ≤ 2 s wall-clock (CI tests assert the snapshot-mutation invariant; the wall-clock observation needs a human).
- T061 SC-003 — panel animation within budget (CI tests assert transition completion; wall-clock easing feel needs a human).
- T061 SC-004 — OS appearance change reflected in ≤ 500 ms wall-clock (fake-timer vitest tests assert the invariant; real-clock observation needs a human).

These will be flagged in the spec register history line as "T061 deferred for manual real-hardware verification" — same treatment as spec 003 T066/T067 and spec 008 T028/T038.
