# Feature Specification: CI on push + pull request

**Feature Branch**: `main` (direct-push per spec-register.md; no feature branch)

**Created**: 2026-06-02

**Status**: Draft

**Input**: User description: "Add a `ci.yml` running the existing gate sweep (eslint/typecheck/vitest/fmt/clippy-strict/cargo test) on push to main + pull_request, not only on `v*.*.*` release tags, so every commit is verified by automation."

## Clarifications

### Session 2026-06-02

- Q: What events trigger CI? → A: `push` to `main` and `pull_request` (any branch targeting `main`). Tag pushes stay owned by `release.yml`.
- Q: How is the Ollama sidecar (required for `cargo test` to compile — `tauri-build` validates `externalBin`) provided without a slow download every run? → A: Run `scripts/fetch-ollama.sh`, wrapped in `actions/cache` keyed on the script's content hash (the pinned version + SHA live in it), so the binary is fetched once per version bump and restored from cache thereafter.
- Q: Cancel superseded in-progress runs on a new push to the same ref? → A: Yes — a `concurrency` group cancels older in-flight runs for the same branch/PR to save runner minutes.
- Q: Run the `#[ignore]`'d hardware tests (real Ollama inference)? → A: No. They require a pulled model + GPU and stay ignored in CI, exactly as in `release.yml`.
- Q: Should CI duplicate `release.yml`'s gate steps or refactor to share? → A: Duplicate the gate steps in a new `ci.yml`. `release.yml` stays the single source for build/sign/notarize; sharing via a reusable workflow is deferred (YAGNI for two jobs).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every commit is verified by automation (Priority: P1)

A commit lands on `main` (solo, direct-push) or a PR is opened. CI runs the
full gate sweep automatically and reports pass/fail, so a regression is caught
the moment it lands instead of weeks later at release-tag time.

**Why this priority**: Today the gates (`release.yml`) only run on a `v*.*.*`
tag push. Between releases, `main` accumulates unverified commits. This closes
that window — the single biggest process gap surfaced in the hardening review.

**Independent Test**: Push a commit that breaks a test (or lint) and confirm
the CI run goes red; push a clean commit and confirm it goes green.

**Acceptance Scenarios**:

1. **Given** a push to `main`, **When** CI runs, **Then** eslint, typecheck, vitest, `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, and `cargo test` all execute and the run's status reflects their combined result.
2. **Given** a pull request targeting `main`, **When** CI runs, **Then** the same gate sweep executes.
3. **Given** a second push to the same branch while a run is in flight, **When** the new run starts, **Then** the older run is cancelled (concurrency).

### Edge Cases

- First run (cold cache) → `fetch-ollama.sh` downloads the binary; subsequent runs restore it from cache keyed on the script hash.
- A tag push (`v*.*.*`) → handled by `release.yml`, NOT `ci.yml` (no double build).
- `cargo test` cannot compile without the sidecar binary (`tauri-build` validates `externalBin`) → the fetch step runs before any Rust step.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A `.github/workflows/ci.yml` workflow MUST run on `push` to `main` and on `pull_request`.
- **FR-002**: The workflow MUST run, at minimum, the same quality gates `release.yml` runs before signing: eslint, TypeScript typecheck, vitest, `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`.
- **FR-003**: The workflow MUST fetch the bundled Ollama sidecar binary (via `scripts/fetch-ollama.sh`) before any Rust compile/test step, because `tauri-build` validates `externalBin` existence at compile time.
- **FR-004**: The Ollama binary fetch MUST be cached (keyed on `fetch-ollama.sh`'s content) so it is not re-downloaded on every run.
- **FR-005**: The workflow MUST NOT build, sign, notarize, or release anything — those stay exclusively in `release.yml`.
- **FR-006**: The workflow MUST cancel superseded in-progress runs for the same ref (concurrency group).
- **FR-007**: The workflow MUST NOT run the `#[ignore]`'d hardware/real-Ollama tests.
- **FR-008**: The workflow MUST NOT introduce any secret usage or outbound call beyond cloning the repo and the already-used Ollama binary download (Principle I — CI must not exfiltrate anything).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A clean commit pushed to `main` produces a green CI run executing all six gates.
- **SC-002**: A commit that breaks any single gate produces a red CI run that names the failing gate.
- **SC-003**: On a warm cache, the CI run does not re-download the Ollama binary (cache hit).
- **SC-004**: 0 build/sign/notarize/release steps appear in `ci.yml` (separation from `release.yml`).

## Assumptions

- Spec-only track: this is CI/infra config with no new entities, state, or user-facing behavior — no `.allium`, no `/tla`, no browser tests (CI config is not an interactive UI surface).
- `release.yml`'s gate steps are the proven-working reference (they shipped v0.1.0); `ci.yml` mirrors them minus the build/sign/notarize/release steps.
- Runner: `macos-latest` (the project is macOS-only; Rust + the sidecar target the host arch).
- Direct-push to `main`, no feature branch (per `spec-register.md`). Note: `pull_request` trigger is included for completeness/future contributors even though the project is currently solo direct-push.
