# Project workflow rule (solo vs team, PR usage)

Before suggesting a pull request or any PR-based flow, know whether the project is **solo** or **team** and whether it **uses PRs**. If unknown, ask once and remember. Long form (memory template, reasoning): `.claude/docs/project-workflow-rationale.md`.

## The check (BLOCKING — before any PR-related suggestion)

Applies before: suggesting a PR, invoking or recommending `commit-commands:commit-push-pr`, ending with "want me to open a PR?", suggesting branch + PR, recommending review via PR.

1. Look in project memory (`.claude/projects/<project>/memory/`) for `project_workflow.md`. If it exists, follow it.
2. If not, ask **once** with `AskUserQuestion`, both questions in one batch:
   - **"How is this project staffed?"** — `Solo` / `Team` / `Mixed` (mostly solo, occasional contributors).
   - **"Should code changes go through pull requests?"** — `No — direct push` / `Yes — always` / `Sometimes` (ask per change).
3. Save immediately as memory `project_workflow.md` (frontmatter `name: Project workflow`, `type: project`, body `**Staffing:**` + `**PRs:**` + the "How to apply" block — exact template in the long-form doc) and add a one-line entry to `MEMORY.md`: `- [Project workflow](project_workflow.md) — staffing + PR policy for this project`.

## Acting on the saved answer

- `PRs=no` → **silent suppression**: never mention, offer or nudge toward PRs. Commit, then push directly; use `commit-commands:commit` + `git push`, never `commit-push-pr`. (Team + no PRs: still no PR suggestions; mention direct-push only if relevant.)
- `PRs=yes` → standard PR flow, regardless of staffing.
- `PRs=sometimes` → ask per PR-suitable change (do not re-ask the global setting).

Re-ask (and overwrite the memory) only when the user says staffing/workflow changed or tells you to forget/update it. Otherwise trust the memory.

## Scope boundary

This rule governs **PR ceremony only**. `PRs=no` / solo / direct-push does **not** authorize skipping any pipeline phase in `.claude/rules/feature-pipeline.md` (`/speckit-clarify`, `/allium:elicit`, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze`, `/tla`…), any non-PR hook (`before_specify`, `after_specify`, `pre-commit`, `post-commit` — read a hook's source if unsure why it fired), browser/unit/TLA+ validation, lint/format/type gates, or the spec register and its per-spec stop (`.claude/rules/spec-register.md`). Direct-push means "push without a PR after the spec is done", not "push without finishing the spec". Citing this rule to bypass non-PR enforcement is a rule violation.

## What this rule forbids

- Suggesting a PR without first checking the workflow memory.
- Re-asking the questions every session once answered.
- Any PR nudge when `PRs=no`.
- Asking the questions pre-emptively mid-task before a PR moment is actually load-bearing.
