# Feature Specification: Frontend Playwright smoke tests

**Feature Branch**: `main` (solo, direct-push — no feature branch per `.claude/rules/spec-register.md`)

**Created**: 2026-06-02

**Status**: Draft

**Input**: User description: "Replace the placeholder Playwright test (`tests/e2e/placeholder.spec.ts`, which only asserts `1+1===2`) with real Playwright smoke tests that drive the actual React frontend in a real browser engine (Chromium) via the Vite dev server, with a mocked Tauri IPC bridge injected before the bundle loads."

## Context (why this spec exists)

Spec 019 (`macos-ui-test-harness`) recorded a hard blocker: JuraDrop is macOS-only, and driving the **real WKWebView** for true end-to-end UI tests is infeasible because no macOS WKWebView WebDriver exists for `tauri-driver`. Spec 019 explicitly deferred the testable substitute to a future spec. **This is that spec.**

Today `npm run test:e2e` runs a single placeholder that asserts `1 + 1 === 2`. It exists only so the script exits 0 on a fresh checkout. It exercises none of the React frontend. That means the entire interactive surface — the wizard→grid gate, the nine zones, the consent modal, settings/help panels, the click-to-browse picker, and the live status/zone/progress event channels — has **zero** browser-engine coverage. The vitest suite covers the React tree under jsdom (no real layout, no real browser event loop), and the Rust integration tests cover the pipeline, but nothing drives the assembled frontend in a real rendering engine.

The substitute spec 019 pre-planned: instead of the native window, serve the **real production frontend bundle** via the Vite dev server and drive it in **Chromium** through Playwright, with the Tauri IPC layer mocked. The frontend gates every Tauri behavior on `'__TAURI_INTERNALS__' in window`; `@tauri-apps/api` routes `invoke()` through `window.__TAURI_INTERNALS__.invoke(cmd, payload, options)` and `listen()` through `window.__TAURI_INTERNALS__.transformCallback(cb)` / `unregisterCallback(id)` plus `invoke('plugin:event|listen', …)`. A mock bridge injected **before the bundle loads** makes the unmodified frontend believe it is running inside Tauri, so Chromium can render and drive the real React tree while the backend is a controllable, deterministic, network-free double.

This is the **light** track: a UI/test-infrastructure feature, single actor (the test runner), no new production concurrency, no new production entities. It changes test infrastructure only — production frontend and Rust code are not expected to change.

## Clarifications

### Session 2026-06-02

- Q: How do smoke tests observe a zone's processing/success/error visual state — add production `data-*` state hooks, or assert on already-rendered content? → A: Assert on the already-rendered accessible DOM (visible Swedish text / role / `aria-*`) plus the existing `data-zone-id`; add an inert `data-*` hook to production code ONLY if a target state is not otherwise observable, and if added it MUST NOT alter runtime behavior (preserves SC-005).
- Q: Does this spec also wire `npm run test:e2e` into the existing CI gate (spec 031 `ci.yml`), or only deliver the suite runnable locally? → A: Wire it into CI — add a Playwright browser-install + `test:e2e` step to the on-push/PR gate, so the smoke suite actually runs on every push (fulfils SC-004's "run on every push"). This extends spec 031's gate rather than creating a new workflow.

## User Scenarios & Testing *(mandatory)*

The "user" of this feature is a **developer / CI runner** invoking `npm run test:e2e`. The value is browser-engine coverage of the frontend that the existing vitest (jsdom) and Rust suites structurally cannot provide.

### User Story 1 - Boot the real frontend in a browser with a deterministic backend double (Priority: P1)

A developer runs `npm run test:e2e`. Playwright boots the Vite dev server, opens the **production** frontend bundle in Chromium, and — because a mock Tauri IPC bridge is injected before the app code runs — the app behaves as if it is inside Tauri: it seeds its store from `get_status`, subscribes to the event channels, and renders the appropriate screen. No real Ollama, no real filesystem, no network — the backend is canned and controllable.

**Why this priority**: Without this, nothing else is testable. The injected-bridge boot is the foundation every other smoke test stands on. It alone proves the production bundle renders in a real engine without crashing — something the placeholder never did and jsdom cannot.

**Independent Test**: Run the suite with only this story implemented; assert the app reaches the zone grid (or the configured initial screen) and the page has no uncaught errors / console errors. Delivers "the real frontend boots in a browser against a mocked backend."

**Acceptance Scenarios**:

1. **Given** the mock bridge is configured to return `get_status` with `visible: 'klar'` and a ready sidecar/model, **When** the page loads in Chromium, **Then** the wizard is absent and the 3×3 zone grid is visible.
2. **Given** the app has loaded, **When** the test inspects the page, **Then** there are no uncaught exceptions and no React error-boundary fallback is shown.
3. **Given** the Vite dev server is not already running, **When** `npm run test:e2e` is invoked, **Then** Playwright starts Vite itself, waits for it to be reachable, runs the tests, and tears it down.

---

### User Story 2 - Smoke the core rendered surface (Priority: P1)

With the frontend booted to the ready state, the test asserts the load-bearing UI is actually present and correctly labelled in Swedish: all nine drop zones with their correct Swedish titles and the chrome (gear + help icons). The spec-002 `WelcomeCard` is **intentionally hidden at the ready (`klar`) state** (it returns `null` to give the grid the full window — verified in `WelcomeCard.tsx`; its status-string content is covered by vitest). The genuinely-reachable first-run surface is instead the **first-run wizard welcome screen** (shown when `consent='not_asked'`), which is what a real user sees on first launch — so that is what US2 smokes.

**Why this priority**: This is the minimum "the screen the user sees is the screen we shipped" guarantee. A regression that drops a zone, mislabels one, or breaks the grid would be caught here and nowhere else at the browser level.

**Independent Test**: Boot to ready, assert nine zones render with their canonical Swedish labels and the welcome card + chrome icons are present. Delivers "the shipped UI renders intact in a browser."

**Acceptance Scenarios**:

1. **Given** the app is at the ready state, **When** the grid renders, **Then** exactly nine drop zones are present, each carrying its `data-zone-id` and its correct Swedish label.
2. **Given** the app is at the ready state, **When** the page renders, **Then** both chrome icons (settings gear, help) are visible.
3. **Given** a fresh-install state (`consent='not_asked'`, `model='not_present'`), **When** the page renders, **Then** the first-run wizard welcome screen is visible (its `role="dialog"` + `#wizard-title` heading), and **Then** at the ready (`klar`) state that wizard is absent (the grid is shown instead).

---

### User Story 3 - Smoke the consent gate and its IPC wiring (Priority: P2)

When the mock backend reports status `begar_samtycke` (consent requested), the consent modal appears. Activating **Fortsätt** invokes `give_consent`; activating **Avbryt** invokes `cancel_consent`. The test verifies both the rendering and that the correct command crossed the (mocked) IPC boundary.

**Why this priority**: The consent gate is a privacy-load-bearing surface (Principle I / FR-019 lineage). Verifying the buttons call the right commands in a real browser closes a gap jsdom can only approximate.

**Independent Test**: Configure status `begar_samtycke`, assert modal shows, click each button, assert the expected command was recorded by the mock bridge. Delivers "the consent gate is wired to the right backend commands."

**Acceptance Scenarios**:

1. **Given** the mock backend returns/emits status `begar_samtycke`, **When** the app renders, **Then** the consent modal is visible with its Swedish copy.
2. **Given** the consent modal is visible, **When** the user activates **Fortsätt**, **Then** the mock bridge records an `invoke('give_consent')` call.
3. **Given** the consent modal is visible, **When** the user activates **Avbryt**, **Then** the mock bridge records an `invoke('cancel_consent')` call.

---

### User Story 4 - Smoke the panels (settings + help) and mutual exclusion (Priority: P2)

The settings panel opens via the gear icon and via the `Cmd+,` shortcut; the help panel opens via the help icon. Opening one closes the other (mutual exclusion). The test drives the real keyboard/click handlers in Chromium.

**Why this priority**: The panel open/close + mutual-exclusion state machine (spec 010/013 lineage) is interaction-heavy and exactly the kind of thing that breaks silently. The `Cmd+,` global shortcut in particular only truly works against a real key event loop.

**Independent Test**: Boot to ready, click gear → settings visible; press `Cmd+,` → toggles; click help → settings closes and help opens. Delivers "the panel state machine works under real browser events."

**Acceptance Scenarios**:

1. **Given** the app is at the ready state, **When** the user clicks the gear icon, **Then** the settings panel becomes visible.
2. **Given** the settings panel is closed, **When** the user presses `Cmd+,` (Meta+Comma), **Then** the settings panel becomes visible; pressing it again hides it.
3. **Given** the settings panel is open, **When** the user opens the help panel, **Then** the settings panel closes and the help panel is shown (at most one panel open at a time).

---

### User Story 5 - Smoke the click-to-browse picker path (Priority: P3)

Clicking a zone's **Välj fil** affordance opens the native picker (mocked `plugin:dialog|open`). When the mock returns a selected path, the frontend dispatches it to the correct zone via `dispatch_to_zone`. When the mock returns `null` (cancelled), nothing is dispatched.

**Why this priority**: This is the spec-016 accessible/keyboard-reachable alternative to drag-drop and the only interaction path that is actually drivable without simulating an OS drag. Confirming the picker→dispatch wiring in a browser is the closest this harness gets to the full drop pipeline.

**Independent Test**: Mock `plugin:dialog|open` to return a path, click **Välj fil** on a zone, assert `dispatch_to_zone` recorded with that zone id + path; repeat with `null` and assert no dispatch. Delivers "the click-to-browse path reaches the right backend command."

**Acceptance Scenarios**:

1. **Given** the mock picker returns a file path, **When** the user activates **Välj fil** on a specific zone, **Then** the mock bridge records `invoke('dispatch_to_zone', { zoneId: <that zone>, paths: [<that path>] })`.
2. **Given** the mock picker returns `null` (user cancelled), **When** the user activates **Välj fil**, **Then** no `dispatch_to_zone` call is recorded.

---

### User Story 6 - Smoke the live event channels (status + per-zone snapshots) (Priority: P3)

The harness can push backend events into the running frontend through the mock bridge's `emit` helper. Emitting a `juradrop://zone/<slug>` snapshot drives that zone's visible state (processing / success / error). Emitting a `juradrop://status` transition (e.g. `klar` → `begar_samtycke`) re-renders the app accordingly.

**Why this priority**: The event-subscription plumbing (`listen` → `transformCallback` → backend emit) is the most Tauri-internal-coupled part of the frontend and the part a naive mock most easily gets wrong. Proving an emitted event actually reaches a React state update validates the whole bridge contract end to end.

**Independent Test**: Boot to ready, emit a zone snapshot with state `processing`, assert the zone reflects it; emit `success`/`error`, assert each reflects; emit a status transition and assert the screen changes. Delivers "backend-pushed events drive the live UI through the mocked bridge."

**Acceptance Scenarios**:

1. **Given** the app is at the ready state, **When** the harness emits a `juradrop://zone/<slug>` snapshot with `state: 'processing'`, **Then** that zone visibly reflects the processing state.
2. **Given** a zone is processing, **When** the harness emits a snapshot with `state: 'success'` (then a separate one with `state: 'error'`), **Then** the zone reflects each terminal state in turn.
3. **Given** the app is at the ready state, **When** the harness emits a `juradrop://status` event transitioning to `begar_samtycke`, **Then** the consent modal appears without a page reload.

---

### Edge Cases

- **Vite port already in use / left running**: the Playwright `webServer` config must reuse an already-running dev server in local runs but start a fresh one in CI, and must point `baseURL` at the right port. A mismatch must fail loudly (test setup error), not hang.
- **Bridge injected too late**: if the mock bridge is registered after the app bundle evaluates, the `'__TAURI_INTERNALS__' in window` gate has already been read and the app runs in "not in Tauri" mode. The injection MUST happen via an init script that runs before any page script (before first paint), on every navigation.
- **Event emitted before the listener is registered**: a `juradrop://…` event emitted before the frontend's `listen()` has completed registration is dropped. Tests that emit events must first wait until the relevant UI is present (proving the subscription is live), or the harness must surface "no listener for event X" rather than silently swallowing.
- **Unhandled command**: if the frontend invokes a command the mock dispatch table does not know, the bridge must reject (or return a typed error) loudly enough that the test fails with a clear "unmocked command: X" message, rather than returning `undefined` and causing a confusing downstream failure.
- **once / unlisten semantics**: an unsubscribed listener (component unmounted, `unregisterCallback` called) must not receive subsequent emits; emitting to it must be a no-op, not a crash.
- **CSP**: spec 030 locked the WKWebView CSP. The Vite-served dev page is a different document; the smoke harness must not depend on relaxing production CSP, and must not introduce any real outbound network call (Principle I) from the test page.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `npm run test:e2e` MUST execute real Playwright tests that load the production React frontend in a Chromium browser context and MUST NOT contain the `1 + 1 === 2` placeholder assertion.
- **FR-002**: Playwright MUST serve the frontend via the Vite dev server (the same bundle the app ships, not the native Tauri app), managed by Playwright's `webServer` configuration so a developer/CI runner needs no manual server step.
- **FR-003**: A mock Tauri IPC bridge MUST be injected into the page **before** the application bundle evaluates, on every page load, so the production frontend's `'__TAURI_INTERNALS__' in window` gate reads `true` and all Tauri-gated code paths execute.
- **FR-004**: The mock bridge MUST implement the IPC contract `@tauri-apps/api` depends on: `transformCallback(cb, once)` returning a stable callback id, `unregisterCallback(id)`, and `invoke(cmd, payload, options)` returning a Promise.
- **FR-005**: The mock bridge's `invoke` MUST resolve the event-plugin commands — at minimum `plugin:event|listen` (register the callback id against the event name, return an event id) and `plugin:event|unlisten` (remove it) — so the frontend's `listen()`/unlisten cycle works.
- **FR-006**: The mock bridge MUST provide a command dispatch table returning deterministic canned data for every command the smoke tests exercise, including at least: `get_status`, `get_settings`, `get_tier_pull_state`, `get_tier_download_state`, `get_diagnostics_status`, `get_app_version`, `give_consent`, `cancel_consent`, `dispatch_to_zone`, and the dialog command `plugin:dialog|open`. Each test MUST be able to override the canned responses (e.g. set the initial `get_status`).
- **FR-007**: The mock bridge MUST record the commands invoked (name + payload) so a test can assert that activating a control produced the expected backend call (e.g. `give_consent`, `dispatch_to_zone`).
- **FR-008**: The mock bridge MUST expose a test-controllable `emit(event, payload)` helper that delivers an event to every live listener registered for that event name, calling the registered callback with the shape `{ event, id, payload }` that `@tauri-apps/api`'s `listen` handler expects.
- **FR-009**: Invoking an unmocked command MUST fail loudly (reject with a clear "unmocked command: X" message), never silently resolve to `undefined`.
- **FR-010**: Emitting an event with no live listener MUST be observably a no-op (and SHOULD be surfaceable to the test as "no listener"), and emitting to an unsubscribed/unregistered callback MUST NOT throw.
- **FR-011**: The smoke suite MUST cover, at minimum: boot-to-grid (US1), nine-zones-with-Swedish-labels + welcome card + chrome (US2), consent modal + Fortsätt/Avbryt command wiring (US3), settings panel via gear and `Cmd+,` + help panel + mutual exclusion (US4), Välj fil → picker → `dispatch_to_zone` incl. the cancelled-null case (US5), and emitted zone-snapshot + status-transition re-render (US6).
- **FR-012**: All mock-bridge and test code MUST live under the test tree (`tests/e2e/`) and MUST NOT be importable by or bundled into the shipped application. This feature MUST NOT add any production-frontend code change unless strictly required for testability; if any production change is required, it MUST be limited to adding inert test affordances (e.g. a stable `data-*` hook) and MUST NOT alter runtime behavior.
- **FR-013**: The mock bridge MUST make no real network calls and MUST return only canned local data, preserving Principle I (privacy by architecture) within the test harness itself.
- **FR-014**: The Playwright project MUST target Chromium and MUST run headless by default so it is CI-runnable on the existing `macos-latest` runner; the suite MUST exit non-zero on any failed smoke assertion.
- **FR-015**: The CI gate established in spec 031 (`.github/workflows/ci.yml`, on push to `main` + pull requests) MUST be extended with a step that installs the Chromium browser binary and runs `npm run test:e2e`, so the smoke suite executes on every push/PR (per the Q2 clarification). It MUST NOT be a separate workflow.
- **FR-016**: Smoke tests MUST observe rendered state through the already-present accessible DOM (visible Swedish text, ARIA roles/attributes) and the existing `data-zone-id` attribute. An inert `data-*` test hook MAY be added to production frontend code ONLY where a target state is otherwise unobservable, and any such hook MUST NOT change runtime behavior (per the Q1 clarification, preserving SC-005).
- **FR-017**: A contract-assertion test MUST pin the `@tauri-apps/api` IPC contract the mock bridge depends on — that `invoke` routes through `window.__TAURI_INTERNALS__.invoke`, that `listen` calls `transformCallback` then `invoke('plugin:event|listen', …)`, and that a transformed callback is invoked with the `{ event, id, payload }` shape — so a future `@tauri-apps/api` upgrade that breaks this contract fails loudly with a clear message rather than silently de-fanging the smoke suite. (Resolves the Allium open question surfaced during elicitation; the native-window coverage from that session's other "Fix now" decision is tracked separately as spec 037.)

### Key Entities

- **Mock Tauri IPC bridge**: the injected `window.__TAURI_INTERNALS__` double plus its test-facing control surface. Attributes: a callback registry (id → function), a listener registry (event name → set of callback ids), a command dispatch table (command → canned-response factory), an invocation log (recorded command calls), and an `emit` helper. No persistence; lives for the lifetime of one page.
- **Canned backend state**: the deterministic data the dispatch table returns — an `AppStatus`, a `SettingsSnapshot`, a `TierPullState`, a `DiagnosticsStatus`, an app version string, and the dialog `open` result. Per-test overridable.
- **Smoke test**: one Playwright test mapping to an acceptance scenario; sets up canned state + the page, drives the real UI, and asserts on rendered DOM and/or the invocation log.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `npm run test:e2e` runs the real Chromium-driven smoke suite (zero `1+1` placeholder assertions remain) and exits 0 on a clean checkout with no manual setup step.
- **SC-002**: The suite covers 100% of the six user stories' acceptance scenarios, with at least one assertion per scenario — boot, nine labelled zones, consent wiring, panel state machine, picker dispatch, and live event re-render.
- **SC-003**: At least one smoke test proves an emitted backend event reaches a visible React state change (the event-channel contract is exercised end to end, not just `invoke`).
- **SC-004**: The full smoke suite completes in under 60 seconds locally on an M-series Mac (fast enough to run on every push without friction).
- **SC-005**: Zero production application files change runtime behavior as a result of this feature; any production diff is limited to inert test hooks (verifiable by diff review), and no new outbound network call is introduced (Principle I holds).
- **SC-006**: A developer can introduce a deliberate frontend regression (e.g. delete a zone, mislabel one, or unwire a consent button) and at least one smoke test turns red — i.e. the suite has real detection power, not just green-by-construction.

## Assumptions

- Chromium (bundled via `@playwright/test`, already a devDependency) is an acceptable rendering engine for smoke coverage. It is **not** WKWebView; this harness deliberately trades native-engine fidelity for testability, exactly as spec 019 framed it. Native-window coverage is tracked as its own spec **037 (native-window-smoke, Swift XCUITest, blocked-on-hardware)** and is out of scope here.
- The Vite dev server serves the same React/TS source the production bundle is built from; differences between dev and production builds (minification, CSP) are out of scope for smoke coverage.
- The frontend's `'__TAURI_INTERNALS__' in window` detection and the `@tauri-apps/api` v2.11 `invoke`/`listen`/`transformCallback` contract (as read from `node_modules/@tauri-apps/api/{core,event}.js`) are the integration surface; if a future `@tauri-apps/api` upgrade changes that contract, the mock bridge must be updated in lockstep. FR-017's contract-assertion test makes such a break fail loudly rather than silently.
- `plugin-dialog`'s `open` routes through `invoke('plugin:dialog|open', …)`; mocking that command id is sufficient to mock the picker without a real native dialog.
- Drag-and-drop of a real file (the OS-level drop path) is **not** simulatable in this harness (Tauri suppresses HTML5 dragover and the drop arrives as a native event); the picker path (US5) is the dispatch coverage substitute, consistent with spec 016/019.
- This is the **light** track: no new production state machine, so `/tla` is not required unless the mock bridge's listener/emit logic is judged a non-trivial state machine during planning (it is a simple registry, so TLA+ is expected to be skipped).
- Solo / direct-push project: work lands on `main` directly, no feature branch, per `.claude/rules/spec-register.md`.
