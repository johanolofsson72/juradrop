#!/usr/bin/env bash
# PostToolUse Bash hook. After `gh run view` / `gh run view --log`, condense
# the CI run output (often 5000+ lines) into a per-job failure digest at
# .claude/.local-llm-gh-run-context.md so Claude can reread the digest
# instead of re-running gh and re-ingesting the full log.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0
echo "$CMD" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+run[[:space:]]+(view|list)' || exit 0

STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
STDERR=$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null)
COMBINED="${STDOUT}
${STDERR}"

[ ${#COMBINED} -gt 1500 ] || exit 0

# Keep both ends. Head usually has the run summary, tail has the failures.
HEAD=$(printf '%s' "$COMBINED" | head -c 8000)
TAIL=$(printf '%s' "$COMBINED" | tail -c 8000)
PAYLOAD=$(printf 'Command:\n%s\n\n== HEAD ==\n%s\n\n== TAIL ==\n%s\n' \
  "$CMD" "$HEAD" "$TAIL")

SYSTEM='Summarize a GitHub Actions run for a coding assistant.
Output sections (omit any that do not apply):

RUN: <workflow name + conclusion + commit sha if visible>
JOBS: <one bullet per job: name + result + duration if visible>
FAILURES: <one bullet per failed step: job > step > error type + file:line if visible + one-line cause>
RETRY: <command to re-run, if obvious>

Be concrete. Quote actual error strings. No filler. Max 30 lines total.'

DRAFT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$PWD"
DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-gh-run-context.md"
mkdir -p "$DRAFT_DIR"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM CI-run digest cached at " + $p + ". Read this for cross-turn context instead of re-running `gh run view` — it is a digest of the run output you already saw, refreshed each time you call gh run.")}'
