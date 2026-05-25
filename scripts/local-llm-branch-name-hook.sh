#!/usr/bin/env bash
# PostToolUse hook for Bash matching branch-creation commands. When a
# new branch is created with a lazy/uninformative name (fix, wip,
# test, temp, foo, branch, etc.), the local LLM suggests descriptive
# alternatives based on the current diff and recent commits so the
# branch name actually communicates intent to reviewers.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Match `git checkout -b <name>` or `git switch -c <name>`.
BRANCH_NAME=""
if BRANCH_NAME=$(echo "$CMD" | sed -nE 's/.*git[[:space:]]+checkout[[:space:]]+-b[[:space:]]+([A-Za-z0-9._\/-]+).*/\1/p' | head -1); then
  :
fi
if [ -z "$BRANCH_NAME" ]; then
  BRANCH_NAME=$(echo "$CMD" | sed -nE 's/.*git[[:space:]]+switch[[:space:]]+-c[[:space:]]+([A-Za-z0-9._\/-]+).*/\1/p' | head -1)
fi
[ -n "$BRANCH_NAME" ] || exit 0

# Strip namespace prefix (feature/, bugfix/, etc.) for lazy-name check.
LEAF="${BRANCH_NAME##*/}"
LEAF_LOWER=$(echo "$LEAF" | tr '[:upper:]' '[:lower:]')

# Lazy-name patterns.
case "$LEAF_LOWER" in
  fix|wip|test|temp|foo|bar|baz|branch|new|update|change|tmp|x|y|z|patch|hotfix|feature|main|master|dev|develop|stuff|work|misc|todo)
    : # known lazy
    ;;
  *)
    # Also flag very short names (≤3 chars) and pure-numeric.
    if [ ${#LEAF} -gt 3 ] && ! echo "$LEAF" | grep -qE '^[0-9]+$'; then
      exit 0
    fi
    ;;
esac

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Gather context for naming suggestion.
RECENT_COMMITS=$(git -C "$REPO_ROOT" log --oneline -10 2>/dev/null)
DIFF_STAT=$(git -C "$REPO_ROOT" diff --stat HEAD 2>/dev/null | head -20)
DIFF_PEEK=$(git -C "$REPO_ROOT" diff HEAD 2>/dev/null | head -c 4000)

PAYLOAD=$(printf 'Branch just created: %s\n\nRecent commits on parent:\n%s\n\nUncommitted changes (will likely live on this branch):\n%s\n\nDiff peek:\n%s\n' \
  "$BRANCH_NAME" "$RECENT_COMMITS" "$DIFF_STAT" "$DIFF_PEEK")

SYSTEM='You are suggesting a better git branch name. The user just created a branch with a lazy/generic name.

Suggest 3 descriptive alternatives based on the recent commits and uncommitted diff. Use kebab-case. Prefix with the appropriate type if obvious:
- feat/<short-description>     for new features
- fix/<short-description>      for bug fixes
- refactor/<short-description> for refactors
- docs/<short-description>     for docs-only
- test/<short-description>     for test-only
- chore/<short-description>    for tooling/build
- speckit/<spec-id>            for speckit work on a specific spec

Each name should be ≤50 chars total, lowercase, kebab-case in the description part.

Output exactly 3 alternatives, one per line:
1. <suggestion>
2. <suggestion>
3. <suggestion>

End with one line:
RENAME: git branch -m <current-name> <best-suggestion>

No preamble, no markdown.'

SUGGESTIONS=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 320 2>/dev/null)

[ -n "$SUGGESTIONS" ] || exit 0

jq -nc --arg b "$BRANCH_NAME" --arg s "$SUGGESTIONS" \
  '{additionalContext: ("Local-LLM branch-name review: \"" + $b + "\" looks generic. Suggestions:\n" + $s)}'
