# Spec interview rule (per-spec anti-drift interview, 15–25 questions, hard-gated)

The project-level interview at the start of a project (the `/project-wizard` inception interview, which produces the register, constitution, and scenario map) decides **what** the project is. It does NOT decide the details of any individual spec. Those details — scope boundaries, data shape, edge cases, error/empty/loading states, authorization, integration points, non-goals — are exactly where an AI implementation drifts from what the developer actually wanted.

`/speckit-clarify` is supposed to catch this, but in this project it runs in **auto-pick mode** (`scripts/emit-clarify-reminder.sh`): it answers its own clarification questions silently with the recommended option. That is the right call for trivial mechanical gaps, but it means a spec can travel all the way to implementation without a human ever engaging with it. A spec nobody answered is a spec that drifts.

This rule closes that hole: **every spec gets a human-answered interview of 15–25 questions before any source code is written.**

## The contract (BLOCKING)

When a project has a spec register (`specs/INDEX.md`), before source code is touched for a spec, the spec MUST carry a completed interview:

1. **Every spec, no exceptions.** Full, light, hardened, spec-only — all of them. The interview is sized to the spec (a one-line config tweak's 15 questions are smaller and faster than a payments flow's 25), but the floor of 15 answered questions is the same for every track. There is no "this one is too small" escape. (A genuinely trivial one-file fix that legitimately bypasses the whole pipeline per `.claude/rules/feature-pipeline.md` also bypasses this — but the moment a spec row exists in the register, the interview is mandatory for it.)
2. **15–25 questions, human-answered.** Conduct the interview with `AskUserQuestion` — **one focused question per turn** (the wizard pattern), NOT a dumped survey. **Auto-pick is OFF for the interview** — the whole point is that a human answers. The `/speckit-clarify` auto-pick stays in force only for residual trivial questions the interview did not already settle.
3. **Recorded in `<spec-dir>/interview.md`.** Every question and its answer is written to the interview file in the spec directory (`specs/<id>-<slug>/interview.md` or `.specify/specs/<id>-<slug>/interview.md`). This is the artifact the hook counts and the audit trail for why the spec is built the way it is.
4. **Hard-gated.** `scripts/spec-interview-guard-hook.sh` (PreToolUse) denies every source-code edit for the active spec until `interview.md` records **at least 15 answered questions**. The block is real — it cannot be silently skipped, exactly like `pipeline-state-guard`.

## Where it sits in the pipeline

The interview runs **right after `/speckit-specify`, before `/speckit-clarify`** — so the human's answers shape clarify, plan, tasks, and the Allium elicitation rather than being bolted on after the design is already set:

```
/speckit-specify → SPEC INTERVIEW (15–25 Q, human) → /speckit-clarify (auto-pick residual)
                                                    → /allium:elicit → /speckit-plan → /speckit-tasks
                                                    → /speckit-analyze → /speckit-implement
```

It is part of the **same task** as the rest of the pipeline (`.claude/rules/continuous-execution.md`) — do NOT stop after the interview to ask "ready to implement?". Conduct it, record the answers, keep going. The interview's findings (a surprising answer, a contradiction, a scope change) are surfaced like any other finding per `.claude/rules/validation-followup.md`; they do not become a silent permission stop.

## What the 15–25 questions cover

Pull questions from the categories below until you have 15–25 genuinely useful ones for *this* spec. Skip a category only when it is truly N/A for the spec's scope (and note why). Quality over filler — 15 sharp questions beat 25 padded ones, but 15 is the floor.

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

For a **hardened** spec (`.claude/rules/spec-hardening.md`), bias toward the top of the band (closer to 25) and make sure the threat-surface questions (authz, input tampering, information disclosure, resource exhaustion) are explicitly among them — the interview is the human-side complement to the automated threat-model pass.

## The artifact format (`interview.md`)

The guard counts answered questions by looking for lines that begin with `**A:**` and have a non-empty answer. Use this exact shape so the count is reliable:

```markdown
# Spec interview — 003-search

Anti-drift interview per .claude/rules/spec-interview.md.
15–25 questions, human-answered (no auto-pick). One question per turn via AskUserQuestion.

## Q1 — Scope boundary
**Q:** Does this spec include faceted filtering, or only free-text search?
**A:** Free-text only. Facets are deferred to spec 007.

## Q2 — Empty state
**Q:** What does the user see when a query returns zero results?
**A:** A "No results for '<query>'" message plus the three most-popular items as a fallback.

...
```

Aim for 15–25 `## Qn` blocks, each with a non-empty `**A:**`. The hook unblocks source edits at the 15th answered question; the 15–25 band is the guidance, not a ceiling the hook enforces.

## How this interacts with the other rules

- `feature-pipeline.md` — the interview is a phase of the per-spec pipeline; its enforcement layer is listed alongside `spec-register-guard` and `pipeline-state-guard`.
- `spec-register.md` — the interview happens per spec row; its status feeds the per-spec status summary (the `Pipeline:` line cites `interview: N answers`).
- `continuous-execution.md` — the interview is part of the same uninterrupted task; finishing it does not create a permission stop.
- `validation-followup.md` — a surprising or contradictory answer is a finding, surfaced for an explicit decision, not buried.
- `emit-clarify-reminder.sh` / `/speckit-clarify` — keeps auto-picking, but now only mops up residual trivia; the substantive clarification is the human-answered interview.

## What this rule forbids

- Editing source code for a spec whose `interview.md` has fewer than 15 answered questions. (The hook blocks it; do not route around it by classifying real work as "trivial".)
- Auto-picking the interview answers, or generating `interview.md` from the model's own assumptions without asking the user. An interview the user did not answer is not an interview — it is the drift this rule exists to prevent, dressed up as compliance.
- Dumping all 15–25 questions in one message. One question per turn (the wizard pattern); the only exception is 2–3 tightly-related trivial sub-questions grouped into a single `AskUserQuestion`.
- Stopping after the interview to ask "ready to implement?" — that is a `continuous-execution.md` violation. Record the answers and continue the pipeline.
- Treating the project-level wizard interview as a substitute. That interview scopes the project; this one scopes the spec. Both are required.
