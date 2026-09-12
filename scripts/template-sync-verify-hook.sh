#!/bin/bash
# SessionStart hook: say that a template sync committed to this branch and nobody
# has checked whether the project still passes.
#
# Why this exists (spec 007at). The sync rewrites a project's enforcement machinery
# unattended, commits it, pushes it, and classifies its own run from an exit code
# that means "the copy loop finished" and knows nothing about the project. It has
# done real damage twice: 0a30a77 took seven of spec 007ak's tests red and the next
# spec ran a full pipeline on top of them and reported green; 5d9234b reverted spec
# 007as and pushed seven red tests to origin/main under "3 updated, 0 added".
#
# The sync cannot run the suite itself — it is bounded at 120 s from a hook whose
# whole contract is that a template problem never blocks a session from starting,
# and msroute's unit suite alone is 46 s warm. So the sync records an obligation and
# this hook keeps reporting it until scripts/template-sync-verify.sh discharges it.
#
# Deliberately NOT rate-limited, unlike template-autosync-hook.sh. That one does
# network I/O and a two-minute sync; this one does a stat and a small read. And
# once-per-six-hours is the failure being fixed: 0a30a77 DID announce itself, once,
# at a session start, and the spec that followed shipped over it anyway. Speaking
# every time is the entire difference between a notification and an obligation.
#
# Executes nothing. The declared command is run only by template-sync-verify.sh, on
# an explicit human invocation — an unattended hook that executes a command string
# read out of a repository file is a trust boundary this spec does not cross.
#
# Fails open on every path: a bookkeeping problem must never stop a session.

set -u

[ "${CLAUDE_TEMPLATE_SYNC_VERIFY_REMINDER:-1}" = "0" ] && exit 0

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  # A directory, not merely a path: a git worktree's .git is a FILE, and a marker
  # path built inside one would be a hook inventing news of a shape nobody tested.
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || exit 0

MARKER="$PROJECT_ROOT/.git/template-sync-unverified"
[ -f "$MARKER" ] || exit 0
[ -r "$MARKER" ] || exit 0

field() { sed -n "s/^$1=//p" "$MARKER" 2>/dev/null | head -1; }

COMMIT=$(field commit)
COMMITS=$(field commits)
TEMPLATE=$(field template)
SYNCED=$(field synced)
PUSHED=$(field pushed)
RESULT=$(field result)
FAILED_AT=$(field failed)
EXIT_CODE=$(field exit)

# A marker with no commit in it is a marker this hook does not understand. Saying
# nothing is the conservative answer; a half-parsed reminder is worse than none.
[ -n "$COMMIT" ] || exit 0

N=$(printf '%s\n' $COMMITS | grep -c . 2>/dev/null)
[ "${N:-0}" -gt 0 ] || N=1

# The file list is what makes the reminder actionable rather than merely alarming —
# "your enforcement machinery moved" reads very differently from "a doc moved". Bounded
# for the same reason the sync's [changed] block is: this text is forwarded verbatim
# into a session's context, and enforcement comes first there for the same reason.
FILES=$(sed -n 's/^file //p' "$MARKER" 2>/dev/null \
  | awk '{ if ($0 == ".claude/settings.json") r = 0
           else if ($0 ~ /^\.claude\/rules\//) r = 1
           else if ($0 ~ /^scripts\//)         r = 2
           else                                r = 3
           printf "%d\t%s\n", r, $0 }' \
  | LC_ALL=C sort -t"$(printf '\t')" -k1,1n -k2,2 | cut -f2)
N_FILES=$(printf '%s\n' "$FILES" | grep -c .)
FILE_LINES=$(printf '%s\n' "$FILES" | head -8 | sed 's/^/  /')
[ "${N_FILES:-0}" -gt 8 ] && FILE_LINES="$FILE_LINES
  … and $((N_FILES - 8)) more"

COMMAND=""
DECL="$PROJECT_ROOT/.claude/.template-sync-verify"
[ -r "$DECL" ] && COMMAND=$(grep -v '^[[:space:]]*#' "$DECL" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)

# The word "unverified" is in both arms on purpose: it is what the sync's own [verify] block
# says, what the marker is named after, and what someone greps a transcript for later.
if [ "$N" -eq 1 ]; then
  HEAD_LINE="1 template-sync commit on this branch is unverified — nothing has checked this project since."
else
  HEAD_LINE="$N template-sync commits on this branch are unverified — nothing has checked this project since."
fi

BODY="$HEAD_LINE
  $COMMIT — template ${TEMPLATE:-unknown}, $([ "$PUSHED" = yes ] && echo pushed || echo "not pushed"), ${SYNCED:-unknown}"
[ "$N" -gt 1 ] && BODY="$BODY
  all outstanding: $COMMITS"
[ -n "$FILES" ] && BODY="$BODY
what it rewrote:
$FILE_LINES"

if [ "$RESULT" = "failed" ]; then
  TAIL=$(sed -n 's/^tail //p' "$MARKER" 2>/dev/null | sed 's/^/  /')
  BODY="$BODY
Verification has already FAILED here — exit ${EXIT_CODE:-?} at ${FAILED_AT:-unknown}:
$TAIL
This branch is known bad, not merely unchecked. Fix it before building on it."
else
  BODY="$BODY
Nobody has run the project's own regression command against it yet."
fi

if [ -n "$COMMAND" ]; then
  BODY="$BODY
Run: scripts/template-sync-verify.sh   ($COMMAND)"
else
  # Spec 007ba. This arm used to be the entire message for 41 of the 42 projects carrying an
  # obligation, and it asked them for a config chore rather than for the thing the reminder is
  # about. A reminder nobody can answer is a reminder everyone learns to skip — which is exactly
  # what 007at removed the rate limit to prevent.
  #
  # Derives, never writes, and still executes nothing: the derived string is printed for a human
  # to run, and template-sync-verify.sh remains the only thing that ever runs it.
  DERIVED=""
  DERIVED_FROM=""
  # Sibling first — see the note in template-sync-verify.sh: these three ship as one piece.
  DETECT="$(dirname "$0")/detect-verify-command.sh"
  [ -f "$DETECT" ] || DETECT="$PROJECT_ROOT/scripts/detect-verify-command.sh"
  if [ -f "$DETECT" ]; then
    # Once, then sliced. Two invocations would pay the whole search twice on the session-start
    # path for one string apiece.
    DETECTED=$(bash "$DETECT" "$PROJECT_ROOT" 2>/dev/null)
    DERIVED=$(printf '%s\n' "$DETECTED" | sed -n '1p')
    DERIVED_FROM=$(printf '%s\n' "$DETECTED" | sed -n '2p')
  fi

  if [ -n "$DERIVED" ]; then
    BODY="$BODY
No declaration — derived from this project's own layout: $DERIVED
  ($DERIVED_FROM)
Run: scripts/template-sync-verify.sh   — it will use that command, and will refuse to
mark anything verified unless the run shows that tests actually executed. To choose a
different command, put it in .claude/.template-sync-verify (first non-comment line)."
  else
    CANDIDATES=""
    [ -f "$DETECT" ] && CANDIDATES=$(bash "$DETECT" "$PROJECT_ROOT" --candidates 2>/dev/null \
      | head -5 | sed 's/^/  /')
    if [ -n "$CANDIDATES" ]; then
      BODY="$BODY
No declaration, and more than one thing it could mean:
$CANDIDATES
Put the one you mean in .claude/.template-sync-verify (first non-comment line), then run
scripts/template-sync-verify.sh."
    else
      BODY="$BODY
No declaration, and no test project or test script was found in this repository.
Put the command that proves this project still works in .claude/.template-sync-verify
(first non-comment line), then run scripts/template-sync-verify.sh."
    fi
  fi
fi

# SPEC 046 — this is a standing obligation addressed to Claude ("N sync commits
# are unverified, run this command"), and it ran to ten lines. As a
# systemMessage that was ten red warnings at every session start, on every
# project carrying the obligation — which is most of them, which is how the
# reminder became wallpaper. hook-notice.sh carries the same jq-free escaping
# this hook hand-rolled, so the no-jq machine is still covered.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hook-notice.sh"
notice_model SessionStart "$BODY"
exit 0
