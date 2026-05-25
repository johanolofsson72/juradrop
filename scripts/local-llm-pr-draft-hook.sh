#!/usr/bin/env bash
# PostToolUse hook for Bash. Fires after `git push -u origin <branch>`,
# which typically precedes a `gh pr create`. Reads the diff between the
# current branch and main, drafts a PR title + Summary + Test Plan, and
# stashes it at .claude/.local-llm-pr-draft.md so the assistant can use
# it when invoking `gh pr create --title --body`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Fire only on `git push -u origin ...` (the canonical first push of a branch).
echo "$CMD" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push[[:space:]]+(-u|--set-upstream)[[:space:]]+origin[[:space:]]' || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ] || exit 0

# Determine base branch (main or master, whichever exists).
BASE=main
git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/$BASE" >/dev/null 2>&1 \
  || { BASE=master; git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/$BASE" >/dev/null 2>&1 || exit 0; }

DIFF_STAT=$(git -C "$REPO_ROOT" diff --stat "origin/$BASE...HEAD" 2>/dev/null)
[ -n "$DIFF_STAT" ] || exit 0

DIFF_FULL=$(git -C "$REPO_ROOT" diff "origin/$BASE...HEAD" 2>/dev/null | head -c 24000)
COMMIT_LOG=$(git -C "$REPO_ROOT" log --oneline "origin/$BASE..HEAD" 2>/dev/null | head -50)

SYSTEM='Draft a pull request description for the diff between a feature branch and its base.

Output format (follow exactly, no preamble, no code fences):

<PR title — imperative, ≤70 chars, prefixed with conventional type if obvious>

## Summary
- <1-3 bullet points describing what the PR does and why>

## Test plan
- [ ] <concrete verification step>
- [ ] <concrete verification step>
- [ ] <concrete verification step>

Rules:
- Title: imperative mood, no trailing period, no marketing language
- Summary bullets: focus on user-visible or system-visible outcome, not file-level detail
- Test plan items: specific and verifiable (commands to run, scenarios to test in browser, etc.)
- No emoji, no AI attribution lines, no Co-authored-by'

DRAFT=$(printf 'Branch: %s → %s\n\nFiles changed:\n%s\n\nCommits on branch:\n%s\n\nDiff (truncated):\n%s\n' \
  "$BRANCH" "$BASE" "$DIFF_STAT" "$COMMIT_LOG" "$DIFF_FULL" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-pr-draft.md"
mkdir -p "$DRAFT_DIR"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" --arg b "$BRANCH" --arg base "$BASE" \
  '{additionalContext: ("Local-LLM PR draft prepared at " + $p + " for " + $b + " → " + $base + ". Read and refine before running `gh pr create --title \"...\" --body \"$(cat " + $p + ")\"` — sanity-check claims against the actual diff, do not commit verbatim.")}'
