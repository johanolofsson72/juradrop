#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on speckit tasks.md files. Reads the
# tasks.md and its sibling spec.md, asks the local LLM to map each
# task to one or more acceptance criteria. Reports tasks without
# criteria coverage (orphan tasks) and criteria without any task
# (orphan criteria). Surfaces drift before /allium:elicit runs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

# Only fire on speckit tasks.md files.
case "$FILE" in
  */specs/*/tasks.md|*/.specify/specs/*/tasks.md|*/specs/tasks.md) ;;
  *) exit 0 ;;
esac

SPEC_FILE=$(dirname "$FILE")/spec.md
[ -r "$SPEC_FILE" ] || exit 0

SIZE_TASKS=$(wc -c < "$FILE" 2>/dev/null || echo 0)
SIZE_SPEC=$(wc -c < "$SPEC_FILE" 2>/dev/null || echo 0)
[ "$SIZE_TASKS" -gt 200 ] || exit 0
[ "$SIZE_SPEC" -gt 200 ] || exit 0
[ $((SIZE_TASKS + SIZE_SPEC)) -lt 30000 ] || exit 0

TASKS=$(head -c 12000 "$FILE")
SPEC=$(head -c 12000 "$SPEC_FILE")

PAYLOAD=$(printf '== SPEC (spec.md) ==\n%s\n\n== TASKS (tasks.md) ==\n%s\n' "$SPEC" "$TASKS")

SYSTEM='You are checking traceability between a feature spec and its task list.

The spec contains acceptance criteria (in a section like "## Acceptance Criteria" or "## Scenarios"). The tasks file contains numbered or bulleted implementation tasks.

For each task, identify which acceptance criterion it implements. For each criterion, identify which tasks cover it. Then report two kinds of gaps:

1. ORPHAN_TASK: a task that does not trace to any criterion (suggests scope creep or undocumented work)
2. ORPHAN_CRITERION: a criterion that has no task covering it (suggests missing implementation work)

Output format (one line per gap):
- ORPHAN_TASK: <task identifier or short summary> | <reason: which criterion would normally cover this, if any>
- ORPHAN_CRITERION: <criterion identifier or short summary> | <reason: what task is missing>

If every task traces to a criterion AND every criterion has a covering task, output exactly: TRACEABLE
No preamble, no markdown.'

REPORT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 512 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*TRACEABLE[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg t "$FILE" --arg s "$SPEC_FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM task ↔ criteria traceability check (" + $t + " vs " + $s + "):\n" + $r + "\nClose gaps before /allium:elicit — orphan tasks become unspecified behavior, orphan criteria become untested promises.")}'
