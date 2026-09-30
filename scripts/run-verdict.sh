#!/bin/bash
# run-verdict.sh — judge a test run from its exit code AND its output, trusting neither alone.
#
#   . scripts/run-verdict.sh
#   run_aborted "$OUT"          # 0 when the output carries an abort line
#   run_verdict "$RC" "$OUT"    # aborted | failed | passed
#
# Spec 031. rocky 2026-09-05: the integration test host crashed and `dotnet test` printed
#
#   The active test run was aborted. Reason: Test host process crashed
#   Passed!  - Failed: 0, Passed: 1673, Skipped: 7, Total: 1680
#   Test Run Aborted.
#
# over a 3050-test suite. 45% never ran and the summary word was `Passed!`. The per-assembly
# summary is truthful about the part that ran, which is what makes it dangerous: every reader
# that keys on `Passed!` calls this green. So an abort line outranks both the summary word and
# the exit code, and the summary word never makes a run green on its own — `dotnet test` has
# also been measured exiting 0 on a run with failures.
#
# The pattern covers vstest's two lines ("The active test run was aborted.", "Test Run
# Aborted.") and Microsoft.Testing.Platform's "Test run summary: Aborted!".
#
# Sourced, not executed: the repeat-failure guard runs on every Bash call and a fork per check
# is not worth it. No side effects on source.

RUN_ABORT_RE='test run (was )?aborted|summary: aborted'
RUN_FAIL_RE='Failed! *-|Failed: *[1-9]|Test Run Failed'

run_aborted() {
  grep -qiE "$RUN_ABORT_RE" <<< "$1"
}

run_verdict() {
  local rc="$1" out="$2"
  if run_aborted "$out"; then echo aborted
  elif [ "$rc" != 0 ] || grep -qE "$RUN_FAIL_RE" <<< "$out"; then echo failed
  else echo passed
  fi
}
