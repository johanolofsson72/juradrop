#!/usr/bin/env bash
# SessionStart hook: generate "where you left off" orientation for the
# assistant. Runs once per session and injects a 5-8 line summary
# (branch, last commit, uncommitted work, recent specs, likely next
# step) so the assistant does not need to re-explore via grep/git on
# every session start.
#
# Honors LOCAL_LLM_ORIENTATION_DISABLE=1 to opt out per-session/shell.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${LOCAL_LLM_ORIENTATION_DISABLE:-0}" = "1" ] && exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
GIT_LOG=$(git -C "$REPO_ROOT" log --oneline -20 2>/dev/null)
GIT_STATUS=$(git -C "$REPO_ROOT" status --short 2>/dev/null | head -30)
GIT_DIFF_STAT=$(git -C "$REPO_ROOT" diff --stat 2>/dev/null | head -20)

# Find specs modified in the last 7 days (speckit / .specify).
ACTIVE_SPECS=""
for d in "$REPO_ROOT/specs" "$REPO_ROOT/.specify/specs"; do
  [ -d "$d" ] || continue
  ACTIVE_SPECS="${ACTIVE_SPECS}$(find "$d" -name "spec.md" -mtime -7 -print 2>/dev/null | head -3)
"
done

PAYLOAD=$(printf 'Branch: %s\n\nRecent commits:\n%s\n\nUncommitted (status):\n%s\n\nDiff stat:\n%s\n\nActive specs (modified last 7 days):\n%s\n' \
  "$BRANCH" "$GIT_LOG" "$GIT_STATUS" "$GIT_DIFF_STAT" "$ACTIVE_SPECS")

SYSTEM='You are summarizing the state of a code repo for a developer (or coding assistant) resuming work.

Output 5-8 lines, no markdown headers, no preamble. Use this exact format:

WHERE: <branch name and what kind of work the branch suggests>
LAST DONE: <most recent significant commit, with hash>
IN PROGRESS: <uncommitted work or recently modified specs/files>
LIKELY NEXT: <one concrete suggestion based on diff/specs/branch name>

If branch is main with no uncommitted work and no active specs, output exactly: CLEAN

Be concrete. Use file names, commit hashes, branch names. No filler. No marketing language.'

ORIENTATION=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 320 2>/dev/null)

[ -n "$ORIENTATION" ] || exit 0
echo "$ORIENTATION" | grep -qE '^[[:space:]]*CLEAN[[:space:]]*$' && exit 0

jq -nc --arg o "$ORIENTATION" \
  '{additionalContext: ("Local-LLM orientation (where you left off):\n" + $o)}'
