# Continuous execution rule

A multi-phase plan is **one task, not N tasks**. Phases are chapter headings, not permission gates. Long form (why, full anti-pattern list): `.claude/docs/continuous-execution-rationale.md`.

## The contract (BLOCKING)

Once a plan exists and the user has approved (or implicitly accepted) the work, execute it to completion in one uninterrupted run. Do not stop between phases, todos, files, or tasks in `.specify/tasks.md`. The work is done when the plan is done.

## What this forbids

Any permission-check on work already authorized, e.g.: "Phase 1 complete. Should I continue with Phase 2?", "Done with the backend. Want me to start on the frontend now?", "Ready for me to write the tests?", "Step 3 of 7 complete. Shall I move on?", "Want me to proceed with the next item?"; stopping after each task-list item; stopping after Allium elicitation to ask "ready to implement?"; stopping after browser tests to ask "ready to run TLA+?".

Also forbidden: relaying spec-kit 1.0's `/speckit-implement` prompt — *"Some checklists have unchecked items. Do you want to proceed with implementation anyway? (yes/no)"*. Judge the unchecked items instead: tick what is satisfied, record real gaps in the spec and `<spec-dir>/run-log.md`, and report them in the per-spec status summary. Never relay it, never convert it into an `AskUserQuestion`. `scripts/speckit-extension-policy.sh` rewrites the stop out of the skill after every `specify init`; see the override in `.claude/rules/feature-pipeline.md`.

## When stopping IS legitimate

Stop and ask only when:

1. **Genuine ambiguity** — a real decision the plan does not cover and you cannot reasonably assume. Use `AskUserQuestion`.
2. **Hard blocker** — missing credentials/infrastructure, failing external dependency, conflicting requirements needing arbitration.
3. **The plan is fully complete** — every phase done, every todo checked, tests passing, validation markers written. Then report.
4. **Allium / TLA+ findings** — per `.claude/rules/validation-followup.md`.
5. **End of a spec when a spec register exists** — one spec = one plan. Stop with the status summary in `.claude/rules/spec-register.md`; do NOT chain into the next spec without explicit instruction.
6. **Register-rewrite proposal** — the register itself is wrong, per `.claude/rules/spec-register.md`.
7. **Convergence stop** — carve ratio ≥ 1.3 over 10+ ticked rows, per `.claude/rules/carve-budget.md`. Finish the current spec, then stop and present the three ways out.

If none of (1)–(7) apply: do not stop. Before composing a stop message, check: is X already in the plan, or implicit in the request? Is there an unfinished item in the task list / `tasks.md`? Did I finish a phase but not the task? → **Do not stop. Continue.**

## Backstop

A `Stop` hook (`scripts/continuous-execution-hook.sh`) detects phase-continuation questions ("should I continue with...", "want me to proceed...", "ready for the next phase...") and refuses the stop. The fix is not to rephrase the question — stop asking and continue the work.
