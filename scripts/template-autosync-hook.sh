#!/bin/bash
# SessionStart hook: keeps a project's Claude Code config current with the
# template repo without anyone ever typing /project-update.
#
# Runs scripts/template-autosync.sh (deterministic file sync + core-hook
# rewiring + commit), then reports what happened as a systemMessage so the
# session opens knowing its own config just moved.
#
# Four outcomes, deliberately kept apart (H6t, + DEFERRED from spec 007be):
#
#   COMPLETED  the sync ran to the end. Report what moved — or stay silent if
#              it moved nothing, which is not news.
#   DEFERRED   the sync ran to the end and decided to write nothing, because a
#              rebase/merge/cherry-pick is in progress. Forward its explanation
#              and come back after the shorter backoff window, not the full one.
#   TIMEOUT    the sync was killed at TEMPLATE_AUTOSYNC_LIMIT seconds. Say so
#              once, and come back after the shorter backoff window.
#   OTHER      anything else failed. Stay silent; this hook names the timeout
#              and nothing else.
#
# Fails open, always: every path exits 0. A template sync problem must never
# stop a session from starting. But failing open is not the same as failing
# indistinguishably — before H6t all three outcomes were one silence, and the
# rate-limit marker was refreshed *before* the sync ran, so a sync that always
# timed out bought itself six hours of quiet and then bought six more. Template
# updates stopped arriving and nothing said so.
#
# Cheap by construction:
#   - rate-limited to once per TEMPLATE_AUTOSYNC_INTERVAL seconds (default 6h)
#     via the mtime of .claude/.template-sync-check, so opening five sessions
#     in an afternoon costs one network round-trip, not five;
#   - when a local template clone exists, the version check is a local
#     `git rev-parse` (no network at all);
#   - when only the remote exists, it is one `git ls-remote` and the tarball is
#     downloaded ONLY if the SHA actually moved;
#   - a run killed at the bound waits only TEMPLATE_AUTOSYNC_TIMEOUT_BACKOFF
#     (default 30 min) before trying again, so it retries without charging
#     every single session start the full bound.
#
# Opt out per project:  export CLAUDE_TEMPLATE_AUTOSYNC=0
# Force a check now:    CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS=1

set -u

[ "${CLAUDE_TEMPLATE_AUTOSYNC:-1}" = "0" ] && exit 0

INTERVAL="${TEMPLATE_AUTOSYNC_INTERVAL:-21600}"        # 6h between normal checks
BACKOFF="${TEMPLATE_AUTOSYNC_TIMEOUT_BACKOFF:-1800}"   # 30m after a killed run
LIMIT="${TEMPLATE_AUTOSYNC_LIMIT:-120}"                # seconds the sync gets

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || exit 0
[ -d "$PROJECT_ROOT/.claude" ] || exit 0
[ -x "$PROJECT_ROOT/scripts/template-autosync.sh" ] || [ -f "$PROJECT_ROOT/scripts/template-autosync.sh" ] || exit 0

# The template repo itself is never a sync target (identified by remote URL —
# file markers get copied into every project by the sync itself).
case "$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)" in
  *johanolofsson72/Claude.git|*johanolofsson72/Claude|*:johanolofsson72/Claude*) exit 0 ;;
esac

# ------------------------------------------------------------- rate limiting
# The marker records *what happened*, not merely when. "ok" (and an empty file,
# which is what the pre-H6t hook left behind) means a run that finished and is
# owed the full interval; "timeout" means one that was killed and "deferred" one
# that declined to write — both are owed a retry much sooner.
MARKER="$PROJECT_ROOT/.claude/.template-sync-check"
if [ "${CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS:-0}" != "1" ] && [ -f "$MARKER" ]; then
  NOW=$(date +%s)
  MT=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null || echo 0)
  WINDOW="$INTERVAL"
  # Spec 007be. `deferred` joins `timeout` on the short window for the same reason `timeout` has
  # it: the run finished without doing the work, so waiting the full interval before retrying is
  # waiting for nothing. A deferral that wrote `ok` here would buy itself six hours of silence,
  # which is the pre-H6t bug in this very block arriving by a new door.
  case "$(head -1 "$MARKER" 2>/dev/null | tr -d ' \t')" in
    timeout|deferred) WINDOW="$BACKOFF" ;;
  esac
  [ $((NOW - MT)) -lt "$WINDOW" ] && exit 0
fi

# ------------------------------------------------------------------ the sync
# The bound is not optional. Stock macOS ships neither `timeout` nor
# `gtimeout`, and without one the sync runs for as long as the session will
# tolerate — which the retry above would then repeat at every single start. So
# there is a bash watchdog with the same rc contract (124).
OUTFILE=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/template-autosync.$$")

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"; fi

if [ -n "$TIMEOUT_BIN" ]; then
  # -k is not optional either, and this was measured rather than assumed: plain
  # `timeout N` sends TERM at N and then *waits* for the child to die, so a sync
  # that ignores TERM is not bounded at all — `timeout 2` against a 20 s
  # TERM-ignoring child returns 124 after the full 20 s. With `-k 5` it returns
  # at 7 s with 137, which FR-001 already reads as a timeout. Probed rather than
  # assumed, so a `timeout` without -k degrades to the old behaviour instead of
  # erroring out into the silent OTHER branch.
  KOPT=""
  "$TIMEOUT_BIN" -k 1 1 true >/dev/null 2>&1 && KOPT="-k 5"
  ( cd "$PROJECT_ROOT" && CLAUDE_PROJECT_DIR="$PROJECT_ROOT" \
    "$TIMEOUT_BIN" $KOPT "$LIMIT" bash scripts/template-autosync.sh --quiet ) >"$OUTFILE" 2>&1
  RC=$?
else
  # Same shape by hand — meaning the shape `timeout -k` has, not the one it has
  # by default, because the default is what turned out not to bound anything.
  # The watcher polls instead of sleeping the whole bound in one call, so a sync
  # that finishes early leaves no long-lived `sleep` behind; it TERMs and then
  # KILLs after a grace; and it says nothing at all, because stdout here is the
  # hook's JSON channel.
  KILLSTAMP="$OUTFILE.killed"
  # `exec` matters: without it SYNC_PID is a wrapper subshell and the signals
  # below reach that instead of the sync, which then survives its own bound.
  ( cd "$PROJECT_ROOT" && CLAUDE_PROJECT_DIR="$PROJECT_ROOT" \
    exec bash scripts/template-autosync.sh --quiet ) >"$OUTFILE" 2>&1 &
  SYNC_PID=$!
  (
    i=0
    while [ "$i" -lt "$LIMIT" ]; do
      kill -0 "$SYNC_PID" 2>/dev/null || exit 0
      sleep 1
      i=$((i + 1))
    done
    kill -0 "$SYNC_PID" 2>/dev/null || exit 0
    : > "$KILLSTAMP"
    kill -TERM "$SYNC_PID" 2>/dev/null
    i=0
    while [ "$i" -lt 5 ]; do
      kill -0 "$SYNC_PID" 2>/dev/null || exit 0
      sleep 1
      i=$((i + 1))
    done
    kill -KILL "$SYNC_PID" 2>/dev/null
  ) >/dev/null 2>&1 &
  WATCH_PID=$!
  # bash announces a reaped-by-signal background job on stderr ("Terminated:
  # 15"). Nothing else writes to stderr here, and that notice is exactly the
  # case the systemMessage below already describes in words.
  exec 3>&2 2>/dev/null
  wait "$SYNC_PID"; RC=$?
  kill "$WATCH_PID" 2>/dev/null
  wait "$WATCH_PID" 2>/dev/null
  exec 2>&3 3>&-
  # The stamp exists if and only if the watchdog decided to stop the sync, so
  # it — not the signal number, and not the clock — is what says "timed out".
  if [ -f "$KILLSTAMP" ]; then RC=124; fi
  rm -f "$KILLSTAMP" 2>/dev/null
fi

OUT=$(cat "$OUTFILE" 2>/dev/null)
rm -f "$OUTFILE" 2>/dev/null

# The sync's output, folded into one JSON string value. Spec 007be gave this a second caller (the
# deferral branch below) and therefore a name: two hand-written copies of an escaping pipeline is
# two chances to fix one of them and ship malformed JSON from the other, on a hook whose stdout IS
# the JSON channel. Escapes the quote, turns each line ending into a literal \n, then collapses the
# real newlines.

# Classify the run BEFORE reading its output. A sync killed mid-flight has
# usually already printed its "[synced]" header, so matching the output first
# would report a dead run as a completed one — the exact confusion this hook
# was fixed to stop.
case "$RC" in
  0)            VERDICT="completed" ;;
  124|137|143)  VERDICT="timeout" ;;
  *)            VERDICT="other" ;;
esac

# Spec 007be. Refined from the OUTPUT, and only for a run that already classified as completed —
# after the exit code, never instead of it. A sync killed mid-flight has usually already printed
# a header, and reading its partial output first is the exact confusion the block above was fixed
# to stop; a deferral is a decision a finished run made, so a killed run is a timeout whatever
# its output happened to say by the time it died.
if [ "$VERDICT" = "completed" ]; then
  case "$OUT" in *"[deferred]"*) VERDICT="deferred" ;; esac
fi

# SPEC 046 — each branch below is real news for the developer (files moved on
# disk, a sync stopped halfway), so each keeps the developer's channel. What it
# loses is the BODY: $OUT lists one rewritten file per line, and the UI renders
# one notification per line, so "9 files synced" arrived as nine red warnings.
# notice_both sends the headline to the person and the file list to Claude,
# which is the half that actually has to act on which files changed.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hook-notice.sh"

# Written AFTER the run, and carrying which kind of run it was. Writing it
# first is what let a sync that never finished suppress its own retries.
case "$VERDICT" in
  timeout)  echo timeout  > "$MARKER" 2>/dev/null ;;
  deferred) echo deferred > "$MARKER" 2>/dev/null ;;
  *)        echo ok       > "$MARKER" 2>/dev/null ;;
esac

if [ "$VERDICT" = "timeout" ]; then
  notice_both SessionStart \
    "Template auto-sync timed out after ${LIMIT}s and was stopped — it may have changed some files and not others." \
    "Template auto-sync timed out after ${LIMIT} s and was stopped, so it may have changed some files and not others. It runs again at the first session start after ${BACKOFF} s. If it keeps timing out, run scripts/template-autosync.sh by hand to see where it sticks."
  exit 0
fi

# Any other failure stays silent: this hook names the timeout, and making every
# failure loud is a separate trade-off nobody has asked for.
[ "$VERDICT" = "other" ] && exit 0

# Spec 007be. Above the [synced] gate because a deferral prints [deferred] INSTEAD of it, so the
# gate would drop it on the floor — measured, and it is the whole reason this branch exists: with
# the pre-007be hook a deferred sync reached the developer as nothing at all.
#
# Forwarded verbatim and with no epilogue. The block already says what was withheld, that the
# stamp is unchanged so the next session start picks it up, and which flag overrides it; the
# "Config files changed on disk" paragraph below would be false here, because none did.
if [ "$VERDICT" = "deferred" ]; then
  notice_both SessionStart \
    "Template auto-sync deferred on this project." \
    "Template auto-sync deferred on this project.
$OUT"
  exit 0
fi

# Spec 007bi. Above BOTH gates below, for the same reason 007be's deferral branch is above the
# first one: the [eol] note is emitted during template resolution, before the sync knows whether it
# will write anything, and both gates would drop it.
#
#   - The [synced] gate drops it whenever the stamp already matches and the sync takes the
#     `[ok] already at template` early exit.
#   - The "0 updated, 0 added" gate drops it in the steady state of exactly the clone this note
#     exists for: the divergent bytes were copied on some earlier run, so a later sync legitimately
#     writes nothing and reports 0/0 — and the warning that the template clone is producing hashes
#     no project can ever match goes to nobody.
#
# So the note reaches --check and --dry-run (where a developer is already looking for trouble) and
# not SessionStart (where nobody runs --check). Forwarded before either gate, with the sync's own
# text: the block already names the files and the one command that fixes the clone.
case "$OUT" in
  *"[eol]"*)
    notice_both SessionStart \
      "Template auto-sync: the template clone is byte-divergent." \
      "Template auto-sync: the template clone is byte-divergent.
$OUT"
    exit 0
    ;;
esac

case "$OUT" in
  *"[synced]"*) ;;                   # the sync ran
  *) exit 0 ;;                       # up to date / skipped — stay silent
esac

# A run that wrote nothing is not news. Only speak when files actually moved —
# otherwise every session start after a template no-op costs context for nothing.
case "$OUT" in
  *"0 updated, 0 added"*) exit 0 ;;
esac

notice_both SessionStart \
  "Template auto-sync updated this project's config — see the session context for the file list." \
  "Template auto-sync ran on this project.
$OUT
Config files changed on disk. Hooks and rules reload at session start, so this session already has the new versions. If the summary lists locally-modified files that were skipped, run /project-update to merge those by hand."
exit 0
