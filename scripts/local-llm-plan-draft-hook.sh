#!/usr/bin/env bash
# PostToolUse Edit/Write hook. When a speckit spec.md is written, draft an
# initial plan.md to <spec-dir>/.local-llm-plan-draft.md so the subsequent
# /plan step refines the draft instead of generating from scratch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

# Per-hook timeout override — same reasoning as tasks-draft. Plan drafts
# emit 30-80 lines of structured sections; with num_predict=1536 on a 32b
# model the wall-clock often exceeds 15s. 60s gives the model headroom.
LOCAL_LLM_TIMEOUT="${LOCAL_LLM_PLAN_DRAFT_TIMEOUT:-60}"
export LOCAL_LLM_TIMEOUT

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0

case "$FILE" in
  */specs/*/spec.md|*/.specify/specs/*/spec.md) ;;
  *) exit 0 ;;
esac
[ -r "$FILE" ] || exit 0

# Section-aware context extraction. A plan only needs the spec's intent
# (Feature/Overview), user-facing behavior (User Story / Acceptance),
# and boundaries (Scope / Constraints / Out of scope). History, links,
# changelogs, and reference appendices are noise here. Falls back to a
# byte cap when the extraction produces too little — e.g. a free-form
# spec with non-standard headings.
SPEC_FULL=$(cat "$FILE")
SPEC_EXTRACTED=$(awk '
  /^#+[[:space:]]+(Feature|Overview|User[[:space:]]+[Ss]tor|Acceptance|Goals?|Requirement|Constraint|Scope|Non[- ]functional|Out[[:space:]]+of[[:space:]]+scope|Functional|Background|Context|Problem|Solution)/ { p=1; print; next }
  /^#+[[:space:]]+/ { p=0; next }
  p { print }
' <<<"$SPEC_FULL")
if [ "${#SPEC_EXTRACTED}" -ge 500 ]; then
  SPEC=$(printf '%s' "$SPEC_EXTRACTED" | head -c 12000)
else
  SPEC=$(printf '%s' "$SPEC_FULL" | head -c 12000)
fi
[ -n "$SPEC" ] || exit 0

SYSTEM='You draft a plan.md for a speckit-style feature spec.

Output sections (use these headings exactly):

# Plan

## Approach
<2-5 sentences on the technical approach: which layers/files, which patterns from the existing codebase>

## Phases
1. <Phase name> — <one-line description>
2. ...

## Files affected
- <path> — <create | modify | delete> — <one-line reason>

## Risks
- <risk> — <mitigation>

## Out of scope
- <bullet of what is NOT in this spec>

Rules:
- Be specific. Cite likely file paths from the spec.
- Phases must include: setup, core implementation, tests, wiring, docs, deploy/rollback if applicable.
- Risks must include any data migrations, breaking changes, or perf concerns implied by the spec.
- 30-80 lines total.
- No preamble, no extra prose.'

DRAFT=$(printf 'Spec:\n%s\n' "$SPEC" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 1536 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR=$(dirname "$FILE")
DRAFT_PATH="$DRAFT_DIR/.local-llm-plan-draft.md"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM plan-draft saved at " + $p + ". When you run /plan for this spec, read and refine this draft instead of generating from scratch — verify approach, phase ordering, and file impacts against the actual codebase before writing the real plan.md.")}'
