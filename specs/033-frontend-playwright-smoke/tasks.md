# Tasks: Frontend Playwright smoke tests

**Feature dir**: `specs/033-frontend-playwright-smoke/` | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

For this feature the *implementation* IS the test harness — the deliverable is the mock bridge + the smoke tests. There is no separate "app code under test" to build; production code is unchanged (SC-005).

**Conventions**: `[P]` = parallelizable (different file, no incomplete dep). Story labels map to spec.md user stories US1–US6 (+ contract test for FR-017).

---

## Phase 1 — Setup

- [ ] T001 Rewrite `playwright.config.ts`: chromium project, `use.baseURL='http://localhost:1420'`, headless, `webServer:{command:'npm run dev', url:'http://localhost:1420', reuseExistingServer:!process.env.CI, timeout:120_000}`, `testDir:'./tests/e2e'`, `reporter:'list'` (per research R-003).
- [ ] T002 Delete `tests/e2e/placeholder.spec.ts` (the `1+1===2` stub — FR-001).
- [ ] T003 Confirm Chromium binary install path works locally (`npx playwright install chromium`) and document it in quickstart (already documented; verify command runs).

## Phase 2 — Foundational (BLOCKING — the mock bridge every story depends on)

- [ ] T004 Create `tests/e2e/support/canned-state.ts`: `CannedState` type + `defaultCanned()` returning the research-R-005 shapes (status klar/ready/fortsatt, settings schema_version 1 / Smart, tierPull smart_pulled, tierDownload null, diagnostics off, appVersion '0.1.0', pickerResult null).
- [ ] T005 Create `tests/e2e/support/tauri-mock.ts`: a single **serializable** init-script function `installTauriMock(canned)` that defines `window.__TAURI_INTERNALS__` (`invoke`/`transformCallback`/`unregisterCallback`) + `window.__JURADROP_TEST__` (`emit`/`invocations`/`setCanned`/`listenerCount`) per `contracts/mock-bridge-contract.md`. Implements the command dispatch table, `plugin:event|listen/unlisten`, the `{event,id,payload}` delivery shape, once-listener teardown, and the unmocked-command reject (FR-004/005/006/007/008/009/010).
- [ ] T006 Create `tests/e2e/support/fixtures.ts`: extend Playwright `test` with a `canned` option + a `juradrop` fixture; in a `page` override, call `page.addInitScript(installTauriMock, mergedCanned)` BEFORE navigation (FR-003). `juradrop.emit/invocations/listenerCount` are thin wrappers that call `page.evaluate((args)=>window.__JURADROP_TEST__.…)` (node→browser; do NOT use `exposeFunction`, which is browser→node). Re-export `test`/`expect`.

## Phase 3 — US1 Boot to grid (P1) 🎯 MVP

**Goal**: production frontend boots in Chromium against the mocked backend and reaches the grid with no crash.
**Independent test**: `npm run test:e2e -- boot` → grid visible, no console errors, Vite auto-started.

- [ ] T007 [US1] `tests/e2e/boot.spec.ts`: with default canned (klar), `page.goto('/')` → assert the zone grid section `[aria-label="Drop-zoner"]` is visible and the wizard is absent (no `Wizard` heading). (US1 AS1)
- [ ] T008 [P] [US1] In `boot.spec.ts`: register a `page.on('console')`/`page.on('pageerror')` collector; assert zero uncaught errors and no error-boundary fallback text after boot. (US1 AS2)
- [ ] T009 [P] [US1] In `boot.spec.ts`: assert no non-localhost network request fired (collect `page.on('request')`, fail if any URL host ∉ {localhost,127.0.0.1}) — Principle I / FR-013. (US1 AS3 + privacy contract)

## Phase 4 — US2 Core rendered surface (P1)

**Goal**: nine zones + Swedish labels + welcome card + chrome render intact.
**Independent test**: `npm run test:e2e -- zones` → 9 `[data-zone-id]`, correct titles, chrome present.

- [ ] T010 [US2] `tests/e2e/zones.spec.ts`: assert exactly nine `[data-zone-id]` sections, each with its `ZONE_ORDER` slug present. (US2 AS1)
- [ ] T011 [P] [US2] In `zones.spec.ts`: assert each zone's `h2` shows its `ZONE_IDENTITIES[slug].title` Swedish label (Sammanfatta, Till engelska, …, Källförteckning). (US2 AS1)
- [ ] T012 [P] [US2] In `zones.spec.ts`: assert both chrome icons (`[data-settings-gear]`, `[data-help-icon]`) are visible at klar (US2 AS2). Separate test: with fresh-install canned (`consent='not_asked'`, `model='not_present'`, `visible='begar_samtycke'`) assert the first-run wizard `#wizard-title` (role=dialog) is visible; at klar assert no `#wizard-title` and the grid is shown (US2 AS3).

## Phase 5 — US3 Consent gate + IPC wiring (P2)

**Goal**: consent modal shows on `begar_samtycke`; Fortsätt/Avbryt invoke give/cancel_consent.
**Independent test**: `npm run test:e2e -- consent` → modal + recorded command per button.

- [ ] T013 [US3] `tests/e2e/consent.spec.ts`: `test.use({canned:{status:{visible:'begar_samtycke',consent:'not_asked',sidecar:'starting',model:'not_present',progress_percent:null}}})`; assert the dialog with title `Ladda ner AI-modell` is visible. (US3 AS1)
- [ ] T014 [US3] In `consent.spec.ts`: click `Fortsätt` → assert `juradrop.invocations()` contains a resolved `give_consent`. (US3 AS2)
- [ ] T015 [US3] In `consent.spec.ts` (separate test): click `Avbryt` → assert `cancel_consent` recorded. (US3 AS3)

## Phase 6 — US4 Panels + mutual exclusion (P2)

**Goal**: settings opens via gear + Cmd+,; help opens; opening one closes the other.
**Independent test**: `npm run test:e2e -- panels` → panel visibility transitions correct.

- [ ] T016 [US4] `tests/e2e/panels.spec.ts`: FIRST read `src/components/SettingsPanel.tsx` + `HelpPanel.tsx` for a stable root marker (data-attr / role / heading); then boot klar, click `[data-settings-gear]` → assert the settings panel becomes visible via that marker. (US4 AS1)
- [ ] T017 [P] [US4] In `panels.spec.ts`: press `Meta+Comma` → assert settings panel toggles open; press again → hidden. (US4 AS2)
- [ ] T018 [US4] In `panels.spec.ts`: open settings, then click `[data-help-icon]` → assert settings closes and help panel shows (mutual exclusion, US4 AS3).

## Phase 7 — US5 Click-to-browse picker (P3)

**Goal**: Välj fil → `plugin:dialog|open` → `dispatch_to_zone`; null → no dispatch.
**Independent test**: `npm run test:e2e -- picker` → dispatch recorded / not recorded.

- [ ] T019 [US5] `tests/e2e/picker.spec.ts`: `test.use({canned:{pickerResult:'/Users/x/avtal.docx'}})`; boot klar; click `[data-zone-pick="sammanfatta"]` → assert `dispatch_to_zone` recorded with `{zoneId:'sammanfatta', paths:['/Users/x/avtal.docx']}`. (US5 AS1)
- [ ] T020 [US5] In `picker.spec.ts` (separate test): `canned.pickerResult=null`; click Välj fil → assert NO `dispatch_to_zone` recorded. (US5 AS2)

## Phase 8 — US6 Live event channels (P3)

**Goal**: emitted zone snapshot drives state; emitted status transition re-renders.
**Independent test**: `npm run test:e2e -- events` → zone state + screen change via emit.

- [ ] T021 [US6] `tests/e2e/events.spec.ts`: boot klar; wait for `[data-zone-id="sammanfatta"]`; `juradrop.emit('juradrop://zone/sammanfatta',{state:'processing',disabled:false,failure:null,job_id:'job-1',progress_hint:'Sammanfattar…'})` → assert `[data-zone-id="sammanfatta"][data-state="processing"]` visible. (US6 AS1)
- [ ] T022 [P] [US6] In `events.spec.ts`: emit `success` then `error` snapshots → assert `[data-state="success"]` then `[data-state="error"]` in turn. (US6 AS2)
- [ ] T023 [US6] In `events.spec.ts`: boot klar; `juradrop.emit('juradrop://status',{visible:'begar_samtycke',consent:'not_asked',sidecar:'starting',model:'not_present',progress_percent:null})` → assert consent dialog appears without reload. (US6 AS3)
- [ ] T024 [P] [US6] In `events.spec.ts`: assert `juradrop.emit('juradrop://zone/sammanfatta',…)` returns delivery count ≥ 1 when subscribed, and `juradrop.emit('juradrop://nonexistent',{})` returns 0 (no-listener no-op, FR-010).

## Phase 9 — FR-017 Contract assertion

**Goal**: pin the `@tauri-apps/api` IPC contract so a future bump fails loudly.

- [ ] T025 `tests/e2e/contract.spec.ts` (FR-017, FR-009). Pin the contract WITHOUT bundling the SDK into the test: (a) boot klar and assert the app's own `listen()` calls produced `plugin:event|listen` records carrying a numeric `handler` (proves `transformCallback`→`invoke` routing); (b) assert `juradrop.emit` delivers the `{event,id,payload}` shape (a subscribed zone reacting proves payload unwrapping); (c) `page.evaluate(()=>window.__TAURI_INTERNALS__.invoke('definitely_not_a_command',{}))` rejects with a message containing `unmocked command:`. If `@tauri-apps/api` changes its routing, (a)/(b) break loudly.

## Phase 10 — Polish & cross-cutting (CI + verification)

- [ ] T026 Extend `.github/workflows/ci.yml` (spec 031): add `npx playwright install --with-deps chromium` + `npm run test:e2e` as a gate step on push-main + PR (FR-015). Keep read-only perms + concurrency-cancel.
- [ ] T027 Run `npm run test:e2e` locally; confirm green, suite < 60s (SC-004), zero `1+1` placeholder remains (SC-001), and the privacy assertion (no non-localhost request) passes.
- [ ] T028 SC-006 regression-detection spot-check: temporarily break one zone label / unwire one consent button, confirm a smoke test goes red, revert. Document the result in the spec's status note.
- [ ] T029 Run the full project gate (`npm run lint && npm run typecheck`, `cd src-tauri && cargo test`) to confirm the new test tree + config rewrite breaks nothing (Rust tests scan TS for forbidden patterns — lesson from specs 016/024).

---

## Dependencies & ordering

- **Phase 1 → Phase 2 → Phases 3–9 → Phase 10.**
- Phase 2 (T004–T006) is the hard blocker: every smoke spec imports the fixture + bridge.
- US1 (Phase 3) is the MVP — boot must work before any other assertion is meaningful.
- US2–US6 phases are independent of each other once Phase 2 exists; can be written in any order / parallel by file.
- T025 (contract) depends only on Phase 2.
- Phase 10 depends on all smoke specs existing.

## Parallel opportunities

- Within a spec file, `[P]` tasks touch the same file so run sequentially in practice; across files, `boot/zones/consent/panels/picker/events/contract` specs are independent once Phase 2 lands.

## MVP scope

Phases 1–3 (T001–T009) deliver the MVP: the placeholder is gone, the bridge exists, and the real frontend provably boots in Chromium against a mocked, network-free backend.
