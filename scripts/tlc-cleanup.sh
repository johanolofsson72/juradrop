#!/bin/bash
# tlc-cleanup.sh — kill TLC runs that outlived their bound; leave live runs and shells alone.
#
# Wired from PostToolUse(Bash), Stop, SubagentStop and SessionEnd, and run by /tla after each run.
# It used to `pkill -f tla2tools`, which matches whole command lines: it killed the hook's own shell
# and any Bash tool shell that mentioned the jar (exit 144, the 056 trap), and a /tla subagent's
# live run whenever another agent stopped (ekofak 005, hireflow 017 — register row 069).
#
# A TLC process here is a `java` process whose arguments name tla2tools or tlc2.TLC. /tla bounds
# every run with `timeout -k 10 300`, so a TLC process older than that has escaped its bound: that
# runaway is what this script kills. Anything younger is a live run and is left alone.
#
# Usage: tlc-cleanup.sh [--all] [--max-age SECONDS] [--only TEXT] [--dry-run]
#   --all        kill every TLC process whatever its age (manual use; no hook passes it)
#   --max-age N  age in seconds past which a run is runaway (default $TLC_MAX_SECONDS or 320)
#   --only TEXT  also require TEXT in the arguments (default $TLC_CLEANUP_ONLY; tests scope with it)
#   --dry-run    print what would be killed, kill nothing
# Exit: 0 nothing left running, 1 a process survived SIGKILL, 2 bad argument, 3 cannot list processes.

MAX_AGE="${TLC_MAX_SECONDS:-320}"
ONLY="${TLC_CLEANUP_ONLY:-}"
ALL=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=1 ;;
    --dry-run) DRY=1 ;;
    --max-age) MAX_AGE="${2:-}"; shift ;;
    --only) ONLY="${2:-}"; shift ;;
    *) echo "tlc-cleanup: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done
case "$MAX_AGE" in ''|*[!0-9]*) echo "tlc-cleanup: --max-age wants whole seconds, got '$MAX_AGE'" >&2; exit 2 ;; esac
[ "$ALL" -eq 1 ] && MAX_AGE=-1

# Prints "<pid> <age-seconds> <args>" for each TLC process past MAX_AGE.
list_runaways() {
  local ps_out
  if ! ps_out=$(ps -A -o pid=,etime=,args= 2>/dev/null); then
    echo "tlc-cleanup: 'ps -A -o pid=,etime=,args=' is not supported here (Git Bash?) — nothing was cleaned" >&2
    return 3
  fi
  printf '%s\n' "$ps_out" | awk -v max="$MAX_AGE" -v only="$ONLY" '
    # etime is [[dd-]hh:]mm:ss
    function secs(e,   d, n, a, i, s) {
      d = 0
      if (index(e, "-")) { d = substr(e, 1, index(e, "-") - 1); e = substr(e, index(e, "-") + 1) }
      n = split(e, a, ":"); s = 0
      for (i = 1; i <= n; i++) s = s * 60 + a[i]
      return d * 86400 + s
    }
    {
      pid = $1; age = secs($2)
      args = $0; sub(/^[ \t]*[0-9]+[ \t]+[0-9:-]+[ \t]+/, "", args)
      if (args !~ /tla2tools|tlc2\.TLC/) next
      if (only != "" && index(args, only) == 0) next
      # region: argv0-java — a shell, timeout, editor or grep naming the jar is not TLC
      prog = $3; sub(/.*[\/\\]/, "", prog); sub(/\.exe$/, "", prog)
      if (prog != "java") next
      # endregion
      # region: age-bound — a run younger than the bound is live
      if (age <= max) next
      # endregion
      print pid, age, args
    }'
}

RUNAWAYS=$(list_runaways) || exit 3
[ -z "$RUNAWAYS" ] && exit 0

VERB="killed"; [ "$DRY" -eq 1 ] && VERB="would kill"
while read -r pid age args; do
  echo "tlc-cleanup: $VERB pid $pid (age ${age}s) $args"
  [ "$DRY" -eq 1 ] || kill "$pid" 2>/dev/null
done <<< "$RUNAWAYS"
[ "$DRY" -eq 1 ] && exit 0

# Re-list rather than reuse the PIDs: a PID freed by SIGTERM and reused by another program in the
# meantime no longer passes the filter and is not hit by SIGKILL.
sleep 1
SURVIVORS=$(list_runaways) || exit 3
[ -z "$SURVIVORS" ] && exit 0
while read -r pid age args; do
  echo "tlc-cleanup: pid $pid ignored SIGTERM — sending SIGKILL"
  kill -9 "$pid" 2>/dev/null
done <<< "$SURVIVORS"
sleep 0.5
LEFT=$(list_runaways) || exit 3
if [ -n "$LEFT" ]; then
  echo "tlc-cleanup: ERROR — still running after SIGKILL:"
  printf '%s\n' "$LEFT"
  exit 1
fi
exit 0
