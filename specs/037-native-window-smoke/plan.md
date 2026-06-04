# Implementation Plan: Native Window Smoke

**Branch**: `main` (register rule) | **Date**: 2026-06-05 | **Spec**: [spec.md](spec.md)

**Input**: spec.md + spec.allium (post-clarify; register-amended local-only scope)

## Summary

A hand-committed minimal Xcode project (`ui-tests/`) hosting one XCUITest bundle that launches the debug-built `JuraDrop.app` with `JURADROP_OLLAMA_URL` pointed at a local Python-stdlib mock (ephemeral port), asserts the twelve zones + chrome via the accessibility tree, drives one Välj fil → native picker → sidecar journey, and cleans up. One runner script (`scripts/native-smoke.sh`) orchestrates build → mock → `xcodebuild test` → teardown. Implementation begins with the FR-009 feasibility probe (WKWebView a11y exposure) — everything downstream is shaped by its outcome.

## Technical Context

**Language/Version**: Swift 5 (XCUITest, Xcode 26.5), Bash (runner), Python 3 stdlib (mock server). No Rust/TS production changes expected (SC-005).

**Primary Dependencies**: zero new — Xcode is present on the machine; python3 ships with dev environments; the `JURADROP_OLLAMA_URL` seam exists (spec 013, `#[cfg(debug_assertions)]`, client.rs:88).

**Storage**: temp dir per run (fixture + sidecar), removed in teardown.

**Testing**: the deliverable IS a test suite. Its own verification = SC-001 mutation proof (break a title → red) + a green run + clean-teardown check.

**Target Platform**: this Mac (darwin, GUI session, Xcode 26.5 at /Applications/Xcode.app).

**Project Type**: desktop-app + new `ui-tests/` native harness tree.

**Performance Goals**: suite < 5 min excluding build (SC-003).

**Constraints**: NO CI wiring (FR-008, register amendment); opt-in only — absent from cargo/npm/Playwright gates; hermetic inference (FR-004).

**Scale/Scope**: ~6 new files (xcodeproj + scheme + 1 Swift test file + mock script + runner script + quickstart docs), 0 production code changes expected.

## Constitution Check

| Principle | Verdict | Evidence |
|---|---|---|
| I. Privacy | PASS | Harness is local tooling; mock is localhost; no user content exists in test fixtures beyond synthetic Swedish sentences. |
| II. Zero-CLI | PASS | Developer tooling, not user path — the install/usage path is untouched. |
| III. Local-Only Inference | PASS | The seam is debug-only and already shipped (spec 013); no remote-host override is added to release builds. |
| IV. Single-User Desktop | PASS | No app changes. |
| V. Swedish UI / English code | PASS | Swift/Bash/Python in English; asserted strings sourced from the canonical Swedish constants (FR-012). |
| VI–IX | PASS | n/a or untouched. |

**Violations**: none.

## Key mechanics (Phase 0 summary — rationale in research.md)

1. **Build target**: `npm run tauri build -- --debug --target aarch64-apple-darwin` → `src-tauri/target/aarch64-apple-darwin/debug/bundle/macos/JuraDrop.app` (debug profile ⇒ the seam compiles in; ad-hoc signed; bundles the sidecar binary). Runner rebuilds only when sources are newer than the bundle (mtime check) or `--build` is forced.
2. **Launch**: register the built app with LaunchServices (`lsregister -f <app>`), then `XCUIApplication(bundleIdentifier: "se.noisycricket.juradrop")` with `launchEnvironment = ["JURADROP_OLLAMA_URL": mockURL]`. The hardcoded spec-026 adoption probe (manager.rs:88, `127.0.0.1:11434`) is left alone: whether the user's real Ollama occupies 11434 (adopt) or the bundled sidecar spawns (port free), INFERENCE goes to the mock via the seam either way — hermetic in both environments, and the sidecar path exercised is the app's true behavior.
3. **Mock** (`scripts/mock-ollama.py`): stdlib `http.server` on an ephemeral port; `GET /api/tags` → `{"models":[{"name":"gemma3:4b"}]}` (matches `ListTagsResponse`); `POST /api/generate` → single JSON `{response: "<canned Swedish>", done: true}` (the client sends `stream:false`). Prints its port to stdout for the runner; `--port` override for the test's env.
4. **Xcode scaffolding**: minimal hand-committed project — a dummy host app target (`HarnessHost`, never shipped, required so the UI-testing bundle has a runner host) + `JuraDropUITests` UI-testing bundle + one shared scheme. No Rust/TS coupling.
5. **Probe first (FR-009)**: the first test launches the app and dumps `XCUIApplication.debugDescription`; web-content buttons reachable ⇒ full scope; not reachable ⇒ STOP, amend spec/register to chrome-only (the allium `chrome_only_fallback` path), then continue with the reduced scope.
6. **Picker driving**: activate `Välj fil` (a11y label `Välj fil för Sammanfatta`), then in the open panel: `Cmd+Shift+G` → type the temp fixture path → Return → Return/Öppna. Sidecar assertion = `FileManager` polling (bounded `XCTNSPredicateExpectation`-style waits, no sleeps) for `dokument.sammanfatta.txt` containing the canned text.
7. **Cleanup**: Swift `addTeardownBlock` terminates the app; the runner additionally `pkill`s strays, stops the mock, and removes the temp dir — pass or fail (trap EXIT).
8. **Permission preflight**: runner probes `osascript -e 'tell application "System Events" to count processes'`; on failure prints the exact System Settings pane to open (Privacy & Security → Automation/Accessibility) and exits 2.
9. **Asserted strings**: a tiny generated header is NOT worth it — the suite reads zone titles from `src/components/DropZone.identity.ts`? No: simplest canonical source readable from Swift at test-build time is the JSON help fixture + a checked constant list; decision in research R6 (the twelve titles come from a small generated `ZoneTitles.json` the runner exports from the canonical TS source via `node -e`, so Swift never hardcodes Swedish).

## Project Structure

```text
ui-tests/
├── JuraDropUITests.xcodeproj/        # hand-committed minimal project + shared scheme
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/JuraDropUITests.xcscheme
├── HarnessHost/                      # dummy host app (a window-less stub)
│   ├── main.swift
│   └── Info.plist
└── JuraDropUITests/
    ├── NativeWindowSmokeTests.swift  # probe + render + pick-to-sidecar
    └── Info.plist

scripts/
├── native-smoke.sh                   # the one-command runner (build→mock→test→clean)
└── mock-ollama.py                    # stdlib mock endpoint

specs/037-native-window-smoke/        # this documentation
docs (quickstart.md)                  # run + permission instructions
```

**Structure Decision**: `ui-tests/` per the 019 spike plan; nothing under `src/`/`src-tauri/` changes (SC-005), except IF the probe shows an a11y anchor is needed (then: additive `aria-label`-class attributes only, recorded explicitly).

## Verification mapping

| Requirement | Proof |
|---|---|
| FR-001/002, SC-001 | green run asserting 12 titles + chrome; one recorded mutation run (broken title → red) |
| FR-003, SC-002 | sidecar file exists + contains canned text after the native journey |
| FR-004 | mock-only URL in launchEnvironment; no model on disk consulted; runner asserts no outbound beyond localhost (structural) |
| FR-005/SC-003 | runner trap-EXIT teardown; post-run `pgrep` + temp-dir checks in the script |
| FR-006/007 | script behavior: non-zero exit on failure; preflight permission message |
| FR-008 | no gate/CI file references the suite (grep-able absence; analyze checks) |
| FR-009 | probe test runs FIRST; outcome recorded in the register/spec on fallback |
| FR-011 | XCUITest `waitForExistence(timeout:)` / expectation waits only |
| FR-012 | titles exported from the canonical TS identity source at run time |
