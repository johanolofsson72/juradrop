# Spec interview — 052-release-tooling-docs

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. The base is auto-answered with the recommended option. The spec is not flagged: it is tooling/docs on the spec-only track. The dependency depth and the release mechanics were already decided by Johan at kickoff: safe upgrades only; prepare v0.5.0 and Johan runs the workflow.

## Q1 — Scope
**Q:** How deep does the dependency upgrade go?
**A:** Safe upgrades only, with no majors (Johan, kickoff).

## Q2 — Release mechanics
**Q:** Who triggers the build?
**A:** Johan runs the manual release workflow. I prepare v0.5.0 (Johan, kickoff).

## Q3 — Actor
**Q:** Who runs the bump script?
**A (auto):** The developer, locally, on a clean `main`.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** One command bumps the 5 files and cuts the CHANGELOG, then prints the tag/push/dispatch steps.

## Q5 — Validation
**Q:** What does it refuse?
**A (auto):** A non-semver or non-increasing version, an empty `[Unreleased]`, missing in-app notes, or a dirty tree.

## Q6 — Error states
**Q:** How does a refusal look?
**A (auto):** It exits non-zero with a one-line `ERROR:` naming the fix. No file is changed.

## Q7 — Dry run
**Q:** Is there a preview mode?
**A (auto):** `--dry-run` prints the planned edits and changes nothing.

## Q8 — Idempotency
**Q:** What happens on a second run with the same version?
**A (auto):** It refuses ("not greater than the current version").

## Q9 — Integration points
**Q:** What does it touch?
**A (auto):** The five version sites, CHANGELOG.md and `startup-strings.ts` (read-only check).

## Q10 — Lockfiles
**Q:** How are the lockfiles bumped?
**A (auto):** `npm version --no-git-tag-version` (package + lock) and a targeted `[[package]] name = "juradrop"` edit in Cargo.lock.

## Q11 — Docs audience
**Q:** Who is the user guide for?
**A (auto):** Law students with no CLI experience. It is written in Swedish, du-form, with no jargon.

## Q12 — Docs accuracy
**Q:** How is the guide kept accurate?
**A (auto):** Every zone description is sourced from `help-strings.ts`, and a vitest checks that the guide names all 12 zone titles.

## Q13 — CI
**Q:** What changes in `release.yml`?
**A (auto):** Node 20 → 22 only, with caching kept. There are no new workflows (per the github-actions rule).

## Q14 — Non-goals
**Q:** What is deliberately not done?
**A (auto):** The Ollama bump (F001), the majors, auto-publishing a release, and pushing tags from scripts.

## Q15 — Reversibility
**Q:** What is the rollback story?
**A (auto):** Everything is a git-tracked text edit, and a local tag is deletable (`git tag -d`).

## Q16 — Acceptance
**Q:** What is the definition of done?
**A (auto):** The script tests pass, all suites are green after the upgrades, v0.5.0 is bumped with a dated CHANGELOG, and the release gate test is green.
