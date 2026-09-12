#!/bin/bash
# harness-state-gc.sh — removes what the harness itself leaves on disk.
#
#   bash scripts/harness-state-gc.sh            # clean this project
#   bash scripts/harness-state-gc.sh --dry-run  # say what it would remove
#   bash scripts/harness-state-gc.sh --report   # just count, remove nothing
#
# Wired to SessionEnd and SessionStart. Exits 0 always: a GC that can fail a
# session is worse than the litter it collects.
#
# WHY A SEPARATE PASS (spec 046)
# -------------------------------------------------------------------------
# Every producer here already had a cleanup, and each one was reachable only
# through the event that produced the mess:
#
#   .claude/state/attempts/  repeat-failure-guard-hook.sh prunes past its TTL —
#       but the prune sits below that hook's "only track verification runs"
#       gate. So the files are created by `dotnet test` and deleted by
#       `dotnet test`, and a project that stops running tests keeps every
#       attempt file it ever wrote. Measured 2026-09-12: 40 files in
#       ighweld-2026, all of them older than the 6-hour TTL, none collected;
#       53 in film-i-vast-demo, 37 in teach.
#
#   TLC scratch                tlc-cleanup.sh kills the java processes and
#       leaves their output. 138 `states/` directories across the repos.
#       fundit carried 2146 scratch files under tests/, which is how register
#       row 044 came to see a traceability scan return "0 of 182".
#
# Coupling cleanup to the producing event is the shape of the bug, so this pass
# runs on session boundaries instead, where it is free and always reached.
#
# WHAT IT WILL NOT TOUCH
# -------------------------------------------------------------------------
# `states/` is not a reserved word. Two real directories on this machine are
# named that and are not scratch: consultpilot/frontend/src/states holds a
# React component, radar/specs/006-containerization/states holds a hand-written
# .tla model with its .cfg and a README. Deleting either would be a genuine
# loss, silently, from a housekeeping script — so the match is not on the name.
#
# TLC writes states/<YY-MM-DD-HH-MM-SS>/ and fills it with .st / .fp / nodes_N /
# ptrs_N. This removes a directory only when its name is that timestamp AND
# every file under it is one of those four shapes. A `states/` parent is removed
# only if it is empty afterwards. Anything with a file it does not recognise
# stays, and is reported.

set -u

MODE="clean"
for a in "$@"; do
  case "$a" in
    --dry-run) MODE="dry" ;;
    --report)  MODE="report" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  esac
done

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || exit 0

REMOVED_ATTEMPTS=0
REMOVED_TLC=0
KEPT_UNRECOGNISED=0
NOTES=""

_act() {  # _act <path>  → remove unless dry/report
  case "$MODE" in
    clean) rm -rf -- "$1" 2>/dev/null ;;
    *)     : ;;
  esac
}

# -prune, not -not -path: the latter still descends into node_modules and makes
# this walk cost minutes on a real frontend repo. This runs at every session
# boundary, so it has to be close to free or it gets unwired.
_find_states() {
  find "$PROJECT_ROOT" \
    \( -type d \( -name node_modules -o -name .git -o -name bin -o -name obj \
                 -o -name dist -o -name .next -o -name vendor \) -prune \) -o \
    -type d -name 'states' -print 2>/dev/null
}

# --------------------------------------------------- 1. attempt fingerprints
# Same TTL and the same env override as repeat-failure-guard-hook.sh, so the
# two agree about when an attempt stops being interesting. Six hours: long
# enough that a session's own retries still count against the 3-attempt cap,
# short enough that yesterday's build failure is not still on disk.
TTL="${ATTEMPT_TTL:-21600}"
STATE_DIR="$PROJECT_ROOT/.claude/state/attempts"
if [ -d "$STATE_DIR" ]; then
  NOW=$(date +%s 2>/dev/null || echo 0)
  if [ "$NOW" -gt 0 ]; then
    for f in "$STATE_DIR"/*; do
      [ -f "$f" ] || continue
      MT=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
      case "$MT" in (*[!0-9]*|'') MT=0 ;; esac
      [ "$MT" -eq 0 ] && continue
      [ $((NOW - MT)) -le "$TTL" ] && continue
      _act "$f"
      REMOVED_ATTEMPTS=$((REMOVED_ATTEMPTS + 1))
    done
  fi
fi

# ------------------------------------------------------------ 2. TLC scratch
# The timestamp directory is the signature. TLC writes it as YY-MM-DD-HH-MM-SS.
TS_RE='^[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$'

_is_pure_tlc_scratch() {   # every file under $1 is a known TLC artifact
  local d="$1" f base
  # An empty directory counts: TLC leaves those behind too.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
      *.st|*.fp|nodes_[0-9]*|ptrs_[0-9]*|*.chkpt) ;;
      *) return 1 ;;
    esac
  done <<EOF
$(find "$d" -type f 2>/dev/null)
EOF
  return 0
}

while IFS= read -r sd; do
  [ -n "$sd" ] || continue
  [ -d "$sd" ] || continue
  if _is_pure_tlc_scratch "$sd"; then
    _act "$sd"
    REMOVED_TLC=$((REMOVED_TLC + 1))
  else
    KEPT_UNRECOGNISED=$((KEPT_UNRECOGNISED + 1))
    NOTES="${NOTES}  kept (unrecognised contents): $sd
"
  fi
done <<EOF
$(_find_states \
   | while IFS= read -r p; do find "$p" -mindepth 1 -maxdepth 1 -type d 2>/dev/null; done \
   | while IFS= read -r c; do [ -n "$c" ] && basename "$c" | grep -qE "$TS_RE" && printf '%s\n' "$c"; done)
EOF

# A states/ parent that is now empty was only ever the container. Removed with
# rmdir, not rm -rf: if anything is still in there, rmdir refuses and the
# directory stays, which is the behaviour this whole file is careful about.
if [ "$MODE" = "clean" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] && rmdir "$p" 2>/dev/null
  done <<EOF
$(_find_states | while IFS= read -r p; do [ -n "$p" ] && [ -z "$(ls -A "$p" 2>/dev/null)" ] && printf '%s\n' "$p"; done)
EOF
fi

# ------------------------------------------------- 3. this session's notices
# hook-notice.sh keeps one directory per session under TMPDIR for its
# once-per-session de-duplication. It sweeps its own siblings, but only while a
# hook is firing; this collects them on a machine whose TMPDIR is never cleared.
NOTICE_BASE="${TMPDIR:-/tmp}"
NOTICE_BASE="${NOTICE_BASE%/}/claude-hook-notices"
if [ -d "$NOTICE_BASE" ] && [ "$MODE" = "clean" ]; then
  find "$NOTICE_BASE" -maxdepth 1 -type d -mtime +2 -exec rm -rf {} + 2>/dev/null
fi

TOTAL=$((REMOVED_ATTEMPTS + REMOVED_TLC))
if [ "$MODE" = "clean" ]; then
  [ "$TOTAL" -eq 0 ] && exit 0
  printf 'harness-state-gc: removed %s attempt fingerprint(s) and %s TLC scratch dir(s).\n' \
    "$REMOVED_ATTEMPTS" "$REMOVED_TLC"
else
  printf 'harness-state-gc (%s): %s attempt fingerprint(s) past TTL, %s TLC scratch dir(s).\n' \
    "$MODE" "$REMOVED_ATTEMPTS" "$REMOVED_TLC"
fi
[ "$KEPT_UNRECOGNISED" -gt 0 ] && printf '%s' "$NOTES"
exit 0
