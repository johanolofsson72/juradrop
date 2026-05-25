# Feature Specification: Tauri Bootstrap

**Feature Branch**: `main` (direct-push per `.claude/rules/spec-register.md`)

**Spec ID**: 001-tauri-bootstrap

**Pipeline track**: light (per `specs/INDEX.md`)

**Created**: 2026-05-25

**Status**: Draft

**Input**: User description: "scaffold Tauri 2.x + React + TypeScript + Tailwind + shadcn/ui, empty window, package.json scripts wired"

## Clarifications

### Session 2026-05-25

- Q: Window sizing and resizability at bootstrap (fixed / resizable+bounds / unrestricted / resizable+min-only)? → A: **Resizable with min 700×500**, no max bound, fullscreen allowed. Rationale: future settings panel + 2×3 zones need flexibility, but a min bound prevents the placeholder (and later UI) from breaking.
- Q: Tauri capability/allowlist posture at bootstrap (deny-by-default / minimal core / full default)? → A: **Deny-by-default** — no frontend capabilities granted at this spec; every later spec must explicitly request what it needs. Aligns with Principle I (Privacy by Architecture).
- Q: Production build target architecture at bootstrap (aarch64 only / universal2 / both files)? → A: **Apple Silicon only** (aarch64-apple-darwin) at this spec. Universal2 binary is deferred to spec 006 (signing-and-ci), where it ships alongside notarization.
- Q: Placeholder window content specificity (text-only / welcome card with shadcn Button / static 2×3 grid preview / blank styled background)? → A: **Welcome card** with title "JuraDrop", subtitle "Lokal AI för svenska juriststudenter", and a single non-functional shadcn `Button` proving the component renders.
- Q: Does the Vite dev-server loopback count as outbound network traffic under FR-016 / NoOutboundNetworkAtBootstrap? (surfaced via `/allium:elicit` findings) → A: **No** — loopback to `127.0.0.1`/`::1` in dev profile is explicitly excluded from "outbound". Production profile MUST have zero network activity. FR-016 amended.

## User Scenarios & Testing *(mandatory)*

<!--
  The "user" for this spec is primarily the JuraDrop developer setting up
  the project foundation. The end-user (law student) only interacts insofar
  as the resulting window opens at all. Real user-facing flows arrive in
  later specs (003-first-zone-sammanfatta onward).
-->

### User Story 1 - Developer can clone, install, and launch the dev window (Priority: P1)

A developer (or contributor) clones the repository, installs JavaScript and Rust dependencies, and runs the dev command. A native macOS window opens within a reasonable startup time, renders a styled placeholder confirming the toolchain works end-to-end, and follows the system appearance (light/dark mode, native window chrome, SF Pro typography).

**Why this priority**: Nothing else in the project can be built, tested, or demoed until this foundation works. Every subsequent spec depends on a developer being able to run `npm run tauri dev` and see a window.

**Independent Test**: Clone the repo on a fresh Mac (with Node 20+ and the Rust toolchain installed), run `npm install`, then `npm run tauri dev`. Verify a native window opens, displays the placeholder content, and matches the system appearance setting. Closing the window quits the app.

**Acceptance Scenarios**:

1. **Given** a fresh clone of the repository on macOS 12+ with Node 20+ and the Rust toolchain available, **When** the developer runs `npm install`, **Then** all JavaScript dependencies install without errors.
2. **Given** dependencies installed, **When** the developer runs `npm run tauri dev`, **Then** a native macOS window titled "JuraDrop" opens, renders a placeholder confirming React + Tailwind are wired, and matches the current system appearance.
3. **Given** the dev window is open with system appearance set to dark, **When** the developer switches macOS appearance to light (or vice versa), **Then** the window follows the change without a restart.
4. **Given** the dev window is open, **When** the developer closes the window, **Then** the app process terminates cleanly (no orphan sidecar processes, since no sidecar exists yet at this spec).

---

### User Story 2 - All toolchain scripts run cleanly on a fresh checkout (Priority: P2)

A developer can run every documented command in `CLAUDE.md` (`npm test`, `npm run lint`, `npm run typecheck`, `cd src-tauri && cargo test`, `cd src-tauri && cargo clippy`, `cd src-tauri && cargo fmt --check`) on a fresh checkout and each command succeeds with zero errors. Vitest finds at least one passing smoke test. Rust tests find at least one passing smoke test. Lint and format checks pass.

**Why this priority**: The CI pipeline, the auto-validation, and the agent's own verification loop all depend on these scripts existing and working. If `npm test` does not exist or fails on a fresh checkout, the project cannot uphold the "Definition of implemented" rule in `CLAUDE.md`.

**Independent Test**: On a fresh checkout, run each of the six scripts in sequence. Confirm each one exits with status 0 and produces sensible output (test counts, lint summary, type-check result).

**Acceptance Scenarios**:

1. **Given** a fresh checkout with dependencies installed, **When** the developer runs `npm test`, **Then** Vitest executes, discovers and runs at least one smoke test, and exits 0.
2. **Given** a fresh checkout, **When** the developer runs `npm run lint`, **Then** ESLint runs against `src/`, finds zero errors, and exits 0.
3. **Given** a fresh checkout, **When** the developer runs `npm run typecheck`, **Then** `tsc --noEmit` runs in strict mode against the React project and exits 0.
4. **Given** a fresh checkout, **When** the developer runs `cd src-tauri && cargo test`, **Then** Cargo builds the Rust crate, runs the test suite (at least one smoke test), and exits 0.
5. **Given** a fresh checkout, **When** the developer runs `cd src-tauri && cargo clippy -- -D warnings`, **Then** Clippy runs with the project's lint configuration and finds zero warnings.
6. **Given** a fresh checkout, **When** the developer runs `cd src-tauri && cargo fmt --check`, **Then** rustfmt confirms all Rust source files conform to the project's formatting rules.

---

### User Story 3 - Production build produces a runnable .app (Priority: P3)

A developer can run `npm run tauri build` and produce a release `.app` bundle (unsigned at this spec — signing arrives in spec 006). Launching the produced `.app` from Finder opens the same window the dev command produced.

**Why this priority**: Confirms the production build pipeline works before the project grows enough to make build failures expensive to debug. Catches webpack/Vite + Rust release-profile issues early. Signing is deliberately deferred to spec 006.

**Independent Test**: Run `npm run tauri build` on a clean checkout. Confirm a `.app` bundle is produced under `src-tauri/target/release/bundle/macos/`. Double-click the produced `.app` from Finder and confirm it launches the same window seen in dev mode.

**Acceptance Scenarios**:

1. **Given** dependencies installed and the dev window verified, **When** the developer runs `npm run tauri build`, **Then** the build completes and produces a `.app` bundle under `src-tauri/target/release/bundle/macos/JuraDrop.app`.
2. **Given** the produced `.app` bundle, **When** the developer double-clicks it from Finder (using right-click → Open to bypass Gatekeeper since unsigned), **Then** the window opens and renders the same placeholder content as the dev command.

---

### Edge Cases

- **Missing Node**: `npm install` fails with the standard Node-missing message. The project does NOT need to handle this with custom messaging — installing Node is a documented prerequisite in `README.md`.
- **Missing Rust toolchain**: `cargo` commands fail with the standard "command not found" message. README documents `rustup` as a prerequisite. JuraDrop does NOT bundle a Rust installer.
- **Stale `node_modules` from a different Node version**: A note in `README.md` instructs the developer to `rm -rf node_modules && npm install` if Node major version changes.
- **macOS version below the supported floor**: Tauri 2.x requires macOS 10.15+ at the framework level. JuraDrop targets macOS 12+ (per project README). Older versions are out of scope.
- **First Rust build takes a long time**: The first `cargo build` (debug or release) compiles all transitive dependencies. README mentions this is expected. No spec-level requirement to optimize first-build time at this stage.
- **Window-close behavior on macOS**: Standard macOS apps keep the dock icon active even when all windows are closed. For JuraDrop, closing the window must quit the app (the window IS the app per `project_juradrop.md`). This is configured in Tauri's `tauri.conf.json`.
- **Dev hot-reload after Rust changes**: Tauri rebuilds the Rust binary on Rust changes — slower than the React hot reload but acceptable. Documented in README.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Repository MUST contain a Tauri 2.x project with a React 18+ + TypeScript frontend in `src/` and a Rust backend in `src-tauri/`.
- **FR-002**: `package.json` MUST define these npm scripts and each MUST work on a fresh checkout: `tauri dev`, `tauri build`, `test` (vitest), `lint` (eslint), `typecheck` (tsc --noEmit), and `test:e2e` (Playwright stub allowed at this spec — wired in later specs).
- **FR-003**: TypeScript MUST be configured in strict mode (`"strict": true` in `tsconfig.json` plus `noUncheckedIndexedAccess`, `noImplicitOverride`, `noFallthroughCasesInSwitch`).
- **FR-004**: ESLint MUST be configured for TypeScript + React with at least the recommended rule set; lint MUST pass with zero warnings on the scaffolded code.
- **FR-005**: Tailwind CSS MUST be installed and active; the placeholder page MUST demonstrate at least one Tailwind utility class rendering correctly.
- **FR-006**: shadcn/ui MUST be installed with its base components registry configured; at least one shadcn/ui component (e.g., `Button` or `Card`) MUST be importable and rendered in the placeholder.
- **FR-007**: The window MUST render a placeholder welcome card visibly confirming React + Tailwind + shadcn/ui are wired. The card MUST display the title "JuraDrop", the subtitle "Lokal AI för svenska juriststudenter", and a single non-functional shadcn `Button` element (so DOM-level tests can assert on the shadcn component). Final visual design (colors, motion, exact spacing) is owned by `design-system/MASTER.md` and refined in later specs — this spec only proves the toolchain renders.
- **FR-008**: The window MUST follow system appearance (light/dark) without explicit user toggling at this spec — automatic via OS-level appearance signals.
- **FR-009**: The window MUST use SF Pro (the macOS system font stack) as the default font family.
- **FR-010**: Closing the window MUST quit the application process — no menu-bar-only mode, no background process retention.
- **FR-011**: Vitest MUST be configured with at least one smoke test that asserts a trivial truth (e.g., `expect(true).toBe(true)`) and passes when `npm test` runs.
- **FR-012**: Cargo MUST have at least one Rust unit test that passes when `cargo test` runs in `src-tauri/`.
- **FR-013**: Cargo clippy MUST run with `-D warnings` and produce zero warnings on the scaffolded Rust code.
- **FR-014**: Cargo fmt MUST find all Rust source files already formatted (`cargo fmt --check` exits 0).
- **FR-015**: `tauri.conf.json` MUST set the bundle identifier to `se.noisycricket.juradrop`, the product name to `JuraDrop`, and configure a single window titled "JuraDrop" with: initial size 900×650, minimum size 700×500, no maximum size (free resize), fullscreen permitted, and resizable.
- **FR-019**: The Tauri frontend MUST run under a **deny-by-default** capability posture at this spec — no Tauri plugins or core APIs are granted to the WebView through `capabilities/`. Every subsequent spec that needs a Tauri API (filesystem, sidecar, dialog, …) MUST add a scoped capability entry explicitly. The audit trail is the `capabilities/` directory contents over time.
- **FR-020**: Production builds at this spec target **Apple Silicon only** (`aarch64-apple-darwin`). The `tauri.conf.json` build config MUST NOT include `x86_64-apple-darwin` or `universal-apple-darwin` targets yet — those arrive with spec 006 (signing-and-ci) where CI handles the universal2 + notarization pipeline.
- **FR-016**: The project MUST NOT include any outbound network traffic at this spec. Loopback connections to `127.0.0.1` or `::1` from the Vite dev server in **dev profile only** are explicitly excluded from "outbound" — they never leave the developer's Mac and are required by the Tauri development workflow. Production-profile builds MUST have zero network activity. No fetch/XHR/WebSocket calls to non-loopback hosts in scaffolded code on either profile.
- **FR-017**: `README.md` MUST document prerequisites (macOS 12+, Node 20+, Rust toolchain via rustup) and the six core commands from `CLAUDE.md`.
- **FR-018**: `.gitignore` MUST exclude `node_modules/`, `src-tauri/target/`, `dist/`, and `.DS_Store`.

### Key Entities

*(No domain entities at this spec — bootstrap is pure scaffolding. Domain entities arrive in spec 003 onward.)*

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer with prerequisites already installed can go from `git clone` to a running dev window in under five minutes on a baseline modern Mac (M1 or later, broadband internet).
- **SC-002**: Every command in the `CLAUDE.md` "Commands" section returns exit code 0 on a fresh checkout (no implementation or test work has happened yet, but the scripts and minimal smoke tests exist).
- **SC-003**: Zero ESLint warnings, zero TypeScript errors, zero Clippy warnings, zero rustfmt violations on the scaffolded codebase.
- **SC-004**: Window startup time (from `npm run tauri dev` until the window is visible and interactive) is under 10 seconds on the second run (first run includes Rust compilation and is expected to be longer).
- **SC-005**: The placeholder window visibly switches between light and dark appearance when the system appearance changes, with no user action other than the OS-level toggle.

## Assumptions

- Developers have macOS 12+, Node 20+ (via nvm or Homebrew), and the Rust toolchain (via rustup) installed before running any project command. These prerequisites are documented in `README.md` but are not the project's responsibility to install.
- This spec targets **Apple Silicon only** (`aarch64-apple-darwin`). Intel Mac (x86_64) is deliberately out of scope until spec 006 (signing-and-ci), which is where the universal2 binary and CI pipeline are introduced together.
- The "empty window" is a styled placeholder that proves the toolchain works — not a finished UI. The actual 2×3 drop-zone grid arrives in spec 003 and 004.
- Code signing and notarization are explicitly deferred to spec 006. Production builds at this spec are unsigned and require right-click → Open to launch.
- No automated CI is configured at this spec — that arrives in spec 006 alongside signing.
- No Ollama sidecar binary is bundled at this spec — that arrives in spec 002.
- `npm` is the package manager; pnpm/yarn are out of scope. Lock file is `package-lock.json`.
- The project README, contribution guide, and constitution already exist in the repo and are not rewritten by this spec — only the prerequisites section of README is updated to reflect the scaffolded reality.

## Functional Coverage Tests *(MANDATORY — per `.claude/docs/spec-testing-checklist.md`)*

Functional inventory of every shippable function from this spec, with at least one browser-level smoke test per function. Bootstrap is mostly toolchain — interactive UI surface is minimal — but the items below are the user-observable functions and each needs verification.

| ID | Function | Test type | What it asserts |
|----|----------|-----------|-----------------|
| FC-001 | Window launches via `npm run tauri dev` | Playwright smoke against built app | Window opens, title is "JuraDrop" |
| FC-002 | Placeholder renders | Playwright smoke / Vitest DOM | At least the "JuraDrop" placeholder text is visible in the DOM |
| FC-003 | Tailwind utility class applied | Vitest DOM | Element has expected computed style from a Tailwind class |
| FC-004 | shadcn/ui component renders | Vitest DOM | Imported shadcn component renders with expected class names |
| FC-005 | Window closes the process | Playwright smoke | After window-close event, app process terminates |
| FC-006 | System appearance respected | Manual + Vitest snapshot | DOM root reflects `prefers-color-scheme` via Tailwind dark variant |
| FC-007 | `npm test` smoke test passes | CI run / local | `expect(true).toBe(true)` passes via Vitest |
| FC-008 | `cargo test` smoke test passes | CI run / local | One Rust unit test passes |
| FC-009 | `npm run typecheck` is clean | CI run / local | `tsc --noEmit` exits 0 |
| FC-010 | `npm run lint` is clean | CI run / local | ESLint exits 0 |
| FC-011 | `cargo clippy -- -D warnings` is clean | CI run / local | Clippy exits 0 |
| FC-012 | `cargo fmt --check` is clean | CI run / local | rustfmt exits 0 |

## Destructive Tests *(per `.claude/docs/spec-testing-checklist.md`)*

Bootstrap has very limited interactive surface — there is no form, no file input, no state machine yet. The destructive tests below focus on the toolchain and the window lifecycle, covering the relevant attack categories. Most "input/XSS/SQL injection" categories do not apply at this spec because there is no user input surface yet; they become mandatory from spec 003 onward.

| ID | Category | Scenario | Expected behavior |
|----|----------|----------|-------------------|
| DT-001 | Wrong order | Run `npm run tauri build` before `npm install` | Build fails with a clear "dependencies missing" message; no half-bundled artifact is produced |
| DT-002 | Wrong order | Run `cargo test` before `cargo build` (cold cache) | Cargo builds dependencies then runs tests; no false-pass from stale binaries |
| DT-003 | Skip steps | Launch the unsigned `.app` from Finder by double-click | macOS Gatekeeper blocks it; user must right-click → Open. This is expected and documented in README |
| DT-004 | Boundary | Attempt to resize the window below the configured minimum (700×500) | Window clamps at the minimum size; placeholder content remains visible and uncropped |
| DT-005 | Boundary | Resize the window to fullscreen via the green stoplight button | Window enters fullscreen cleanly, placeholder remains visible and centered, no overflow artifacts |
| DT-006 | Timing/race | Close window during initial render (within first 500 ms) | Process exits cleanly, no orphaned Rust process visible in Activity Monitor |
| DT-007 | Timing/race | Rapid open/close (open window, close, reopen from dev rebuild) within 2 seconds | No port conflicts, no zombie processes, dev server reconnects |
| DT-008 | Accessibility | Tab through the rendered placeholder | Focus traversal works; no focus traps; ESC has no destructive effect at this spec |
| DT-009 | Skip steps | Frontend code attempts to call a Tauri core API (e.g., `invoke('fs:read_dir')`) that is NOT in the capability allowlist | Tauri runtime rejects the call with a capability error; no filesystem or process access granted. Validates FR-019 (deny-by-default). |

These destructive tests are intentionally light. Spec 003 (which introduces the first drop zone and real user input) is where the full 6-attack-category destructive matrix begins.

## Out of Scope (explicit non-goals)

To prevent scope creep, this spec explicitly does NOT include:

- The 2×3 drop-zone grid UI (specs 003, 004)
- Any Ollama integration or sidecar bundling (spec 002)
- Code signing, notarization, or CI/CD (spec 006)
- Auto-updater (spec 007)
- First-run wizard (spec 008)
- Settings panel (spec 010)
- Error recovery from sidecar crashes (spec 011)
- Document parsing (.docx/.pdf/.rtf/.pages/.odt) — those are not even possible without the sidecar (specs 003, 005, 009)
- Any final visual design beyond placeholder — the design system in `design-system/MASTER.md` is the authoritative source for later specs; this spec only proves the toolchain renders
