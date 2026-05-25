#!/usr/bin/env bash
# PostToolUse Bash hook. After `gh issue view`, digest issue + comments to
# .claude/.local-llm-issue-context.md for cheap rereads on follow-up turns.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0
echo "$CMD" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+issue[[:space:]]+view' || exit 0

STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
[ ${#STDOUT} -gt 800 ] || exit 0

PAYLOAD=$(printf 'Command:\n%s\n\nOutput:\n%s\n' \
  "$CMD" "$(printf '%s' "$STDOUT" | head -c 16000)")

SYSTEM='Digest a GitHub issue view output for a coding assistant.
Output sections:

ISSUE: <number, title, author, state, labels>
PROBLEM: <2-4 lines describing the actual problem from the issue body>
DISCUSSION: <bullets of key points from comment thread, attribute to commenter>
DECISIONS: <bullets of any conclusions reached>
NEXT: <bullets of what work remains>

Quote useful reviewer text. Skip empty sections. Max 40 lines.'

DRAFT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$PWD"
DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-issue-context.md"
mkdir -p "$DRAFT_DIR"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM issue digest cached at " + $p + ". Read this for issue context on follow-up turns instead of re-running `gh issue view`.")}'
