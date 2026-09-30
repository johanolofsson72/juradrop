#!/bin/bash
# checkpoint-cadence.sh — how many feature specs since the last integration checkpoint?
#
# WHY THIS EXISTS. .claude/rules/spec-hardening.md asks for an integration-hardening checkpoint
# after every 5 completed specs. Two readers enforced it, and both computed `DONE % 5` over every
# ticked row. That counted the checkpoint rows themselves (H1, H2) and carved rows (016a, "carved
# by …") as feature specs: fundit was told "checkpoint due" at 20 done with four feature specs
# ticked since H2 (F211, spec 068). The modulo also failed the other way — at 21 done the alarm went
# quiet, so a checkpoint skipped at a multiple of 5 was never mentioned again.
#
# One engine, two readers (spec-register-orientation-hook.sh, project-maintenance.sh). Neither
# recomputes; two readers of one question that could answer differently is the silent disagreement
# maintenance-due.sh was written to prevent.
#
# WHAT COUNTS. A ticked row below the last ticked checkpoint row (file order), that is not:
#   a checkpoint  id H<digit>…, or track field (field 3) "checkpoint"
#   a carve       id NNN<letters> (016a), or "carved by <id>" on the row
#   standing      track field "standing" / "stående" (the T0 pointer row)
# The track is read from field 3 only: a slug must not be able to decide what a row is (SC-1444).
#
# Usage:
#   bash scripts/checkpoint-cadence.sh [--dir DIR]
# Output: one line  since=<checkpoint id|none> count=<N> due=<0|1>
# Exit:   0 due · 1 not due · 4 no register / unreadable / usage

set -uo pipefail
export LC_ALL=C

EVERY=5
DIR="."
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "checkpoint-cadence.sh: unknown argument '$1'" >&2; exit 4 ;;
  esac
done

REG="$DIR/specs/INDEX.md"
[ -r "$REG" ] || { echo "checkpoint-cadence.sh: no readable register at $REG" >&2; exit 4; }

# Every `- [x]` line, like the DONE count it replaces: a heading test would read zero on a
# register whose heading is written in Swedish. History entries never start with a checkbox.
# LC_ALL=C: awk sees the em-dash as three bytes, which is all the " — " split needs.
OUT=$(awk -v every="$EVERY" '
  /^- \[x\] / {
    line = $0
    sub(/^- \[x\] +/, "", line)
    n = split(line, f, / — /)
    id = f[1]; gsub(/[*[:space:]]/, "", id)
    track = (n >= 3) ? tolower(f[3]) : ""
    # region: skip-checkpoint
    if (id ~ /^H[0-9]/ || track ~ /checkpoint/) { since = id; count = 0; next }
    # endregion
    if (track ~ /standing|st\303\245ende/) next
    # region: skip-carved
    if (id ~ /^[0-9]+[a-z]+$/ || tolower($0) ~ /carved by /) next
    # endregion
    count++
  }
  END {
    if (since == "") since = "none"
    due = 0
    # region: due-at-least
    if (count >= every) due = 1
    # endregion
    printf "since=%s count=%d due=%d\n", since, count, due
  }' "$REG") || { echo "checkpoint-cadence.sh: could not read $REG" >&2; exit 4; }

printf '%s\n' "$OUT"
case "$OUT" in *due=1) exit 0 ;; *) exit 1 ;; esac
