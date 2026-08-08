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

MAX="${RUNLOG_MAX:-60}"
STAMP=$(date -u +%Y-%m-%dT%H:%MZ 2>/dev/null || echo "unknown")

# ---------------------------------------------------------------- append core
# $1 = spec dir, $2 = line body
append_line() {
  _dir="$1"; _body="$2"
  [ -d "$_dir" ] || return 0
  _log="$_dir/run-log.md"
  _slug=$(basename "$_dir")

  if [ ! -f "$_log" ]; then
    {
      printf '# Run log — %s\n\n' "$_slug"
      printf 'One line per event. Failure memory for a spec resumed in a fresh session.\n'
      printf 'Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.\n\n'
    } > "$_log" 2>/dev/null || return 0
  fi

  # Dedupe: identical body as the last entry → no new line (guards that deny
  # repeatedly, or a file edited five times in a row, log once).
  _last=$(grep -E '^- ' "$_log" 2>/dev/null | tail -1 | sed 's/^- [^·]*· //')
  [ "$_last" = "$_body" ] && return 0

  printf -- '- %s · %s\n' "$STAMP" "$_body" >> "$_log" 2>/dev/null || return 0

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
if [ "${1:-}" = "--note" ]; then
  NOTE="${2:-}"
  [ -z "$NOTE" ] && exit 0
  DIR=""
  [ "${3:-}" = "--spec" ] && DIR="${4:-}"
  if [ -z "$DIR" ]; then
    # Resolve the active spec from the register: the "- [/]" row, else the first "- [ ]".
    ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
    while [ "$ROOT" != "/" ] && [ -n "$ROOT" ]; do
      [ -d "$ROOT/.git" ] && break
      ROOT=$(dirname "$ROOT")
    done
    REG="$ROOT/specs/INDEX.md"
    [ -f "$REG" ] || exit 0
    ROW=$(grep -m1 -E '^- \[/\]' "$REG" 2>/dev/null || grep -m1 -E '^- \[ \]' "$REG" 2>/dev/null)
    ID=$(printf '%s' "$ROW" | sed -E 's/^- \[.\] *//' | awk '{print $1}')
    SLUG=$(printf '%s' "$ROW" | awk -F' — ' '{print $2}' | tr -d ' ')
    [ -z "$ID" ] && exit 0
    for cand in "$ROOT/specs/$ID-$SLUG" "$ROOT/.specify/specs/$ID-$SLUG"; do
      [ -d "$cand" ] && DIR="$cand" && break
    done
  fi
  [ -n "$DIR" ] && append_line "$DIR" "$NOTE"
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
exit 0
