# Feature Specification: Polish and Public Beta Prep

**Feature Branch**: `main` (solo direct-push)
**Created**: 2026-05-28
**Status**: Draft
**Track**: Spec-only (per `specs/INDEX.md` row 012) — no `.allium`, no `/tla`, no plan/tasks/analyze artifacts. Doc + asset work only.

**Input**: Final pass before public announcement — README polish, screenshots, LICENSE file, beta test with 3+ Swedish law students, fix surfaced rough edges.

## Clarifications

### Session 2026-05-28

- Q: How are the 3+ screenshots actually generated, given Claude cannot run a signed `.app` build in this session? → A: **Ship placeholder PNGs now + document the regeneration step in CHANGELOG/runbook.** The placeholders are honest-stub images (a 1280×800 PNG with the file's intent text rendered in a system font — e.g., "Skärmdump: sex-zoners rutnät (genereras vid v0.1.0)"). The repo gets the directory + the embedding in README; the actual screenshots get committed as part of the v0.1.0 release tag preparation. This unblocks the spec without lying about pixel-level fidelity from a build Claude can't make.
- Q: What language should `CHANGELOG.md` be in — Swedish or English? → A: **Swedish.** The CHANGELOG is user-facing (it's read by people deciding whether to upgrade, the same audience as the README). Per Principle V (Swedish-first UI), Swedish wins. The Keep-a-Changelog headings (`## [0.1.0]`, `### Added`, `### Fixed`, `### Changed`) stay in English because they're a structural convention; the entry bodies are Swedish.
- Q: Should the README include a CI status badge linking to GitHub Actions? → A: **Skip.** The spec 006 release workflow only runs on `v*.*.*` tag pushes — there's no per-commit CI green/red signal to badge. A badge that's blank or grey looks broken; a badge that links to an empty workflow runs page looks abandoned. Skip until a per-commit CI workflow exists (which would be a future spec, not this one).
- Q: For the "current state" line in README's Status section, do we write it as if v0.1.0 is imminent OR honest "polish-prep done, no signed DMG yet"? → A: **Honest current state.** Write the Status section to say specs 001-011 are done, spec 012 (polish + beta-prep) is in progress / has just shipped, and the first signed DMG is the next user-facing milestone (when the user pushes a `v0.1.0` tag). No marketing language pretending the release is imminent until it actually is. Bumping to "v0.1.0 shipped" happens in a follow-up README amendment after the tag push.
- Q: Should `docs/` have sub-grouping (e.g., `docs/screenshots/`, `docs/runbooks/`) or be flat? → A: **Flat-ish with one subdirectory for screenshots.** `docs/screenshots/` (PNGs need their own dir for tooling reasons — image-glob patterns + .gitattributes for binary handling) and `docs/beta-test-runbook.md` as a single file. No `docs/runbooks/` subdirectory yet — premature taxonomy on a 2-file docs tree.

## What's IN scope vs OUT of scope (read first)

This is the LAST spec in the register. To stay honest about a spec-only / doc-only feature, here is the scope boundary:

| Item | In/Out | Why |
|---|---|---|
| README status section update (add spec 010 + 011 + drop stale `spec 001` references on lines 84/93/101) | **IN** | Reader-visible accuracy; spec 010 + 011 + the signed-release pipeline (spec 006) are all done, README still claims pre-MVP-with-009 + "unsigned at spec 001". |
| LICENSE file at repo root | **IN** | Top of README has a `[![License: MIT]]` shield that links to `LICENSE`, but no `LICENSE` file exists. Public beta cannot ship with a broken link. |
| First-launch screenshot set (welcome wizard, six-zone grid, settings panel, error state) | **IN** | Public README needs visual proof the app exists. Four screenshots at light + dark theme = 8 PNGs in a new `docs/screenshots/` directory. |
| Beta test with 3+ Swedish law students | **OUT (user action, cannot be coded)** | The spec acknowledges this as a step the user takes manually after this spec ships. Not implementable. |
| "Fix surfaced rough edges" from beta feedback | **OUT (requires future spec)** | Without the beta data, there's nothing to fix yet. If beta surfaces issues, they become spec 013+ candidates. Out of scope here. |
| New features, new UI, new state machines, new dependencies | **OUT** | This is spec-only / polish. No behavior changes. |
| Allium spec + TLA+ verification | **OUT (spec-only track)** | Per the register triage table — doc/asset specs do NOT get `.allium` files. Per `.claude/rules/allium.md` § "Skip `/allium:elicit` for the spec-only track" — running it would produce a fabricated `.allium` that surfaces as false drift later. |

The single user-blocking deferral (beta test + rough-edge fixes) is the honest reason this spec doesn't pretend to be a coding feature.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Discover JuraDrop via GitHub README (Priority: P1)

A Swedish law student (or their professor, or a developer evaluating the project) lands on `github.com/johanolofsson72/juradrop` from a tweet, a forum post, or a search result. Within 30 seconds of scrolling, they have:

1. Seen the value proposition (Swedish, terse, no marketing fluff).
2. Seen visual proof the app exists (welcome screen + zone grid + at least one error state screenshot).
3. Confirmed the project is actively maintained (status section accurate; specs 001-011 listed as done; "v0.1 released" or "v0.1 in beta" line — whichever applies at publish time).
4. Found the install link to a signed DMG OR an honest "first signed release coming, here's the timeline" note.
5. Confirmed the license (MIT, with a clickable LICENSE file at repo root that actually exists).

**Why this priority**: First impressions decide whether the project gets a second look. A README claiming "Pre-MVP spec 001" while spec 011 has shipped reads as abandonment.

**Independent Test**: A human reader (not Claude) opens the README on github.com, scrolls top to bottom, and answers: "Is the status section accurate?" "Are there screenshots?" "Does the LICENSE link work?" Three yeses = pass.

**Acceptance Scenarios**:

1. **Given** the README on the main branch, **When** a reader scrolls to the Status section, **Then** specs 001 through 011 are listed as done (with 012 as the current polish pass) and no line claims "spec 001" current behaviour (e.g., the "unsigned at spec 001" line is removed or rewritten to reflect the spec 006 signed-DMG pipeline that's been live since 2026-05-27).
2. **Given** the README, **When** a reader clicks the `[![License: MIT]]` shield, **Then** the link resolves to a `LICENSE` file at the repo root containing the standard MIT license text with the project's copyright line.
3. **Given** the README, **When** a reader scrolls past the value proposition, **Then** at least one screenshot is visible showing the six-zone grid in the OS-appropriate appearance (light or dark) and the screenshot embeds via a path under `docs/screenshots/`.

---

### User Story 2 — Verify the beta-test runbook is honest about who does what (Priority: P2)

A beta-testing law student wants to know what they're agreeing to. They open the `docs/beta-test-runbook.md` (new file from this spec) and see a one-page document covering:

- What JuraDrop does and what it does NOT do (the constitution's privacy promise in plain Swedish).
- How to install (drag-and-drop DMG).
- The five tasks to try (one per remaining zone — sammanfatta, tillengelska, tillsvenska, punktlista, anonymisera, forenkla).
- How to report a bug (GitHub issue link, e-mail address, OR a one-page Google Form — whichever the project chooses).
- What data the project collects (NONE — restate the constitution).
- How to uninstall (drag-to-trash + optional `~/Library/Application Support/com.juradrop.app/` cleanup).

**Why this priority**: A beta with NO runbook is a beta where the tester guesses at expectations. A runbook makes the contract explicit.

**Independent Test**: Apply the runbook step-by-step on a clean Mac. Each step is unambiguous and completes without external help.

**Acceptance Scenarios**:

1. **Given** the runbook, **When** a tester follows step 1 (install), **Then** they reach a working app launch without consulting any other document.
2. **Given** the runbook, **When** a tester reaches the "report a bug" section, **Then** they see a single canonical channel (GitHub issues is the default; email is optional fallback) with the URL in clickable form.
3. **Given** the runbook, **When** a tester reaches the "what data is collected" section, **Then** they see the literal sentence: **JuraDrop samlar in noll data om dig eller dina dokument.** (Restating the constitution in beta-test context.)

---

### User Story 3 — Project root looks like a real OSS project, not a half-built side project (Priority: P3)

A passing developer scanning the repo tree at github.com expects to see:

- `LICENSE` (MIT, present) — currently missing
- `README.md` (present, accurate) — needs status update
- `CHANGELOG.md` (NEW — at least documenting v0.1 release notes, even if a stub)
- `CONTRIBUTING.md` (OPTIONAL — out of scope here; can be added if/when external PRs become a thing)
- `docs/` (NEW — homes the screenshots and beta-test runbook)
- A version tag matching the current build (`v0.1.0` once signed DMG ships)

**Why this priority**: Repo-shape signals professionalism. A repo with `CLAUDE.md` and `PROJECT-BRIEF.md` but no `LICENSE` looks half-built. The fix is one new file + one new directory.

**Independent Test**: Run `ls /Users/jool/repos/juradrop/` and observe `LICENSE`, `CHANGELOG.md`, `docs/` at the top level.

**Acceptance Scenarios**:

1. **Given** a fresh `git clone`, **When** the developer runs `ls`, **Then** `LICENSE` and `CHANGELOG.md` are present at the repo root.
2. **Given** the `docs/` directory, **When** the developer lists its contents, **Then** they see `screenshots/` (subdirectory with PNGs) and `beta-test-runbook.md`.

---

### Edge Cases

- **Screenshots get stale fast.** Every UI change after this spec could invalidate the screenshots. Mitigation: take screenshots from the actual signed v0.1.0 build (locked at release tag); regenerate only when a major UI change ships (spec 013+, if any).
- **LICENSE shield breaks if `LICENSE` is renamed.** The shield URL hard-codes the lowercase path `LICENSE`. Don't add an extension; keep it `LICENSE` (the GitHub convention).
- **Beta runbook drift.** If the install flow changes after the runbook is written (e.g., signed DMG → notarization-required → user must right-click to open), the runbook becomes wrong. Mitigation: pin the runbook to the v0.1.0 release; cross-reference the release notes when the next signed DMG ships.
- **Reviewers expect a CI badge.** Spec 006 ships the release-on-tag workflow; this spec MAY add a `[![CI]]` shield linking to the GitHub Actions runs page. OPTIONAL — only if a green badge is available; broken badges are worse than no badge.
- **`docs/` directory might shadow something else.** Currently no `docs/` directory exists at the repo root. Confirmed safe to create.

## Requirements *(mandatory)*

### Functional Requirements

#### Documentation polish
- **FR-001**: The README's "Status" section MUST be updated to list specs 001 through 011 as done, and to remove (or rewrite) any line claiming "spec 001" current state. Stale lines specifically to fix: line 84 (`fetch-ollama.sh is required... spec 002 bundles`), line 93 (`unsigned at spec 001`), line 101 (`stub at spec 001`). All three should reflect the post-spec-006 reality: signed DMG pipeline live, fetch-ollama.sh wired into CI, Playwright stub still acceptable (it remains a stub but the comment should not anchor on spec 001).
- **FR-002**: The README's status paragraph (currently line 40) MUST mention that the settings panel (spec 010) and the error-recovery hardening (spec 011) are part of v0.1.0. Specifically: the gear icon for tier selection, the auto-restart-once on crash with Swedish-only error surface, and the two new grep-enforced invariants (no English tells, no telemetry libraries).
- **FR-003**: The README MUST embed at least 3 screenshot slots: (a) the six-zone grid, (b) the welcome wizard's progress screen, (c) the settings panel (spec 010) open. Screenshots live under `docs/screenshots/` with descriptive lowercase-hyphenated filenames. **Initial commit ships placeholder PNGs per Clarification Q1** — each placeholder is a 1280×800 PNG with the descriptive title rendered in Swedish (e.g., `Skärmdump: sex-zoners rutnät — genereras vid v0.1.0`). The real screenshots replace the placeholders as part of the v0.1.0 tag-push release commit. The README embedding survives the swap (same filenames).

#### LICENSE file
- **FR-004**: A `LICENSE` file MUST exist at the repo root containing the standard MIT license text. The copyright line MUST read **Copyright (c) 2026 Johan Olofsson**. No customisations beyond the standard MIT template + copyright line.
- **FR-005**: The README's existing `[![License: MIT]]` shield's link target MUST resolve to the new `LICENSE` file (verified by GitHub rendering — clicking the badge opens the file).

#### CHANGELOG
- **FR-006**: A `CHANGELOG.md` MUST exist at the repo root in Keep-a-Changelog format. **Headings (e.g., `## [0.1.0]`, `### Added`) stay English** (Keep-a-Changelog structural convention); **entry bodies are Swedish** (Clarification Q2 — Principle V applies to the user-facing content). The initial entry covers `## [Unreleased]` listing the polish prep (spec 012) + an `## [0.1.0] - YYYY-MM-DD` planned entry whose body is filled when the user pushes the v0.1.0 tag.

#### Beta-test runbook
- **FR-007**: A `docs/beta-test-runbook.md` MUST exist with the 6 sections enumerated in User Story 2. Written in Swedish (per Principle V — user-facing). Maximum 2 printed pages (roughly 1500 Swedish words).
- **FR-008**: The runbook MUST include the literal sentence `JuraDrop samlar in noll data om dig eller dina dokument.` exactly once. This is the operationalised privacy promise per the constitution's Principle I.

#### Repo tree
- **FR-009**: After this spec, the repo root MUST contain (in addition to existing files): `LICENSE`, `CHANGELOG.md`, and a `docs/` directory with at least `screenshots/` and `beta-test-runbook.md`.
- **FR-010**: NO existing file may be deleted by this spec. Only additions + the four enumerated README line edits.

#### Out-of-scope reaffirmation
- **FR-011**: This spec MUST NOT modify any file under `src/`, `src-tauri/src/`, or `src-tauri/tests/` (with the EXCEPTION of any fixture file that documents a Swedish string we're now also referencing in a doc — which would be a one-line addition only, not behavior change). If a code change feels needed to support a README claim, that's a spec 013+ candidate.
- **FR-012**: This spec MUST NOT add any new dependency (Cargo, npm, system tool). Doc + asset work only.

### Key Entities

- **README** (existing `/Users/jool/repos/juradrop/README.md`): the project's GitHub-rendered front page. Status section is the staleness-prone region.
- **LICENSE** (new `/Users/jool/repos/juradrop/LICENSE`): standard MIT license text.
- **CHANGELOG** (new `/Users/jool/repos/juradrop/CHANGELOG.md`): Keep-a-Changelog format, v0.1.0 entry.
- **Beta-test runbook** (new `/Users/jool/repos/juradrop/docs/beta-test-runbook.md`): one-page Swedish doc for the 3+ student tester cohort.
- **Screenshots** (new `/Users/jool/repos/juradrop/docs/screenshots/*.png`): at least 3 PNGs covering the zone grid, the wizard, and the settings panel.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the four enumerated README staleness lines (lines 40, 84, 93, 101 per current state) are corrected to reference the post-spec-011 reality. Verified by `grep -n 'spec 001' README.md` returning zero matches in the status/install/test sections (other historical references in legitimate context — e.g., "spec 001 (Tauri-bootstrap)" in a completed-specs list — are acceptable).
- **SC-002**: The `LICENSE` file exists at the repo root and contains the MIT license text with the copyright line **Copyright (c) 2026 Johan Olofsson**. Verified by `test -f LICENSE && grep -q "Copyright (c) 2026 Johan Olofsson" LICENSE`.
- **SC-003**: `CHANGELOG.md` exists at the repo root with a v0.1.0 entry in Keep-a-Changelog format. Verified by `grep -q '## \[0.1.0\]' CHANGELOG.md`.
- **SC-004**: `docs/beta-test-runbook.md` exists, is in Swedish, contains the literal privacy sentence `JuraDrop samlar in noll data om dig eller dina dokument.` exactly once, and is ≤ 1500 Swedish words. Verified by file existence + grep + `wc -w`.
- **SC-005**: `docs/screenshots/` contains at least 3 PNG files. Verified by `ls docs/screenshots/*.png | wc -l` ≥ 3.
- **SC-006**: NO file under `src/` or `src-tauri/src/` or `src-tauri/tests/` is modified by this spec. Verified by `git diff --name-only HEAD~1` excluding the doc files.
- **SC-007**: NO new dependency is added. Verified by no changes to `Cargo.toml`, `Cargo.lock`, `package.json`, `package-lock.json`. (The telemetry-denylist test from spec 011 already enforces no telemetry libs — this spec MUST NOT trigger that test by accident.)
- **SC-008**: All existing tests (369 Rust + 326 vitest from spec 011 close) still pass — this spec adds no code, so no regression possible, but the CI gates run as final confirmation.

## Assumptions

- **Beta-test runbook is published to the repo, NOT to a separate website.** Keeps everything in one place; the runbook follows the project's version history via git rather than being a moving Notion page.
- **GitHub issues is the canonical bug channel.** No separate forum, no Discord, no email-only flow. Lowest-friction for both reporters and the maintainer.
- **The MIT license year is 2026.** Spec 001 was written 2026-05-25, the constitution was ratified 2026-05-25, and the current spec is 2026-05-28. No prior-year contribution exists.
- **Screenshots come from a real build, not Figma mockups.** The frontend-design discipline established by spec 010 demands actual screenshots from `npm run tauri dev` — Figma mockups would lie about pixel-level rendering on macOS.
- **Beta tester recruitment is the user's responsibility.** Spec 012 cannot recruit 3+ Swedish law students. The runbook + the README polish are the SHIPPABLE artifacts; the actual beta is a user-driven follow-up.
- **No `.allium` file for this spec.** Per the register triage table + `.claude/rules/allium.md` § spec-only track. Forcing an Allium spec on a doc-only feature would produce fabricated invariants that later show up as false drift.
- **No new "rough edges" fixed in this spec.** Spec 012 is the polish-prep pass — the actual rough-edge fixes from beta feedback are spec 013+ candidates. If beta surfaces a P0 blocker, that's a follow-up spec, not silently bundled here.
