#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on speckit plan.md files. The local
# LLM scans the plan for unrealistic estimates, missing critical
# phases (testing, deploy, rollback), tech choices that conflict with
# the project's declared stack, and hand-wavy implementation steps.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

case "$FILE" in
  */specs/*/plan.md|*/.specify/specs/*/plan.md|*/specs/plan.md) ;;
  *) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 500 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

PLAN_CONTENT=$(head -c 10000 "$FILE")

# Pull declared tech stack from CLAUDE.md if present, so we can flag mismatches.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$(dirname "$FILE")"
TECH_STACK=""
if [ -r "$REPO_ROOT/CLAUDE.md" ]; then
  TECH_STACK=$(awk '/^##[[:space:]]+Tech[[:space:]]+stack/,/^##[[:space:]]/' "$REPO_ROOT/CLAUDE.md" 2>/dev/null | head -40)
fi

PAYLOAD=$(printf '== PLAN (plan.md) ==\n%s\n\n== DECLARED TECH STACK (from CLAUDE.md, may be empty) ==\n%s\n' "$PLAN_CONTENT" "$TECH_STACK")

SYSTEM='You are reviewing an implementation plan for feasibility.

Scan for these specific issues:

1. Unrealistic time estimates:
   - "1 hour" / "few hours" for a multi-component feature with database changes, UI, and tests
   - Estimates with no breakdown (single number for whole project)
   - Estimates that ignore review, testing, deploy time

2. Missing critical phases:
   - No testing phase (unit, integration, browser)
   - No deploy/release phase
   - No rollback or migration plan for irreversible changes (DB schema, API contracts)
   - No observability (logging, metrics) for production-facing changes

3. Tech-stack conflicts (only flag if the declared stack section above is non-empty):
   - Plan introduces a tech not in the declared stack (e.g. plan says "use Redis" but stack says SQLite + .NET)
   - Plan uses a deprecated approach the stack moved away from

4. Hand-wavy steps:
   - Single-line tasks for non-trivial work ("integrate with X" with no breakdown)
   - "TBD" / "to be determined" / "details later" markers in a plan that should be actionable
   - Steps with no acceptance criteria or "done when..." condition

For each issue, output one line:
- ISSUE: <short description with section/step reference> | FIX: <concrete remediation>

If the plan looks feasible and aligned with the stack, output exactly: FEASIBLE
No preamble, no markdown.'

REPORT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 512 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*FEASIBLE[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM plan feasibility review on " + $f + ":\n" + $r + "\nUnrealistic plans become unrealistic implementations.")}'
