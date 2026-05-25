#!/usr/bin/env bash
# Per-project ROI reporter for Graphify telemetry. Reads graphify-fire.log
# and prints per-subcommand fire counts, ok%, average argument size, and
# average response size — the same shape as local-llm-stats.sh so they
# read side-by-side.
#
# Usage:
#   scripts/graphify-stats.sh                 # this project
#   scripts/graphify-stats.sh --all           # aggregate across ~/repos/* and ~/Projects/*
#   GRAPHIFY_TELEMETRY_LOG=path scripts/graphify-stats.sh

set -uo pipefail

if [ "${1:-}" = "--all" ]; then
  TOTAL=0
  printf '%-50s %6s %6s %s\n' "project" "fires" "ok%" "avg_resp"
  printf '%s\n' "-------------------------------------------------- ------ ------ --------"
  for ROOT in "$HOME/repos" "$HOME/Projects"; do
    [ -d "$ROOT" ] || continue
    for D in "$ROOT"/*/; do
      LOG="$D/.claude/graphify-fire.log"
      [ -f "$LOG" ] || continue
      LINE=$(awk -F'\t' '
        { n++; ok += ($3==0); resp += $5 }
        END {
          if (n>0) printf "%d\t%.0f\t%.0f", n, (ok/n)*100, (resp/n)
        }' "$LOG" 2>/dev/null)
      [ -n "$LINE" ] || continue
      printf '%-50s %6s %5s%% %8s\n' "$(basename "$D")" $(printf '%s' "$LINE" | tr '\t' ' ')
      TOTAL=$((TOTAL + $(printf '%s' "$LINE" | cut -f1)))
    done
  done
  printf '%s\n' "-------------------------------------------------- ------ ------ --------"
  printf 'total fires across all projects: %d\n' "$TOTAL"
  exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG="${GRAPHIFY_TELEMETRY_LOG:-$PROJECT_ROOT/.claude/graphify-fire.log}"

if [ ! -f "$LOG" ]; then
  printf 'No graphify telemetry log at %s\n' "$LOG"
  printf 'Either the hook hasn'\''t fired yet, or telemetry is disabled.\n'
  exit 0
fi

printf 'Reading: %s\n\n' "$LOG"
printf '%-12s %6s %5s %10s %12s\n' "subcmd" "fires" "ok%" "avg_arg" "avg_resp"
printf '%s\n' "------------ ------ ----- ---------- ------------"

awk -F'\t' '
  { hooks[$2]++; ok[$2] += ($3==0); arg[$2] += $4; resp[$2] += $5; total++ }
  END {
    for (h in hooks) {
      printf "%-12s %6d %4d%% %10.0f %12.0f\n",
        h, hooks[h], (ok[h]/hooks[h])*100, arg[h]/hooks[h], resp[h]/hooks[h]
    }
    print ""
    printf "total fires: %d\n", total
  }
' "$LOG" | sort -k2 -rn -t' '

# Graph size snapshot (from the most recent line — the schema records
# node/edge counts at every fire so the freshest values are at the tail).
LAST=$(tail -1 "$LOG" 2>/dev/null)
if [ -n "$LAST" ]; then
  NODES=$(printf '%s' "$LAST" | awk -F'\t' '{print $6}')
  EDGES=$(printf '%s' "$LAST" | awk -F'\t' '{print $7}')
  if [ "${NODES:-0}" -gt 0 ] 2>/dev/null; then
    printf '\ngraph state (last sample): %s nodes, %s edges\n' "$NODES" "$EDGES"
  fi
fi
