# Feature Specification: Dependency vulnerability auditing

**Feature Branch**: `main` (direct-push per spec-register.md; no feature branch)

**Created**: 2026-06-02

**Status**: Draft

**Input**: User description: "Wire `cargo audit` + `npm audit --omit=dev` into CI and add Dependabot; guards the untrusted-document parser crates (pdf-extract/docx-rs/rtf-parser/zip/quick-xml) against future CVEs. Extends the fetch-ollama.sh pinned-SHA discipline to the whole dep tree."

## Clarifications

### Session 2026-06-02

- Q: Separate workflow or fold into `ci.yml`? → A: A separate `audit.yml`. Audits read lockfiles (no compile, no sidecar fetch) and also run on a schedule, so they have a different shape/cadence than the gate sweep.
- Q: What triggers audits? → A: `push` to `main`, `pull_request`, and a weekly `schedule` (cron) so a newly-published advisory against an unchanged dependency is still caught.
- Q: `npm audit` failure threshold? → A: `--omit=dev --audit-level=high` — fail on high/critical only (moderate/low in a small desktop app's prod tree are noise; runtime deps are what ship to users).
- Q: How is `cargo audit` run? → A: Install the prebuilt binary via `taiki-e/install-action` (fast, no compile) and run `cargo audit -f src-tauri/Cargo.lock`. CORRECTION (found during planning): the `rustsec/audit-check` action assumes a repo-root `Cargo.lock`, but ours lives in `src-tauri/`; the explicit `-f <path>` invocation is unambiguous. The job runs on `ubuntu-latest` (lockfile audits are platform-independent — cheaper + faster than macOS).
- Q: Do audit findings block the workflow? → A: A high+ npm advisory or any RustSec **vulnerability** fails the run. RustSec **warning**-level advisories (unmaintained/unsound) are printed but do NOT fail CI. CORRECTION (found during baseline run): `cargo audit` against the current `Cargo.lock` surfaces 17 warning-level advisories (16 unmaintained + 1 unsound), 0 vulnerabilities — all transitive through `tauri`/`wry`/`tauri-utils`, none fixable by us, 10 of them Linux-only GTK3 deps a macOS app never compiles. Failing CI on them would be permanent red noise that trains CI-blindness; `--deny warnings` is therefore NOT used. The weekly schedule + Dependabot surface fixes when Tauri upstream bumps its tree.
- Q: Which Dependabot ecosystems + cadence? → A: `cargo` (in `/src-tauri`), `npm` (in `/`), and `github-actions` (in `/`), all weekly. Grouped minor/patch updates to limit PR noise.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A parser-crate CVE cannot ship silently (Priority: P1)

JuraDrop parses untrusted documents through `pdf-extract`, `docx-rs`,
`rtf-parser`, `zip`, `quick-xml`. When a security advisory is published against
any of them (or any transitive dependency), CI surfaces it and Dependabot opens
a bump PR — instead of the vulnerable version shipping to users who feed it
confidential legal files.

**Why this priority**: Untrusted-document parsing is the app's primary attack
surface. `npm audit` is clean today, but nothing keeps it that way, and
`cargo-audit` isn't run at all. This is the supply-chain half of the hardening
review.

**Independent Test**: Run `cargo audit` and `npm audit --omit=dev --audit-level=high` locally and confirm both exit cleanly today; confirm the workflow runs both and that a seeded advisory (or `--deny warnings`) would fail it.

**Acceptance Scenarios**:

1. **Given** a push to `main` or a PR, **When** `audit.yml` runs, **Then** `cargo audit` (against `Cargo.lock`) and `npm audit --omit=dev --audit-level=high` both execute.
2. **Given** a published advisory against a (transitive) dependency, **When** the weekly scheduled run executes, **Then** the run fails and names the advisory.
3. **Given** a dependency with a newer version, **When** Dependabot runs, **Then** it opens a bump PR for the cargo / npm / github-actions ecosystem.

### Edge Cases

- A RustSec advisory with no fixed version available → the run fails; the developer decides to `cargo audit --ignore RUSTSEC-XXXX` with a documented rationale (not done preemptively).
- Dev-only npm vulnerabilities (build tooling) → excluded by `--omit=dev` (they never ship to users).
- `audit.yml` must NOT need the Ollama sidecar or a compile — audits read `Cargo.lock` / `package-lock.json` only, keeping the job fast.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A `.github/workflows/audit.yml` MUST run `cargo audit` against `Cargo.lock` and `npm audit --omit=dev --audit-level=high`.
- **FR-002**: `audit.yml` MUST trigger on `push` to `main`, `pull_request`, and a weekly `schedule`.
- **FR-003**: The audit job MUST NOT fetch the Ollama sidecar or compile the project (audits read lockfiles only) — keeping it independent of, and faster than, `ci.yml`.
- **FR-004**: A high or critical npm advisory in the production dependency tree MUST fail the run; a RustSec **vulnerability** MUST fail the run. RustSec **warning**-level advisories (unmaintained/unsound) MUST be reported (printed in the run) but MUST NOT fail it (`--deny warnings` is not used) — see the accepted-advisories list below.
- **FR-005**: A `.github/dependabot.yml` MUST configure update checks for the `cargo` ecosystem (in `/src-tauri`), the `npm` ecosystem (in `/`), and `github-actions` (in `/`).
- **FR-006**: Dependabot MUST run on a weekly cadence and group minor/patch updates to limit PR noise.
- **FR-007**: The audit workflow MUST use read-only repository permissions and introduce no secret usage (Principle I — CI must not exfiltrate).

## Accepted advisories (baseline 2026-06-02)

`cargo audit` against the current `Cargo.lock`: **0 vulnerabilities**, 17 warnings.
All transitive through `tauri 2.11.2` / `wry 0.55.1` / `tauri-utils 2.9.2`; none
fixable in this repo (they resolve when Tauri upstream bumps its tree). Reported
every run, not failed:

| Advisory | Crate | Kind | Reachable on macOS? |
|---|---|---|---|
| RUSTSEC-2024-0411…0420 (10) | `atk(-sys)`, `gdk(-sys)`, `gdkwayland-sys`, `gdkx11(-sys)`, `gtk(-sys)`, `gtk3-macros` | unmaintained | No — Linux-only GTK3 stack, never compiled |
| RUSTSEC-2024-0429 | `glib` 0.18.5 | unsound (VariantStrIter) | No — Linux GTK stack |
| RUSTSEC-2024-0370 | `proc-macro-error` 1.0.4 | unmaintained | No — via GTK macros |
| RUSTSEC-2025-0075/0080/0081/0098/0100 (5) | `unic-char-range/common/property`, `unic-ucd-ident/version` | unmaintained | Yes — via `tauri-utils → urlpattern → unic` |

npm audit (`--omit=dev --audit-level=high`): **0 vulnerabilities**.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `cargo audit` (vulnerabilities only) and `npm audit --omit=dev --audit-level=high` both exit 0 against the current lockfiles (baseline clean: 0 vulnerabilities; 17 reported-but-not-failing RustSec warnings).
- **SC-002**: `audit.yml` runs both audits on push/PR/schedule and goes red if either reports a qualifying advisory.
- **SC-003**: `.github/dependabot.yml` is valid and covers cargo + npm + github-actions.
- **SC-004**: The audit job completes without fetching the Ollama binary or compiling Rust (it reads lockfiles only).

## Assumptions

- Spec-only track: CI/infra + config, no new entities/state/UI — no `.allium`, no `/tla`, no browser tests.
- `Cargo.lock` and `package-lock.json` are committed (verified present).
- `cargo audit` via `rustsec/audit-check@v2`; `npm audit` via the bundled npm CLI.
- Direct-push to `main`, no feature branch.
