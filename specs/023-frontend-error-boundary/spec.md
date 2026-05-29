# Feature Specification: Frontend error boundary

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: Draft
**Track**: Light (UI feature; new component/rule → `.allium`; trivial 2-state → skip `/tla`).

**Input**: If any React component throws during render, the whole WKWebView goes blank — a white screen with no explanation. That violates Principle VIII (honest failure states) on the frontend: the user gets neither a plain-Swedish message nor a way out. Add a top-level React error boundary that catches render crashes and shows a calm Swedish fallback ("Något gick fel i appen. Starta om så försöker vi igen.") with a restart button — never a blank screen, never a stack trace.

## Why this spec exists

Confirmed gap: `grep -rn "ErrorBoundary|componentDidCatch|getDerivedStateFromError" src/` returns nothing. The Rust side has honest-failure discipline (spec 011); the React tree has none. A single boundary closes the frontend half of Principle VIII.

## What's IN scope

| Item | Type |
|---|---|
| `ErrorBoundary` class component (the only React API that catches render errors) | Code (UI) |
| Swedish fallback UI: message + "Starta om"-button (reloads the webview) | Code (UI) |
| Wrap `<App/>` in the boundary (main.tsx) | Code |
| Never leak the error text/stack to the UI (Principle VIII); log to console only | Code |
| vitest: a throwing child renders the Swedish fallback, not the error; reload button present | Test |

## What's OUT of scope

| Item | Reason |
|---|---|
| Per-component granular boundaries | One top-level boundary is the right scope; per-zone crashes are already state-handled by the store |
| Sending the error anywhere | Principle I — no telemetry; console-only, local |
| Recovering in-place without reload | A render crash means corrupt UI state; a clean reload is the honest recovery |

## Clarifications

### Session 2026-05-29 (auto-picked)

- Q: Recover in-place or reload? → A: **Reload.** A render crash implies corrupt component state; the honest, reliable recovery is a clean `window.location.reload()` via a "Starta om"-button, not a partial in-place retry.
- Q: Show the error detail? → A: **No.** Principle VIII — plain Swedish only; the actual error goes to `console.error` (local, dev-visible), never to the UI.
- Q: One boundary or several? → A: **One top-level boundary** wrapping `<App/>`. Per-zone failures already have store-driven error states; this catches the catastrophic render-time crash.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A render crash shows Swedish, not a white screen (Priority: P1)

A component throws during render. Instead of a blank WKWebView, the user sees "Något gick fel i appen. Starta om så försöker vi igen." and a "Starta om"-button.

**Independent Test**: vitest — render `<ErrorBoundary><Throws/></ErrorBoundary>`; assert the Swedish fallback text + the restart button are present and the thrown error message is NOT in the DOM.

**Acceptance Scenarios**:
1. **Given** a child that throws on render, **When** the boundary catches it, **Then** the Swedish fallback message + "Starta om"-button render.
2. **Given** the fallback is shown, **When** the DOM is inspected, **Then** the raw error/stack text is absent (Principle VIII).
3. **Given** a non-throwing child, **When** rendered, **Then** the boundary renders the child transparently (no fallback).

### Edge Cases

- The fallback copy is Swedish, humanizer-reviewed.
- "Starta om" calls `window.location.reload()` (full webview reload).
- The boundary itself must not throw (no store/tauri access in its render).

## Requirements

- **FR-001**: `src/components/ErrorBoundary.tsx` MUST be a class component implementing `getDerivedStateFromError` (+ `componentDidCatch` for `console.error` logging) that renders a fallback on caught render errors.
- **FR-002**: The fallback MUST show a Swedish message + a "Starta om"-button that calls `window.location.reload()`. Calm, matching the app aesthetic.
- **FR-003**: The fallback MUST NOT render the error message or stack (Principle VIII); the error goes to `console.error` only.
- **FR-004**: `<App/>` MUST be wrapped in `<ErrorBoundary>` at the mount point (`src/main.tsx`).
- **FR-005**: Fallback copy MUST be Swedish, humanizer-reviewed.

## Success Criteria

- **SC-001**: A throwing child renders the Swedish fallback + restart button (not a white screen). Verified by vitest.
- **SC-002**: The raw error/stack is absent from the fallback DOM. Verified by vitest.
- **SC-003**: A non-throwing child renders transparently. Verified by vitest.
- **SC-004**: Net new deps: 0.
