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

**The ban comes with an answer.** "No `schedule:` triggers" is only half a policy — the other half is where the recurring work actually happens, otherwise "nightly" quietly means "never" (which is what happened to the mutation gate and the secret scan). `scripts/project-maintenance.sh` is the local recurring pass: secrets + CVEs, context-cost canary, register drift, the every-5 hardening checkpoint, and `--full` for the mutation kill rate. It reports in attention mode (clean = one line) and exits 0/1/2 so a scheduler can branch. Wire it with `/schedule` (a weekly cloud routine), `/loop 7d`, or a plain crontab entry — all of which cost zero Actions minutes.

When a spec says "add a CI gate", the correct implementation is a local script, a Claude Code hook, or a step inside the existing deploy workflow's validation gate. Not a new workflow file. If a spec explicitly demands a new workflow, that is a register-rewrite conversation per `.claude/rules/spec-register.md`, not a silent `mkdir .github/workflows`.

Dependabot config (`.github/dependabot.yml`) is allowed — Dependabot PRs consume no Actions minutes by themselves. But remember: every Dependabot PR triggers any push/PR-triggered workflows that exist. One more reason the allowed set excludes them.

## Workflow hygiene (for the deploy workflow that is allowed)

- `workflow_dispatch` trigger only, with the `confirm_deploy` input
- `concurrency` group with `cancel-in-progress: true`
- `timeout-minutes` on every job (a hung job bills until the 6-hour default kills it)
- No third-party actions beyond the well-known set (`actions/checkout`, `actions/setup-dotnet`, `appleboy/scp-action` etc.) — fewer moving parts, fewer minutes

## Caching (BLOCKING — mandatory on the allowed workflow)

The two-workflow allowance in this rule caps *how many* workflows exist; caching is what keeps the *one* that remains cheap. An uncached `dotnet restore`/`npm ci` + Docker build on every deploy run burns minutes on work that hasn't changed since the last run. Every job in the allowed deploy workflow (and the optional validation workflow, if one exists) MUST cache its restorable state:

- **Shallow checkout.** `actions/checkout` with `fetch-depth: 1` (default) unless a step genuinely needs history (e.g. computing a changelog) — a shallow clone is faster to fetch and has nothing to do with Actions-minute billing directly, but it removes one avoidable source of job wall-clock.
- **.NET restore cache.** `actions/setup-dotnet` with its built-in `cache: true` (available since setup-dotnet v4), keyed on the lockfile/`*.csproj`/`*.sln` set. If the project has no `packages.lock.json`, generate one (`dotnet restore --use-lock-file`) so the cache key is stable — without a lock file the cache degrades to "restore everything, every time."
- **Node/npm restore cache.** `actions/setup-node` with `cache: 'npm'` (or `'pnpm'`/`'yarn'` to match the project's package manager) pointed at the correct lockfile. For a React frontend built into `wwwroot`, this is the single biggest minute-saver after Docker layer caching.
- **Docker layer caching.** The deploy workflow builds one image — cache its layers with `docker/build-push-action`'s built-in `cache-from`/`cache-to` using `type=gha` (GitHub Actions cache backend, no extra registry needed):
  ```yaml
  - uses: docker/build-push-action@v6
    with:
      cache-from: type=gha
      cache-to: type=gha,mode=max
  ```
  `mode=max` caches intermediate layers too (not just the final stage), which matters for multi-stage Dockerfiles (build stage + runtime stage — the common shape for a .NET+React single-image build). Without this, every deploy rebuilds the SDK image, restores every package, and re-runs `npm run build` from scratch, even when only a config file changed.
- **Order Dockerfile layers for cache reuse.** Copy `*.csproj`/`package.json`+lockfile and run restore/`npm ci` *before* copying the rest of the source — so a source-only change doesn't invalidate the restore layer. This is a Dockerfile-authoring concern, not a workflow-YAML one, but it's the other half of making `cache-from`/`cache-to` actually pay off.
- **Path filters to skip the job entirely.** If the deploy workflow's validation gate (build + unit tests) runs on paths that didn't change relevant files, use `paths`/`paths-ignore` (team workflows only, since solo projects don't trigger on push at all — see below) so unrelated commits don't even queue a run.
- **No redundant cache layers.** Don't hand-roll a `actions/cache@v4` step for `~/.nuget/packages` or `node_modules` *in addition to* `setup-dotnet`'s/`setup-node`'s built-in cache — that double-caches the same bytes under two keys and wastes cache storage/restore time without adding hit rate. Use the built-in `cache:` option first; only add a manual `actions/cache` step for something the setup action doesn't already cover (e.g. a Docker Buildx cache dir with `type=local`, if `type=gha` isn't available on self-hosted runners).

None of this changes the two-workflow ceiling — caching is an amendment *within* the allowed workflow(s), not a reason to add more of them. When reviewing an existing deploy workflow, missing cache configuration is a finding to fix in place, same priority as a missing `timeout-minutes`.

## Team projects

If the project workflow memory says `staffing: team` AND `PRs: yes`, a single push/PR-triggered validation workflow (build + unit tests, with `paths` filters and concurrency cancellation) is acceptable, because there is a reviewer who needs the signal remotely. The heavy checks (CodeQL, mutation testing, scheduled scans) stay forbidden without an explicit, recorded user decision.

## Mobile app builds (the one mobile carve-out)

A native mobile app cannot ship from the live4 cluster — App Store / Play builds need signing and store APIs that have no local equivalent on a Linux server. The shipping options, in order of preference:

- **React Native / Expo → EAS Workflows (preferred).** Define the build → submit → update chain in `.eas/workflows/` and run it on Expo's infrastructure. It does **not** consume the org's GitHub Actions minutes at all, so it sidesteps this budget rule entirely. This is the first choice for an Expo project. See `.claude/docs/deployment-mobile.md`.
- **React Native / Expo → GitHub Actions (fallback).** If the team is standardized on GHA, **one** `workflow_dispatch`-only `eas build` / `eas submit` workflow is allowed in addition to any backend deploy workflow. The compile runs on Expo's servers, so the Action only triggers it — near-zero Actions minutes.
- **Flutter →** a `flutter build ipa` / `flutter build appbundle` + fastlane workflow. This one DOES compile on the runner (macOS minutes for iOS — the expensive case), so it must be `workflow_dispatch` only, `timeout-minutes` set, and never on push/schedule.

Everything else stays forbidden: no push/PR-triggered build on every commit, no per-spec mobile workflows, no scheduled rebuilds, no matrix across OS versions. The same minimalism rule that protects the cluster budget protects the mobile build budget — store builds happen on demand, not on every push. Gate the build job behind `npx tsc --noEmit && npm test` (RN) or `flutter analyze && flutter test` (Flutter) so a broken build never reaches a store.

## How to apply

- Before creating ANY file under `.github/workflows/`: count what is already there. If the new file is not the deploy workflow, stop and ask the user with `AskUserQuestion` — name this rule and the budget incident.
- When touching an existing project that has workflow sprawl: do not delete anything silently. Report the inventory (file, trigger, estimated minutes) and let the user decide what dies.
- When the wizard or sync runs on a project: this rule ships with the config, so every future session knows the policy without being told.
