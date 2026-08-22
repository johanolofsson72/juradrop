# Feature pipeline rule (auto-trigger, end-to-end execution)

The speckit + Allium + TLA+ pipeline is **not optional** for non-trivial work. Skipping it is the single biggest quality regression in this project — it loses functional inventory, drift detection, formal invariants, and destructive test coverage all at once. This rule closes that hole.

> **Platform-neutral — EVERY spec runs the full speckit pipeline, web or mobile (non-negotiable).** This pipeline is identical for web/.NET (client-server) and native mobile (React Native / Expo · Flutter). Where this rule and its diagram say "browser tests", a native app substitutes Maestro/Patrol/`integration_test` flows + component/widget tests — see `.claude/rules/specs.md` and `.claude/docs/testing-mobile.md`. Every phase (specify → clarify → allium:elicit → plan → tasks → analyze → implement → tests → tla) and every enforcement hook fires on mobile too: `pubspec.yaml` is a recognized language marker (alongside `package.json` for RN), and the test hooks match `npm test`/`maestro`/`flutter test`/`patrol`.
>
> The "always via speckit" guarantee is deterministic, not advisory — three `PreToolUse` guards block source edits (`.dart`, `.tsx`, …) until the artifacts exist: **`spec-register-guard`** denies the edit until `specs/INDEX.md` and a spec row exist, **`pipeline-state-guard`** denies it until that spec has `spec.md` (with a `## Clarifications` section), `spec.allium` (full/light), `plan.md`, and `tasks.md`, and **`spec-interview-guard`** denies it until that spec's `interview.md` records ≥15 answered questions (the anti-drift interview — base auto-answered by default, human on flag; `.claude/rules/spec-interview.md`). There is no bypass for mobile — a Flutter `lib/` edit is blocked exactly like a `.cs` edit. Mobile gets the same teeth as client-server.

## The contract (BLOCKING)

Every developer request that is **not** a trivial one-file fix MUST go through the pipeline. You do not need the user's permission to start it — the user authorized it by giving you the work. Starting the pipeline is the default, not the exception.

```
/speckit-specify  →  SPEC INTERVIEW  →  /speckit-clarify  →  /allium:elicit  →  /speckit-plan  →  /speckit-tasks  →  /speckit-analyze  →  /speckit-implement
                (15–25 Q, base       (auto-pick     (full/light                              (auto-applies         │
                 AUTO-answered w/     recommended,   tracks only)                             all suggested         │
                 recommended;         residual                                                remediations)         ▼
                 human overflow if                                                              /speckit-converge
                 flagged; every spec)  only)                                          (unbuilt work → tasks.md; loop
                                                                                       back to implement if any)
                                                                                             │
                                                                                             ▼
                                                                                            /simplify
                                                                                  (quality-only pass on the
                                                                                   changed code; no bug hunt)
                                                                                             │
                                                                                             ▼
                                                                                    browser tests (functional + destructive)
                                                                                             │
                                                                                             ▼
                                                                                    /tla (distill + drift + invariants)
```

**`/speckit-converge` is mandatory after `/speckit-implement`** (spec-kit 0.16+). It assesses the codebase against the spec, plan and tasks, and appends any remaining unbuilt work to `tasks.md`. If it appends anything, go back and implement it — then converge again, until it appends nothing. This is the phase that catches "the spec described twelve behaviours and nine got built", which is the same failure the functional-coverage inventory exists to prevent, caught one stage earlier and mechanically rather than by eye. It complements `/allium:distill` (semantic drift between spec and code) by working at task granularity. Skip only on the spec-only track.

**After converge stops appending, run `/simplify` on the changed code.** It is a built-in, quality-only pass — reuse,
simplification, efficiency, altitude — and it does not hunt for bugs, so it never substitutes for `/code-review` or the test
matrix. It exists in this chain because "Simplicity — minimum necessary complexity" is priority 3 in `CLAUDE.md` and nothing else
in the pipeline enforces it: converge proves the work is *complete*, the tests prove it is *correct*, and neither notices that a
behaviour got built three times in three shapes. Run it before the test phase, so the tests are written against the code that will
actually ship rather than against a draft you are about to restructure. Skip on the spec-only track.

> **Extension policy (BLOCKING).** spec-kit 0.16.x ships extensions that `specify init --here --force` enables by default. The **`git` extension is disabled in these projects** — its five skills (`speckit-git-feature`, `-git-validate`, `-git-commit`, `-git-remote`, `-git-initialize`) create numbered feature branches, enforce branch naming, and auto-commit after every phase, all of which contradict `.claude/rules/spec-register.md` (one spec → one commit → direct push, no branches, no merge step). `specify init --force` re-enables them on every run, so `scripts/speckit-extension-policy.sh` runs after every init in both `/project-wizard` and `/project-update` to switch it back off. `agent-context` stays enabled. Do not invoke the `speckit-git-*` skills; if you find them enabled, run the policy script.
>
> **Command names (spec-kit v0.10.0+ — 0.16.2 as of August 2026 — with `--integration claude`).** The hyphenated skill names below have been stable since the v0.10 line; v0.11–v0.14 normalized hyphenation across integrations, moved Claude Code files from `.claude/commands/` to `.claude/skills/`, and added a `py` script type (v0.14.0) alongside `sh`/`ps`. The install commands in `/project-wizard` and `/project-update` pull from `git+…/spec-kit.git` (i.e. whatever `main` is that day) — pin a tag (`uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.14.2`) when two developers need identical phases.
>
> **Skill names.** `specify init` installs these phases as **skills** with hyphenated names: `/speckit-specify`, `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze`, `/speckit-implement` (plus `/speckit-constitution` and `/speckit-checklist`). Earlier spec-kit used bare `/specify` etc. — those no longer match the installed skills, so always use the `/speckit-` prefix. `/allium:elicit` and `/tla` are this project's OWN skills (not spec-kit) and keep their names.
>
> **Other phases 0.16.2 installs, and what we do with them:** `/speckit-converge` is **in** the chain (above). `/speckit-agent-context-update` refreshes the managed Spec Kit section of the agent context file — harmless, run it when that section goes stale. `/speckit-taskstoissues` converts tasks into GitHub issues and is **not used**: these are solo, direct-push projects with no issue workflow (`.claude/rules/project-workflow.md`), and it adds GitHub surface for nothing. The five `speckit-git-*` skills are disabled per the extension policy above.
>
> **Two spec-kit phases sit outside the per-spec blocking chain above:**
> - **`/speckit-constitution`** — establishes the project's principles. Runs **once at project init** (the `/project-wizard` skill generates the constitution), not per spec. Re-run only when amending principles.
> - **`/speckit-checklist`** — generates a requirements quality-checklist for a spec, after `/speckit-clarify`. **Optional** here: this project already enforces a stronger destructive-test checklist (`spec-testing-checklist.md`) plus Allium invariants, so `/speckit-checklist` is available as an extra gate but not mandatory. Use it on a large/ambiguous spec where a requirements sanity pass adds value.

The **spec interview** is **mandatory** immediately after `/speckit-specify`, on **every** spec regardless of track, and runs **before** `/speckit-clarify`. It is a 15–25 question anti-drift interview recorded in `<spec-dir>/interview.md`, and the `spec-interview-guard` PreToolUse hook hard-blocks source-code edits until it records ≥15 answered questions. **By default (AUTO mode) Claude auto-answers the base** with the recommended option for each (tagged `**A (auto):**`), escalating only genuinely-ambiguous questions to the developer via `AskUserQuestion`, and — when it judges the spec **large/advanced** (the hardened triggers are the strong prior) — asking the developer the **overflow** questions the complexity demands. The developer can override per spec (`[interview:manual]` / `[interview:auto]`), and a project can force fully-human answering with `SPEC_INTERVIEW_MODE=manual`. See `.claude/rules/spec-interview.md`. The interview's answers then feed clarify, plan, tasks, and the Allium elicitation — it is part of the same uninterrupted task, with no "ready to implement?" stop after it.

`/speckit-clarify` is **mandatory** immediately after `/speckit-specify` on every track. The auto-pick hook in `.claude/settings.json` accepts the recommended answer for every clarification question without prompting (and only falls back to `AskUserQuestion` for the rare question with no defensible recommendation). It is the canonical speckit phase that catches under-specified requirements before `/speckit-plan` and `/speckit-tasks` lock them in — running `/speckit-specify → /speckit-plan` directly is the single most common pipeline-skip failure mode and it is forbidden.

`/speckit-analyze` is **mandatory** between `/speckit-tasks` and `/speckit-implement`. The hook in `.claude/settings.json` auto-applies every remediation from the analysis report and auto-chains to `/speckit-implement` without prompting. There is no stop between `/speckit-tasks` → `/speckit-analyze` → auto-apply → `/speckit-implement` — the whole sub-chain is one continuous segment of the larger pipeline.

The whole chain is **one task**. Per `continuous-execution.md` you do not stop between phases. Per `validation-followup.md` Allium and TLA+ findings get explicit per-finding decisions — those are the only legitimate stops other than genuine ambiguity or hard blockers.

## Triage — what to actually run

After `/speckit-specify` produces the spec, classify it per `specs.md` and pick the matching track. Do **not** force the full pipeline on everything — over-application produces fabricated `.allium` files that surface as false drift in `/tla`.

| Spec shape | Pipeline track |
|---|---|
| **Hardened** (full-track AND crosses a risk threshold — auth/payments/PII/upload/new external surface, full-track state machine/concurrency, new entity or ≥6 files, or explicitly tagged) | **Hardened:** the full track **plus** the four hardening additions — threat-model pass, expanded destructive + stress, hard mutation-kill gate, adversarial review. See `.claude/rules/spec-hardening.md`. |
| Behavior-changing (new feature, new entity, new state machine, new concurrency, new API surface) | **Full:** spec → `/speckit-clarify` → `/allium:elicit` → impl → browser tests → `/tla` |
| UI feature, single actor, no concurrency (CRUD form, search/filter, simple linear workflow) | **Light:** spec → `/speckit-clarify` → `/allium:elicit` → impl → browser tests (skip `/tla` unless state machine non-trivial) |
| Non-behavior (refactor, doc, dependency bump, config tweak, cosmetic, i18n, logging) | **Spec-only:** spec → `/speckit-clarify` → impl. No `.allium`, no `/tla`. Browser tests still apply if user-facing surface changes. |
| Fix / hardening / security with no new entities AND no new state transitions | **Spec-only.** spec → `/speckit-clarify` → impl. Express the constraint as a test, not as an Allium invariant. |

The **spec interview** (15–25 questions → `interview.md`, base AUTO-answered with recommended, human overflow when flagged) and `/speckit-clarify` (auto-pick) both run on **every** track — not just full/light; the interview is the deliberate pass over the spec, clarify mops up residual trivia. `/allium:elicit` is the step that varies by track. **Hardened is full + a surcharge, not a separate path** — a hardened spec runs the entire full pipeline and adds the four checks; mark its register row `full track [hardened]`.

When the track is unclear, ask **once** with `AskUserQuestion` and then proceed. Do not default to "full" out of caution. (The cross-spec **integration-hardening checkpoint** — every 5 completed specs — is a register row, not a per-spec track; see `.claude/rules/spec-hardening.md`.)

## When the pipeline is NOT required

Only these qualify as "trivial" and may skip the pipeline:

- Single-file typo, formatting fix, or whitespace change
- Renaming a single local variable
- Single-line bug fix where the wrong-value is obvious and the spec impact is zero
- Doc-only changes to comments inside one file (CLAUDE.md, README, etc. still count as doc work but typically spec-only track, not "trivial")
- Reverting a single recent commit verbatim

If you find yourself thinking "this is small enough to skip the pipeline" but the change touches 2+ files, introduces a new function, modifies state, or changes user-visible behavior — **it is not trivial**. Run the pipeline (spec-only track is fine if no new behavior).

When you skip the pipeline because the work is trivial, state that classification explicitly in your first sentence ("This is a trivial typo fix — skipping the pipeline."). That sentence is the audit trail for why the pipeline did not run.

## How this rule fires

Four enforcement layers — the first two are a reminder hook and this rule (the source of truth); the last two are the hard `PreToolUse` blocks (interview-guard and state-guard, alongside the spec-register guard described in `.claude/rules/spec-register.md`):

1. **`UserPromptSubmit` reminder hooks** (`scripts/feature-pipeline-detect.sh` + the three speckit-command hooks wired through `scripts/pipeline-trigger-match.sh`) — when your prompt contains feature-build trigger words or a clean invocation of a speckit command (`/speckit-specify`, `/speckit-clarify`, `/speckit-analyze`, etc.), the hook injects a pipeline reminder into the conversation. The reminder is non-blocking. The trigger matcher anchors to line-start and strips quoted regions (markdown code blocks, blockquotes, table cells, Claude transcript bullets, pipeline-flow diagrams) so pasted transcripts that *mention* a command do not fire the hook. Test harness: `bash scripts/test-pipeline-hooks.sh`.

2. **This rule file** — auto-loaded each session via `.claude/rules/`. The rule is the source of truth; the reminder hooks are deterministic re-injection so the rule cannot be silently forgotten across long sessions.

3. **`PreToolUse` interview-guard hook** (`scripts/spec-interview-guard-hook.sh`) — a second **hard block**, sibling to the state-guard. On every `Edit`/`Write`/`MultiEdit` against a source-code file it walks to the project root, finds the active spec in `specs/INDEX.md`, and counts answered questions in that spec's `interview.md`. Fewer than 15 → `permissionDecision: deny` with instructions to run the interview. In the default AUTO mode it counts both auto (`**A (auto):**`) and human (`**A:**`) answers; with `SPEC_INTERVIEW_MODE=manual` it counts only human answers. Same scope rules as the state-guard (source extensions only; markdown/config/`.claude/**`/`scripts/**`/`specs/**` pass through; silent on template/scratch repos; fails open). See `.claude/rules/spec-interview.md`.

4. **`PreToolUse` state-guard hook** (`scripts/pipeline-state-guard-hook.sh`) — this is the **hard block**. On every `Edit` / `Write` / `MultiEdit` against a source-code file, the hook walks up to the project root, reads `specs/INDEX.md` to find the active spec (`- [/]` row or first `- [ ]` row), parses the track from the row, and verifies that the required artifacts exist in the spec directory (`spec.md` with a `## Clarifications` section, `spec.allium` on full/light tracks, `plan.md`, `tasks.md`). If any required phase is missing, the hook returns `permissionDecision: deny` with a phase-by-phase deny reason. The block scope is strictly source-code extensions — markdown, config, `.claude/**`, `scripts/**`, and `specs/**` edits remain allowed so the pipeline can produce its artifacts. The hook is silent on template/scratch repos (no language marker at the `.git` root) and fails open on internal errors.

## What this rule forbids

- Jumping straight to `Edit`/`Write` on production code for a multi-file feature without `/speckit-specify` first.
- Skipping `/speckit-clarify` after `/speckit-specify`. The auto-pick hook makes it zero-cost when the spec has no real gaps; running `/speckit-specify → /speckit-plan` directly is the canonical pipeline-skip failure mode this rule exists to prevent.
- Skipping the **spec interview** entirely. Every spec carries a 15–25 question interview in `interview.md` before source code is touched, and the `spec-interview-guard` hook blocks source edits until it is done. In AUTO mode Claude auto-answers the base with recommended options but MUST still (a) escalate genuinely-ambiguous, spec-affecting questions to the developer rather than inventing a "recommended" answer, and (b) ask the developer the overflow questions when it judges the spec large/advanced — silently auto-answering a risky spec is exactly the drift this gate exists to stop. See `.claude/rules/spec-interview.md`.
- Writing a spec without then running `/allium:elicit` on the full/light track.
- Implementing without `/speckit-plan` and `/speckit-tasks` derived from the spec (so the functional inventory is explicit before code is written).
- Writing browser tests that cover only "the happy path" — functional coverage means **every implemented function**, plus a **destructive suite per interactive UI function, sized to its input domain** (not a flat quota, not one batch per spec) across the relevant attack categories, plus **unit + integration tests** underneath. The **mutation kill rate** (Stryker, nightly/on-demand) is what proves the suite actually bites.
- Declaring "done" without running `/tla` (or stating spec-only track and why).
- Asking "should I start with /speckit-specify?" — the answer is yes for any non-trivial work; just start.

## When to stop (the only legitimate cases)

You may stop and ask during pipeline execution **only** when:

1. **Genuine ambiguity** the spec/triage cannot resolve — use `AskUserQuestion`, not free-text questions.
2. **Hard blocker** outside your control — missing credentials, missing infra, conflicting requirements that need arbitration.
3. **Allium or TLA+ findings** — these have their own per-finding decision protocol in `validation-followup.md`.

Otherwise: keep going. The pipeline is one task, not seven.

## Why this rule exists

Without it, Claude tends to short-circuit the pipeline on prompts that "feel small" or arrive without an explicit `/speckit-specify` invocation. The result is: no functional inventory (so tests cover 3 of 12 functions), no Allium baseline (so drift cannot be detected), no TLA+ invariants (so race conditions are not caught), and no destructive tests (so the feature ships brittle). Every one of those failure modes has bitten this project before. The pipeline is the deterministic fix.
