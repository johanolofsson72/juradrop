#!/bin/bash
# PostToolUse hook on Edit/Write (also callable by hand): keeps a one-line-per-event
# run log per spec at <spec-dir>/run-log.md.
#
# WHY THIS EXISTS — failure memory across /clear.
# Pipeline state is already derived from artifacts on disk (pipeline-state-guard
# reads spec.md / spec.allium / plan.md / tasks.md), and artifact-derived state is
# strictly better than a self-reported PROGRESS.md because an artifact cannot lie
# about existing. But artifacts answer only "which phase am I in" — they carry no
# memory of what went WRONG on the way there. A spec that is resumed in a fresh
# session (which .claude/rules/spec-hardening.md actively encourages for full /
# hardened rows) starts blind to: the interview answer that was escalated, the
# mutation score that came back at 41%, the TLA+ gap that was deferred, the third
# failed attempt at the same integration test. That is the gap this closes.
#
# Deliberately NOT a PROGRESS.md:
#   - one LINE per event, never a paragraph — the register/scenario bloat lesson
#     (.claude/rules/spec-register.md "Keep the register lean") applies here too;
#   - append-only, capped at RUNLOG_MAX lines, and deduped against the PREVIOUS
#     line only — so editing plan.md ten times in a row logs once, but re-entering
#     an earlier phase (tasks → back to plan) IS recorded. The pipeline running
#     backwards is precisely the kind of event this log exists to remember;
#   - it is NOT pipeline input. Nothing gates on it. The orientation hook surfaces
#     only the TAIL, and only for an in-progress spec.
#
# Modes:
#   (hook)  stdin = PostToolUse payload → logs phase transitions when a pipeline
#           artifact is written (spec.md, interview.md, spec.allium, plan.md,
#           tasks.md). Deduped, so re-editing plan.md ten times logs once.
#   (cli)   spec-run-log-hook.sh --note "<text>" [--spec <dir>]
#           logs an arbitrary one-liner — a finding, a failed gate, a decision.
#
# Never blocks, never errors out loud. bash 3.2-safe, cross-platform.
# Disable with RUNLOG_DISABLE=1.

set -u

[ "${RUNLOG_DISABLE:-0}" = "1" ] && exit 0

# Spec H6s2 — code comes from beside THIS FILE, data comes from the project.
#
# The resolver used to be looked up under the project root being inspected
# ("$ROOT/scripts/resolve-active-spec.sh"), i.e. the hook went looking for its own
# sibling inside the directory of the data it was asked to read. Wherever that
# root is not also a checkout of this template — a test fixture, a project whose
# autosync was cut short before the .py pass, a bare directory — the lookup found
# nothing and the note was dropped in silence. Same split resolve-active-spec.sh
# already makes against spec_active.py, and the two PreToolUse guards against the
# module they import.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-active-spec.sh"

MAX="${RUNLOG_MAX:-60}"
STAMP=$(date -u +%Y-%m-%dT%H:%MZ 2>/dev/null || echo "unknown")

# ---------------------------------------------------------------- append core
# $1 = spec dir, $2 = line body
# Returns 0 when the line is on disk (or was deduped away against the previous
# line, which is the same outcome for the caller: the log already says it), and
# non-zero when the write did not happen. It used to `return 0` on every failure
# path, so a read-only or full disk produced the same observable as a successful
# log — H6s2 finding 2, the same shape as the CLI branch below and on the one
# path the resolver never reaches. Hook mode still ignores the return value and
# still ends on an explicit `exit 0`: nothing here can block a session.
append_line() {
  _dir="$1"; _body="$2"
  [ -d "$_dir" ] || return 1
  _log="$_dir/run-log.md"
  _slug=$(basename "$_dir")

  if [ ! -f "$_log" ]; then
    {
      printf '# Run log — %s\n\n' "$_slug"
      printf 'One line per event. Failure memory for a spec resumed in a fresh session.\n'
      printf 'Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.\n\n'
    } > "$_log" 2>/dev/null || return 1
  fi

  # Dedupe: identical body as the last entry → no new line (guards that deny
  # repeatedly, or a file edited five times in a row, log once).
  _last=$(grep -E '^- ' "$_log" 2>/dev/null | tail -1 | sed 's/^- [^·]*· //')
  [ "$_last" = "$_body" ] && return 0

  printf -- '- %s · %s\n' "$STAMP" "$_body" >> "$_log" 2>/dev/null || return 1

  # Cap: keep the header + the newest $MAX entries.
  _count=$(grep -cE '^- ' "$_log" 2>/dev/null | tr -dc '0-9')
  case "$_count" in (''|*[!0-9]*) _count=0 ;; esac
  if [ "$_count" -gt "$MAX" ]; then
    _tmp="$_log.tmp.$$"
    {
      grep -vE '^- ' "$_log" 2>/dev/null
      grep -E '^- ' "$_log" 2>/dev/null | tail -n "$MAX"
    } > "$_tmp" 2>/dev/null && mv "$_tmp" "$_log" 2>/dev/null
    rm -f "$_tmp" 2>/dev/null
  fi
  # NOTE: a failed cap is deliberately NOT a failure. The line is already on
  # disk; the file is merely longer than MAX. The caller asked for the note to be
  # recorded and it was.
  return 0
}

# ------------------------------------------------------- spec dir from a path
# Echoes the spec directory for a file path inside specs/<id>-<slug>/ or
# .specify/specs/<id>-<slug>/, or nothing.
spec_dir_of() {
  case "$1" in
    */specs/*) ;;
    *) return 0 ;;
  esac
  _d=$(dirname "$1")
  # Walk up until the parent is a `specs` directory.
  while [ "$_d" != "/" ] && [ -n "$_d" ]; do
    if [ "$(basename "$(dirname "$_d")")" = "specs" ]; then
      case "$(basename "$_d")" in
        [0-9]*|H[0-9]*) printf '%s' "$_d"; return 0 ;;
      esac
      return 0
    fi
    _d=$(dirname "$_d")
  done
  return 0
}

# ------------------------------------------------------------------- CLI mode
#
# Spec H6s2 — this branch has three outcomes and used to report one.
#
# "Never errors out loud" (see the header) is a rule about the PostToolUse path,
# where a hook that interferes is worse than a hook that misses. It was applied
# here too, and a CLI a human or an agent typed has no other channel: not writing
# the note looked exactly like writing it — exit 0, no output — in the one script
# whose whole purpose is failure memory across /clear.
#
#   exit 0  the note was recorded (or deduped against the previous line)
#   exit 3  an ANSWER, nothing to record: no register, or every row ticked
#   exit 4  cannot answer: no resolver, no python3, unreadable register, no dir
#
# The codes are spec_active.py's own contract rather than a second grammar, and
# every non-zero path says on stderr WHICH of them fired — "could not log" has no
# fix, "spec_active.py missing" has one. Nothing here writes to stdout, and
# nothing here blocks: stderr and an exit code cannot stop a session.
_note_stop() {  # $1 message, $2 exit code
  printf 'spec-run-log-hook: %s\n' "$1" >&2
  exit "$2"
}

if [ "${1:-}" = "--note" ]; then
  NOTE="${2:-}"
  [ -z "$NOTE" ] && exit 0        # caller passed no text; nothing was asked of us
  DIR=""
  [ "${3:-}" = "--spec" ] && DIR="${4:-}"
  if [ -n "$DIR" ]; then
    # append_line answers a missing directory with a silent `return 0`, which is
    # right for hook mode and wrong for a hand-typed path with a typo in it.
    [ -d "$DIR" ] || _note_stop "spec directory does not exist: $DIR — note NOT recorded" 4
  else
    # Resolve the active spec from the register: the "- [/]" row, else the first "- [ ]".
    ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
    while [ "$ROOT" != "/" ] && [ -n "$ROOT" ]; do
      [ -d "$ROOT/.git" ] && break
      ROOT=$(dirname "$ROOT")
    done
    REG="$ROOT/specs/INDEX.md"
    [ -f "$REG" ] || _note_stop "no specs/INDEX.md under $ROOT — note NOT recorded" 3
    [ -f "$RESOLVER" ] || _note_stop \
      "cannot resolve the active spec: $RESOLVER not found — note NOT recorded" 4
    # Spec 007m — resolve through the ONE canonical resolver instead of parsing
    # the register here. This block used to rebuild the path as "$ID-$SLUG",
    # which is a fifth independent opinion about which spec is active and breaks
    # on any row whose slug is formatted (bold, parenthesised). The resolver
    # globs "<id>-*" and is the same code the guards use.
    #
    # Deliberately NO fallback to inline parsing when the resolver cannot answer:
    # that is the fifth opinion coming back through the side door, silent and
    # reachable only on the degraded path. Say you cannot answer instead.
    RC=0
    OUT=$(bash "$RESOLVER" --root "$ROOT" 2>&1) || RC=$?
    case "$RC" in
      0) : ;;
      3) _note_stop "no active spec row in $REG (every row ticked) — note NOT recorded" 3 ;;
      *) _note_stop "cannot resolve the active spec (resolver exit $RC): ${OUT:-no output} — note NOT recorded" 4 ;;
    esac
    DIR_REL=$(printf '%s' "$OUT" | sed -n 's/.*"dir": *"\([^"]*\)".*/\1/p')
    [ -z "$DIR_REL" ] && _note_stop \
      "cannot resolve the active spec: resolver named no directory — note NOT recorded" 4
    [ -d "$ROOT/$DIR_REL" ] || _note_stop \
      "spec directory does not exist: $ROOT/$DIR_REL — note NOT recorded" 4
    DIR="$ROOT/$DIR_REL"
  fi
  append_line "$DIR" "$NOTE" \
    || _note_stop "could not write the note to $DIR/run-log.md — note NOT recorded" 4
  exit 0
fi

# ------------------------------------------------------------------ hook mode
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -z "$FILE" ] && exit 0

BASE=$(basename "$FILE")
case "$BASE" in
  spec.md)      EVENT="specify · spec.md written" ;;
  interview.md) EVENT="interview · interview.md written" ;;
  *.allium)     EVENT="allium:elicit · $BASE written" ;;
  plan.md)      EVENT="plan · plan.md written" ;;
  tasks.md)     EVENT="tasks · tasks.md written" ;;
  *) exit 0 ;;
esac

SPEC_DIR=$(spec_dir_of "$FILE")
[ -n "$SPEC_DIR" ] && append_line "$SPEC_DIR" "$EVENT"

# Spec 007m FR-007m-05 — refresh .specify/feature.json from the register.
#
# A pipeline artifact was just written, which is exactly the moment a spec
# becomes "the active one". Session start covers the usual case; this covers a
# spec started MID-session, so spec-kit's check-prerequisites.sh cannot spend
# the rest of the spec pointing at the previous one — the defect register row
# 007m was opened for. Idempotent: writes only when it disagrees.
_RL_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
while [ "$_RL_ROOT" != "/" ] && [ -n "$_RL_ROOT" ]; do
  [ -d "$_RL_ROOT/.git" ] && break
  _RL_ROOT=$(dirname "$_RL_ROOT")
done
# Spec 007q — the refresh that used to sit here has moved out.
#
# H6s2 fixed WHERE this call looked for the resolver. 007q is about WHEN it was
# reached at all: everything above returns early unless the written basename is
# one of five, so a spec.md produced by a heredoc, a script, an editor outside
# the session, or a git checkout refreshed nothing. A refresh bolted to the tail
# of a LOGGING hook is a refresh nobody audits — which is how it kept both a
# gating bug and a coverage bug in plain sight.
#
# It now has its own file: scripts/sync-feature-json-hook.sh, wired to
# SessionStart and to PostToolUse for Write/Edit AND Bash. Do not re-add it here;
# this hook keeps one job, which is the run log.
exit 0
