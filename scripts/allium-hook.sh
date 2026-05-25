#!/bin/bash
# PostToolUse hook: when a speckit spec/plan/tasks file is written, check for .allium companion.
#
# Scope: anchored to actual speckit paths only. The previous loose regex
# (spec|tasks|plan|feature).*\.md fired on any markdown with those words
# (feature-roadmap.md, plan-old.md, etc.) and produced false STOP messages.
# Triage rule: only behavior-changing specs need .allium files. The path
# anchors below are the structural signal that the file is a speckit
# artifact rather than free-form documentation.
set -u

FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Match only canonical speckit layouts:
#   .specify/**/*.md
#   specs/<feature>/spec.md   (also plan.md, tasks.md)
if ! echo "$FILE" | grep -qE '(\.specify/.+\.md$|specs/[^/]+/(spec|plan|tasks)\.md$)'; then
  exit 0
fi

# Check if a .allium file exists in the same directory
DIR=$(dirname "$FILE")
ALLIUM_COUNT=$(find "$DIR" -maxdepth 1 -name "*.allium" 2>/dev/null | wc -l | tr -d ' ')

if [ "$ALLIUM_COUNT" -eq 0 ] && [ -d "$DIR" ]; then
  echo '{"systemMessage": "Speckit spec detected with no .allium companion. If this spec is behavior-changing (full/light pipeline), run /allium:elicit '"$FILE"' now. If it is the spec-only track (refactor, doc change, dependency bump, cosmetic UI, fix with no new entities/transitions), skip Allium — see .claude/rules/specs.md → Spec triage."}'
fi
