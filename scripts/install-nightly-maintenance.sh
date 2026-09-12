#!/bin/bash
# install-nightly-maintenance.sh — give "nightly" a body.
#
# WHY THIS EXISTS. Three documents describe the mutation gate as running
# "nightly/on-demand" and .claude/rules/github-actions.md correctly bans cron
# triggers in GitHub Actions after the iskvalp incident (3000 Actions minutes in
# four days). Net effect: nightly ran never. scripts/project-maintenance.sh was
# written as the local answer and then nothing scheduled IT either -- the same
# gap one level down. This installs the schedule.
#
# It runs the slow, expensive checks -- the mutation kill rate above all -- while
# nobody is typing, which is the whole point: the gate that proves the tests bite
# takes minutes to hours, so asking for it mid-session means never asking.
#
# Costs zero GitHub Actions minutes. Runs on the developer's own machine.
#
# Usage:
#   bash scripts/install-nightly-maintenance.sh            # install for THIS project
#   bash scripts/install-nightly-maintenance.sh --at 03:30 # a different hour
#   bash scripts/install-nightly-maintenance.sh --list     # what is installed
#   bash scripts/install-nightly-maintenance.sh --remove   # take it out
#   bash scripts/install-nightly-maintenance.sh --dry-run  # print, change nothing

set -uo pipefail
export LC_ALL=C

AT="02:30"; MODE="install"; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --at) AT="${2:-}"; shift 2 ;;
    --list) MODE="list"; shift ;;
    --remove) MODE="remove"; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install-nightly-maintenance.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$AT" in
  [0-2][0-9]:[0-5][0-9]) ;;
  *) echo "install-nightly-maintenance.sh: --at wants HH:MM (24h), got '$AT'" >&2; exit 2 ;;
esac
HH=${AT%%:*}; MM=${AT##*:}
[ "$HH" -le 23 ] 2>/dev/null || { echo "install-nightly-maintenance.sh: hour out of range in '$AT'" >&2; exit 2; }
# 08 and 09 are not octal here because every arithmetic use is string-compared or
# passed to cron verbatim -- but strip the leading zero anyway so a future edit
# that does arithmetic on them cannot inherit the trap.
HH=$((10#$HH)); MM=$((10#$MM))

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "install-nightly-maintenance.sh: not inside a git repository" >&2; exit 2; }
PROJECT=$(basename "$ROOT")
LOGDIR="$HOME/.claude/nightly"
LOG="$LOGDIR/$PROJECT.log"
# The marker is what makes this idempotent and removable: it identifies OUR line
# in a crontab the developer also uses for their own things.
MARKER="# claude-nightly-maintenance:$ROOT"

if ! command -v crontab >/dev/null 2>&1; then
  cat <<MSG
install-nightly-maintenance.sh: no crontab on this machine.

On Windows (Git Bash / PowerShell) use Task Scheduler instead:

  schtasks /Create /SC DAILY /ST $AT /TN "claude-nightly-$PROJECT" ^
    /TR "C:\\Program Files\\Git\\bin\\bash.exe -lc \"cd '$ROOT' && bash scripts/project-maintenance.sh --full --suite --if-due\""

Or, on any platform, from a Claude Code session in this project:
  /loop 1d  bash scripts/project-maintenance.sh --full --suite --if-due
MSG
  exit 3
fi

current=$(crontab -l 2>/dev/null || true)

if [ "$MODE" = "list" ]; then
  printf '%s\n' "$current" | grep -F "claude-nightly-maintenance:" || echo "(no claude nightly jobs installed)"
  exit 0
fi

# Drop any existing line for THIS project. Both modes need it: remove is only this,
# and install must not stack a second entry every time it is run.
cleaned=$(printf '%s\n' "$current" | grep -vF "$MARKER" | sed '/^$/d')

if [ "$MODE" = "remove" ]; then
  if [ "$DRY" -eq 1 ]; then echo "(dry-run) would remove the nightly job for $PROJECT"; exit 0; fi
  printf '%s\n' "$cleaned" | crontab -
  echo "removed: nightly maintenance for $PROJECT"
  exit 0
fi

# `--full` is the point of running at night: it is what adds the mutation pass.
# The log is truncated per run, not appended, so a nightly job cannot quietly fill
# a disk over a year -- and the only run anyone reads is the last one.
LINE="$MM $HH * * * cd $ROOT && /bin/bash scripts/project-maintenance.sh --full --suite --if-due > $LOG 2>&1 $MARKER"

if [ "$DRY" -eq 1 ]; then
  echo "(dry-run) would install:"; echo "  $LINE"; exit 0
fi

mkdir -p "$LOGDIR"
printf '%s\n%s\n' "$cleaned" "$LINE" | sed '/^$/d' | crontab - || {
  echo "install-nightly-maintenance.sh: crontab refused the update" >&2; exit 1; }

cat <<MSG
installed: $PROJECT — nightly maintenance at $(printf '%02d:%02d' "$HH" "$MM")

  runs:  scripts/project-maintenance.sh --full --suite --if-due   (secrets + CVEs, register drift,
         convergence, context-cost canary, hardening cadence, mutation kill rate)
  log:   $LOG
  check: bash scripts/install-nightly-maintenance.sh --list
  undo:  bash scripts/install-nightly-maintenance.sh --remove

On macOS the first run needs Full Disk Access for /usr/sbin/cron
(System Settings -> Privacy & Security), or cron cannot read the repo.
MSG
