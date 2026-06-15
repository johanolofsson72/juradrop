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

# Ground-truth facts shipped ALONGSIDE the summary so a wrong 14B paraphrase
# cannot seed a wrong mental model. The summary is advisory; the raw git
# state below is authoritative, and specs/INDEX.md (read by the spec-register
# orientation hook) is the real "what to work on next".
RAW_FACTS=$(printf 'Branch: %s\nLast 5 commits:\n%s\nUncommitted:\n%s' \
  "$BRANCH" \
  "$(printf '%s' "$GIT_LOG" | head -5)" \
  "$(if [ -n "$GIT_STATUS" ]; then printf '%s' "$GIT_STATUS"; else printf '(clean working tree)'; fi)")

jq -nc --arg o "$ORIENTATION" --arg r "$RAW_FACTS" \
  '{additionalContext: ("Local-LLM orientation — ADVISORY ONLY. A small local model paraphrased the git state below; it can be wrong. VERIFY against the GROUND TRUTH before acting on any \"LIKELY NEXT\", and for what to actually work on, trust specs/INDEX.md (the spec register) over this summary.\n\nSummary (advisory):\n" + $o + "\n\n--- GROUND TRUTH (authoritative — trust over the summary) ---\n" + $r)}'
