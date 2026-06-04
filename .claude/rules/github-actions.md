# GitHub Actions rule (CI minimalism — budget protection)

GitHub Actions minutes come from one shared free tier (3000 minutes/month on the org). In June 2026 the iskvalp project exhausted the entire month's budget in **four days** with 17 workflows (CodeQL, gitleaks, Stryker mutation testing, a11y audits, per-spec CI suites, actionlint, trufflehog, scheduled scans). Every one of those checks already ran locally before deploy. The CI runs bought nothing and cost everything. This rule exists so that never happens again.

## The contract (BLOCKING)

On a solo project (the default — see `.claude/rules/project-workflow.md`), the repo's `.github/workflows/` directory contains **at most two workflows**:

1. **`deploy-[projectname].yml`** — deploy to the live4.se Linux cluster, triggered by `workflow_dispatch` with the `confirm_deploy: "deploy"` safety input. Never on push. This workflow MAY contain a minimal validation gate (build + unit tests) as its first job, because a broken build must not reach the cluster.
2. **(Optional) one minimal validation workflow** — only if the project genuinely needs a remote check that cannot run locally. Most projects do not need this. If in doubt, it does not exist.

That is the whole allowance. Everything else runs locally.

## Why local-first is correct here

Per `CLAUDE.md`, nothing is "done" until `dotnet test`, Playwright E2E, and visual verification pass **locally**. The full test suite, stress tests, security scans, and formal verification all run on the developer's machine before any deploy. A CI job that re-runs them on `ubuntu-latest` re-buys information we already have, at metered prices.

## What this rule forbids

Creating any of the following as GitHub Actions workflows:

- CodeQL / code scanning workflows — run `security-scanner` agent or `gitleaks detect` locally
- Secret scanning (gitleaks, trufflehog) on push or schedule — run locally before commit
- Mutation testing (Stryker) — local, on demand
- Accessibility audits (a11y, Lighthouse) — local, pre-deploy per `.claude/docs/stress-testing.md`
- Per-spec or per-feature CI workflows ("spec 033 CI", "comments-ci", "i18n-ci") — the spec pipeline runs locally; specs never add workflows
- actionlint or workflow-linting workflows
- Matrix builds across OS/runtime versions — we ship one Docker image to one Linux cluster
- `schedule:` (cron) triggers of any kind
- Push-triggered test or build workflows — tests run locally per the Definition of Done
- EAS/store build workflows on push — run `eas build` locally or via `workflow_dispatch` only if truly needed

When a spec says "add a CI gate", the correct implementation is a local script, a Claude Code hook, or a step inside the existing deploy workflow's validation gate. Not a new workflow file. If a spec explicitly demands a new workflow, that is a register-rewrite conversation per `.claude/rules/spec-register.md`, not a silent `mkdir .github/workflows`.

Dependabot config (`.github/dependabot.yml`) is allowed — Dependabot PRs consume no Actions minutes by themselves. But remember: every Dependabot PR triggers any push/PR-triggered workflows that exist. One more reason the allowed set excludes them.

## Workflow hygiene (for the deploy workflow that is allowed)

- `workflow_dispatch` trigger only, with the `confirm_deploy` input
- `concurrency` group with `cancel-in-progress: true`
- `timeout-minutes` on every job (a hung job bills until the 6-hour default kills it)
- No third-party actions beyond the well-known set (`actions/checkout`, `actions/setup-dotnet`, `appleboy/scp-action` etc.) — fewer moving parts, fewer minutes

## Team projects

If the project workflow memory says `staffing: team` AND `PRs: yes`, a single push/PR-triggered validation workflow (build + unit tests, with `paths` filters and concurrency cancellation) is acceptable, because there is a reviewer who needs the signal remotely. The heavy checks (CodeQL, mutation testing, scheduled scans) stay forbidden without an explicit, recorded user decision.

## How to apply

- Before creating ANY file under `.github/workflows/`: count what is already there. If the new file is not the deploy workflow, stop and ask the user with `AskUserQuestion` — name this rule and the budget incident.
- When touching an existing project that has workflow sprawl: do not delete anything silently. Report the inventory (file, trigger, estimated minutes) and let the user decide what dies.
- When the wizard or sync runs on a project: this rule ships with the config, so every future session knows the policy without being told.
