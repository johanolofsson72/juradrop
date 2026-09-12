#!/bin/bash
# Discharge the obligation a template sync left behind (spec 007at).
#
# The sync rewrites a project's enforcement machinery at SessionStart, commits it and
# pushes it. It cannot check the project afterwards: it is bounded at 120 s by a hook
# whose contract is that a template problem never blocks a session from starting, and a
# real regression suite is tens of seconds even warm. So it writes what it did not check
# to .git/template-sync-unverified, and this is the thing that checks it.
#
# This is the ONLY place the project's declared command is ever executed, and it runs
# only when a human types it. The sync and both SessionStart hooks read the marker and
# never run anything — the declaration is a command string in a repository file, and
# unattended machinery has no business executing one.
#
#   scripts/template-sync-verify.sh
#
#   exit 0  verified (or nothing outstanding)  ·  1  the command failed  ·  2  usage
#        3  no declaration and nothing derivable  ·  4  a derived command ran and proved nothing
#
# Declare the command in .claude/.template-sync-verify — first line that is neither
# blank nor a # comment. It should be the project's real regression suite, and NOT a
# filter narrowed to whatever class you are thinking about today: spec 007an shipped
# over seven red tests precisely because its filtered runs never selected the class
# they were in.
#
# With no declaration this DERIVES one from the project's own layout via
# scripts/detect-verify-command.sh (spec 007ba) — because when that spec was written, 42
# projects carried this obligation and exactly one carried a declaration, so for the other
# 41 the reminder above was unanswerable. A derived command is held to a stricter standard
# than a declared one: it must show that tests actually ran before anything is marked
# verified (exit 4 when it does not), because nobody chose it. See the evidence gate below.

set -u

TAIL_LINES="${TEMPLATE_SYNC_VERIFY_TAIL:-20}"
case "$TAIL_LINES" in ''|*[!0-9]*) TAIL_LINES=20 ;; esac
HISTORY_LINES=20

case "${1:-}" in
  -h|--help)
    # Everything from the shebang to the first non-comment line. A hard line range drifts
    # the first time the header is edited, and the drift is silent.
    awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  "") ;;
  *)
    printf 'template-sync-verify: unknown argument %s (try --help)\n' "$1" >&2
    exit 2 ;;
esac

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
if [ -z "$PROJECT_ROOT" ]; then
  printf 'template-sync-verify: not inside a git repository.\n'
  exit 0
fi

MARKER="$PROJECT_ROOT/.git/template-sync-unverified"
HISTORY="$PROJECT_ROOT/.git/template-sync-verified"
DECL="$PROJECT_ROOT/.claude/.template-sync-verify"

# Nothing outstanding runs nothing. A verify that burns the suite whether or not there
# is anything to check is a verify people stop running, and this one is worth running.
if [ ! -f "$MARKER" ]; then
  printf 'nothing to verify: no template-sync commit is outstanding on this branch.\n'
  if [ -f "$HISTORY" ]; then
    printf 'last verified: %s\n' "$(tail -1 "$HISTORY")"
  fi
  exit 0
fi

field() { sed -n "s/^$1=//p" "$MARKER" 2>/dev/null | head -1; }
COMMIT=$(field commit)
COMMITS=$(field commits)
TEMPLATE=$(field template)
SYNCED=$(field synced)
PUSHED=$(field pushed)

COMMAND=""
[ -r "$DECL" ] && COMMAND=$(grep -v '^[[:space:]]*#' "$DECL" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)

# Spec 007ba. A declaration always wins and is never second-guessed — a human chose it, and
# judging their choice is a different spec. Only when there is none do we derive.
#
# EVIDENCE is what makes a derived command safe to trust. It is a pattern the run's output must
# contain before the obligation may be discharged, and it is non-empty only for commands this
# script COMPOSED (a `dotnet test` built from a path found on disk). Exiting 0 proves nothing:
# `dotnet test` returns 0 both on a solution holding no test project and on a test project holding
# no test (007ba research.md M1, M2), so an exit-code-only reading would write "verified" over a
# project nothing ran against — which is the defect this whole mechanism exists to replace.
#
# A derived `npm test` carries no pattern, deliberately: scripts.test in package.json is a
# sentence a human wrote about their own project. The evidence rule governs guesses.
DERIVED=""
PROVENANCE=""
EVIDENCE=""
# Resolved as a SIBLING, not through $PROJECT_ROOT/scripts/. The detector, this script and the
# reminder are one piece of CORE machinery that ships together, so the copy that answers must be
# the copy that was installed alongside this one — a project part-way through adopting the
# template can have the running script from one place and nothing at all under scripts/.
DETECT="$(dirname "$0")/detect-verify-command.sh"
[ -f "$DETECT" ] || DETECT="$PROJECT_ROOT/scripts/detect-verify-command.sh"

if [ -z "$COMMAND" ] && [ -f "$DETECT" ]; then
  DETECTED=$(bash "$DETECT" "$PROJECT_ROOT" 2>/dev/null)
  COMMAND=$(printf '%s\n' "$DETECTED" | sed -n '1p')
  PROVENANCE=$(printf '%s\n' "$DETECTED" | sed -n '2p')
  EVIDENCE=$(printf '%s\n' "$DETECTED" | sed -n '3p')
  [ -n "$COMMAND" ] && DERIVED=yes
fi

if [ -z "$COMMAND" ]; then
  printf 'This project declares no regression command, and none could be derived from its\n'
  printf 'layout, so there is nothing to run.\n\n'
  printf 'Outstanding: %s (template %s, %s)\n\n' \
    "${COMMIT:-unknown}" "${TEMPLATE:-unknown}" "${SYNCED:-unknown}"
  if [ -f "$DETECT" ]; then
    CANDIDATES=$(bash "$DETECT" "$PROJECT_ROOT" --candidates 2>/dev/null | head -5)
    if [ -n "$CANDIDATES" ]; then
      printf 'What is here, none of it unambiguous enough to pick for you:\n\n'
      printf '%s\n' "$CANDIDATES" | sed 's/^/    /'
      printf '\n'
    fi
  fi
  printf 'Create .claude/.template-sync-verify with one line — the command that proves\n'
  printf 'this project still works. For a .NET project that is usually its unit suite:\n\n'
  printf '    dotnet test tests/<Project>.Tests.Unit/<Project>.Tests.Unit.csproj\n\n'
  printf 'Then run this script again. The obligation stands until something checks it.\n'
  exit 3
fi

printf 'Verifying %s (template %s, synced %s, %s)\n' \
  "${COMMIT:-unknown}" "${TEMPLATE:-unknown}" "${SYNCED:-unknown}" \
  "$([ "$PUSHED" = yes ] && echo 'already pushed' || echo 'not pushed')"
if [ -n "$DERIVED" ]; then
  printf '  %s\n' "$COMMAND"
  printf '  derived, not declared — %s\n\n' "${PROVENANCE:-derived from this repository layout}"
else
  printf '  %s\n\n' "$COMMAND"
fi

LOG=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/template-sync-verify.$$")

# Streamed, not captured. A suite that prints nothing for a minute cannot be told from a
# hang, and the first thing anyone does about that is stop running it. The tee keeps a
# copy only so the marker can carry a tail.
( cd "$PROJECT_ROOT" && sh -c "$COMMAND" 2>&1 ) | tee "$LOG"
RC=${PIPESTATUS[0]}

NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Spec 007ba — the evidence gate. Fires only for a DERIVED command carrying a pattern, i.e. one
# this script composed rather than one a human wrote. Exit 0 is not proof: `dotnet test` exits 0
# on a solution with no test project and on a test project with no test, printing "No test is
# available" in the second case and nothing at all in the first (research.md M1, M2).
#
# This deliberately does NOT stamp result=failed. "It ran and proved nothing" is a statement about
# the command; result=failed means KNOWN BAD, which is a statement about the project — and
# reporting a healthy project as broken poisons this reminder as thoroughly as a false green does.
# So the obligation is simply left standing, exactly as it was, and exit 4 says why.
#
# Fails CLOSED, unlike everything else in this family: if the log cannot be read, that is not
# evidence that tests ran. Detection failing open protects a session from a broken detector;
# verification failing open would hand back the false green the gate exists to prevent.
if [ "$RC" -eq 0 ] && [ -n "$DERIVED" ] && [ -n "$EVIDENCE" ]; then
  PROVED=""
  if [ -r "$LOG" ]; then
    if grep -qE "$EVIDENCE" "$LOG" 2>/dev/null && ! grep -q 'No test is available' "$LOG" 2>/dev/null; then
      PROVED=yes
    fi
  fi
  if [ -z "$PROVED" ]; then
    rm -f "$LOG"
    printf '\nThe derived command exited 0, but nothing in its output shows that a test ran.\n'
    printf 'That is not a failing project — it is a command that proved nothing, so the\n'
    printf 'obligation for %s still stands.\n\n' "${COMMIT:-unknown}"
    printf 'Nobody chose this command; it was derived from your layout:\n'
    printf '    %s\n' "$COMMAND"
    printf '    %s\n\n' "${PROVENANCE:-derived from this repository layout}"
    printf 'Put the command that really exercises this project in\n'
    printf '.claude/.template-sync-verify (first non-comment line) and run this again.\n'
    exit 4
  fi
fi

if [ "$RC" -eq 0 ]; then
  rm -f "$MARKER"
  # Every outstanding SHA, not just the newest. One run of the suite verifies the tree as it
  # stands, which is all of them — and a history line naming one of three is the same kind of
  # partial truth this whole mechanism exists to stop.
  # "derived:" is load-bearing in the receipt, not decoration (spec 007ba). Someone reading this
  # file in six months must be able to see that nobody chose the command a green line rests on.
  printf '%s verified %s (template %s) — %s%s\n' \
    "$NOW" "${COMMITS:-${COMMIT:-unknown}}" "${TEMPLATE:-unknown}" \
    "$([ -n "$DERIVED" ] && printf 'derived: ')" "$COMMAND" >> "$HISTORY"
  # Bounded: this file answers "when was this branch last checked", which needs the last
  # few entries and never the first ones.
  if [ "$(grep -c . "$HISTORY" 2>/dev/null)" -gt "$HISTORY_LINES" ]; then
    tail -n "$HISTORY_LINES" "$HISTORY" > "$HISTORY.tmp" 2>/dev/null && mv -f "$HISTORY.tmp" "$HISTORY"
  fi
  N_DISCHARGED=$(printf '%s\n' $COMMITS | grep -c .)
  if [ "${N_DISCHARGED:-1}" -gt 1 ]; then
    printf '\nverified %s — %s outstanding sync commits discharged.\n' "$COMMITS" "$N_DISCHARGED"
  else
    printf '\nverified %s — the obligation is discharged.\n' "${COMMIT:-unknown}"
  fi
  rm -f "$LOG"
  exit 0
fi

# Failed. The obligation is not merely renewed, it is upgraded: the branch is now known
# bad rather than unchecked, and the reminder says so in those words from here on.
{
  printf '# Template sync commits this branch has not been verified against (spec 007at).\n'
  printf '# Written by scripts/template-autosync.sh · discharged by scripts/template-sync-verify.sh\n'
  printf 'commit=%s\n' "$COMMIT"
  printf 'commits=%s\n' "$COMMITS"
  printf 'template=%s\n' "$TEMPLATE"
  printf 'synced=%s\n' "$SYNCED"
  printf 'pushed=%s\n' "$PUSHED"
  printf 'result=failed\n'
  # The command's OWN exit code, kept rather than flattened into this script's 1: it is the
  # first thing anyone reading the marker wants, and a test runner's code carries meaning
  # that the word "failed" does not.
  printf 'exit=%s\n' "$RC"
  printf 'failed=%s\n' "$NOW"
  # Bounded at the END. The last lines are where a runner puts its verdict; a head-bounded
  # tail would faithfully record twenty lines of build chatter.
  tail -n "$TAIL_LINES" "$LOG" 2>/dev/null | tr -d '\r' | sed 's/^/tail /'
  grep '^file ' "$MARKER" 2>/dev/null
} > "$MARKER.tmp" 2>/dev/null && mv -f "$MARKER.tmp" "$MARKER"

rm -f "$LOG"
printf '\nverification FAILED (exit %s) for %s.\n' "$RC" "${COMMIT:-unknown}"
printf 'The obligation stands and now reads "failed" — every session start will say so\n'
printf 'until the project passes again.\n'
exit 1
