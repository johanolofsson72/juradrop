# Implementation Plan: 001 — Tauri Bootstrap

**Branch**: `main` (direct-push per `.claude/rules/spec-register.md`) | **Date**: 2026-05-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-tauri-bootstrap/spec.md`. Allium spec at [spec.allium](./spec.allium).

## Summary

Scaffold the JuraDrop project foundation so every later spec has a working dev loop. Deliverable: a Tauri 2.x project with React 18 + TypeScript + Tailwind + shadcn/ui in the WebView, a Rust backend with one smoke test, all six toolchain scripts (`tauri dev`, `tauri build`, `test`, `lint`, `typecheck`, `test:e2e`) wired and green on a fresh clone, and a single window that opens to a placeholder welcome card. Deny-by-default capability allowlist. aarch64-apple-darwin release target. No outbound network traffic except the Vite dev-server loopback. No signing, no sidecar, no drop zones — all explicitly deferred to later specs in `specs/INDEX.md`.

## Technical Context

**Language/Version**: Rust (stable, ≥ 1.75 per Tauri 2.x baseline) for the desktop core. TypeScript 5.x with `strict: true` for the React WebView.

**Primary Dependencies**:
- **Tauri 2.x** — `tauri = "2"`, `tauri-build = "2"` (Cargo); `@tauri-apps/cli = "^2"`, `@tauri-apps/api = "^2"` (npm).
- **React 18+** with `@types/react`, `@types/react-dom`.
- **Vite 5+** as the WebView dev server and bundler.
- **Tailwind CSS 3+** with PostCSS + Autoprefixer.
- **shadcn/ui** registry initialised with the New York style + neutral base color (matches the Resize Images / native macOS aesthetic referenced in `project_juradrop` memory). Components installed at this spec: `Button` (FR-007), `Card` (welcome card wrapper).
- **Vitest** + `@testing-library/react` + `jsdom` for unit/component tests.
- **Playwright** scaffolded but the `test:e2e` script is a stub command at this spec (real E2E driving the built `.app` is wired in spec 003 when there's actual interactive surface).
- **ESLint 9** flat config + `@typescript-eslint`, `eslint-plugin-react`, `eslint-plugin-react-hooks`.
- **Prettier** (formatting; not strictly required by the spec but standard with shadcn/ui).

**Storage**: None at this spec. Settings persistence arrives in spec 010.

**Testing**: Vitest (frontend) + `cargo test` (Rust). Playwright stub for `test:e2e` to keep the script available without driving anything yet.

**Target Platform**: macOS 12+, Apple Silicon only at this spec (`aarch64-apple-darwin`). Universal2 binary arrives with spec 006.

**Project Type**: Single desktop app — frontend (`src/`) + Rust core (`src-tauri/`). Two-tree layout, single repo.

**Performance Goals**: Dev window startup ≤ 10 s (second run, SC-004). `npm install` ≤ 2 min, `cargo build` ≤ 5 min on a cold cache on M1.

**Constraints**:
- Deny-by-default Tauri capability allowlist — no plugins, no core APIs granted to the WebView at this spec (FR-019).
- Zero outbound network traffic except 127.0.0.1 loopback in dev profile (FR-016, amended).
- All Tailwind utility classes resolve at build time; no runtime CSS-in-JS.
- SF Pro is the default font family per FR-009 + Constitution Principle VI.

**Scale/Scope**: One window, one placeholder card, ~12 functional coverage tests and 9 destructive tests planned (per spec). Zero domain entities at this spec.

## Constitution Check

*GATE: Must pass before Phase 0. Re-checked after Phase 1.*

Mapping each constitution principle against this plan:

| # | Principle | Plan compliance |
|---|-----------|----------------|
| I | Privacy by Architecture (NON-NEGOTIABLE) | **PASS.** No outbound network calls in scaffolded code. Vite dev-server loopback is dev-profile-only and goes through 127.0.0.1, explicitly excluded by amended FR-016. No telemetry, no analytics, no crash reporting in this spec. |
| II | Zero-CLI Install | **PASS (deferred verification).** Signing + DMG are out of scope for this spec (spec 006). At this spec, dev work is necessarily CLI-driven — that is developer experience, not end-user install. The constitution targets end-user install, not dev environment setup. |
| III | Local-Only Inference | **PASS (vacuous).** No LLM integration at this spec; first sidecar bring-up is spec 002. |
| IV | Single-User Desktop App | **PASS.** Single window, no backend, no daemon, no menu-bar tray. `tauri.conf.json` configures a single window; closing it quits the app (FR-010, captured in `tauri.conf.json` via the macOS-specific `decorations` + `closable` + close-window-quits-app semantics). |
| V | Swedish-First UI, English-First Code | **PASS.** The only user-facing copy in this spec is the welcome card subtitle "Lokal AI för svenska juriststudenter" (Swedish). All code, comments, commits, file names: English. |
| VI | Native macOS Feel | **PASS.** SF Pro via the macOS system font stack in Tailwind's `theme.extend.fontFamily`. Standard window chrome (no custom title bar at this spec). Auto dark/light via Tailwind's `darkMode: 'media'` (uses `prefers-color-scheme`). No bouncing/confetti motion in the placeholder card. |
| VII | Bundled Sidecar | **PASS (vacuous).** No sidecar at this spec. |
| VIII | Honest Failure States | **PASS.** There are no failure states at this spec beyond a window failing to open (which is a developer-level failure, not a user-level one). Plain-Swedish error states arrive with spec 003. |
| IX | Open Source, Free, No Lock-In | **PASS.** MIT license already in repo. No paywalls, no telemetry, output is plain HTML/CSS/JS + WebView. |

**Result**: All nine principles pass. No violations. No Complexity Tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/001-tauri-bootstrap/
├── spec.md                  # Markdown specification (done)
├── spec.allium              # Formal Allium spec (done)
├── checklists/
│   └── requirements.md      # Quality checklist (done)
├── plan.md                  # This file
├── research.md              # Phase 0 output (this command)
├── data-model.md            # Phase 1 output (this command)
├── quickstart.md            # Phase 1 output (this command)
├── contracts/               # Phase 1 output (this command)
│   ├── tauri-conf.md        # tauri.conf.json shape contract
│   └── package-scripts.md   # npm scripts contract
└── tasks.md                 # /speckit-tasks output (NOT created here)
```

### Source Code (repository root)

```text
juradrop/                              # repo root (working dir name: revisorstudent — legacy, see project memory)
├── package.json                       # FR-002: tauri dev/build, test, lint, typecheck, test:e2e
├── package-lock.json                  # committed (npm is the lockfile authority)
├── tsconfig.json                      # FR-003: strict + noUncheckedIndexedAccess
├── tsconfig.node.json                 # Vite/Node-side TS config
├── vite.config.ts                     # Vite + Tauri dev server config
├── tailwind.config.ts                 # FR-005: utility config, dark variant, SF Pro font stack (FR-009)
├── postcss.config.js                  # PostCSS + Tailwind plugin
├── eslint.config.js                   # FR-004: ESLint 9 flat config
├── .prettierrc                        # Prettier config (companion to ESLint)
├── components.json                    # shadcn/ui registry config (style=new-york, base=neutral)
├── index.html                         # Vite entry HTML
├── README.md                          # FR-017: prerequisites + commands (already exists; update if needed)
│
├── src/                               # React + TypeScript WebView code
│   ├── main.tsx                       # React root mount
│   ├── App.tsx                        # Renders the placeholder welcome card (FR-007)
│   ├── components/
│   │   ├── WelcomeCard.tsx            # The welcome card; uses shadcn Card + Button (FR-007, FC-002..FC-004)
│   │   └── ui/                        # shadcn-generated components
│   │       ├── button.tsx             # shadcn Button (registry add)
│   │       └── card.tsx               # shadcn Card (registry add)
│   ├── lib/
│   │   └── utils.ts                   # shadcn's cn() helper
│   ├── styles/
│   │   └── globals.css                # Tailwind base/components/utilities directives
│   └── __tests__/
│       ├── App.test.tsx               # FC-002, FC-003, FC-004 — DOM-level rendering assertions
│       ├── WelcomeCard.test.tsx       # FC-002..FC-004 detail
│       └── smoke.test.ts              # FC-007 — `expect(true).toBe(true)` smoke
│
├── src-tauri/                         # Rust core
│   ├── Cargo.toml                     # tauri = "2", tauri-build = "2"
│   ├── Cargo.lock                     # committed
│   ├── build.rs                       # tauri-build runner
│   ├── tauri.conf.json                # FR-015 + FR-019 + FR-020: window config, identifier, target, capabilities
│   ├── icons/                         # placeholder icons (1×1 PNG; real icons arrive in spec 012)
│   ├── capabilities/
│   │   └── default.json               # FR-019: deny-by-default — empty `permissions: []` array, scope = main window
│   └── src/
│       ├── main.rs                    # Tauri Builder::default().run()
│       └── lib.rs                     # Library form so `cargo test` can target it; contains one smoke test (FC-008)
│
├── tests/
│   └── e2e/
│       └── placeholder.spec.ts        # Playwright stub — passes immediately. Real E2E in spec 003.
│
└── design-system/                     # Already exists; not modified by this spec
    └── MASTER.md
```

**Structure Decision**: Standard Tauri 2.x layout — React frontend in `src/`, Rust core in `src-tauri/`. Matches both the official Tauri scaffolding from `npm create tauri-app@latest` and the structure documented in `CLAUDE.md`. No multi-package monorepo, no custom restructuring — this spec is foundation, not innovation.

## Phase 0 — Research output

See [research.md](./research.md). One open question from `/allium:elicit` ("Window.appearance binding mechanism") is resolved there. Two adjacent best-practice questions (Tauri 2.x capability config shape, shadcn/ui base color choice) are also documented.

## Phase 1 — Design output

- [data-model.md](./data-model.md) — minimal at this spec (no domain entities; just the Application + Window lifecycle from `spec.allium`).
- [contracts/tauri-conf.md](./contracts/tauri-conf.md) — exact `tauri.conf.json` shape.
- [contracts/package-scripts.md](./contracts/package-scripts.md) — exact `package.json` `scripts` section.
- [quickstart.md](./quickstart.md) — clone-to-running-window in 5 minutes (SC-001 verification path).

## Re-evaluated Constitution Check (post-Phase 1)

Post-design re-check: all nine principles still pass. The contracts in `contracts/` encode FR-019 (deny-by-default) and FR-016 (no outbound network) directly into the config files, making the privacy posture machine-checkable rather than convention-checkable. No new violations introduced.

## Complexity Tracking

Empty — no constitution gate violations to justify.
