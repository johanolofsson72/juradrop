#!/bin/bash
# next-scenario-id.sh — the next free scenario id, across every lane this clone can see.
#
# WHY THIS EXISTS (row 060). Register rows have next-register-id.sh; scenario ids had nothing, so
# every spec picked its range by eye and every parallel merge collided. agentcrm measured 47
# colliding ids on 2026-09-21: 26 from specs 052 and 055 both taking ids 1625..1650 in one
# window, the rest spread over 017/017b, 008b/022, 055/063. The same defect produced S1 (104 ids
# renumbered) and S2 (13). A cleanup without an allocator recreates it at the next parallel spec.
#
# Reads the map the way the gates do — table rows whose first cell is an id, struck rows
# (`~~SC-nnn~~`) included because a retired id is never reused — in the working tree AND in every
# local and remote-tracking branch (scripts/max-id-in-refs.sh). Appends past the highest; never
# fills a gap, for the same reason next-register-id.sh does not.
#
# Width follows the highest id, three digits minimum, and simply grows past 999 (row 048: a map
# that outgrew three digits gets a four-digit id, not a refusal).
#
# Take the ids BEFORE writing the map rows, and push the spec branch once they are in: an unpushed
# branch is the one place this cannot look.
#
# Usage:
#   bash scripts/next-scenario-id.sh              # one past the highest id
#   bash scripts/next-scenario-id.sh --count 12   # a block for one spec
#   bash scripts/next-scenario-id.sh --prefix UC  # a map with its own prefix
#
# Exit: 0 with ids on stdout · 2 usage
set -uo pipefail
export LC_ALL=C

COUNT=1; PREFIX="SC"; DIR="."
while [ $# -gt 0 ]; do
  case "$1" in
    --count)  COUNT="${2:-}"; shift 2 || { echo "next-scenario-id.sh: --count needs a number" >&2; exit 2; } ;;
    --prefix) PREFIX="${2:-}"; shift 2 || { echo "next-scenario-id.sh: --prefix needs a value" >&2; exit 2; } ;;
    --dir)    DIR="${2:-.}"; shift 2 || { echo "next-scenario-id.sh: --dir needs a path" >&2; exit 2; } ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "next-scenario-id.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$COUNT" in ''|*[!0-9]*) echo "next-scenario-id.sh: --count wants an integer" >&2; exit 2 ;; esac
[ "$COUNT" -ge 1 ] || { echo "next-scenario-id.sh: --count must be >= 1" >&2; exit 2; }
case "$PREFIX" in ''|*[!A-Za-z]*) echo "next-scenario-id.sh: --prefix is letters only" >&2; exit 2 ;; esac

MAX=$(bash "$(dirname "$0")/max-id-in-refs.sh" --dir "$DIR" \
        --regex "^\| *(~~)?${PREFIX}-[0-9]+" -- 'specs/SCENARIOS*.md' 'specs/scenarios/*.md')
WIDTH=${#MAX}; [ "$WIDTH" -ge 3 ] || WIDTH=3
N=$(printf '%s' "$MAX" | sed 's/^0*//'); N=$(( ${N:-0} + 1 ))
i=0
while [ "$i" -lt "$COUNT" ]; do
  printf '%s-%0*d\n' "$PREFIX" "$WIDTH" "$((N + i))"
  i=$((i + 1))
done
