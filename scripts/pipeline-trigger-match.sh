#!/bin/bash
# UserPromptSubmit helper — decides whether a prompt is a *clean invocation*
# of a speckit pipeline subcommand (specify / clarify / plan / tasks /
# implement / analyze), versus an incidental substring match in pasted /
# quoted content (markdown code blocks, inline code, blockquotes, table
# cells, Claude transcript bullets, pipeline-flow diagrams).
#
# The pre-existing inline hooks in .claude/settings.json used unanchored
# grep against the entire prompt, which made them fire on any pasted
# transcript that *mentioned* the command (e.g. an `/speckit.analyze` cell
# in a markdown table copied from another session).
#
# Usage:
#   bash scripts/pipeline-trigger-match.sh <subcommand>
#   <subcommand> ∈ {specify, clarify, plan, tasks, implement, analyze}
#
# Reads the UserPromptSubmit JSON payload from stdin. Exit 0 on clean
# invocation, exit 1 on no match. All matching logic lives in
# scripts/pipeline-trigger-match.py — this wrapper just extracts the
# prompt from JSON and pipes it to the Python core.

set -u

SUBCMD="${1:-}"
[ -z "$SUBCMD" ] && exit 1

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
printf '%s' "$PROMPT" | python3 "$SCRIPT_DIR/pipeline-trigger-match.py" "$SUBCMD"
exit $?
