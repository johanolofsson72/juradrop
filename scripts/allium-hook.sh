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

# SPEC 046 — addressed to Claude ("run /allium:elicit on this spec"), so it goes
# on Claude's channel and once per spec file per session.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hook-notice.sh"

INPUT=$(cat)

# Cheapest exit first (spec 073, R9): only a speckit spec/plan/tasks file is looked at,
# and that name appears in the raw JSON verbatim (escaping leaves letters, dots and slashes alone),
# so a payload without it needs no jq to be ruled out. A match only means
# "look properly" — the tests below still decide. Bounded, because bash's matcher is slow on long
# strings; a large payload skips this and pays what it paid before.
if [ "${#INPUT}" -le 4096 ]; then
  case "$INPUT" in *.specify/*|*spec.md*|*plan.md*|*tasks.md*) ;; *) exit 0 ;; esac
fi
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
SID=$(hn_session_id "$INPUT")
[ -z "$FILE" ] && exit 0

# Match only canonical speckit layouts:
#   .specify/**/*.md
#   specs/<feature>/spec.md   (also plan.md, tasks.md)
if ! grep -qE '(\.specify/.+\.md$|specs/[^/]+/(spec|plan|tasks)\.md$)' <<< "$FILE"; then
  exit 0
fi

# Check if a .allium file exists in the same directory
DIR=$(dirname "$FILE")
ALLIUM_COUNT=$(find "$DIR" -maxdepth 1 -name "*.allium" 2>/dev/null | wc -l | tr -d ' ')

if [ "$ALLIUM_COUNT" -eq 0 ] && [ -d "$DIR" ]; then
  notice_once PostToolUse "$SID" "allium:$FILE" \
"Speckit spec detected with no .allium companion. If this spec is behavior-changing (full/light pipeline), run /allium:elicit $FILE now. If it is the spec-only track (refactor, doc change, dependency bump, cosmetic UI, fix with no new entities/transitions), skip Allium — see .claude/rules/specs.md → Spec triage."
fi
