# Feature Specification: Native Window Smoke (XCUITest against the real app)

**Feature Branch**: `037-native-window-smoke`

**Created**: 2026-06-05 (unblocked + amended by register rewrite; original row 2026-06-02)

**Status**: Draft

**Input**: Register row 037 as amended: "the spec-019 Option A made real: a Swift XCUITest target driving the built `.app` via the spec-016 'Välj fil' accessibility affordance (drag-drop is NOT a11y-drivable), asserting the twelve zones render + sidecar-on-pick for ≥1 zone. LOCAL-ONLY: XCUITest runs via a local script + quickstart, NO macOS CI workflow."

## Why this exists (the bug class nothing else catches)

The spec-013-era drag-drop position bug survived from spec 003 to spec 012 undetected because **no test ever drove the real window**. Today's coverage is layered but stops short of the native seam: Rust integration tests drive the real pipeline against mocks, vitest drives the React tree, Playwright (spec 033) drives the real frontend — in Chromium, with a mocked IPC bridge. None of them can catch: WKWebView-specific rendering failures, broken real Tauri IPC wiring, a native file-picker regression, or the window simply not showing its content. This spec adds the one harness that exercises the real `.app`: real WKWebView, real event loop, real IPC, real `NSOpenPanel`, real sidecar file on disk.

## Clarifications

### Session 2026-06-05 (inherited from the register rewrite — user-decided)

- Q: CI job? → A: NO — local-only runner script + quickstart; the github-actions budget rule forbids the macOS workflow (10× minutes). Recorded as an explicit register amendment.
- Q: Signed release app or debug build? → A: Debug build — it carries the spec-013 debug-only mock-endpoint seam, making the harness hermetic (no real model, no model download); ad-hoc signing is sufficient for a locally-run app. The release path stays covered by the existing release process.
- Q: Zone count? → A: Twelve (the row predated spec 036; updated in the rewrite).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The real window renders the real app (Priority: P1)

A developer (or the agent) runs the native smoke suite. It launches the actually-built JuraDrop app in a real window and asserts, through the macOS accessibility tree, that the twelve drop zones with their Swedish titles and the chrome (help + settings affordances) are present. If the WKWebView fails to render, the IPC bridge fails to boot, or the window comes up empty — the exact class of failure invisible to every existing suite — this fails loudly.

**Why this priority**: this is the assertion that would have caught the spec-003→012 bug class. Without it the spec has no reason to exist.

**Independent Test**: run the suite against the built app; break a zone title in source; rebuild; the suite goes red.

**Acceptance Scenarios**:

1. **Given** the debug app is built, **When** the suite launches it, **Then** a window appears and the accessibility tree exposes twelve zone elements with the canonical Swedish titles within a reasonable launch timeout.
2. **Given** the app is running under the harness, **Then** the chrome affordances (help, settings) are present in the accessibility tree.
3. **Given** the mock model endpoint reports the model present, **Then** the zones present as enabled (not the disabled/wizard state).

---

### User Story 2 - One full pipeline pass through the real seams (Priority: P1)

The suite drives one complete user journey natively: activate a zone's "Välj fil" affordance (the spec-016 accessibility path — OS drag-drop is not automatable), navigate the real native file picker to a fixture document, confirm, and assert that (a) the zone visibly reaches a success state and (b) the sidecar result file actually appears next to the fixture on disk. The model endpoint is the hermetic debug-seam mock — no real inference, no downloads.

**Why this priority**: shares P1 — rendering without interaction proves little; this is the end-to-end proof through real IPC, real picker, real file system.

**Independent Test**: run the suite; verify the sidecar file exists in the temp fixture directory afterwards and is cleaned up.

**Acceptance Scenarios**:

1. **Given** the running app and a temp directory containing a fixture document, **When** the suite activates "Välj fil" on one zone and selects the fixture via the native picker, **Then** the zone reaches a visible success state and a sidecar file with the zone's suffix exists next to the fixture.
2. **Given** the run completes (pass or fail), **Then** temp artifacts are removed and the app under test is terminated (no orphaned processes or files).
3. **Given** the mock endpoint returns a canned Swedish response, **Then** the sidecar content contains that canned response (the pipeline genuinely ran; the file is not a stale artifact).

---

### User Story 3 - One command, honest failures (Priority: P2)

A developer runs a single local script. It builds the debug app if stale, starts the mock model endpoint, runs the XCUITest suite via Xcode's command-line tools, reports pass/fail, and cleans up — mock server, app process, temp files — regardless of outcome. If macOS automation/accessibility permission is missing (a first-run reality), the script says so in plain language instead of letting the suite fail cryptically.

**Why this priority**: without a runner the harness rots — nobody hand-assembles a five-step incantation twice. P2 because US1/US2 can be exercised manually during development.

**Independent Test**: run the script from a clean shell on a machine with Xcode; it completes end-to-end. Revoke automation permission; it explains what to grant.

**Acceptance Scenarios**:

1. **Given** a Mac with Xcode and a built or buildable workspace, **When** the developer runs the script, **Then** it builds (if needed), tests, reports, and exits non-zero on failure.
2. **Given** automation permission has not been granted to the test runner, **Then** the script (or suite) surfaces a clear instruction naming the permission to grant, not a bare timeout.
3. **Given** the script is interrupted, **Then** a rerun works (stale processes/state from the previous run do not poison it).

---

### Edge Cases

- **WKWebView accessibility exposure is the load-bearing unknown** (named by the 019 research): if the web content's buttons are not visible to the automation API, the interaction path fails. The implementation MUST start with a feasibility probe; if web-content elements are not reachable, the fallback is the 019 Option B scope (window + chrome assertions only) and the spec is amended honestly — not silently shipped as "smoke" that smokes nothing.
- The native file picker may be an out-of-process remote view — path entry happens via the picker's go-to-folder affordance rather than element-by-element navigation.
- A previous JuraDrop instance already running → the runner terminates it first (single-instance assumptions must not poison the run).
- The app under test spawns its bundled sidecar process on launch even though the client talks to the mock seam → teardown must ensure the spawned process tree dies with the app.
- First run on a machine prompts for automation/accessibility consent → quickstart documents it; the script detects the denial case.
- Launch timing: model-ready state arrives asynchronously after launch → assertions wait with explicit timeouts, not sleeps.
- The suite must NOT run as part of `cargo test`/`npm test`/CI gates — it requires a GUI session and permissions; it is an opt-in local suite (its absence from the default gates is deliberate and documented).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST contain a native UI test suite (separate `ui-tests/` tree) that launches the built debug app in the real window and drives it through the macOS accessibility/automation API.
- **FR-002**: The suite MUST assert that all twelve zones expose their canonical Swedish titles and that the chrome affordances are present (US1).
- **FR-003**: The suite MUST drive one full pick-to-sidecar journey on at least one zone: "Välj fil" activation → native picker → fixture selection → visible success state → sidecar file on disk whose content reflects the mock response (US2).
- **FR-004**: The harness MUST be hermetic: the app under test is pointed at a local mock model endpoint via the existing debug-only seam; no real model, no model download, no network beyond localhost.
- **FR-005**: The suite MUST clean up after itself in all outcomes: app process tree terminated, mock server stopped, temp fixtures/sidecars removed.
- **FR-006**: A single local runner script MUST build (if stale), run, report, and clean up; it MUST exit non-zero on failure and run repeatably after interruption.
- **FR-007**: Missing automation/accessibility permission MUST surface as a plain, actionable message (script preflight or suite-level), never a bare timeout.
- **FR-008**: The suite MUST NOT be wired into `cargo test`, `npm test`, Playwright, or any CI workflow — local opt-in only (register amendment; github-actions rule).
- **FR-009**: The implementation MUST begin with a recorded feasibility probe of WKWebView accessibility exposure; if web-content interaction is infeasible, scope falls back to window/chrome assertions and the spec + register are amended to say exactly that.
- **FR-010**: Documentation MUST cover: how to run, what to grant on first run, what the suite does and deliberately does not cover.
- **FR-011**: The suite's assertions MUST wait on conditions with bounded timeouts (no fixed sleeps as correctness mechanisms).
- **FR-012**: All user-visible strings asserted by the suite MUST be sourced from the canonical string constants (no retyped Swedish literals that can drift).

### Key Entities

- **App under test**: the debug-built JuraDrop `.app` (ad-hoc signed), launched with a controlled environment (mock endpoint seam + temp paths).
- **Native test suite**: Swift XCUITest bundle in `ui-tests/`, independent of the Rust/TS test trees.
- **Mock model endpoint**: a localhost HTTP stub serving the minimal model-API surface the app touches (model listing + generation), with canned Swedish responses.
- **Runner script**: the one-command orchestrator (build → mock → test → report → clean).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The suite, run locally, verifies the real window renders all twelve zones — and goes red when a zone title is deliberately broken (mutation-style proof, performed once and recorded).
- **SC-002**: One native pick-to-sidecar journey completes with a sidecar file on disk containing the canned mock content — through real IPC and the real picker, with zero real-model involvement.
- **SC-003**: The full suite completes in under 5 minutes on this machine (build excluded), and leaves zero orphaned processes and zero temp residue.
- **SC-004**: A developer with Xcode can go from clean checkout to a completed run with one documented command (plus at most one one-time permission grant).
- **SC-005**: Zero new CI workflows, zero new runtime dependencies in the shipped app, zero changes to production code paths (the seam already exists) — or, where production changes prove necessary (e.g. an accessibility attribute), they are test-anchors only with no behavioral effect.

## Assumptions

- **Debug build is the test subject**: the `JURADROP_OLLAMA_URL` seam is `#[cfg(debug_assertions)]`-gated by design (spec 013) — testing the release binary hermetically is impossible without weakening that gate, which we will not do. The release binary's correctness is inferred from debug + the existing release process.
- **Sammanfatta with a `.txt` fixture** is the pick-to-sidecar zone: mirror-output gives a trivially-readable `.txt` sidecar.
- **`ui-tests/` location** per the 019 spike plan.
- **The suite runs on demand** (developer or agent, locally) — its cadence is "when native wiring changes or before releases", not every commit.
- **Xcode project scaffolding is committed** so the suite survives machine changes; generated build products are not.
