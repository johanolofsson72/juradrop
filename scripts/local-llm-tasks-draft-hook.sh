#!/usr/bin/env bash
# PostToolUse Edit/Write hook. When a speckit spec.md is written, draft an
# initial tasks.md to <spec-dir>/.local-llm-tasks-draft.md so the
# subsequent /tasks step refines the draft instead of generating from
# scratch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

# Per-hook timeout override — drafting tasks with 1536 num_predict on a
# 14b/32b model regularly exceeds the global 15s default. Bumping to 60s
# keeps the hook within the same wall-clock envelope as /tasks itself
# would have spent generating the file from scratch.
LOCAL_LLM_TIMEOUT="${LOCAL_LLM_TASKS_DRAFT_TIMEOUT:-60}"
export LOCAL_LLM_TIMEOUT

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0

# Match speckit spec layouts: specs/<id>/spec.md or .specify/specs/<id>/spec.md
case "$FILE" in
  */specs/*/spec.md|*/.specify/specs/*/spec.md) ;;
  *) exit 0 ;;
esac
[ -r "$FILE" ] || exit 0

# Section-aware context extraction. Tasks are derived from acceptance
# criteria + functional/non-functional requirements + explicit test
# expectations. History, narrative background, and reference appendices
# don't drive task IDs — drop them. Falls back to a byte cap when the
# extraction produces too little for a spec with non-standard headings.
SPEC_FULL=$(cat "$FILE")
SPEC_EXTRACTED=$(awk '
  /^#+[[:space:]]+(Feature|Overview|User[[:space:]]+[Ss]tor|Acceptance|Goals?|Requirement|Constraint|Scope|Non[- ]functional|Out[[:space:]]+of[[:space:]]+scope|Functional|Test|Coverage)/ { p=1; print; next }
  /^#+[[:space:]]+/ { p=0; next }
  p { print }
' <<<"$SPEC_FULL")
if [ "${#SPEC_EXTRACTED}" -ge 500 ]; then
  SPEC=$(printf '%s' "$SPEC_EXTRACTED" | head -c 12000)
else
  SPEC=$(printf '%s' "$SPEC_FULL" | head -c 12000)
fi
[ -n "$SPEC" ] || exit 0

SYSTEM='You draft a tasks.md for a speckit-style feature spec.

Output a numbered task list ready for the assistant to refine. Format:

# Tasks

T001  <verb-led, single-deliverable task>     [refs: AC-N]
T002  <next task>                             [refs: AC-N, AC-M]
...

Rules:
- Every task is a single concrete deliverable (file created, function implemented, test added, command run)
- Tasks should be ordered: setup → core implementation → tests → wiring → docs
- Each task references the acceptance criteria it satisfies (AC-1, AC-2, etc.) — use the IDs visible in the spec
- Include explicit test tasks for every implemented function (functional coverage) plus 8+ destructive scenarios
- Do not invent tasks not implied by the spec
- 15-40 tasks total
- No preamble, no markdown beyond the format'

DRAFT=$(printf 'Spec:\n%s\n' "$SPEC" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 1536 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR=$(dirname "$FILE")
DRAFT_PATH="$DRAFT_DIR/.local-llm-tasks-draft.md"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM tasks-draft saved at " + $p + ". When you run /tasks for this spec, read and refine this draft instead of generating from scratch — verify task ordering and AC mappings before writing the real tasks.md.")}'
