#!/bin/sh
# maintenance-due.sh — "what does this project owe, and what made it owe it?"
#
# WHY THIS EXISTS. Every recurring check in this template had exactly two settings: run it by hand
# during the day, or put it on a nightly cron. Both fail in the same way from opposite ends. By hand
# means it competes with the work — agentcrm's integration suite grew the test host to 11.5 GB over
# 45 minutes and OOM-killed a session at 14:00 on 2026-09-01. On a cron it runs whether or not there
# is anything to do, on a laptop that sleeps through 02:00, and cron does not catch up a job it
# missed. Seven jobs were scheduled on 2026-09-03 and not one had produced a log by the next morning.
#
# The project already knew how to do this properly, for exactly one job.
# spec-register-orientation-hook.sh:201 computes `DONE % 5` and says an integration-hardening
# checkpoint is due. That is the whole idea, working, since spec-hardening.md was written. The other
# five recurring jobs had no equivalent because the primitive underneath was missing:
# project-maintenance.sh never recorded that it ran, so nothing could ask "how long since".
#
# WHAT IS DUE IS NOT A CLOCK. Each job is triggered by whatever actually invalidates it:
#
#   secrets + CVEs      days          a published advisory arrives on the world's schedule, not yours
#   mutation gate       ticked specs  a kill rate is invalidated by code landing, and specs land code
#   full test suite     ticked specs  a green suite ages the moment the next spec is pushed
#   register similarity rows added    it is a duplicate-row detector; rows are its input
#
# A time trigger on the mutation gate would fire on a week you wrote nothing, and stay silent through
# a week of five specs. That is the cron failure again, wearing a different hat.
#
# THIS SCRIPT DECIDES NOTHING AND RUNS NOTHING. It reads state and reports. Three readers share it —
# the SessionStart banner, the per-spec status summary, and `project-maintenance.sh --if-due` — for
# the reason .claude/rules/lane-handoff.md gives about lane status: two readers of one question that
# could answer differently is worse than either being wrong, because the disagreement is silent.
#
# Usage:
#   bash scripts/maintenance-due.sh              # full report
#   bash scripts/maintenance-due.sh --brief      # one line per due job, nothing when clean
#   bash scripts/maintenance-due.sh --any        # exit 0 if anything is due, 1 if not (no output)
#   bash scripts/maintenance-due.sh --stamp JOB  # record that JOB just ran
#   bash scripts/maintenance-due.sh --state      # dump the state file as it stands
#
# Exit: 0 something is due (or the report printed) · 1 nothing due (--any only) · 2 could not run

set -u
export LC_ALL=C

MODE=full
STAMP_JOB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --brief) MODE=brief; shift ;;
    --any)   MODE=any;   shift ;;
    --state) MODE=state; shift ;;
    --stamp) MODE=stamp; STAMP_JOB="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "maintenance-due.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT="$PWD"
STATE="$ROOT/.claude/.maintenance-state"
REG="$ROOT/specs/INDEX.md"

# The register is the clock for every work-driven trigger. Counted the same way the orientation hook
# counts it, deliberately: two places that disagree about "how many specs are done" would disagree
# about what is due.
DONE=0
[ -f "$REG" ] && DONE=$(grep -cE '^- \[x\]' "$REG" 2>/dev/null || echo 0)
ROWS=0
[ -f "$REG" ] && ROWS=$(grep -cE '^- \[[ xX/!]\]' "$REG" 2>/dev/null || echo 0)
case "$DONE" in ''|*[!0-9]*) DONE=0 ;; esac
case "$ROWS" in ''|*[!0-9]*) ROWS=0 ;; esac

TODAY=$(date +%Y-%m-%d)
today_days() { python3 -c 'import datetime,sys; print(datetime.date.fromisoformat(sys.argv[1]).toordinal())' "$1" 2>/dev/null || echo 0; }
TODAY_N=$(today_days "$TODAY")

# job | trigger kind | threshold | label
# Thresholds are the ones the rules already state, not new numbers:
#   mutation 5   — .claude/rules/spec-hardening.md, the every-5 checkpoint cadence
#   suite    1   — CLAUDE.md's Definition of Done: a spec is not done until the suite is green,
#                  so one ticked spec is exactly what makes the whole-project suite stale
#   secrets  7   — .claude/rules/github-actions.md calls the local pass weekly
#   similar 10   — .claude/rules/carve-budget.md runs it "as part of the periodic maintenance pass"
JOBS='findings|specs|5|findings review (decide what becomes a row — scripts/finding.sh --list)
secrets|days|7|secrets + dependency CVEs
suite|specs|1|full test suite (unit + integration + E2E + visual regression)
mutation|specs|5|mutation kill rate (Stryker)
similarity|rows|10|register similarity (duplicate-row scan)'

state_get() { # $1 job -> "date<TAB>done<TAB>rows", empty when never run
  [ -f "$STATE" ] || return 0
  awk -F'\t' -v j="$1" '$1==j {print $2"\t"$3"\t"$4; found=1} END{exit !found}' "$STATE" 2>/dev/null
}

if [ "$MODE" = state ]; then
  if [ -f "$STATE" ]; then cat "$STATE"; else echo "(no state file at $STATE — nothing has been stamped)"; fi
  exit 0
fi

if [ "$MODE" = stamp ]; then
  [ -n "$STAMP_JOB" ] || { echo "maintenance-due.sh: --stamp needs a job name" >&2; exit 2; }
  printf '%s\n' "$JOBS" | grep -q "^$STAMP_JOB|" || {
    echo "maintenance-due.sh: unknown job '$STAMP_JOB' — known: $(printf '%s\n' "$JOBS" | cut -d'|' -f1 | tr '\n' ' ')" >&2
    exit 2; }
  mkdir -p "$ROOT/.claude" || exit 2
  TMP="$STATE.tmp.$$"
  # Rewrite rather than append: an append-only stamp file grows without bound and the newest entry
  # would win only by luck of the awk order.
  { [ -f "$STATE" ] && grep -v "^$STAMP_JOB	" "$STATE" 2>/dev/null; printf '%s\t%s\t%s\t%s\n' "$STAMP_JOB" "$TODAY" "$DONE" "$ROWS"; } > "$TMP" 2>/dev/null
  mv "$TMP" "$STATE" 2>/dev/null || { rm -f "$TMP"; exit 2; }
  exit 0
fi

DUE_COUNT=0
DUE_TEXT=""
NEVER_TEXT=""

OLDIFS=$IFS
IFS='
'
for line in $JOBS; do
  job=$(printf '%s' "$line" | cut -d'|' -f1)
  kind=$(printf '%s' "$line" | cut -d'|' -f2)
  thresh=$(printf '%s' "$line" | cut -d'|' -f3)
  label=$(printf '%s' "$line" | cut -d'|' -f4)

  # A findings review with an empty ledger is not due. The cadence exists to force a DECISION on
  # what accumulated; with nothing accumulated there is nothing to decide, and firing anyway would
  # make the loudest banner in the project the one that means least.
  if [ "$job" = findings ]; then
    NF=0
    [ -f "$ROOT/specs/FINDINGS.md" ] && NF=$(grep -cE '^- \[ \]' "$ROOT/specs/FINDINGS.md" 2>/dev/null | head -1)
    case "$NF" in ''|*[!0-9]*) NF=0 ;; esac
    [ "$NF" -eq 0 ] && continue
    label="$label — $NF open"
  fi

  rec=$(state_get "$job")
  if [ -z "$rec" ]; then
    # NEVER RUN IS DUE, and it says so differently. "0 days since" would be a lie about a run that
    # did not happen, and .claude/rules/mutation-timeouts.md trap 4 is exactly this: an unmeasured
    # thing and a measured-clean thing must never render identically.
    DUE_COUNT=$((DUE_COUNT + 1))
    NEVER_TEXT="$NEVER_TEXT  · $label — never run in this project
"
    continue
  fi
  last_date=$(printf '%s' "$rec" | cut -f1)
  last_done=$(printf '%s' "$rec" | cut -f2)
  last_rows=$(printf '%s' "$rec" | cut -f3)
  case "$last_done" in ''|*[!0-9]*) last_done=0 ;; esac
  case "$last_rows" in ''|*[!0-9]*) last_rows=0 ;; esac

  case "$kind" in
    days)
      n=$(today_days "$last_date"); delta=$((TODAY_N - n))
      [ "$delta" -ge "$thresh" ] && {
        DUE_COUNT=$((DUE_COUNT + 1))
        DUE_TEXT="$DUE_TEXT  · $label — $delta day(s) since $last_date (due at $thresh)
"; } ;;
    specs)
      delta=$((DONE - last_done))
      [ "$delta" -ge "$thresh" ] && {
        DUE_COUNT=$((DUE_COUNT + 1))
        DUE_TEXT="$DUE_TEXT  · $label — $delta spec(s) ticked since $last_date (due at $thresh)
"; } ;;
    rows)
      delta=$((ROWS - last_rows))
      [ "$delta" -ge "$thresh" ] && {
        DUE_COUNT=$((DUE_COUNT + 1))
        DUE_TEXT="$DUE_TEXT  · $label — $delta row(s) added since $last_date (due at $thresh)
"; } ;;
  esac
done
IFS=$OLDIFS

if [ "$MODE" = any ]; then
  [ "$DUE_COUNT" -gt 0 ] && exit 0 || exit 1
fi

if [ "$DUE_COUNT" -eq 0 ]; then
  [ "$MODE" = brief ] || echo "maintenance: nothing due — $DONE spec(s) done, $ROWS row(s) in the register."
  exit 1
fi

if [ "$MODE" = brief ]; then
  printf '⚠ MAINTENANCE DUE (%s):\n%s%s' "$DUE_COUNT" "$DUE_TEXT" "$NEVER_TEXT"
  echo "  Run now: bash scripts/project-maintenance.sh --full"
  echo "  Or defer: it stays due until it runs, so the next session says so again."
else
  echo "maintenance due — $DUE_COUNT job(s)   [$DONE spec(s) done, $ROWS row(s)]"
  echo
  printf '%s%s' "$DUE_TEXT" "$NEVER_TEXT"
  echo
  echo "Run:      bash scripts/project-maintenance.sh --full"
  echo "Deferring is safe: nothing is cleared until the job actually runs."
fi
exit 0
