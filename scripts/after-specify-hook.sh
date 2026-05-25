#!/bin/bash
# PostToolUse hook: auto-commit after /specify creates spec.md
# Triggers only for files named spec.md (the GitHub Spec Kit output).
# Safety: only commits on non-main/master branches, and only stages the spec file itself.
set -u

FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only act on spec.md files (typically specs/<feature>/spec.md from /specify)
case "$(basename "$FILE")" in
  spec.md) ;;
  *) exit 0 ;;
esac

# Must be inside a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Refuse to auto-commit on main/master — feature specs belong on feature branches
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ] || [ -z "$BRANCH" ]; then
  echo '{"systemMessage": "after_specify: skipped auto-commit (on '"$BRANCH"' branch). Create a feature branch first."}'
  exit 0
fi

# Only commit if the spec file has uncommitted changes
if git diff --quiet -- "$FILE" && git diff --cached --quiet -- "$FILE"; then
  exit 0
fi

FEATURE=$(basename "$(dirname "$FILE")")
git add -- "$FILE" 2>/dev/null
git commit --only -m "spec: add ${FEATURE} specification" -- "$FILE" >/dev/null 2>&1 && \
  echo '{"systemMessage": "after_specify: committed '"$FILE"' on branch '"$BRANCH"'"}'
