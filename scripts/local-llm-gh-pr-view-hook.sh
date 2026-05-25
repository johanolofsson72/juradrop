#!/usr/bin/env bash
# PostToolUse Bash hook. After `gh pr view` / `gh pr view --comments`, write
# a digest of the PR (description, decisions, open threads) to
# .claude/.local-llm-pr-context.md so Claude can reread the digest on
# follow-up turns instead of re-running gh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0
echo "$CMD" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+view' || exit 0

STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
[ ${#STDOUT} -gt 1000 ] || exit 0

PAYLOAD=$(printf 'Command:\n%s\n\nOutput (truncated):\n%s\n' \
  "$CMD" "$(printf '%s' "$STDOUT" | head -c 16000)")

SYSTEM='Digest a GitHub PR view output for a coding assistant.
Output sections:

PR: <number, title, author, state, branch, commit count>
SUMMARY: <2-4 lines on what the PR does, from description>
DECISIONS: <bullets of any decisions made in review threads>
OPEN: <bullets of any unresolved review threads — quote the path:line and the asks>
ACTIONS: <bullets of remaining work the assistant likely needs to do>

Quote actual reviewer text where useful. Skip empty sections. Max 40 lines.'

DRAFT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$PWD"
DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-pr-context.md"
mkdir -p "$DRAFT_DIR"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM PR digest cached at " + $p + ". Read this for PR context on follow-up turns instead of re-running `gh pr view` — refreshed each time you call gh pr view.")}'
