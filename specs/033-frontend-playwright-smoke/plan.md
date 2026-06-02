# Implementation Plan: Frontend Playwright smoke tests

**Branch**: `main` (solo, direct-push) | **Date**: 2026-06-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/033-frontend-playwright-smoke/spec.md`

## Summary

Replace the `1+1===2` placeholder e2e test with a real Playwright smoke suite that boots the **production** React frontend in **Chromium** via the Vite dev server, with a mocked Tauri IPC bridge (`window.__TAURI_INTERNALS__`) injected before the bundle evaluates. The bridge reproduces the `@tauri-apps/api` v2.11 `invoke`/`listen`/`transformCallback` contract deterministically and network-free (Principle I), so the unmodified frontend renders and behaves as if inside Tauri. Six smoke groups cover boot-to-grid, nine labelled zones + chrome, consent wiring, panel state machine, picker→dispatch, and live event-channel re-render — plus a contract-assertion test (FR-017) pinning the `@tauri-apps/api` IPC shapes. Wire the suite into the spec-031 CI gate (FR-015).

**Key enabling discovery (read from code):** the frontend already exposes everything the assertions need — `DropZone` renders `data-zone-id`, `data-state` (idle/dragover/processing/success/error), `data-disabled`, and the picker button carries `data-zone-pick={zoneId}` with `aria-label="Välj fil för …"`. **Therefore zero production-code change is required** (SC-005 holds by construction).

## Technical Context

**Language/Version**: TypeScript 5.9 (test code), Node ESM; targets the existing React 18 + Vite 5 frontend.

**Primary Dependencies**: `@playwright/test` ^1.60 (already a devDependency, no new dep), Vite dev server (existing), `@tauri-apps/api` v2.11 + `@tauri-apps/plugin-dialog` v2.7 (the contract being mocked — read, not bundled into tests).

**Storage**: N/A — canned in-memory state per page, no persistence.

**Testing**: Playwright (Chromium project, headless) driven by `npm run test:e2e`; the bridge is injected via `page.addInitScript` / a fixture.

**Target Platform**: Chromium under Playwright on `macos-latest` (CI) and local M-series Mac. Explicitly NOT WKWebView — native-window fidelity is spec 037's job.

**Project Type**: Desktop-app frontend test harness (test infrastructure only).

**Performance Goals**: Full suite < 60s locally (SC-004).

**Constraints**: No real network calls (Principle I / FR-013); bridge injected before first paint (FR-003); unmocked command rejects loudly (FR-009); no production runtime behavior change (FR-012 / SC-005).

**Scale/Scope**: ~6 spec files under `tests/e2e/`, one mock-bridge module, ~12–16 smoke tests across 6 user stories + 1 contract test, plus a `playwright.config.ts` rewrite and a CI step.

## Constitution Check

*GATE: must pass before Phase 0; re-checked after Phase 1.*

| Principle | Verdict | Note |
|---|---|---|
| I — Privacy by architecture | ✅ PASS (strengthens) | Bridge returns only canned local data; `network_calls = 0` invariant; no Ollama, no telemetry. The harness can detect a future egress regression but introduces none. |
| II — Zero-CLI install | ✅ N/A | Test infrastructure; not in the install/usage path. |
| III — Local-only inference | ✅ N/A | No inference; `plugin:dialog\|open` and all commands are mocked. |
| IV — Single-user desktop | ✅ N/A | No backend/accounts introduced. |
| V — Swedish UI / English code | ✅ PASS | Test code + comments in English; assertions read the shipped Swedish strings. |
| VI — Native macOS feel | ✅ N/A (documented tradeoff) | Chromium ≠ WKWebView; this is the deliberate, spec-019-framed testability tradeoff, tracked alongside spec 037 for true native coverage. Not a violation — a recorded fidelity limit. |
| VII / VIII — Honest failure | ✅ PASS | FR-009: unmocked command rejects with a clear message, never silent `undefined`. |

**No violations. No complexity-tracking entries required.** Re-check after Phase 1: still clean — design adds no production code, no deps, no egress.

## Project Structure

### Documentation (this feature)

```text
specs/033-frontend-playwright-smoke/
├── spec.md
├── spec.allium
├── plan.md              # this file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── mock-bridge-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
tests/e2e/
├── placeholder.spec.ts          # DELETED (replaced)
├── support/
│   ├── tauri-mock.ts            # the injected window.__TAURI_INTERNALS__ double (string-serializable init script)
│   ├── canned-state.ts          # default AppStatus/SettingsSnapshot/TierPullState/… + per-test overrides
│   └── fixtures.ts              # Playwright test fixture: injects the bridge before load, exposes page helpers (emit, invocationLog)
├── boot.spec.ts                 # US1 — boot-to-grid, no crash, webServer
├── zones.spec.ts                # US2 — nine zones + Swedish labels + welcome card + chrome
├── consent.spec.ts              # US3 — consent modal + Fortsätt/Avbryt → give/cancel_consent
├── panels.spec.ts               # US4 — settings via gear + Cmd+, ; help; mutual exclusion
├── picker.spec.ts               # US5 — Välj fil → plugin:dialog|open → dispatch_to_zone (+ null cancel)
├── events.spec.ts               # US6 — emitted zone snapshot + status transition re-render
└── contract.spec.ts             # FR-017 — pin @tauri-apps/api invoke/listen/transformCallback shapes

playwright.config.ts             # rewritten: chromium project, webServer→vite:1420, baseURL, headless
.github/workflows/ci.yml         # FR-015 — add browser-install + test:e2e step
```

### Production code

**No changes.** The frontend already provides the required selectors (`data-zone-id`, `data-state`, `data-zone-pick`, `aria-label`s, role-based dialog/buttons). FR-016's escape hatch (inert `data-*` hook) is NOT needed.

## Phase 0 — Research

See [research.md](./research.md). Resolved: the exact `@tauri-apps/api` v2.11 IPC contract (from `node_modules/@tauri-apps/api/{core,event}.js`), the init-script injection timing, the Vite port/`webServer` config, the event-delivery callback shape, the canned-state shapes needed to render the wizard-gated grid + settings panel without crashing, and the Chromium-vs-WKWebView fidelity boundary.

## Phase 1 — Design & Contracts

- **[data-model.md](./data-model.md)** — the bridge's internal registries (callbacks, listeners, command table, invocation log) and the canned-state shapes.
- **[contracts/mock-bridge-contract.md](./contracts/mock-bridge-contract.md)** — the exact `window.__TAURI_INTERNALS__` surface the bridge must implement and the test-facing control API (`__JURADROP_TEST__.emit`, `.invocationLog`, `.setCanned`).
- **[quickstart.md](./quickstart.md)** — how to run the suite, how to add a smoke test, and the regression-detection check (SC-006).

### Agent context

CLAUDE.md's active-spec block is updated to point at this plan.

## Phase 2 — Tasks

Generated by `/speckit-tasks` into `tasks.md`.
