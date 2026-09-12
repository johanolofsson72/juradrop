#!/bin/bash
# PostToolUse hook: auto-commit after /specify creates spec.md
# Triggers only for files named spec.md (the GitHub Spec Kit output).
# Safety: only commits on non-main/master branches, and only stages the spec file itself.
set -u

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hook-notice.sh"

FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only act on spec.md files (typically specs/<feature>/spec.md from /specify)
case "$(basename "$FILE")" in
  spec.md) ;;
  *) exit 0 ;;
esac

# Must be inside a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Refuse to auto-commit on main/master. An auto-commit is a side effect the
# developer did not ask for, and on the shared branch it is the one place that
# is never safe to guess at.
#
# SPEC 046 — silently. This used to answer with "Create a feature branch first",
# as a red warning, on every spec.md written. These projects are solo and
# direct-push by policy (.claude/rules/project-workflow.md, and spec-register.md
# says "no feature branch, no PR, no merge step"), so main IS the working
# branch: the advice contradicted the rule that governs it, and it fired on
# every single spec. Declining to commit is correct; announcing it as a problem
# was not.
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ] || [ -z "$BRANCH" ]; then
  exit 0
fi

# Only commit if the spec file has uncommitted changes
if git diff --quiet -- "$FILE" && git diff --cached --quiet -- "$FILE"; then
  exit 0
fi

FEATURE=$(basename "$(dirname "$FILE")")
git add -- "$FILE" 2>/dev/null
# A commit nobody typed is news for the developer, and it fits on one line.
git commit --only -m "spec: add ${FEATURE} specification" -- "$FILE" >/dev/null 2>&1 && \
  notice_user "after_specify: committed $FILE on branch $BRANCH"
