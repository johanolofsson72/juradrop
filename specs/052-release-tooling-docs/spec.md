# Spec 052 — release-tooling-docs

**Track:** spec-only (tooling, docs, dependency bumps; no new runtime behaviour or state).
**Created:** 2026-09-25 · **Requested by:** Johan: "gör dokumentation och uppdatering av appen enklare", "se till att vi använder … senaste tekniken", "skapa en ny deploy och en ny version".

## Problem

- Cutting a version means editing five files by hand: `package.json`, `package-lock.json`, `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock` and `src-tauri/tauri.conf.json`. You also move CHANGELOG `[Unreleased]` by hand. Nothing checks that the in-app "Nytt i versionen" notes (spec 051) exist for the new version.
- `scripts/release-prep.sh` tells the developer to push a tag and says "GitHub Actions will pick up the tag push". That is false: `release.yml` is `workflow_dispatch`-only. A developer who follows it gets no build.
- The README says the latest version is v0.3.0, that checks go to `api.github.com`, and that the download is ~2 GB. The runbook says "sex zoner" (there are 12) and "~3 GB". No end-user guide covers the 12 zones.
- The CI runs Node 20, which reached end-of-life in April 2026. `@types/react` 19 is paired with React 18, which is a type mismatch. Lockfiles have drifted behind semver-compatible patches.

## Functional requirements

- **FR-001** `scripts/bump-version.sh X.Y.Z [--dry-run]` bumps all five version sites, moves `## [Unreleased]` → `## [X.Y.Z] - <today>` (leaving an empty `[Unreleased]`), and refuses to run when any of these hold: the version is not semver; it is not greater than the current version; `[Unreleased]` is empty; `RELEASE_NOTES` has no entry for X.Y.Z; the tree is dirty. It never commits, tags or pushes; it prints the next steps.
- **FR-002** `scripts/release-prep.sh` prints the true next step. That means creating the tag and pushing it, then running the **release** workflow from the Actions tab with `tag=vX.Y.Z` and `confirm_release=release`, then smoke-testing and publishing the draft. It does not mention a tag-push trigger.
- **FR-003** A vitest release gate asserts that `RELEASE_NOTES[package.json version]` exists (moved here from spec 051).
- **FR-004** A `docs/anvandarguide.md` Swedish end-user guide covers install, first start, all 12 zones, the instruction field, Välj fil, settings (models, appearance, tips), updates, privacy, and common errors. The README and runbook are corrected, and `.claude/docs/deployment.md` documents the new one-command flow.
- **FR-005** Safe upgrades only (Johan). They cover: `npm update` within the declared ranges; `@types/react`/`@types/react-dom` aligned to React 18; `cargo update` (semver-compatible); and Node 22 in `release.yml`. No majors (React 19, Vite 7, Tailwind 4) and no Ollama bump (finding F001).
- **FR-006** v0.5.0 is cut with the script. The CHANGELOG entry covers 050 + 051 + 052.

## Clarifications

### Session 2026-09-25 (auto-picked, recommended)

- Q: Should the bump script also tag or push? → A: No. Pushing and dispatching are outward-facing, and the developer does them deliberately. The script prints the exact commands.
- Q: Should it replace `release-prep.sh`? → A: No. Bump edits; prep verifies at tag time. They are two steps with one responsibility each.
- Q: Does thiserror 2 count as a "safe" upgrade? → A: No. It is a major, so it is recorded as a finding, not done.
- Q: Should the actions be bumped to newer majors (checkout v5)? → A: No. Only the Node runtime changes. The action majors are unchanged.

## Scenarios

This spec is tooling and docs only; it adds no user-facing app scenario. The script is covered by `scripts/test-bump-version.sh` (happy path, dry-run, each refusal).
