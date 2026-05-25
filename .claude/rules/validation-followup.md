# Validation follow-up rule (Allium + TLA+)

When `/allium`, `/allium:elicit`, `/allium:distill`, or `/tla` runs and produces a report — the findings are NOT background reading. They are the deliverable. Glossing over them defeats the entire pipeline.

## The contract (BLOCKING — applies after every Allium or TLA+ run)

After any Allium or TLA+ skill run completes, the very next response MUST do one of these — nothing else is acceptable:

1. **Findings exist** → list every single one as a numbered item, then immediately call `AskUserQuestion` with one decision per finding (fix now / defer / dismiss with reason).
2. **No findings** → state explicitly: "Allium/TLA+ run complete. Zero drift, zero gaps, zero open questions, zero ambiguities." If you cannot say this verbatim and mean it, you have findings — see option 1.
3. **Run failed or was inconclusive** → say so plainly, then ask whether to retry, fix the blocker, or skip.

A response that summarizes the report without surfacing every finding for explicit decision is a **rule violation** and must be retried.

## What counts as a "finding"

ALL of the following are findings and MUST be surfaced individually:

- Allium drift items (specified-but-not-implemented, implemented-but-not-specified, behavioral drift)
- Allium `open question "..."` entries
- Allium `-- AMBIGUITY:` comments produced during elicitation
- Allium `deferred` markers
- TLA+ `GAP-N` entries (safety, liveness, fairness)
- TLA+ counterexamples / state traces
- TLA+ "MISSING TEST" rows in the coverage matrix
- TLC errors, deadlocks, invariant violations
- Any "consider implementation change" recommendations
- Any "the spec is too vague to formalize" notes

If you find yourself thinking "this one is minor, I'll skip it" — that is exactly the failure mode this rule exists to prevent. Surface it. Let the user decide.

## How to surface findings

Use `AskUserQuestion` with one question per finding. Each question:

- States the finding in one line, exactly as the report described it (no softening, no paraphrasing-into-blandness).
- Cites the source (file path, line, rule name, or counterexample step).
- Offers concrete options. Default options are: `Fix now`, `Defer (track in spec)`, `Dismiss (with reason)`. Add a fourth bespoke option when one applies (e.g. `Update spec instead of code`).
- Defaults to `Fix now` framing — the language must make dismissing feel like an active choice, not the path of least resistance.

Batch questions in a single `AskUserQuestion` call when there are multiple findings (the tool supports that). Do not split across turns to "make it manageable" — the user wants the full picture at once.

## What this rule forbids

- "Looks good overall" / "mostly clean" summaries that bury findings.
- Acting on the easy fixes silently while ignoring the hard ones.
- Treating `open question` or `-- AMBIGUITY:` markers as the user's problem to discover later.
- Continuing to the next task while findings remain undecided.
- Asking a single vague question like "want me to address the issues?" — every finding gets its own decision.

## Scope

This rule applies whenever the Allium or TLA+ skills run, regardless of trigger (manual `/allium`, `/tla`, automatic post-implementation hook, or as part of a larger workflow like `/feature-dev`). It applies even if the user did not explicitly ask to see findings — surfacing them is the whole point of running these tools.
