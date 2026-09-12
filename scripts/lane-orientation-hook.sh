#!/usr/bin/env bash
# SessionStart: what the OTHER lane holds, what is unclaimed, and what is waiting.
#
# Why this exists. On a project with two developers on two machines, the only channel
# between the sessions was a human pasting one session's output into the other's prompt.
# Git already carries the register, the pending diagnoses and the open questions; nothing
# read the other lane's half at session start, so a finding made on one machine stayed
# invisible on the other until somebody quoted it by hand.
#
# SINGLE-LANE PROJECTS PAY NOTHING. lane_status.py prints nothing in brief mode unless the
# register actually carries an owner tag, so a one-developer project sees no change at all.
# Same additive shape as the lane logic in .claude/rules/spec-register.md.
#
# All the reasoning lives in scripts/lane_status.py, which scripts/lane-status.sh also
# calls. One parser, two renderings — a session-start brief and the full answer to "is
# there anything for me to do?". Two readers of one register that could disagree about who
# owns what is the failure .claude/rules/spec-register.md names.
#
# It does NOT resolve "which spec is active": scripts/spec_active.py owns that question and
# the PreToolUse guards enforce its answer.
#
# Fails open in every direction: no register, no python3, no jq, a parse error → silent
# exit 0. A session start that says nothing is a nuisance; one that dies is a broken
# session.

set -u

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -e "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || exit 0
[ -f "$PROJECT_ROOT/specs/INDEX.md" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lane_status.py" ] || exit 0

MSG=$(python3 "$SCRIPT_DIR/lane_status.py" --root "$PROJECT_ROOT" 2>/dev/null)
[ -n "$MSG" ] || exit 0

MSG="$MSG

Ask \"is there anything for me to do?\" for the full picture (bash scripts/lane-status.sh)."

# SPEC 046 — orientation is addressed to Claude, not to the developer.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hook-notice.sh"
notice_model SessionStart "$MSG"
exit 0
