# Feature Specification: macOS UI test harness (RESEARCH — BLOCKED)

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: BLOCKED (native tooling not runnable in this environment)
**Track**: Research spike. No implementation in this run — scaffolding + a spike plan only.

## The blocker (why this is not implemented)

JuraDrop is macOS-only by constitution. Driving the real WKWebView for true end-to-end UI tests requires a WebDriver/automation bridge that **does not exist** for macOS:

- The earlier (withdrawn) spec 013 established it directly: the official Tauri 2.x docs state *"On desktop, only Windows and Linux are supported [for WebDriver] due to macOS not having a WKWebView driver tool available."*
- So `tauri-driver` + Playwright/WebdriverIO is fundamentally infeasible on this platform until Apple ships a WKWebView WebDriver, or the Tauri team finds an alternative.

This is also why the spec-013-era drag-drop position bug survived from spec 003 → spec 012 undetected: **no test ever drove the real window.** The Rust integration tests (spec 013) + vitest now cover the pipeline and the React tree, but not the native window's actual event wiring.

## Why this spec exists

To record the gap honestly and pre-plan the only viable substitute so it can be picked up when someone has a real Mac + the time, rather than rediscovering the blocker.

## The two viable approaches (spike plan)

### Option A — XCUITest (native, recommended if pursued)
- A small XCUITest target that launches the built `.app`, performs accessibility-API interactions (focus the "Välj fil" button — spec 016 made this keyboard-reachable! — activate it, assert the sidecar appears), and queries the WKWebView's accessibility tree.
- **Pros:** real window, real event loop, the only thing that would have caught the drag-drop bug.
- **Cons:** native Swift/Xcode harness, separate from `cargo test`; CI needs a macOS runner with Xcode; ~1–2 weeks setup; WKWebView a11y tree is awkward to query.
- **Leverage from spec 016:** the click-to-browse affordance is accessibility-API-drivable (drag-drop is not), so XCUITest can exercise the full pipeline via the picker without simulating an OS drag.

### Option B — Accessibility-API smoke (lighter)
- A Rust or Swift helper using the macOS Accessibility API (AXUIElement) to assert the 9 zones + chrome render with correct labels in the real window, without full interaction.
- **Pros:** lighter than XCUITest; catches "window renders, labels present, nothing panics on launch."
- **Cons:** doesn't exercise the drop/dispatch path; partial coverage.

## User action items (BLOCKED ON YOU / future)

- [ ] Decide whether the ~1–2 week XCUITest investment is worth it now, or defer until Tauri/Apple ship macOS WebDriver.
- [ ] If pursuing: add a `ui-tests/` XCUITest target driving the built `.app` via the spec-016 "Välj fil" affordance; add a macOS+Xcode CI job; assert sidecar-on-pick for ≥1 zone.
- [ ] Re-evaluate when Tauri 2.x ships macOS WebDriver (then `tauri-driver` + Playwright becomes viable and this spec is superseded).

## Status
SCAFFOLDED — research recorded, spike planned. No code. Re-open as a `full`/`light` spec when the user commits to the XCUITest path or WebDriver lands.
