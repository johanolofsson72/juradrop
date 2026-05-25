#!/usr/bin/env bash
# PostToolUse hook for Bash matching `git push -u origin <branch>`.
# When the diff between the branch and main is large (>500 changed
# lines), the local LLM analyzes the file groupings and suggests
# natural split points so the PR is reviewable instead of a single
# 2000-line wall.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

echo "$CMD" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push[[:space:]]+(-u|--set-upstream)[[:space:]]+origin[[:space:]]' || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ] || exit 0

BASE=main
git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/$BASE" >/dev/null 2>&1 \
  || { BASE=master; git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/$BASE" >/dev/null 2>&1 || exit 0; }

# Count changed lines.
LINES_CHANGED=$(git -C "$REPO_ROOT" diff --shortstat "origin/$BASE...HEAD" 2>/dev/null \
  | sed -nE 's/.*[[:space:]]([0-9]+)[[:space:]]+insertion.*[[:space:]]([0-9]+)[[:space:]]+deletion.*/\1+\2/p' \
  | head -1)
[ -n "$LINES_CHANGED" ] || LINES_CHANGED="0+0"
TOTAL=$(echo "$LINES_CHANGED" | awk -F+ '{print $1+$2}')

THRESHOLD="${LOCAL_LLM_PR_SPLIT_MIN_LINES:-500}"
[ "$TOTAL" -gt "$THRESHOLD" ] || exit 0

DIFF_STAT=$(git -C "$REPO_ROOT" diff --stat "origin/$BASE...HEAD" 2>/dev/null)
COMMIT_LOG=$(git -C "$REPO_ROOT" log --oneline "origin/$BASE..HEAD" 2>/dev/null | head -50)

PAYLOAD=$(printf 'Branch: %s → %s\nTotal lines changed: %s\n\nFiles changed (with line counts):\n%s\n\nCommits on branch:\n%s\n' \
  "$BRANCH" "$BASE" "$TOTAL" "$DIFF_STAT" "$COMMIT_LOG")

SYSTEM='You are suggesting how to split a large PR into smaller, reviewable pieces.

The branch is large enough that a single PR will be hard to review. Analyze the file groupings (by directory, by concern, by commit theme) and propose 2-4 natural splits. Each split should be:
- Coherent (related files, same concern)
- Independently reviewable (does not require the other splits to make sense)
- Small enough to review in 15-30 minutes (typically <300 lines per split)

Output format (no preamble, no markdown):

SIZE: <total lines> changes across <total files> files in <total commits> commits

SPLIT 1: <one-line theme>
  Files: <comma-separated file paths or globs>
  Why: <one-line reason this stands alone>

SPLIT 2: <one-line theme>
  Files: ...
  Why: ...

(repeat for SPLIT 3 / SPLIT 4 if needed)

ORDER: Suggest a merge order if splits depend on each other (e.g. SPLIT 1 → SPLIT 2 → SPLIT 3). If splits are independent, write: parallel.

If the PR is large but cannot be cleanly split (single coherent change), output exactly: COHESIVE — single PR is appropriate, just write a thorough description.'

SPLITS=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$SPLITS" ] || exit 0
echo "$SPLITS" | grep -qE '^[[:space:]]*COHESIVE' && {
  jq -nc --arg n "$TOTAL" \
    '{additionalContext: ("Local-LLM PR splitter: " + $n + "-line PR is large but llama3 deemed it cohesive — write a thorough description and consider whether reviewers can reasonably handle this in one read.")}'
  exit 0
}

jq -nc --arg n "$TOTAL" --arg b "$BRANCH" --arg s "$SPLITS" \
  '{additionalContext: ("Local-LLM PR splitter on " + $b + " (" + $n + " lines):\n" + $s + "\nConsider splitting before opening as a single PR — small reviewable PRs > one giant PR.")}'
