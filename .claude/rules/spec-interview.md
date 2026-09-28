# Spec interview rule (per-spec anti-drift interview — auto by default, human on flag, hard-gated)

Every spec carries a 15–25 question interview in `<spec-dir>/interview.md`, run right after `/speckit-specify` and before `/speckit-clarify`, on **every** track. It pins down the per-spec details (scope, data shape, edge cases, error/empty/loading states, authorization, integrations, non-goals) where AI implementations drift. Long form (reasoning, full example): `.claude/docs/spec-interview-rationale.md`.

## Two modes — AUTO by default, MANUAL on opt-in

- **AUTO (default).** Claude auto-answers the base 15–25 with the **recommended** option, tagged `**A (auto):**`. Two safeguards: (1) **escalate** a question with no defensible recommendation (options equivalent, all conflict with the spec, or behaviour-changing and not pickable with confidence) via `AskUserQuestion` (auto-pick OFF), recorded as `**A:**` — the exception, not the rule; (2) **human overflow** on large/advanced specs — questions beyond the base, answered by the developer.
- **MANUAL (opt-in).** `SPEC_INTERVIEW_MODE=manual` (settings `env` or `CLAUDE.local.md`): every question human-answered via `AskUserQuestion`, one per turn; only `**A:**` answers count.

## The flag — when Claude asks the human (AUTO mode)

Claude judges each spec; the **hardened triggers are the strong prior** for large/advanced: auth / authz, payments, PII or secrets, file upload / parsing, new external API surface; full track with state machine or concurrency; new entity/aggregate or ≥ 6 files; a `[hardened]` row tag (`.claude/rules/spec-hardening.md`). Such a spec should almost always get overflow questions; Claude may also flag by judgment or decline a borderline one. Bias toward asking. On a hardened spec the overflow must include threat-surface questions (authz, input tampering, information disclosure, resource exhaustion).

## Override (both directions, per spec)

- `[interview:manual]` on the row (or the developer says so) → fully human for that spec.
- `[interview:auto]` → base auto, no overflow even if a trigger fired (no effect in a MANUAL-mode project).

Claude proposes the flag, the developer disposes; a waved-through flag is recorded as `[interview:auto]` behaviour.

## Hard-gated

`scripts/spec-interview-guard-hook.sh` (PreToolUse) denies every source-code edit for the active spec until `interview.md` records **≥ 15 answered questions** — AUTO counts `**A:**` + `**A (auto):**`, MANUAL counts only `**A:**`. 15 is the floor (`SPEC_INTERVIEW_MIN`), 25 is guidance, never a ceiling.

## Where it sits in the pipeline

`/speckit-specify → SPEC INTERVIEW → /speckit-clarify (auto-pick residual, scripts/emit-clarify-reminder.sh) → /allium:elicit → /speckit-plan → /speckit-tasks → /speckit-analyze → /speckit-implement`. Same continuous task — no "ready to implement?" stop after it. Surprising or contradictory answers are findings (`.claude/rules/validation-followup.md`).

## What the 15–25 questions cover

Pull from these until you have 15–25 sharp questions for *this* spec; skip a category only when truly N/A (note why):

1. **Scope boundary** — explicitly IN / OUT (deferred).
2. **Primary actor & trigger** — who, from where, in what state.
3. **Happy-path outcome** — concretely what success looks like.
4. **Data model** — entities/fields CRUD'd; types, required/optional, defaults.
5. **Validation rules** — what is rejected, exact rule (length, format, range, uniqueness).
6. **The four observable states** — success / specific error (never silent) / empty / loading.
7. **Error semantics** — recoverable vs fatal; exact, actionable messages.
8. **Authorization** — who may; what happens to unauthorized / unauthenticated actors.
9. **Concurrency / ordering** — simultaneous actors, order significance, idempotency.
10. **Integration points** — features, services, external APIs touched; the contract.
11. **Edge cases** — empty, max, duplicate, stale, partial failure, backing out mid-flow.
12. **Non-functional limits** — volume, payload size, latency, pagination, rate limits.
13. **Acceptance criteria** — measurable definition of done (drives the destructive suite).
14. **Non-goals & assumptions.**
15. **Reversibility** — undo, migration / rollback story.

## The artifact format (`interview.md`)

```markdown
# Spec interview — 003-search

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).

## Q1 — Scope boundary
**Q:** Does this spec include faceted filtering, or only free-text search?
**A (auto):** Free-text only; facets deferred to a later spec.

## Q7 — Authorization  (escalated — no defensible default)
**Q:** Can an unauthenticated visitor search, or is search behind login?
**A:** Behind login. Anonymous search is a separate later spec.
```

AUTO: base `**A (auto):**`, escalated/overflow `**A:**`. MANUAL: all `**A:**`, header `Mode: MANUAL`. Answers must be non-empty.

## What this rule forbids

- Editing source for a spec with < 15 counted answers (no routing around it by calling real work "trivial").
- AUTO: inventing a "recommended" answer for a genuinely-ambiguous, spec-affecting question instead of escalating.
- AUTO: silently auto-answering a large/advanced spec without overflow questions, unless overridden to `[interview:auto]`.
- MANUAL: expecting `**A (auto):**` answers to unlock code.
- Dumping all questions in one message when asking the developer — one per turn (2–3 tightly-related trivial sub-questions may share one `AskUserQuestion`).
- Stopping after the interview to ask "ready to implement?".
- Treating the project-level wizard interview as a substitute.
