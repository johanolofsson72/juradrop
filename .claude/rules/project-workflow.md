# Project workflow rule (solo vs team, PR usage)

Before suggesting a pull request, branch-based review flow, or any "open a PR for this" action, you MUST know whether the project is **solo** or **team**, and whether the project **uses PRs** at all. If you do not know, ask once and remember the answer.

## The check (BLOCKING — before any PR-related suggestion)

When you are about to do any of the following, first check whether the project workflow is known:

- Suggest opening a pull request
- Invoke the `commit-commands:commit-push-pr` skill (or recommend it)
- End a task with "want me to open a PR?"
- Suggest a branch + PR workflow for a change
- Recommend code review via PR

**Where to look:** check the project memory (`.claude/projects/<project>/memory/`) for an entry named `project_workflow.md` (or similar). If it exists, read it and follow what it says. Done.

**If it does not exist:** ask the user. Once. Then save the answer.

## How to ask

Use `AskUserQuestion` with these two questions in a single batch:

**Question 1 — "How is this project staffed?"**
- `Solo` — I am the only developer on this project
- `Team` — Multiple developers contribute to this project
- `Mixed` — Mostly solo but occasional contributors

**Question 2 — "Should code changes go through pull requests?"**
- `No — direct push` — Commit and push straight to the working branch, no PR
- `Yes — always` — Every change opens a PR for review (even solo, for self-review or audit trail)
- `Sometimes` — Ask me each time depending on the change

After the user answers, save the result as a project memory immediately. See "Saving the answer" below.

## Saving the answer

Write a project memory file `project_workflow.md` in the active project's memory directory with this content:

```markdown
---
name: Project workflow
description: Solo vs team staffing and PR usage for this project — drives whether PR suggestions and PR-based workflows are offered.
type: project
---

**Staffing:** {solo|team|mixed}
**PRs:** {no|yes|sometimes}

**How to apply:**
- If staffing=solo AND PRs=no → never suggest opening a PR. After commit, push directly to the working branch. Do not offer to open a PR. Do not invoke `commit-commands:commit-push-pr` — use `commit-commands:commit` plus a direct `git push`.
- If PRs=yes → offer PR-based flow as normal, regardless of staffing.
- If PRs=sometimes → for each PR-suitable change, briefly ask whether to use a PR for this one (do not re-ask the global setting).
- If staffing=team AND PRs=no → still do not suggest PRs, but mention that the team is using direct-push if it seems relevant to the user's question.
```

Then add a one-line entry to `MEMORY.md`:

```
- [Project workflow](project_workflow.md) — staffing + PR policy for this project
```

## Acting on the saved answer

Once the memory exists, every PR-related decision MUST consult it:

- `PRs=no` → **silent suppression**. Do not mention PRs. Do not offer to open one. Do not suggest "you might want to open a PR for review". The feature is off; act like PRs are not part of this project's workflow at all.
- `PRs=yes` → standard PR flow, suggestions allowed.
- `PRs=sometimes` → ask per-change.

## What this rule forbids

- Suggesting a PR without first checking the project workflow memory.
- Re-asking the staffing/PR questions on every session — once answered, the memory is authoritative until the user changes it.
- "Pestering" the user about PRs when `PRs=no` — even gentle nudges like "for visibility you could open a PR" are forbidden in solo/no-PR mode.
- Asking the questions in the middle of unrelated work. If the user is mid-task and you have not hit a real PR-suggestion moment, do not pre-emptively ask. Wait until the question is actually load-bearing.

## What this rule does NOT govern (scope boundary)

This rule is **narrow**. It governs PR ceremony — opening pull requests, branch-based review flows, the `commit-commands:commit-push-pr` skill, and PR-related suggestions. It does NOT govern anything else about the project's workflow.

In particular, a `PRs=no` / solo / direct-push setting does **not** authorize skipping:

- `/speckit-clarify`, `/allium:elicit`, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze`, `/tla`, or any other phase in `.claude/rules/feature-pipeline.md`. The pipeline is independent of PR ceremony.
- `before_specify`, `after_specify`, `pre-commit`, `post-commit`, or any other hook that is not specifically a PR-creation hook. If a hook fires and you don't understand why, read its source — do not wave it away with "solo direct-push".
- Browser tests (Playwright), unit tests, TLA+ verification, or any other validation step required by `CLAUDE.md`.
- Linting, formatting, type-checking, or any other automated quality gate that runs on commit.
- The spec register (`specs/INDEX.md`) and the per-spec stop pattern in `.claude/rules/spec-register.md`. Direct-push means "push without opening a PR after the spec is done" — not "push without finishing the spec".

If you find yourself reasoning "the project is solo direct-push, so I can skip X", and X is not literally a PR or PR-related artifact, the reasoning is wrong. Re-examine why the hook or phase exists and address it on its own terms. Citing this rule to bypass non-PR enforcement is a documented anti-pattern and a rule violation.

## When to re-ask

You may re-ask (and overwrite the memory) only when:

- The user explicitly says the project's staffing or workflow has changed ("we have a new dev joining", "we are going to start using PRs").
- The user explicitly tells you to forget or update the workflow setting.

Otherwise: the saved answer stands. Do not re-confirm. Do not double-check. Trust the memory.

## Why this rule exists

PR suggestions are noise on solo projects. There is no reviewer, no second pair of eyes, no compliance need — just an extra ceremony that wastes time and trains the user to dismiss prompts. By asking once and remembering, Claude adapts to the actual workflow instead of defaulting to an enterprise-team assumption that fits maybe 30% of the projects this template is dropped into.
