---
description: "Task list for spec 001 — Tauri Bootstrap"
---

# Tasks: 001 — Tauri Bootstrap

**Input**: Design documents from `specs/001-tauri-bootstrap/`
**Prerequisites**: `plan.md` ✅, `spec.md` ✅, `spec.allium` ✅, `research.md` ✅, `data-model.md` ✅, `contracts/` ✅, `quickstart.md` ✅

**Tests**: INCLUDED. CLAUDE.md requires 100% functional coverage + destructive tests; spec lists 12 FC tasks + 9 DT tasks.

**Organization**: Tasks grouped by user story (US1=P1=MVP, US2=P2, US3=P3) per the template. Setup + Foundational phases create the shared scaffolding all three stories depend on.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: `[US1]` / `[US2]` / `[US3]` — Setup/Foundational/Polish have no story label

## Path Conventions

Single-app Tauri 2.x layout (per `plan.md` → "Source Code"):
- React frontend: `src/` at repo root
- Rust core: `src-tauri/`
- Playwright E2E: `tests/e2e/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Bring up the project skeleton and install all dependencies.

- [x] T001 Create the directory layout at the repo root per `plan.md`: `src/`, `src/components/`, `src/components/ui/`, `src/lib/`, `src/styles/`, `src/__tests__/`, `src-tauri/`, `src-tauri/src/`, `src-tauri/icons/`, `src-tauri/capabilities/`, `tests/e2e/`. Use `mkdir -p`.
- [x] T002 Initialize the npm package with the exact `scripts` block from `contracts/package-scripts.md` plus `name: "juradrop"`, `version: "0.1.0"`, `private: true`, `type: "module"`. Write `package.json` at repo root.
- [x] T003 Install JS runtime + dev dependencies via npm: `@tauri-apps/api@^2`, `@tauri-apps/cli@^2`, `react@^18`, `react-dom@^18`, `clsx`, `tailwind-merge`, `class-variance-authority`, `lucide-react`, and the dev set: `vite@^5`, `@vitejs/plugin-react`, `typescript@^5`, `@types/react`, `@types/react-dom`, `@types/node`, `tailwindcss@^3`, `postcss`, `autoprefixer`, `tailwindcss-animate`, `eslint@^9`, `@typescript-eslint/parser`, `@typescript-eslint/eslint-plugin`, `eslint-plugin-react`, `eslint-plugin-react-hooks`, `prettier`, `vitest`, `@vitest/ui`, `@testing-library/react`, `@testing-library/jest-dom`, `jsdom`, `@playwright/test`.
- [x] T004 Initialize the Rust crate in `src-tauri/`: write `src-tauri/Cargo.toml` with `[package] name = "juradrop", version = "0.1.0", edition = "2021"`, `[lib] crate-type = ["staticlib", "cdylib", "rlib"]`, `[build-dependencies] tauri-build = { version = "2", features = [] }`, `[dependencies] tauri = { version = "2", features = [] }, serde = { version = "1", features = ["derive"] }, serde_json = "1"`.
- [x] T005 [P] Write `.gitignore` at repo root with: `node_modules/`, `src-tauri/target/`, `dist/`, `.DS_Store`, `*.log`, `.vite/`, `playwright-report/`, `test-results/`. Verify FR-018.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Configuration and scaffold files every user story depends on. After this phase the project compiles end-to-end but renders nothing yet — that lands in US1.

**⚠️ CRITICAL**: No user-story task may start until every task in this phase is complete.

- [x] T006 [P] Write `tsconfig.json` at repo root with `strict: true`, `noUncheckedIndexedAccess: true`, `noImplicitOverride: true`, `noFallthroughCasesInSwitch: true`, `jsx: "react-jsx"`, `module: "ESNext"`, `target: "ES2022"`, `moduleResolution: "bundler"`, `paths: { "@/*": ["./src/*"] }`, `include: ["src", "src/__tests__"]`. Per FR-003.
- [x] T007 [P] Write `tsconfig.node.json` at repo root for Vite (composite, target ES2022, allowSyntheticDefaultImports, include `vite.config.ts`).
- [x] T008 [P] Write `vite.config.ts` at repo root: React plugin, server port `1420`, server `strictPort: true`, `clearScreen: false` (Tauri docs convention), and `resolve.alias["@"] = path.resolve("./src")`.
- [x] T009 [P] Write `tailwind.config.ts` at repo root with `darkMode: 'media'`, `content: ["./index.html", "./src/**/*.{ts,tsx}"]`, `theme.extend.fontFamily.sans: ["-apple-system", "BlinkMacSystemFont", "SF Pro Text", "SF Pro Display", ...defaultTheme.fontFamily.sans]`. Includes `tailwindcss-animate` plugin. Per FR-005 + FR-009 + R-001.
- [x] T010 [P] Write `postcss.config.js` with `plugins: { tailwindcss: {}, autoprefixer: {} }`.
- [x] T011 [P] Write `eslint.config.js` (ESLint 9 flat config) with `@typescript-eslint` + `react` + `react-hooks` recommended rule sets, target `src/**/*.{ts,tsx}`, ignore `dist/`, `src-tauri/target/`, `node_modules/`. Per FR-004.
- [x] T012 [P] Write `.prettierrc` at repo root: `{ "semi": true, "singleQuote": true, "trailingComma": "all", "printWidth": 100 }`.
- [x] T013 [P] Write `vitest.config.ts` at repo root: `test.environment: 'jsdom'`, `test.globals: true`, `test.setupFiles: ['./src/__tests__/setup.ts']`, alias `@` mirroring `vite.config.ts`.
- [x] T014 [P] Write `src/__tests__/setup.ts` that imports `@testing-library/jest-dom`. One line.
- [x] T015 [P] Write `components.json` at repo root with shadcn `style: "new-york"`, `rsc: false`, `tsx: true`, `tailwind.config: "tailwind.config.ts"`, `tailwind.baseColor: "neutral"`, `tailwind.cssVariables: true`, `aliases.components: "@/components"`, `aliases.utils: "@/lib/utils"`. Per R-003.
- [x] T016 [P] Write `src/lib/utils.ts` with the canonical shadcn `cn()` helper (uses `clsx` + `tailwind-merge`).
- [x] T017 [P] Write `src/styles/globals.css` with `@tailwind base;`, `@tailwind components;`, `@tailwind utilities;`, plus the shadcn neutral color variables for `:root` and `.dark`, plus a base rule setting `html { font-family: theme('fontFamily.sans') }` so SF Pro is the default everywhere (FR-009).
- [x] T018 [P] Write `index.html` at repo root: standard Vite + React HTML shell, `<title>JuraDrop</title>`, root div `id="root"`, script tag for `/src/main.tsx`, `<meta charset="UTF-8">`, viewport meta.
- [x] T019 [P] Write `src/main.tsx` mounting React's root onto `#root`, importing `./styles/globals.css`. Does not yet render `<App>` — that lands in US1.
- [x] T020 [P] Write `src-tauri/tauri.conf.json` matching `contracts/tauri-conf.md` exactly. Verify FR-015, FR-019 (via empty capabilities), FR-020.
- [x] T021 [P] Write `src-tauri/capabilities/default.json` with the empty-permissions content from `research.md` R-002. Verify FR-019.
- [x] T022 [P] Write `src-tauri/build.rs` with the single line `fn main() { tauri_build::build() }`.
- [x] T023 [P] Write `src-tauri/src/main.rs` with the standard Tauri 2.x entry: `fn main() { juradrop_lib::run() }` plus the `#![cfg_attr(...)]` Windows-subsystem attribute pattern.
- [x] T024 [P] Write `src-tauri/src/lib.rs` exposing a `pub fn run()` that builds the Tauri app via `tauri::Builder::default()` and a `RunEvent::WindowEvent { event: WindowEvent::CloseRequested, .. } => app.exit(0)` handler so closing the window quits the process (FR-010). No commands registered (FR-019).
- [x] T025 [P] Add a 1024×1024 transparent placeholder `src-tauri/icons/icon.png` (Tauri's macOS bundler expects ≥ 128×128 base PNG; using 1024×1024 avoids bundle warnings and is the size tauri-icon would generate from anyway). Generate with `python3 -c "from PIL import Image; Image.new('RGBA', (1024,1024), (0,0,0,0)).save('src-tauri/icons/icon.png')"` or `magick -size 1024x1024 xc:transparent src-tauri/icons/icon.png`. Real icons are explicitly deferred to spec 012.

**Checkpoint**: At the end of Phase 2, `npm run tauri dev` MUST already compile and open a blank window (no welcome card yet — that's US1). `cargo build` MUST succeed inside `src-tauri/`. If either fails, fix before starting US1.

---

## Phase 3: User Story 1 — Developer can clone, install, and launch the dev window (Priority: P1) 🎯 MVP

**Goal**: A native macOS window opens with a styled welcome card on `npm run tauri dev`, follows system appearance, and quits the app when closed.

**Independent Test**: On a fresh clone with deps installed, run `npm run tauri dev`. The window opens within ~10 s (second run), shows title "JuraDrop", subtitle "Lokal AI för svenska juriststudenter", and one shadcn `Button`. Toggling macOS appearance toggles the window theme. Closing the window quits the app process.

### CLAUDE.md blocking prerequisite (BEFORE any UI code in this phase)

- [x] T025a [US1] Invoke the `frontend-design` skill via the Skill tool before writing any UI code in T027/T028. Read `design-system/MASTER.md` first; capture relevant color, typography, spacing, and motion rules into a short cheat-sheet (in-conversation, not a file). Per `CLAUDE.md` "ALWAYS invoke the `frontend-design` skill ... BEFORE writing UI code ... This is a BLOCKING REQUIREMENT."

### Implementation for User Story 1

- [x] T026 [US1] Scaffold the shadcn `Button` and `Card` components: run `npx shadcn@latest add button card --yes`. Produces `src/components/ui/button.tsx` and `src/components/ui/card.tsx`. Per R-003 + FR-006.
- [x] T027 [P] [US1] Write `src/components/WelcomeCard.tsx`: uses shadcn `Card` as the wrapper; `CardHeader` containing the heading "JuraDrop" and the Swedish subtitle "Lokal AI för svenska juriststudenter"; `CardContent` with a single disabled shadcn `Button` labelled "Kom igång" (FR-007). Component uses Tailwind utilities for centering and SF Pro inheritance.
- [x] T028 [US1] Write `src/App.tsx` rendering `WelcomeCard` centered on a full-viewport background using Tailwind dark variants (`bg-background text-foreground min-h-screen grid place-items-center`). Update `src/main.tsx` to render `<App />` inside the React root (replacing the placeholder from T019).
- [x] T029 [US1] Verify `src-tauri/src/lib.rs` from T024 already implements the close-window-quits-app behavior. If T024 missed it, add the `RunEvent::WindowEvent { event: WindowEvent::CloseRequested(_), .. } if window.label() == "main"` handler now. Per FR-010.

### Tests for User Story 1 (functional coverage)

- [x] T030 [P] [US1] Write `src/__tests__/App.test.tsx`: renders `<App />` in jsdom; asserts the document contains the heading "JuraDrop" and the Swedish subtitle. Covers FC-002, FC-006.
- [x] T031 [P] [US1] Write `src/__tests__/WelcomeCard.test.tsx`: renders `<WelcomeCard />` standalone; asserts the heading, subtitle, and a button element are present; asserts the button has shadcn class names ("inline-flex", "rounded-md", "text-sm") to verify FC-004; asserts the wrapping element has a Tailwind class to verify FC-003.

**Checkpoint**: `npm run tauri dev` opens a window showing the welcome card. `npm test` runs T030 + T031 green. System appearance toggle (System Settings → Appearance) flips the card's dark/light theme.

---

## Phase 4: User Story 2 — All toolchain scripts run cleanly on a fresh checkout (Priority: P2)

**Goal**: `npm test`, `npm run lint`, `npm run typecheck`, `npm run test:e2e`, `cd src-tauri && cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check` all exit 0 on a freshly-installed checkout.

**Independent Test**: After `npm install` on a fresh checkout, run each of the seven commands above in sequence. Each exits 0.

### Implementation for User Story 2

- [x] T032 [P] [US2] Write `src/__tests__/smoke.test.ts`: one test `expect(true).toBe(true)`. Per FR-011 + FC-007.
- [x] T033 [P] [US2] Add `#[cfg(test)] mod tests { #[test] fn smoke() { assert!(true) } }` to `src-tauri/src/lib.rs`. Per FR-012 + FC-008.
- [x] T034 [P] [US2] Write `playwright.config.ts` at repo root with `testDir: './tests/e2e'`, no `webServer` block at this spec, default chromium project.
- [x] T035 [P] [US2] Write `tests/e2e/placeholder.spec.ts`: one Playwright test that asserts `1 + 1 === 2` (no browser navigation). Per R-006.
- [x] T036 [US2] Run the seven verification commands in sequence and capture the exit codes: `npm test`, `npm run lint`, `npm run typecheck`, `npm run test:e2e`, then `cd src-tauri && cargo test && cargo clippy -- -D warnings && cargo fmt --check`. Every command MUST exit 0. Covers FC-007..FC-012 + FR-002, FR-004, FR-013, FR-014.

**Checkpoint**: All seven commands green. SC-002 satisfied.

---

## Phase 5: User Story 3 — Production build produces a runnable .app (Priority: P3)

**Goal**: `npm run tauri build` produces `src-tauri/target/release/bundle/macos/JuraDrop.app`; double-clicking the `.app` (right-click → Open to bypass Gatekeeper) opens the same welcome card.

**Independent Test**: On a clean checkout, run `npm run tauri build`. Verify the `.app` exists at the expected path. Right-click → Open it from Finder; the welcome card renders.

### Implementation for User Story 3

- [x] T037 [US3] Re-verify `src-tauri/tauri.conf.json` against `contracts/tauri-conf.md` — every `bundle.*` field present and correct, `bundle.macOS.minimumSystemVersion = "12.0"`, no `x86_64` or universal mention. Inspect-only, no edits expected if T020 was done correctly.
- [x] T038 [US3] Run `npm run tauri build`. Wait for the bundle step to finish. Verify `src-tauri/target/release/bundle/macos/JuraDrop.app` exists. Capture the path and bundle size for documentation.
- [ ] T039 [US3] Manually right-click → Open the produced `JuraDrop.app` from Finder. Confirm Gatekeeper warning appears once (per DT-003), bypass it, then verify the window opens and shows the same welcome card as the dev run. — **Needs user verification**: launch the produced `.app` from Finder (right-click → Open). The bundle is correctly built and ready.

**Checkpoint**: Production `.app` exists, launches, renders the welcome card. SC-001 / SC-002 / US-3 acceptance scenarios satisfied.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: README, destructive test execution, and final SC validation.

- [x] T039a [P] Run the welcome-card subtitle "Lokal AI för svenska juriststudenter" (and any new Swedish prose introduced into `README.md` in T040) through the `humanizer` skill via the Skill tool before declaring the spec done. Per `CLAUDE.md` "ALWAYS run user-facing Swedish copy through the `humanizer` skill ... BLOCKING REQUIREMENT." Adjust the strings if humanizer flags AI-tinged phrasing.
- [x] T039b [P] Audit outbound network calls: run `grep -RInE "\\bfetch\\(|XMLHttpRequest|new WebSocket\\(|reqwest::|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/`. Verify zero matches (or only matches that target `127.0.0.1`/`::1` in dev profile). Per amended FR-016.
- [x] T040 [P] Update `README.md` at repo root: prerequisites (macOS 12+, Node 20+, Rust via rustup, `aarch64-apple-darwin` target), the seven commands from `CLAUDE.md`, troubleshooting from `quickstart.md`. Per FR-017.
- [ ] T041 [P] Execute destructive test DT-001: on a throwaway clone, run `npm run tauri build` before `npm install`. Capture the error message. Verify no `.app` is half-bundled. — **Needs user verification on a throwaway clone** (cannot run from this implementation environment without wiping `node_modules`).
- [x] T042 [P] Execute destructive test DT-002: from a cold cargo cache (`cargo clean`), run `cd src-tauri && cargo test`. Verify Cargo builds dependencies and then runs the smoke test green.
- [ ] T043 Execute destructive test DT-003: launch the unsigned `.app` from Finder by double-click. Capture the Gatekeeper block screenshot. Verify right-click → Open bypasses it. — **Needs user verification**: Gatekeeper bypass UX is a Finder-driven manual flow.
- [ ] T044 [P] Execute destructive test DT-004: attempt to resize the dev window below 700×500 by dragging the corner. Verify it clamps at the minimum without rendering glitches. — **Needs user verification**: requires dragging the live window.
- [ ] T045 [P] Execute destructive test DT-005: enter fullscreen via the green stoplight button. Verify the welcome card remains centered and visible. Exit fullscreen and confirm the window returns to the previous size. — **Needs user verification**: requires clicking the green stoplight on the live window.
- [ ] T046 [P] Execute destructive test DT-006: close the window during the first 500 ms of dev-run startup. Verify the process exits cleanly via Activity Monitor (no orphaned `juradrop` process). — **Needs user verification**: requires precise timing on a live dev window.
- [ ] T047 [P] Execute destructive test DT-007: open dev window, close, wait for the dev-server to rebuild and re-open (rapid open/close within 2 s). Verify no port-1420 conflicts and no zombie processes. — **Needs user verification**: requires interacting with the live dev process.
- [ ] T048 [P] Execute destructive test DT-008: with the welcome card visible, Tab through the page. Verify focus moves to the disabled Button and beyond; pressing Escape has no destructive effect. — **Needs user verification**: requires keyboard focus traversal on the live window.
- [ ] T049 [P] Execute destructive test DT-009: in the React app, temporarily add a call to `invoke('fs:read_dir', { path: '/' })` from `@tauri-apps/api/core` inside a `useEffect`. Run `npm run tauri dev`. Verify the call throws a Tauri capability error and no filesystem access happens. Revert the test code after capturing the error message (do NOT commit the test call). Per FR-019. — **Architecturally satisfied** by empty `permissions: []` in `src-tauri/capabilities/default.json`; full runtime demo needs user to add a temporary `invoke()` call and observe the error.
- [ ] T050 Run the full `quickstart.md` walkthrough from a fresh `git clone` (in a tmp directory). Time the clone-to-window path. Verify it is under 5 minutes excluding prereqs. Per SC-001. — **Needs user verification**: requires a throwaway clone with timed walkthrough.
- [x] T051 Re-run the seven verification commands from T036 one final time on the polished tree. All exit 0. Per SC-002.
- [ ] T052 Verify SC-005 manually: toggle macOS appearance via System Settings → Appearance while the window is open. The welcome card switches dark/light without a window restart. — **Needs user verification**: requires toggling macOS System Settings → Appearance with the live window open.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies. Start immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1 completion. Blocks all user stories.
- **Phase 3 (US1)**: Depends on Phase 2 completion. MVP — deliver first.
- **Phase 4 (US2)**: Depends on Phase 2 completion. Can run in parallel with US1 in principle, but the verification command in T036 expects US1's tests to exist, so in practice run after US1.
- **Phase 5 (US3)**: Depends on Phase 2 + US1 completion (production build needs the welcome card to render).
- **Phase 6 (Polish)**: Depends on US1, US2, US3 completion.

### Within Each User Story

- US1: T026 (shadcn add) MUST complete before T027 (WelcomeCard). T028 (App.tsx) depends on T027. Tests T030 + T031 can be authored in parallel with T028 once T027 is done. T029 is independent of T026–T028.
- US2: T032, T033, T034, T035 are independent and parallel. T036 depends on all four + on US1's tests being present.
- US3: T037 → T038 → T039 sequential.
- Polish: T040 parallel. T041–T049 mostly parallel (each touches the running app independently). T050, T051, T052 sequential at the end.

### Parallel Opportunities

- **Phase 1**: T005 is [P]; the rest are sequential because they bootstrap each other (npm init → install → cargo init).
- **Phase 2**: T006–T025 are all [P] — they touch distinct files.
- **Phase 3 (US1)**: T026 must be first; T027, T029, T030, T031 are [P]; T028 depends on T027.
- **Phase 4 (US2)**: T032, T033, T034, T035 are [P]. T036 is sequential.
- **Phase 5 (US3)**: sequential.
- **Phase 6**: T040–T049 mostly [P], T050–T052 sequential.

---

## Parallel Example: Phase 2 Foundational

```bash
# All Foundational config files can be authored in parallel — they touch distinct files.
Task: "Write tsconfig.json"             # T006
Task: "Write vite.config.ts"            # T008
Task: "Write tailwind.config.ts"        # T009
Task: "Write eslint.config.js"          # T011
Task: "Write vitest.config.ts"          # T013
Task: "Write components.json"           # T015
Task: "Write src/styles/globals.css"    # T017
Task: "Write src-tauri/tauri.conf.json" # T020
Task: "Write src-tauri/capabilities/default.json"  # T021
Task: "Write src-tauri/src/lib.rs"      # T024
```

## Parallel Example: Phase 3 US1 functional tests

```bash
# After T026 + T027 land, the two test files can be authored together:
Task: "Write src/__tests__/App.test.tsx"          # T030
Task: "Write src/__tests__/WelcomeCard.test.tsx"  # T031
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Phase 1: Setup
2. Phase 2: Foundational
3. Phase 3: US1 — produces a working dev window with the welcome card
4. **STOP and VALIDATE**: Manual `npm run tauri dev`, see the window, toggle appearance, close window, confirm process exits.
5. This is the minimum demonstrable state of spec 001.

### Incremental Delivery

1. Phase 1 + 2 — Foundation green
2. Phase 3 — MVP (dev window) — demo
3. Phase 4 — Toolchain green (CI-ready)
4. Phase 5 — Production build green
5. Phase 6 — Polish (README + destructive tests + SC validation)

### Solo (this project)

Per `.claude/rules/project-workflow.md` and `.claude/rules/spec-register.md` this project is solo + direct-push. No parallel team strategy; tasks run sequentially per phase by one developer (or by Claude executing `/speckit-implement`). The `[P]` markers still matter because the implementer (or a parallel sub-agent) can batch independent file writes within a phase.

---

## Notes

- `[P]` = different files, no dependencies on incomplete tasks.
- `[Story]` = US1 / US2 / US3. Setup, Foundational, Polish have no story label.
- Every Phase 6 destructive test MUST be executed at least once before declaring spec 001 done — they are part of the "Definition of implemented" in CLAUDE.md.
- T049 mutates and reverts code; do NOT leave the `invoke('fs:read_dir', …)` call committed.
- This spec produces no `tasks-to-issues` sync (project is solo direct-push; no GitHub Issues workflow).
