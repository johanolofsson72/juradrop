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
#
# The line runs under the PATH this installer runs under, because cron's own PATH
# (/usr/bin:/bin:/usr/sbin:/sbin) has no dotnet, node, npm, docker or timeout
# (fundit F084). Install from the shell your tools work in; re-run after adding a
# toolchain. The PATH lives in ~/.claude/nightly/<project>.path, not in the line:
# BSD/macOS cron truncates a command at 999 characters without a word, and a
# developer PATH alone is longer than that. A line over the limit is refused.
#
# The line opens its log before anything else and brackets the run with start/end
# lines, so a run that fired can always be told from one that did not (F086). It
# is syntax-checked with /bin/sh -n before crontab is touched.
# NIGHTLY_PARSE_SHELL overrides that shell -- a test seam, nothing else.

set -uo pipefail
export LC_ALL=C

AT="02:30"; MODE="install"; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --at) AT="${2:-}"; shift 2 ;;
    --list) MODE="list"; shift ;;
    --remove) MODE="remove"; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
PATHFILE="$LOGDIR/$PROJECT.path"
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
  ours=$(printf '%s\n' "$current" | grep -F "claude-nightly-maintenance:")
  [ -n "$ours" ] || { echo "(no claude nightly jobs installed)"; exit 0; }
  # A line from before row 065 runs under cron's bare PATH and fails every night.
  printf '%s\n' "$ours" | while IFS= read -r l; do
    case "$l" in
      *"PATH="*) echo "$l" ;;
      *) echo "STALE (no PATH= -- runs under cron's bare PATH; reinstall from that project): $l" ;;
    esac
  done
  exit 0
fi

# Drop any existing line for THIS project. Both modes need it: remove is only this,
# and install must not stack a second entry every time it is run.
cleaned=$(printf '%s\n' "$current" | grep -vF "$MARKER" | sed '/^$/d')

if [ "$MODE" = "remove" ]; then
  if [ "$DRY" -eq 1 ]; then echo "(dry-run) would remove the nightly job for $PROJECT"; exit 0; fi
  printf '%s\n' "$cleaned" | crontab -
  rm -f "$PATHFILE"
  echo "removed: nightly maintenance for $PROJECT"
  exit 0
fi

# `--full` is the point of running at night: it is what adds the mutation pass.
# The log is truncated per run, not appended, so a nightly job cannot quietly fill
# a disk over a year -- and the only run anyone reads is the last one.
#
# Cron turns an unescaped % into a newline before the shell sees the line, and a
# newline ends the entry, so neither can be quoted around. Refuse them by name.
for pair in "root:$ROOT" "log:$LOG" "PATH file:$PATHFILE"; do
  case "${pair#*:}" in
    *%*|*"
"*) echo "install-nightly-maintenance.sh: refusing -- the ${pair%%:*} contains % or a newline, which cron rewrites before the shell runs: ${pair#*:}" >&2
        exit 2 ;;
  esac
done

# Absolute entries only: an empty or relative one would resolve against the cron
# cwd. First occurrence wins, so the order the developer's shell uses is kept.
CAPTURED=""
IFS=: read -r -a _entries <<< "$PATH"
for e in "${_entries[@]}"; do
  case "$e" in /*) ;; *) continue ;; esac
  case ":$CAPTURED:" in *":$e:"*) continue ;; esac
  CAPTURED="${CAPTURED:+$CAPTURED:}$e"
done

# Single-quote for /bin/sh: an embedded ' becomes '\''.
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# exec comes first so the log opens before anything that can fail; the start and
# end lines make "fired and failed" visible and distinct from "never fired".
# A missing PATH file stops the run with cat's error in the log, not a blind run.
CMD="exec >$(q "$LOG") 2>&1; echo \"claude-nightly: start \$(date)\"; cd $(q "$ROOT") && PATH=\$(cat $(q "$PATHFILE")) && export PATH && /bin/bash scripts/project-maintenance.sh --full --suite --if-due; echo \"claude-nightly: end exit=\$?\""
LINE="$MM $HH * * * $CMD $MARKER"

# BSD cron (macOS, FreeBSD) reads at most MAX_COMMAND-1 = 999 characters of the
# command and drops the rest silently; the truncated line then fails to parse.
MAX_CMD=999
if [ "${#CMD}" -gt "$((MAX_CMD - ${#MARKER} - 1))" ]; then
  echo "install-nightly-maintenance.sh: refusing -- the cron command would be $((${#CMD} + ${#MARKER} + 1)) characters and BSD/macOS cron cuts at $MAX_CMD. Shorten the project path: $ROOT" >&2
  exit 2
fi

# What cron will hand to /bin/sh must parse, or the job fails silently every night.
PARSE_SHELL="${NIGHTLY_PARSE_SHELL:-/bin/sh}"
if ! perr=$("$PARSE_SHELL" -n -c "$CMD $MARKER" 2>&1); then
  echo "install-nightly-maintenance.sh: the line does not parse under $PARSE_SHELL -- not installed:" >&2
  echo "  $LINE" >&2
  echo "  $perr" >&2
  exit 1
fi

if [ "$DRY" -eq 1 ]; then
  echo "(dry-run) would install:"; echo "  $LINE"; exit 0
fi

mkdir -p "$LOGDIR"
printf '%s\n' "$CAPTURED" > "$PATHFILE" || {
  echo "install-nightly-maintenance.sh: cannot write $PATHFILE" >&2; exit 1; }
printf '%s\n%s\n' "$cleaned" "$LINE" | sed '/^$/d' | crontab - || {
  echo "install-nightly-maintenance.sh: crontab refused the update" >&2; exit 1; }

cat <<MSG
installed: $PROJECT — nightly maintenance at $(printf '%02d:%02d' "$HH" "$MM")

  runs:  scripts/project-maintenance.sh --full --suite --if-due   (secrets + CVEs, register drift,
         convergence, context-cost canary, hardening cadence, mutation kill rate)
  log:   $LOG
  PATH:  $PATHFILE (captured from this shell)
  check: bash scripts/install-nightly-maintenance.sh --list
  undo:  bash scripts/install-nightly-maintenance.sh --remove

tools on the captured PATH (re-run this installer after installing one):
$(for t in dotnet node npm npx docker timeout; do
    if [ "$t" = timeout ] && ! PATH="$CAPTURED" command -v timeout >/dev/null 2>&1 \
       && PATH="$CAPTURED" command -v gtimeout >/dev/null 2>&1; then t=gtimeout; fi
    if PATH="$CAPTURED" command -v "$t" >/dev/null 2>&1; then printf '  %-8s found\n' "$t"
    else printf '  %-8s missing\n' "$t"; fi
  done)

On macOS the first run needs Full Disk Access for /usr/sbin/cron
(System Settings -> Privacy & Security), or cron cannot read the repo.
MSG
