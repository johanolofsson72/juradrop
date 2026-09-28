# Validation follow-up rule (Allium + TLA+)

After `/allium`, `/allium:elicit`, `/allium:distill` or `/tla` produces a report, the findings are the deliverable, not background reading. Long form (examples, reasoning): `.claude/docs/validation-followup-rationale.md`.

## The contract (BLOCKING — applies after every Allium or TLA+ run)

The very next response MUST do exactly one of:

1. **Findings exist** → list every one as a numbered item, then immediately call `AskUserQuestion` with one decision per finding (fix now / defer / dismiss with reason).
2. **No findings** → state verbatim: "Allium/TLA+ run complete. Zero drift, zero gaps, zero open questions, zero ambiguities." If you cannot say this and mean it, you have findings — see 1.
3. **Run failed or inconclusive** → say so plainly, then ask whether to retry, fix the blocker, or skip.

A summary that does not surface every finding for explicit decision is a **rule violation** and must be retried.

## What counts as a "finding"

Every one of these, surfaced individually: Allium drift items (specified-not-implemented, implemented-not-specified, behavioral drift); Allium `open question "..."` entries; `-- AMBIGUITY:` comments; `deferred` markers; TLA+ `GAP-N` entries (safety, liveness, fairness); TLA+ counterexamples / state traces; "MISSING TEST" rows in the coverage matrix; TLC errors, deadlocks, invariant violations; any "consider implementation change" recommendation; any "the spec is too vague to formalize" note. "This one is minor, I'll skip it" is exactly the failure mode — surface it.

## Surfacing is not rowing (`.claude/rules/carve-budget.md`)

Surface all of them, then give each one of three dispositions, defaulting to the first:

1. **Fix it inside the current spec** — when the fix is smaller than the ceremony of recording it.
2. **Record it as a finding** — `bash scripts/finding.sh --add "<one line>" --spec NNN` → `specs/FINDINGS.md`, decided at the next 5-spec review. The default for everything else.
3. **Carve a row immediately** — the exception, for work that blocks the next spec.

All three satisfy this rule; only the third grows the register. "Defer (track in spec)" means the third only when the budget allows — not "always make a row".

## How to surface findings

`AskUserQuestion`, one question per finding, batched in a single call (never split across turns). Each question states the finding in one line exactly as reported (no softening), cites the source (file, line, rule, counterexample step), and offers `Fix now` / `Defer (track in spec)` / `Dismiss (with reason)` plus a bespoke option when one applies (e.g. `Update spec instead of code`). Frame it so dismissing is an active choice.

## What this rule forbids

- "Looks good overall" / "mostly clean" summaries that bury findings.
- Silently fixing the easy ones while ignoring the hard ones.
- Leaving `open question` / `-- AMBIGUITY:` markers for the user to discover later.
- Continuing to the next task while findings remain undecided.
- One vague question ("want me to address the issues?") instead of a decision per finding.

**Scope:** every Allium or TLA+ run, however triggered (manual, automatic hook, inside `/feature-dev`), even if the user did not ask to see findings.
