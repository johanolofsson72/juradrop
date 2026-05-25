#!/bin/bash
# Emits the SPECKIT ANALYZE auto-apply + auto-chain reminder as
# UserPromptSubmit additionalContext JSON. Invoked when the user types a
# clean invocation of /speckit.analyze (matched by
# scripts/pipeline-trigger-match.sh analyze).

read -r -d '' MSG <<'EOM'
SPECKIT ANALYZE — AUTO-APPLY MODE + AUTO-CHAIN TO /speckit.implement. READ-ONLY consistency check across spec/plan/tasks; do NOT trigger the spec→Allium→TLA+ pipeline for the analyze step itself. Steps for this run, executed as ONE continuous task per .claude/rules/continuous-execution.md:

1. Produce the analysis report (findings with IDs A1, A2, ...) and the Next Actions block exactly as analyze.md prescribes.
2. Immediately AUTO-APPLY concrete remediation edits for EVERY finding in the report without prompting the user. This is the user's standing instruction and overrides the analyze.md Step 8 default of asking before applying. Do NOT emit any phrasing like "Reply suggest & apply for all" — that wait-for-user UX is removed.
3. After all remediation is applied and the spec/plan/tasks are consistent, AUTO-CHAIN to /speckit.implement without stopping, without asking, and without status-summary in between. The transition tasks → analyze → auto-apply → implement is a single uninterrupted run.

Legitimate stops during this chain (same rules as the pipeline): genuine ambiguity (AskUserQuestion), hard blocker, Allium/TLA+ findings (per validation-followup.md), or a register-rewrite proposal (per spec-register.md). Otherwise: keep going. Asking the user mid-chain about whether to apply or whether to continue is a rule violation.

At the end of remediation, emit one short audit block (in addition to the analysis report) before /speckit.implement starts:

**Auto-applied remediation:**
- A1 — <one-line topic>: <what changed> — <file:line>
- A2 — <one-line topic>: <what changed> — <file:line>
- ...

Then start /speckit.implement.
EOM

jq -n --arg msg "$MSG" '{additionalContext: $msg}'
