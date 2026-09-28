# GitHub Actions rule (CI minimalism — budget protection)

Actions minutes come from one shared 3000-min/month free tier; iskvalp burned it in four days with 17 workflows that re-ran checks already done locally. Long form (incident, caching YAML, due-state design, mobile details): `.claude/docs/github-actions-rationale.md` — read it before creating or editing anything under `.github/workflows/`.

## The contract (BLOCKING)

On a solo project (default, `.claude/rules/project-workflow.md`) `.github/workflows/` holds **at most two workflows**:

1. **`deploy-[projectname].yml`** — deploy to the live4.se cluster, `workflow_dispatch` only with the `confirm_deploy: "deploy"` input, never on push. May start with a minimal build + unit-test gate.
2. **(Optional) one minimal validation workflow** — only for a check that genuinely cannot run locally. If in doubt, it does not exist.

Everything else runs locally. Before creating ANY file under `.github/workflows/`: count what exists; if the new file is not the deploy workflow, stop and ask with `AskUserQuestion`, naming this rule and the budget incident. On an existing sprawl: report the inventory (file, trigger, estimated minutes), delete nothing silently. A spec demanding a new workflow is a register-rewrite conversation (`.claude/rules/spec-register.md`); "add a CI gate" means a local script, a hook, or a step in the deploy workflow's gate.

**Recurring work** runs via the project's due-state, not a scheduler: `scripts/maintenance-due.sh` records when each job last ran and presents what is due at SessionStart and in the per-spec status summary. `scripts/install-nightly-maintenance.sh` (`--at HH:MM`, `--list`, `--remove`) is opt-in only; if used, pass `--if-due`.

**Allowed-workflow hygiene (mandatory):** `workflow_dispatch` + `confirm_deploy`; `concurrency` with `cancel-in-progress: true`; `timeout-minutes` on every job; only well-known actions. **Caching is BLOCKING:** shallow checkout; `actions/setup-dotnet` `cache: true` with a lock file (`dotnet restore --use-lock-file`); `actions/setup-node` `cache: 'npm'` (or pnpm/yarn); `docker/build-push-action` with `cache-from: type=gha` / `cache-to: type=gha,mode=max`; Dockerfile restores before copying source; no redundant `actions/cache` for what setup actions already cache. Missing cache config is a finding to fix in place.

**Team + PRs=yes:** one push/PR-triggered build + unit-test workflow (with `paths` filters and concurrency cancellation) is acceptable; heavy checks stay forbidden without a recorded user decision. `.github/dependabot.yml` is allowed.

**Mobile carve-out:** Expo → EAS Workflows (`.eas/workflows/`, no Actions minutes) preferred, else one `workflow_dispatch`-only `eas build`/`eas submit` workflow; Flutter → one `workflow_dispatch`-only build + fastlane workflow with `timeout-minutes`. Gate on `npx tsc --noEmit && npm test` / `flutter analyze && flutter test`. See `.claude/docs/deployment-mobile.md`.

## What this rule forbids (as GitHub Actions workflows)

CodeQL / code scanning; secret scanning (gitleaks, trufflehog) on push or schedule; mutation testing (Stryker); a11y / Lighthouse audits; per-spec or per-feature CI workflows; actionlint / workflow linting; OS/runtime matrix builds; **any `schedule:` (cron) trigger**; push-triggered test or build workflows; EAS/store builds on push; per-spec mobile workflows or scheduled rebuilds.
