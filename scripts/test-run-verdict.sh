#!/bin/bash
# Self-test for scripts/run-verdict.sh (spec 031).
#
#   bash scripts/test-run-verdict.sh
#
# Both directions, because either one alone is theatre: a helper that calls every run red passes
# the abort arms, and one that reads the summary word passes the green arms. ROCKY is the
# transcript captured on rocky 2026-09-05 — 1673 of 3050 tests ran and the summary said Passed!.
#
# bash 3.2-safe (macOS system bash).

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/run-verdict.sh"

PASS=0; FAIL=0
expect() {  # $1 name · $2 expected verdict · $3 rc · $4 output
  local got; got=$(run_verdict "$3" "$4")
  if [ "$got" = "$2" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$2" "${got:-<empty>}"; fi
}

ROCKY='The active test run was aborted. Reason: Test host process crashed
Passed!  - Failed: 0, Passed: 1673, Skipped: 7, Total: 1680
Test Run Aborted.'
GREEN='Passed!  - Failed:     0, Passed:    12, Skipped:     0, Total:    12, Duration: 88 ms - X.Tests.dll (net10.0)'
GREEN_NORMAL='Test Run Successful.
Total tests: 12
     Passed: 12'
FAILED0='Failed!  - Failed:     5, Passed:    40, Skipped:     0, Total:    45'
MTP='Test run summary: Aborted! - bin/Debug/net10.0/X.Tests.dll (net10.0|arm64)
  total: 800
  failed: 0
  succeeded: 800'

printf 'run-verdict self-test\n'
expect "rocky transcript, exit 1 → aborted"               aborted 1 "$ROCKY"
expect "rocky transcript, exit 0 → aborted (not Passed!)" aborted 0 "$ROCKY"
expect "only the vstest trailer line → aborted"           aborted 0 "Test Run Aborted."
expect "only the leading line → aborted"                  aborted 0 "The active test run was aborted. Reason: Test host process crashed"
expect "MTP summary Aborted! → aborted"                   aborted 0 "$MTP"
expect "green minimal summary, exit 0 → passed"           passed  0 "$GREEN"
expect "green normal-verbosity summary, exit 0 → passed"  passed  0 "$GREEN_NORMAL"
expect "failures at exit 0 → failed"                      failed  0 "$FAILED0"
expect "green text at exit 1 → failed"                    failed  1 "$GREEN"
expect "empty output, exit 0 → passed (rc is all there is)" passed 0 ""

if run_aborted "$ROCKY"; then PASS=$((PASS + 1)); printf '  ok   run_aborted true on rocky\n'
else FAIL=$((FAIL + 1)); printf '  FAIL run_aborted true on rocky\n'; fi
if run_aborted "$GREEN"; then FAIL=$((FAIL + 1)); printf '  FAIL run_aborted false on green\n'
else PASS=$((PASS + 1)); printf '  ok   run_aborted false on green\n'; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
