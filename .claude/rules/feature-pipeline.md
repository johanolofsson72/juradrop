# Feature pipeline rule (auto-trigger, end-to-end execution)

The speckit + Allium + TLA+ pipeline is **not optional** for non-trivial work. Long form (spec-kit version history, 1.0 changes, why each phase exists, enforcement internals): `.claude/docs/feature-pipeline-rationale.md`.

> **Platform-neutral — EVERY spec runs the full speckit pipeline, web or mobile (non-negotiable).** Native apps (React Native / Expo · Flutter) substitute Maestro/Patrol/`integration_test` flows + component/widget tests for "browser tests" (`.claude/rules/specs.md`, `.claude/docs/testing-mobile.md`); every phase and hook fires on mobile too (`pubspec.yaml` and `package.json` are language markers). Three `PreToolUse` guards block source edits (`.dart`, `.tsx`, `.cs`, …) until the artifacts exist — **`spec-register-guard`**, **`pipeline-state-guard`**, **`spec-interview-guard`** — with no mobile bypass.

## The contract (BLOCKING)

Every request that is **not** a trivial one-file fix goes through the pipeline. You need no permission to start it — the user authorized it by giving you the work.

```
/speckit-specify → SPEC INTERVIEW → /speckit-clarify → /allium:elicit → /speckit-plan → /speckit-tasks → /speckit-analyze → /speckit-implement
                   (15–25 Q, every   (auto-pick,       (full/light                                         (auto-applies
                    spec)             every track)      tracks only)                                        remediations)
→ /speckit-converge (loop back to implement until it appends nothing) → /simplify → browser tests (functional + destructive) → /tla
```

- **Spec interview** — mandatory on every spec, after specify, before clarify; `interview.md` ≥ 15 answers, base AUTO-answered (`.claude/rules/spec-interview.md`).
- **`/speckit-clarify`** — mandatory on every track right after the interview; auto-pick hook accepts recommended answers (falls back to `AskUserQuestion` only with no defensible recommendation). `specify → plan` directly is the canonical skip and is forbidden.
- **`/speckit-analyze`** — mandatory between tasks and implement; its hook auto-applies every remediation and auto-chains to implement. No stop in `tasks → analyze → apply → implement`.
- **`/speckit-converge`** — mandatory after implement (spec-kit 0.16+): appends unbuilt work to `tasks.md`; if it appends anything, implement it and converge again. Skip only on spec-only.
- **`/simplify`** — after converge stops appending, on the changed code, before tests (quality only; never substitutes for `/code-review` or tests). Skip on spec-only.

**Override (BLOCKING) — the spec-kit 1.0 checklist stop is not a permission gate.** `/speckit-implement` says *"STOP and ask: Some checklists have unchecked items. Do you want to proceed with implementation anyway? (yes/no)"*. **Do not ask it.** Read and judge the unchecked items; tick the satisfied ones; record real gaps in the spec and `<spec-dir>/run-log.md` and report them in the per-spec status summary. Never relay the prompt in any form, including as an `AskUserQuestion`. `scripts/speckit-extension-policy.sh` rewrites the STOP block (and the `_[Wait for user response]_` line in `speckit-specify/SKILL.md`) after every `specify init`; when upstream wording changes it warns instead, and this rule governs.

**Command names.** Use the hyphenated skills: `/speckit-specify`, `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze`, `/speckit-implement`, `/speckit-converge` (plus `/speckit-constitution` — once at project init via `/project-wizard` — and optional `/speckit-checklist`). `/allium:elicit` and `/tla` are this project's own skills. `/speckit-taskstoissues` is **not used**; the `speckit-git-*` skills are disabled by the extension policy. spec-kit is **pinned** in `scripts/speckit-version`; `bash scripts/speckit-sync.sh` brings the CLI and `.specify/` to it (`--check` to only look). Never install it from an untagged `git+…spec-kit.git`.

The whole chain is **one task** (`.claude/rules/continuous-execution.md`). Allium/TLA+ findings get per-finding decisions (`.claude/rules/validation-followup.md`).

## Triage — what to actually run

Classify after `/speckit-specify` per `specs.md`. Do not force full on everything (fabricated `.allium` files surface as false drift).

| Spec shape | Pipeline track |
|---|---|
| **Hardened** (full-track AND a risk threshold — auth/payments/PII/upload/new external surface, state machine/concurrency, new entity or ≥6 files, or tagged) | Full **plus** threat model, expanded destructive + stress, hard mutation gate, adversarial review (`.claude/rules/spec-hardening.md`). Row: `full track [hardened]`. |
| Behavior-changing (new feature, entity, state machine, concurrency, API surface) | **Full:** spec → clarify → `/allium:elicit` → impl → browser tests → `/tla` |
| UI feature, single actor, no concurrency (CRUD, search/filter, linear workflow) | **Light:** spec → clarify → `/allium:elicit` → impl → browser tests (skip `/tla` unless state machine non-trivial) |
| Non-behavior (refactor, doc, dependency bump, config, cosmetic, i18n, logging) | **Spec-only:** spec → clarify → impl. No `.allium`, no `/tla`. Browser tests if user-facing surface changes. |
| Fix / hardening / security with no new entities AND no new state transitions | **Spec-only.** Express the constraint as a test, not an Allium invariant. |

The interview and clarify run on **every** track. When the track is unclear, ask **once** with `AskUserQuestion`, then proceed. The every-5 integration checkpoint is a register row, not a track.

## When the pipeline is NOT required

Only: single-file typo/formatting/whitespace; renaming one local variable; single-line obvious bug fix with zero spec impact; comment-only doc changes inside one file; reverting one recent commit verbatim. Touching 2+ files, adding a function, modifying state, or changing user-visible behavior is **not trivial**. When skipping, say so in your first sentence ("This is a trivial typo fix — skipping the pipeline.").

## How this rule fires

1. **`UserPromptSubmit` reminders** — `scripts/feature-pipeline-detect.sh` + speckit-command hooks via `scripts/pipeline-trigger-match.sh` (non-blocking; test: `bash scripts/test-pipeline-hooks.sh`).
2. **This rule file** — the source of truth.
3. **`scripts/spec-interview-guard-hook.sh`** — hard block until `interview.md` has ≥ 15 answers.
4. **`scripts/pipeline-state-guard-hook.sh`** — hard block until the active spec (`- [/]` or first `- [ ]` row) has `spec.md` with `## Clarifications`, `spec.allium` (full/light), `plan.md`, `tasks.md`. Markdown, config, `.claude/**`, `scripts/**`, `specs/**` stay editable; silent on template/scratch repos; fails open.

## What this rule forbids

- Editing production code for a multi-file feature without `/speckit-specify` first.
- Skipping `/speckit-clarify`, the spec interview, `/allium:elicit` (full/light), or `/speckit-plan` + `/speckit-tasks`.
- AUTO interview: inventing answers to genuinely-ambiguous questions, or skipping overflow on a large/advanced spec.
- Happy-path-only browser tests — every implemented function, a destructive suite per interactive function sized to its input domain, unit + integration underneath; mutation kill rate proves it bites.
- Declaring "done" without `/tla` (or stating spec-only and why).
- Asking "should I start with /speckit-specify?" — just start.

## When to stop

Only for: (1) genuine ambiguity (`AskUserQuestion`); (2) a hard blocker outside your control; (3) Allium/TLA+ findings (`validation-followup.md`). Otherwise keep going — the pipeline is one task, not seven.
