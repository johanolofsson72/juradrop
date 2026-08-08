# Spec interview rule (per-spec anti-drift interview — auto by default, human on flag, hard-gated)

The project-level interview at the start of a project (the `/project-wizard` inception interview, which produces the register, constitution, and scenario map) decides **what** the project is. It does NOT decide the details of any individual spec. Those details — scope boundaries, data shape, edge cases, error/empty/loading states, authorization, integration points, non-goals — are exactly where an AI implementation drifts from what the developer actually wanted.

`/speckit-clarify` is supposed to catch this, but in this project it runs in **auto-pick mode** (`scripts/emit-clarify-reminder.sh`): it answers its own clarification questions silently with the recommended option. The per-spec interview is the deliberate, recorded pass over the spec that pins those details down and leaves an audit trail — so every spec carries a 15–25 question interview before any source code is written.

## Two modes — AUTO by default, MANUAL on opt-in

The interview runs in one of two modes. **AUTO is the shipped default** for every project.

- **AUTO (default).** Claude **auto-answers** the base 15–25 questions with the **recommended** option for each — the developer has standing instructions that they always accept the recommended answer, so making them click through 15–25 `AskUserQuestion` turns per spec is pure friction. Claude records the auto answers in `interview.md` (tagged `**A (auto):**`) and keeps moving. Two things keep AUTO honest rather than blind:
  1. **Escalate the genuinely-ambiguous ones.** If a base question has no defensible recommended answer (all options genuinely equivalent, or all conflict with the spec, or the choice materially changes behaviour and Claude cannot pick with confidence), that ONE question is escalated to the developer via `AskUserQuestion` (auto-pick OFF) and recorded as a human `**A:**`. This mirrors the `/speckit-clarify` fallback — it should be the exception, not the rule.
  2. **Human overflow on large/advanced specs.** When Claude judges the spec **large or advanced**, it goes *beyond* the base 15–25 and asks the developer the **overflow** questions the complexity demands (see "The flag" below). The base stays auto; the overflow is human-answered.
- **MANUAL (opt-in).** A project that wants the old fully-human behaviour sets `SPEC_INTERVIEW_MODE=manual` (in `.claude/settings.json` `env`, or `CLAUDE.local.md`). In MANUAL mode every question is human-answered via `AskUserQuestion` (auto-pick OFF), one per turn, and the guard hook counts **only** human `**A:**` answers — so auto answers do not unlock code. This is the escape hatch for a developer (e.g. a teammate) who wants to engage with every spec by hand.

Both modes still produce a complete `interview.md` and both are hard-gated at 15 answered questions (§ "Hard-gated" below). The difference is purely *who answers*.

## The flag — when Claude asks the human (AUTO mode)

Under AUTO mode, Claude does not silently auto-answer everything regardless of stakes. It **judges each spec** and, when the spec is large or advanced, flags it and asks the developer the overflow questions. Claude's judgment is the mechanism; the **hardened triggers are the strong prior** — treat a spec that crosses any of them as large/advanced by default:

- authentication / authorization, payments / money movement, PII or secrets, file upload / parsing, or a **new external API surface**;
- a full-track spec with a **state machine or concurrency**;
- a **new entity/aggregate** OR an estimated **≥ 6 files** touched;
- an explicit **`[hardened]`** tag on the spec's register row (`.claude/rules/spec-hardening.md`).

A spec crossing one of these should almost always get overflow questions. Claude may **also** flag a spec by judgment even when no hardened trigger fires (an unusually subtle CRUD flow, a surprising data model), and it may decline to flag a borderline one — that discretion is the point of "Claude judges + flags". Bias toward asking when unsure: the cost of an unnecessary overflow question is one `AskUserQuestion`; the cost of a silently-wrong auto-answer on a risky spec is a breach.

The overflow questions are the ones the base 15 categories don't cover for *this* spec — the deeper threat-surface, data-integrity, and edge-case questions a large/advanced feature raises. On a hardened spec make the threat-surface questions (authz, input tampering, information disclosure, resource exhaustion) explicitly part of the overflow set — the interview is the human-side complement to the automated threat-model pass.

## Override (both directions)

The developer can override Claude's judgment either way, per spec:

- **Force full manual for one spec** — the developer says so, or tags the register row `[interview:manual]`. Claude then human-answers the whole interview for that spec (`AskUserQuestion`, auto-pick OFF), even though the project is in AUTO mode.
- **Force auto-only for one spec** — the developer says so, or tags the register row `[interview:auto]`. Claude auto-answers the base and does **not** ask overflow questions, even if a hardened trigger fired. (Note: in a MANUAL-mode project this override does nothing — the project chose manual, and the guard counts only human answers.)

An override is a developer decision; Claude proposes the flag, the developer disposes. When Claude flags a spec and the developer waves it through, record that as `[interview:auto]` behaviour for that spec.

## Hard-gated

`scripts/spec-interview-guard-hook.sh` (PreToolUse) denies every source-code edit for the active spec until `interview.md` records **at least 15 answered questions**. The block is real — it cannot be silently skipped, exactly like `pipeline-state-guard`. The count depends on the mode:

- **AUTO mode** — counts human `**A:**` + auto `**A (auto):**` answers. So a base of 15 auto answers unlocks code; the escalated + overflow human answers add on top.
- **MANUAL mode** — counts only human `**A:**` answers. Auto answers do not unlock code.

15 is the floor; 25 is guidance, not a hard ceiling. The hook never blocks for "too many". Override the floor with `SPEC_INTERVIEW_MIN` (default 15).

## Where it sits in the pipeline

The interview runs **right after `/speckit-specify`, before `/speckit-clarify`** — so its answers shape clarify, plan, tasks, and the Allium elicitation rather than being bolted on after the design is already set:

```
/speckit-specify → SPEC INTERVIEW (base 15–25 auto-answered; human overflow if flagged) → /speckit-clarify (auto-pick residual)
                                                    → /allium:elicit → /speckit-plan → /speckit-tasks
                                                    → /speckit-analyze → /speckit-implement
```

It is part of the **same task** as the rest of the pipeline (`.claude/rules/continuous-execution.md`) — do NOT stop after the interview to ask "ready to implement?". Conduct it (auto-answer the base, ask any overflow), record the answers, keep going. The interview's findings (an escalated question the developer answered surprisingly, a contradiction, a scope change) are surfaced like any other finding per `.claude/rules/validation-followup.md`; they do not become a silent permission stop.

## What the 15–25 questions cover

Pull questions from the categories below until you have 15–25 genuinely useful ones for *this* spec. Skip a category only when it is truly N/A for the spec's scope (and note why). Quality over filler — 15 sharp questions beat 25 padded ones, but 15 is the floor. In AUTO mode Claude answers each with the recommended option (escalating the genuinely-ambiguous ones); in MANUAL mode the developer answers each.

1. **Scope boundary** — what is explicitly IN this spec, and what is explicitly OUT (deferred to a later spec)?
2. **Primary actor & trigger** — who initiates this, from where, and what state are they in?
3. **Happy-path outcome** — concretely, what does success look like to the user?
4. **Data model** — what entities/fields are created, read, updated, deleted? Types, required vs optional, defaults?
5. **Validation rules** — what input is rejected, and what is the exact rule (length, format, range, uniqueness)?
6. **The four observable states** — what does the user see on success / on a specific error (never silent) / when empty / while loading?
7. **Error semantics** — which failures are recoverable vs fatal? What does each error message say, and is it actionable?
8. **Authorization** — who is allowed to do this? What happens to an unauthorized or unauthenticated actor?
9. **Concurrency / ordering** — what if two actors do this at once? Is order significant? Idempotency?
10. **Integration points** — what other features, services, or external APIs does this touch? What is the contract?
11. **Edge cases** — empty input, maximum input, duplicate, stale data, partial failure, the user backing out mid-flow.
12. **Non-functional limits** — expected volume, payload size, latency budget, pagination, rate limits.
13. **Acceptance criteria** — what is the measurable, testable definition of done for this spec? (Drives the destructive suite.)
14. **Non-goals & assumptions** — what are we deliberately NOT doing, and what are we assuming is already true?
15. **Reversibility** — can this be undone? What is the migration / rollback story if it ships wrong?

For a **flagged** (large/advanced) spec, the overflow questions go past this base list into the spec-specific threat-surface and data-integrity depth the feature demands — and those overflow questions are the ones the developer answers even in AUTO mode.

## The artifact format (`interview.md`)

The guard counts answered questions by looking for `**A:**` (human) and `**A (auto):**` (auto) lines with a non-empty answer. Use this exact shape so the count is reliable, and record the mode in a header so the file is self-documenting:

```markdown
# Spec interview — 003-search

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).

## Q1 — Scope boundary
**Q:** Does this spec include faceted filtering, or only free-text search?
**A (auto):** Free-text only; facets deferred to a later spec — matches the register goal and avoids scope creep.

## Q2 — Empty state
**Q:** What does the user see when a query returns zero results?
**A (auto):** A "No results for '<query>'" message plus the three most-popular items as a fallback — standard empty-state pattern.

## Q7 — Authorization  (escalated — no defensible default)
**Q:** Can an unauthenticated visitor search, or is search behind login?
**A:** Behind login. Anonymous search is a separate later spec.

...
```

- **AUTO mode**: base answers are `**A (auto):**`; escalated and overflow answers are `**A:**`. Aim for 15–25 base blocks plus any overflow.
- **MANUAL mode**: every answer is `**A:**`; the header reads `Mode: MANUAL`.

The hook unblocks source edits at the 15th counted answer; the 15–25 band is guidance, not a ceiling.

## How this interacts with the other rules

- `feature-pipeline.md` — the interview is a phase of the per-spec pipeline; its enforcement layer is listed alongside `spec-register-guard` and `pipeline-state-guard`.
- `spec-register.md` — the interview happens per spec row; its status feeds the per-spec status summary (the `Pipeline:` line cites `interview: N answers (auto/human)`). The `[interview:manual]` / `[interview:auto]` per-spec override tags live on the register row.
- `spec-hardening.md` — the hardened triggers are the strong prior for flagging a spec for human overflow questions.
- `continuous-execution.md` — the interview is part of the same uninterrupted task; finishing it does not create a permission stop.
- `validation-followup.md` — a surprising or contradictory answer (from an escalated or overflow question) is a finding, surfaced for an explicit decision, not buried.
- `emit-clarify-reminder.sh` / `/speckit-clarify` — keeps auto-picking; it mops up residual trivia after the interview.

## What this rule forbids

- Editing source code for a spec whose `interview.md` has fewer than 15 counted answers. (The hook blocks it; do not route around it by classifying real work as "trivial".)
- **AUTO mode**: auto-answering a genuinely-ambiguous, spec-affecting question with a made-up "recommended" answer instead of escalating it to the developer. If you cannot pick with confidence, ask — that is the anti-drift safety valve.
- **AUTO mode**: silently auto-answering a large/advanced spec (a hardened trigger fired) without asking the overflow questions, unless the developer explicitly overrode to `[interview:auto]`. Failing to flag a risky spec is the exact failure this rule guards against.
- **MANUAL mode**: recording auto `**A (auto):**` answers and expecting them to unlock code — in manual mode they don't count. Answer by hand.
- Dumping all questions in one message when asking the developer (MANUAL mode, escalations, or overflow). One question per turn (the wizard pattern); the only exception is 2–3 tightly-related trivial sub-questions grouped into a single `AskUserQuestion`.
- Stopping after the interview to ask "ready to implement?" — that is a `continuous-execution.md` violation. Record the answers and continue the pipeline.
- Treating the project-level wizard interview as a substitute. That interview scopes the project; this one scopes the spec. Both are required.
