# Plan — 052 release-tooling-docs

1. `scripts/bump-version.sh`: bash, `set -euo pipefail`. It validates and then edits the files with node (JSON) and python-free sed/awk (TOML), and is POSIX-friendly where possible. `scripts/test-bump-version.sh` runs it against a temp copy of the five files + CHANGELOG + startup-strings in a throwaway git repo.
2. `scripts/release-prep.sh`: correct the final instructions (dispatch, not tag trigger).
3. `src/__tests__/release-gate.test.ts`: the RELEASE_NOTES entry for the package version, and the user guide naming all 12 zones.
4. Docs: `docs/anvandarguide.md` (new), README (version, 12 zones, size 3.3 GB, update endpoint, link to the guide, release flow), `docs/beta-test-runbook.md` (12 zones, 3.3 GB), `.claude/docs/deployment.md` (one-command flow).
5. Deps: `npm update`, `@types/react@^18`/`@types/react-dom@^18`, `cargo update`; `release.yml` Node 22. Re-run lint/tsc/vitest/cargo test/clippy/playwright.
6. Cut: `bash scripts/bump-version.sh 0.5.0`, then commit `chore(release): v0.5.0` and create the local annotated tag `v0.5.0`.
