# Continuous execution rule

A multi-phase plan is **one task, not N tasks**. Phases are chapter headings in a single book — they are NOT decision gates where the user has to give permission to keep reading.

## The contract (BLOCKING)

Once a plan exists and the user has approved (or implicitly accepted) the work, execute the plan to completion in a single uninterrupted run. Do not stop between phases. Do not stop between todos. Do not stop between files. Do not stop between tasks in `.specify/tasks.md`. The work is done when the plan is done.

## What this forbids

The following are explicit anti-patterns. Each one is a rule violation:

- "Phase 1 complete. Should I continue with Phase 2?"
- "Done with the backend. Want me to start on the frontend now?"
- "I've finished the implementation. Ready for me to write the tests?"
- "Step 3 of 7 complete. Shall I move on to step 4?"
- "Want me to proceed with the next item in the plan?"
- "The first task is done. Continue with the rest?"
- Stopping after every TodoWrite item to confirm the next one
- Stopping after Allium elicitation to ask "ready to implement?" — the spec → implementation handoff is part of the same pipeline
- Stopping after browser tests to ask "ready to run TLA+?" — the testing → verification handoff is part of the same pipeline

If the user has already said "build feature X" and you wrote a plan covering Phases A/B/C, then asking "ready for Phase B?" after finishing Phase A is asking the same question twice. The user already answered. Keep going.

## When stopping IS legitimate

You SHOULD stop and ask when (and only when):

1. **Genuine ambiguity** — a real decision the plan does not cover and that you cannot reasonably assume. Use `AskUserQuestion`. Examples: "the spec says 'send notification' but does not specify channel — email, SMS, or in-app?", "the API contract supports two valid interpretations of the timeout field — which one do you want?".
2. **Hard blocker** — something you cannot resolve autonomously. Missing credentials, missing infrastructure, a failing external dependency, conflicting requirements that need human arbitration.
3. **The plan is fully complete** — every phase done, every todo checked, every test passing, validation markers written. Then you stop and report.
4. **Allium / TLA+ findings** — these have their own decision protocol per `.claude/rules/validation-followup.md` and ARE legitimate stop points.
5. **End of a spec when a spec register exists** — when `specs/INDEX.md` is the authoritative plan, **one spec = one plan**. Finishing a spec (pipeline done, committed, pushed, register ticked) is case (3) at the spec boundary. Stop with the status summary defined in `.claude/rules/spec-register.md`. Do NOT chain into the next spec without explicit user instruction — the project-level register defines plan boundaries, the project as a whole does not.
6. **Register-rewrite proposal** — if mid-spec you discover the register itself is wrong (next spec impossible, scope creep needs a new row, project goal shifted), stop with the rewrite proposal per `.claude/rules/spec-register.md`. This is the only mid-spec stop that is not (1), (2), or (4).

If none of (1)-(6) apply: do not stop. Continue with the next phase, the next todo, the next file. Whatever is next in the plan, just do it.

## How to apply

Before composing a stop message, check yourself:

- Am I about to ask "should I continue with X?" where X is already in the plan? → **Do not stop. Just do X.**
- Am I about to ask "want me to also do Y?" where Y was implicit in the original request? → **Do not stop. Just do Y.**
- Is there an unfinished item in the active TodoWrite list / tasks.md / plan? → **Do not stop. Continue.**
- Did I just complete a "phase" but the overall task is not done? → **Do not stop. Start the next phase.**

The stop button is for completion or for blocking ambiguity, not for permission-checking.

## Why this rule exists

Splitting a plan into ask-for-permission checkpoints feels safe but is actually waste:

- The user has already approved the plan. Asking again wastes their time.
- Each interruption breaks context — the next continuation costs more tokens to reload state than just continuing would have cost.
- It teaches the user to rubber-stamp, which trains them to skim — and then real ambiguities (the kind that should stop you) get nodded through too.
- The autonomous-mode rules in `CLAUDE.md` already say "Stagnation is treated as failure." Asking permission for work the user already authorized is stagnation in a polite costume.

## Backstop

A `Stop` hook (`scripts/continuous-execution-hook.sh`) inspects the last assistant message for phase-continuation question patterns ("should I continue with...", "want me to proceed...", "ready for the next phase...") and refuses to stop the session when one is detected. If you hit this hook, the fix is not to rephrase the question — the fix is to stop asking and just continue the work.
