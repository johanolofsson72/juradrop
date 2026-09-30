#!/bin/bash
# Self-test for scripts/template-sync-verify.sh — the abort gate (spec 031).
#
#   bash scripts/test-template-sync-verify.sh
#
# rocky's crashed test host printed `Passed!` between two abort lines with 45% of the suite unrun.
# At exit 0 that transcript would discharge a sync obligation as "verified". Each fixture is a git
# repo with an outstanding marker and a declared command that replays a transcript at a chosen code.
#
# bash 3.2-safe (macOS system bash).

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
VERIFY="$DIR/template-sync-verify.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/template-sync-verify-test.$$")
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$2" "$3"; }
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

ABORTED='The active test run was aborted. Reason: Test host process crashed
Passed!  - Failed: 0, Passed: 1673, Skipped: 7, Total: 1680
Test Run Aborted.'
GREEN='Passed!  - Failed:     0, Passed:    12, Skipped:     0, Total:    12'

mkfix() { # mkfix NAME RC TEXT — outstanding marker, declared command printing TEXT, exiting RC
  local d="$TMP/$1"
  mkdir -p "$d/.claude"
  ( cd "$d" && git init -q . >/dev/null 2>&1 )
  printf '%s\n' "$3" > "$d/transcript.txt"
  printf 'cat transcript.txt; exit %s\n' "$2" > "$d/.claude/.template-sync-verify"
  printf 'commit=abc1234\ncommits=abc1234\ntemplate=def5678\nsynced=2026-09-29\npushed=no\n' \
    > "$d/.git/template-sync-unverified"
  printf '%s' "$d"
}
run() { CLAUDE_PROJECT_DIR="$1" bash "$VERIFY" >/dev/null 2>&1; }
verified() { [ -f "$1/.git/template-sync-verified" ] && echo yes || echo no; }

printf 'template-sync-verify self-test (abort gate)\n'

D=$(mkfix aborted0 0 "$ABORTED"); run "$D"; RC=$?
expect "aborted run at exit 0 — exit 4 (proved nothing)" 4 "$RC"
expect "aborted run at exit 0 — the obligation stands"   yes "$([ -f "$D/.git/template-sync-unverified" ] && echo yes || echo no)"
expect "aborted run at exit 0 — nothing written verified" no "$(verified "$D")"

D=$(mkfix aborted1 1 "$ABORTED"); run "$D"; RC=$?
expect "aborted run at exit 1 — exit 1, as before"       1 "$RC"
expect "aborted run at exit 1 — nothing written verified" no "$(verified "$D")"

D=$(mkfix green 0 "$GREEN"); run "$D"; RC=$?
expect "green run — exit 0"                              0 "$RC"
expect "green run — verified"                            yes "$(verified "$D")"
expect "green run — obligation discharged"               no "$([ -f "$D/.git/template-sync-unverified" ] && echo yes || echo no)"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
