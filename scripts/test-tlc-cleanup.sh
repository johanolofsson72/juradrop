#!/bin/bash
# test-tlc-cleanup.sh — the TLC cleanup kills runaway runs, never live ones and never its own shell.
#
# ekofak 005 / hireflow 017 (spec 069): `pkill -f tla2tools` from the hooks killed the hook's own
# shell (exit 144), the Bash tool shell that started TLC, and a /tla subagent's live run whenever
# another agent stopped. Every case starts fake TLC processes (`exec -a "java … tlc2.TLC"`) carrying
# a unique token, and every run of the script under test is scoped to that token, so the harness
# never touches a real TLC run on this machine — even with a sabotaged script.
set -uo pipefail
export LC_ALL=C
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P=0; F=0
ok(){ echo "  PASS  $1"; P=$((P+1)); }
bad(){ echo "  FAIL  $1"; F=$((F+1)); }
T=$(mktemp -d)
PIDS=""
cleanup_fakes() { for p in $PIDS; do kill -9 "$p" 2>/dev/null; done; }
trap 'cleanup_fakes; rm -rf "$T"' EXIT

TOKEN="tlccleanuptest$$"
export TLC_CLEANUP_ONLY="$TOKEN"

# fake <argv> [ignore-term] — a detached `sleep` whose command line reads <argv>. Detached so init
# reaps it once killed; a zombie child would still answer kill -0.
fake() {
  local f="$T/pid.$RANDOM$RANDOM" pre=""
  [ "${2:-}" = ignore-term ] && pre='trap "" TERM; '
  # stdio to /dev/null: an inherited $(…) pipe would hold the caller's substitution open for 600 s.
  ( bash -c "${pre}exec -a \"\$0\" sleep 600" "$1" </dev/null >/dev/null 2>&1 & echo $! > "$f" )
  local p; p=$(cat "$f"); PIDS="$PIDS $p"; printf '%s' "$p"
}
tlc_argv() { echo "java -Xmx1g -cp /x/$TOKEN/tla2tools.jar tlc2.TLC -workers auto $1.tla"; }
alive() { kill -0 "$1" 2>/dev/null; }
settle() { local i=0; while alive "$1" && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; }
run() { bash "$ENGINE" "$@"; }

cases() {
  # AC1 — a young run survives the default (hook) mode.
  local y; y=$(fake "$(tlc_argv ac1)")
  sleep 0.3; run >/dev/null 2>&1
  alive "$y" && ok "AC1 young TLC run survives the default mode" || bad "AC1 young TLC run was killed"

  # AC2 — the real PostToolUse(Bash) hook command from settings.json, on a payload that mentions
  # TLC, run from a shell whose own command line carries the pattern.
  local proj="$T/proj" hook rc out
  mkdir -p "$proj/scripts"; cp "$ENGINE" "$proj/scripts/tlc-cleanup.sh"
  hook=$(jq -r '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[].command | select(test("tlc-cleanup"))' "$SD/../.claude/settings.json")
  if [ -z "$hook" ]; then
    bad "AC2 no PostToolUse(Bash) tlc-cleanup hook found in settings.json"
  else
    printf '{"tool_input":{"command":"java -cp /x/%s/tla2tools.jar tlc2.TLC S.tla"}}' "$TOKEN" \
      | CLAUDE_PROJECT_DIR="$proj" bash -c "$hook"; rc=$?
    [ "$rc" -eq 0 ] && ok "AC2 hook command exits 0" || bad "AC2 hook command exit $rc"
    alive "$y" && ok "AC2 hook leaves the young run alive" || bad "AC2 hook killed the young run"
  fi
  out=$(bash -c ": /x/$TOKEN/tla2tools.jar tlc2.TLC; bash \"$ENGINE\" --all >/dev/null 2>&1; echo alive" 2>&1); rc=$?
  [ "$out" = alive ] && [ "$rc" -eq 0 ] && ok "AC2 a shell carrying the pattern survives --all" \
    || bad "AC2 the calling shell died (exit $rc) — the 056 trap"
  # BSD pkill skips its own ancestors, so on macOS the case above only bites on Linux. A sibling
  # shell carrying the pattern (another hook, another agent's Bash tool) is hit on both.
  local sh; sh=$(fake "bash -c : /x/$TOKEN/tla2tools.jar tlc2.TLC")

  # AC4 — a non-java process mentioning the jar survives even --all.
  local v; v=$(fake "vim /x/$TOKEN/tla2tools.jar tlc2.TLC")
  sleep 0.3; run --all >/dev/null 2>&1; settle "$y"
  alive "$v" && ok "AC4 a non-java process naming the jar survives --all" || bad "AC4 --all killed a non-java process"
  alive "$sh" && ok "AC4 a sibling shell carrying the pattern survives --all" || bad "AC4 --all killed a sibling shell"

  # AC5 — --all kills the young run (it was still alive after AC1/AC2).
  alive "$y" && bad "AC5 --all left the young run alive" || ok "AC5 --all kills a young run"

  # AC3 — an old run is killed and reported.
  local o; o=$(fake "$(tlc_argv ac3)")
  sleep 2.2; out=$(run --max-age 1 2>&1); settle "$o"
  alive "$o" && bad "AC3 run older than --max-age survived" || ok "AC3 run older than --max-age is killed"
  grep -q "killed pid $o " <<< "$out" && ok "AC3 the kill is reported" || bad "AC3 no report line: $out"

  # AC6 — --dry-run lists and leaves alive.
  local d; d=$(fake "$(tlc_argv ac6)")
  sleep 0.3; out=$(run --all --dry-run 2>&1)
  grep -q "would kill pid $d " <<< "$out" && ok "AC6 --dry-run lists the run" || bad "AC6 --dry-run output: $out"
  alive "$d" && ok "AC6 --dry-run leaves it alive" || bad "AC6 --dry-run killed it"
  kill -9 "$d" 2>/dev/null

  # AC7 — nothing to kill: silent, exit 0, fast. Three runs inside one second rules out the old
  # unconditional `sleep 1` (date has no sub-second field on macOS).
  local s e; s=$(date +%s); out=$(run 2>&1; run 2>&1; run 2>&1); rc=$?; e=$(date +%s)
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ $((e - s)) -le 1 ] && ok "AC7 nothing to kill: silent exit 0, no sleep" \
    || bad "AC7 rc=$rc, $((e - s))s, output: $out"

  # AC8 — a run that ignores SIGTERM gets SIGKILL.
  local k; k=$(fake "$(tlc_argv ac8)" ignore-term)
  sleep 0.3; run --all >/dev/null 2>&1; settle "$k"
  alive "$k" && bad "AC8 a TERM-ignoring run survived" || ok "AC8 a TERM-ignoring run is killed with SIGKILL"

  # AC9 — bad argument.
  run --bogus >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && ok "AC9 unknown argument exits 2" || bad "AC9 unknown argument exit $rc, want 2"

  kill -9 "$v" "$sh" 2>/dev/null
}

ENGINE="$SD/tlc-cleanup.sh"
echo "tlc-cleanup"
cases
echo "  $P passed, $F failed"
TOTAL_F=$F

# AC10 — sabotage. Each arm deletes one marked region of the script; at least one case must go red.
echo "sabotage"
for arm in argv0-java age-bound; do
  S="$T/sabotaged-$arm.sh"
  awk -v r="$arm" '$0 ~ "# region: " r {skip=1} !skip {print} skip && /# endregion/ {skip=0}' "$SD/tlc-cleanup.sh" > "$S"
  cmp -s "$S" "$SD/tlc-cleanup.sh" && { echo "  FAIL  arm $arm changed nothing — the region marker is gone"; TOTAL_F=$((TOTAL_F+1)); continue; }
  ENGINE="$S"; P=0; F=0; cases >/dev/null
  if [ "$F" -gt 0 ]; then echo "  PASS  arm $arm turns $F case(s) red"; else echo "  FAIL  arm $arm: every case stayed green"; TOTAL_F=$((TOTAL_F+1)); fi
done

[ "$TOTAL_F" -eq 0 ] && { echo "OK"; exit 0; } || { echo "FAILED ($TOTAL_F)"; exit 1; }
