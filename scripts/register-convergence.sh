#!/bin/bash
# register-convergence.sh — does this register close faster than it grows?
#
# WHY THIS EXISTS. A register is a branching process: working a row produces some
# number of new rows. Below 1.0 the backlog drains; above 1.0 it grows without
# bound however fast you work, because the work is what makes the rows. Nothing
# measured this until 2026-09-03, when five projects were measured at once and
# rocky came back at 2.40 — 96 rows added against 40 ticked in three weeks.
#
# consultpilot is the control: same project, same developer, same tooling, 0.72
# in July and 1.42 in August. The gates got good at finding things faster than
# the pipeline could close them, and no rule anywhere said stop.
#
# WHAT IT MEASURES. Walks specs/INDEX.md through git history, samples one commit
# per day, and computes over the trailing window:
#     ratio = rows added / rows ticked
# Reports the verdict per .claude/rules/carve-budget.md and exits with it, so a
# scheduler or a hook can branch.
#
# Usage:
#   bash scripts/register-convergence.sh [--dir DIR] [--window N] [--json] [--quiet]
#
#   --window N   trailing window in ticked rows (default 10; the rule's threshold
#                only applies at 10+, because a ratio over three ticks is noise)
#   --json       machine-readable one-liner
#   --quiet      print only when the verdict is flat or diverging
#
# Exit: 0 converging · 1 flat · 2 diverging · 3 not enough history · 4 usage/no register

set -uo pipefail

# A Swedish (or any comma-decimal) locale makes awk print "1,23" and then parse it
# back as 1 — so a diverging register reported a ratio of 1,23 and the verdict
# "converging" in the same line. Numbers here are compared, not read aloud; pin the
# numeric locale for the whole script.
export LC_NUMERIC=C LC_ALL=C

DIR="."; WINDOW=10; JSON=0; QUIET=0
# The rule's thresholds. Kept here as the single definition so the script and the
# rule cannot drift apart silently.
FLAT_AT="1.0"; DIVERGE_AT="1.3"

CARVES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    --window) WINDOW="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --carves) CARVES=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "register-convergence.sh: unknown argument '$1'" >&2; exit 4 ;;
  esac
done

# ── the two rules the ratio does NOT measure (--carves) ──────────────────────────────────────────
#
# carve-budget.md states three limits and until now exactly one was measured:
#
#   section 5  carve ratio >= 1.3   measured above, and it is what fires the convergence stop
#   section 2  max 2 carves/spec    measured by nothing
#   section 3  no depth 3           measured by nothing
#
# David's session found both gaps on agentcrm by hand on 2026-09-04: S11 carved SIX rows in one run
# against a budget of two, and S6 -> S9 -> S11 -> S18 sits at depth 3. His report also named why
# nothing caught it -- "Ingen rad bär (d2)-markör". The rule asks the author to write the depth onto
# the row, and a rule that depends on remembering to annotate has an expiry date; that is the same
# lesson archive-completed-rows.sh records about a row archive built by hand twice and then forgotten.
#
# So depth is DERIVED from the attribution rather than trusted from a marker. The engine is
# scripts/carve_audit.py -- a separate file, not an inline heredoc, because this script is itself
# read through heredocs by three test harnesses.
if [ "$CARVES" -eq 1 ]; then
  REG_FILE="$DIR/specs/INDEX.md"
  [ -f "$REG_FILE" ] || { echo "register-convergence: no register at $REG_FILE" >&2; exit 4; }
  AUDIT="$(dirname "$0")/carve_audit.py"
  [ -f "$AUDIT" ] || { echo "register-convergence: scripts/carve_audit.py is missing" >&2; exit 4; }
  REG="$REG_FILE" BUDGET="${SPEC_CARVE_BUDGET:-2}" python3 "$AUDIT"
  exit $?
fi

case "$WINDOW" in ''|*[!0-9]*) echo "register-convergence.sh: --window wants an integer" >&2; exit 4 ;; esac
[ "$WINDOW" -ge 1 ] || { echo "register-convergence.sh: --window must be >= 1" >&2; exit 4; }

ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || {
  echo "register-convergence.sh: not a git repository: $DIR" >&2; exit 4; }
REG="$ROOT/specs/INDEX.md"
[ -f "$REG" ] || { echo "register-convergence.sh: no specs/INDEX.md under $ROOT" >&2; exit 4; }

# One sample per calendar day, newest first. A register touched twenty times in a
# day would otherwise weight that day twenty-fold, and the ratio is a property of
# the project's week, not of how often the file was saved.
#
# 400 commits is a deliberate ceiling: it bounds a `git show` per commit on a repo
# with thousands of register touches, and no window this script offers needs more.
# `mapfile` is bash 4+; macOS ships bash 3.2 and cross-platform is a base
# requirement here, so this reads the log with a plain while-read.
#
# The walk is LAZY on purpose. It samples newest-first and stops the moment the
# window's worth of ticks is covered, because this runs at SessionStart: reading
# 400 revisions of a 359 KB register (rocky) costs minutes, and a check that slow
# gets switched off. A converging register needs a handful of `git show` calls.
#
# 400 is the ceiling for the pathological case — a register that ticks nothing —
# so the walk terminates on a project that never closes a row.
seen=""
NOW_DATE=""; NOW_TOTAL=0; NOW_DONE=0
BASE_DATE=""; BASE_TOTAL=0; BASE_DONE=0
samples=0
while IFS=' ' read -r sha date; do
  [ -n "$sha" ] || continue
  case " $seen " in *" $date "*) continue ;; esac
  seen="$seen $date"
  body=$(git -C "$ROOT" show "${sha}:specs/INDEX.md" 2>/dev/null) || continue
  total=$(printf '%s\n' "$body" | grep -cE '^- \[[ x/!]\]' || true)
  done_n=$(printf '%s\n' "$body" | grep -cE '^- \[x\]' || true)
  : "${total:=0}" "${done_n:=0}"
  samples=$((samples + 1))
  if [ "$samples" -eq 1 ]; then
    NOW_DATE="$date"; NOW_TOTAL="$total"; NOW_DONE="$done_n"
    BASE_DATE="$date"; BASE_TOTAL="$total"; BASE_DONE="$done_n"
    continue
  fi
  BASE_DATE="$date"; BASE_TOTAL="$total"; BASE_DONE="$done_n"
  [ $((NOW_DONE - BASE_DONE)) -ge "$WINDOW" ] && break
done <<SAMPLES
$(git -C "$ROOT" log --format='%H %ad' --date=short -- specs/INDEX.md 2>/dev/null | head -400)
SAMPLES

[ "$samples" -ge 2 ] || { echo "register-convergence.sh: register has too little history"; exit 3; }

ADDED=$((NOW_TOTAL - BASE_TOTAL))
TICKED=$((NOW_DONE - BASE_DONE))
OPEN_NOW=$((NOW_TOTAL - NOW_DONE))
OPEN_BASE=$((BASE_TOTAL - BASE_DONE))

# A register that ticked nothing in the window has no ratio to report — dividing by
# zero here would print "infinity" for a project that simply had a quiet week, which
# is the false alarm that teaches people to ignore the whole check.
if [ "$TICKED" -le 0 ]; then
  [ "$QUIET" -eq 1 ] || echo "register-convergence: no rows ticked since $BASE_DATE — nothing to measure"
  exit 3
fi

# A NEGATIVE delta is not a ratio, it is a batch or a cut.
#
# carve-budget.md section 2 tells a spec to fold its excess findings into one row, and section 7
# allows a row to be deleted outright. Both REMOVE rows, so ADDED goes negative — and `a/t` then
# prints something like "-0.45", which reads as a broken instrument rather than as the register
# doing exactly what the rule asked. Measured on ighweld-2026 on 2026-09-04, minutes after its
# session batched its light rows: -5 added over 11 ticked, 52 open down to 36. The best outcome the
# rule can produce rendered as its most confusing number.
if [ "$ADDED" -lt 0 ]; then
  REMOVED=$(( -ADDED ))
  [ "$QUIET" -eq 1 ] || echo "register-convergence: CLOSING — $REMOVED row(s) folded or cut and $TICKED ticked since $BASE_DATE, $OPEN_BASE → $OPEN_NOW open. No ratio: the register shrank."
  [ "$JSON" -eq 1 ] && printf '{"verdict":"closing","ratio":null,"added":%d,"ticked":%d,"open_now":%d,"open_base":%d,"from":"%s","to":"%s"}\n' \
    "$ADDED" "$TICKED" "$OPEN_NOW" "$OPEN_BASE" "$BASE_DATE" "$NOW_DATE"
  exit 0
fi
RATIO=$(awk -v a="$ADDED" -v t="$TICKED" 'BEGIN{printf "%.2f", a/t}')

# The threshold only bites at a real window. Under it, report the number and stay quiet:
# a 2.0 over two ticked rows is one busy afternoon, not a diverging project.
if [ "$TICKED" -lt 10 ]; then
  VERDICT="thin"; CODE=0
elif awk -v r="$RATIO" -v d="$DIVERGE_AT" 'BEGIN{exit !(r>=d)}'; then
  VERDICT="diverging"; CODE=2
elif awk -v r="$RATIO" -v f="$FLAT_AT" 'BEGIN{exit !(r>=f)}'; then
  VERDICT="flat"; CODE=1
else
  VERDICT="converging"; CODE=0
fi

if [ "$JSON" -eq 1 ]; then
  printf '{"verdict":"%s","ratio":%s,"added":%d,"ticked":%d,"open_now":%d,"open_base":%d,"from":"%s","to":"%s"}\n' \
    "$VERDICT" "$RATIO" "$ADDED" "$TICKED" "$OPEN_NOW" "$OPEN_BASE" "$BASE_DATE" "$NOW_DATE"
  exit "$CODE"
fi

if [ "$QUIET" -eq 1 ] && [ "$CODE" -eq 0 ]; then exit "$CODE"; fi

case "$VERDICT" in
  converging) echo "register-convergence: converging — ratio $RATIO ($ADDED added / $TICKED ticked since $BASE_DATE), $OPEN_BASE → $OPEN_NOW open" ;;
  thin)       echo "register-convergence: only $TICKED ticked since $BASE_DATE — ratio $RATIO, too thin to judge" ;;
  flat)       echo "register-convergence: FLAT — ratio $RATIO ($ADDED added / $TICKED ticked since $BASE_DATE), $OPEN_BASE → $OPEN_NOW open. Closing about as fast as it grows." ;;
  diverging)
    cat <<MSG
register-convergence: DIVERGING — ratio $RATIO ($ADDED added / $TICKED ticked since $BASE_DATE), $OPEN_BASE → $OPEN_NOW open.

The register grows faster than it closes. Per .claude/rules/carve-budget.md this is a
convergence stop: finish the current spec, then put the three ways out to the developer
(freeze carving · batch the open spec-only rows · cut what no longer matters).
MSG
    ;;
esac
exit "$CODE"
