#!/bin/bash
# PostToolUse hook on Bash: makes CLAUDE.md's "max 3 attempts per problem" real.
#
# The rule has always been prose ("if the same approach fails 3 times, /clear and
# try a different strategy"). Prose does not count. This does: it fingerprints
# every VERIFICATION command (build / test / lint / typecheck / e2e) and tracks
# consecutive failures per fingerprint. On the 3rd identical failure it injects a
# loud additionalContext telling Claude to stop re-running and change strategy;
# on the 5th it escalates to "surface this to the developer as a hard blocker".
#
# Why only verification commands: those are the ones that get re-run in a tight
# loop when the model is stuck. `git status` failing twice is noise, not a spiral.
#
# State lives in $PROJECT_ROOT/.claude/state/attempts/ — one small file per
# fingerprint, gitignored. Entries older than ATTEMPT_TTL (default 6h) are pruned
# on each run so yesterday's failure never counts toward today's spiral.
#
# THREE STATES, NOT TWO (H6s). Classification is heuristic by necessity: the
# PostToolUse payload carries the command's combined output, not always an exit
# status. So every run lands in exactly one of:
#
#   FAILED  — a recognized failure signature (FAIL_RE, or "Exit code: N≠0")
#             → count up.
#   PASSED  — a recognized success signature (PASS_RE, or "Exit code: 0"), or a
#             READABLE payload whose output is empty (tsc --noEmit, eslint and
#             dotnet format all print nothing when they pass) → reset.
#   UNKNOWN — neither, or a payload we could not read → LEAVE THE FAILURE
#             COUNTER ALONE, and count the run on a separate "unclassified
#             streak" instead (state file "<fp>.unknown").
#
# That third state is the whole point. This hook used to read "no failure
# signature" as success and DELETE the counter, so (a) a spiral of novel-signature
# failures never tripped the guard that exists to catch spirals, and (b) one
# unreadable payload erased the evidence of the failures before it. Both were
# measured: specs/H6s-repeat-failure-guard-defaults-to-success/research.md.
#
# The separate streak exists because "leave the counter untouched" alone would
# have left (a) still true: an unclassifiable spiral would accumulate nothing and
# nudge nothing. The streak nudges with weaker wording ("I cannot tell whether
# this passed") so the guard never asserts a failure it did not observe.
#
# Readability is checked explicitly rather than inferred from emptiness, because
# jq's `?` operator yields empty BOTH for a tool_response it cannot traverse and
# for a tool that legitimately printed nothing (research.md R-3).
#
# Accepted cost, stated rather than hidden: an unrecognized SUCCESS now leaves a
# stale counter, so the guard can fire one attempt early on that fingerprint.
# That is a non-blocking nudge, scoped to one command, and pruned by ATTEMPT_TTL
# anyway — the safe direction versus a guard that silently never fires. It is
# also why PASS_RE must cover every stack the command matcher below tracks, not
# just .NET, and why both pattern sets are anchored and specific rather than a
# bare grep for "error" / "passed": a FALSE success resets a real spiral.
#
# Never blocks. Fails open on every error. bash 3.2-safe (macOS system bash),
# cross-platform (macOS / Linux / Windows Git Bash).
#
# Tunables:  ATTEMPT_LIMIT (default 3) · ATTEMPT_ESCALATE (default 5)
#            ATTEMPT_TTL seconds (default 21600) · REPEAT_FAILURE_DISABLE=1

set -u

[ "${REPEAT_FAILURE_DISABLE:-0}" = "1" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$CMD" ] && exit 0

# ------------------------------------------------- only track verification runs
case "$CMD" in
  *"dotnet build"*|*"dotnet test"*|*"dotnet run"*|*"dotnet format"*|*"dotnet stryker"*) ;;
  *"npm test"*|*"npm run build"*|*"npm run lint"*|*"npm run typecheck"*|*"npm run test"*) ;;
  *"pnpm "*test*|*"pnpm "*build*|*"yarn "*test*|*"yarn "*build*) ;;
  *"npx tsc"*|*"tsc --noEmit"*|*"eslint"*|*"vitest"*|*"jest"*|*"playwright test"*) ;;
  *"pytest"*|*"ruff check"*|*"mypy"*) ;;
  *"go test"*|*"go build"*|*"cargo test"*|*"cargo build"*|*"cargo clippy"*) ;;
  *"flutter test"*|*"flutter build"*|*"flutter analyze"*|*"maestro test"*|*"patrol test"*) ;;
  *"gradlew test"*|*"mvn test"*|*"mvn verify"*) ;;
  *) exit 0 ;;
esac

# ------------------------------------------------------------ project root
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || exit 0

STATE_DIR="$PROJECT_ROOT/.claude/state/attempts"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# --------------------------------------------------------------- fingerprint
# Normalize whitespace so `dotnet test  ` and `dotnet test` are the same attempt.
NORM=$(printf '%s' "$CMD" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
FP=$(printf '%s' "$NORM" | cksum 2>/dev/null | awk '{print $1"-"$2}')
[ -z "$FP" ] && exit 0
FILE="$STATE_DIR/$FP"

# ------------------------------------------------------------------- pruning
TTL="${ATTEMPT_TTL:-21600}"
NOW=$(date +%s 2>/dev/null || echo 0)
if [ "$NOW" -gt 0 ]; then
  for f in "$STATE_DIR"/*; do
    [ -f "$f" ] || continue
    MT=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    case "$MT" in (*[!0-9]*|'') MT=0 ;; esac
    [ "$MT" -gt 0 ] && [ $((NOW - MT)) -gt "$TTL" ] && rm -f "$f" 2>/dev/null
  done
fi

# ------------------------------------------------- can we read this payload?
# One jq call for the three facts that decide readability. A tool_response that
# is not an object, or that carries none of the four output fields, or that was
# interrupted, tells us nothing about whether the command passed — and "tells us
# nothing" must not be spelled the same way as "passed".
META=$(printf '%s' "$INPUT" | jq -r '[(.tool_response | type),
  ([.tool_response.stdout?, .tool_response.stderr?, .tool_response.output?, .tool_response.error?]
     | map(select(type == "string")) | length | tostring),
  ((.tool_response.interrupted? // false) | tostring)] | join(" ")' 2>/dev/null) || META=""
RESP_TYPE=$(printf '%s' "$META" | cut -d' ' -f1)
FIELDS=$(printf '%s' "$META" | cut -d' ' -f2)
INTERRUPTED=$(printf '%s' "$META" | cut -d' ' -f3)
case "$FIELDS" in (''|*[!0-9]*) FIELDS=0 ;; esac

# ------------------------------------------- FAILED / PASSED / UNKNOWN
VERDICT=unknown

if [ "$RESP_TYPE" = "object" ] && [ "$INTERRUPTED" != "true" ] && [ "$FIELDS" -gt 0 ]; then
  # No `|| OUT=""` fallback here: it was unreachable. jq's `?` suppresses the
  # traversal error and returns empty (rc 0), and a payload that is not valid
  # JSON at all has already exited above where the command was read. Keeping a
  # fallback that never runs preserves an explanation that is false (H6s R-3).
  OUT=$(printf '%s' "$INPUT" | jq -r '[.tool_response.stdout?, .tool_response.stderr?, .tool_response.output?, .tool_response.error?] | map(select(type == "string")) | join("\n")' 2>/dev/null)
  TAIL=$(printf '%s' "$OUT" | tail -c 8000)

  # Failure is evaluated FIRST and short-circuits: a `dotnet test` run prints
  # "Build succeeded." / "0 Error(s)" from the build and "Failed: 3" from the
  # tests, and reading that as a success would rebuild this hook's own defect.
  if printf '%s' "$TAIL" | grep -qE 'Exit code: [1-9]'; then
    VERDICT=failed
  elif printf '%s' "$TAIL" | grep -qE '(Build FAILED|error [A-Z]+[0-9]+:|Failed! *-|Failed: *[1-9]|npm ERR!|Test Run Failed|FAILED \(failures|[0-9]+ (test|spec)s? failed|=+ [0-9]+ failed|[1-9][0-9]* failed|test result: FAILED|error TS[0-9]+|panic:|FAIL[[:space:]]|Compilation failed|BUILD FAILURE)'; then
    # `[1-9][0-9]* failed` and `test result: FAILED` were added with the positive
    # set, not before it: pytest -q prints "3 failed, 41 passed in 1.20s", which
    # the positive pattern `[0-9]+ passed in ` matches. Without a failure pattern
    # for that line, this hook would have RESET a live counter on a failing test
    # run — the exact defect H6s exists to remove, rebuilt from the other side.
    # (Measured: the test asserting it seeds the counter first, because "no state
    # file" cannot tell a reset from an untouched counter.)
    VERDICT=failed
  elif [ -z "$(printf '%s' "$TAIL" | tr -d '[:space:]')" ]; then
    # Readable payload, nothing printed. tsc --noEmit, eslint and dotnet format
    # all pass in silence; they fail loudly. This is the only reason emptiness
    # may be read as success, and it is safe only because the payload was
    # confirmed readable above.
    VERDICT=passed
  elif printf '%s' "$TAIL" | grep -qE '(Exit code: 0([^0-9]|$)|Build succeeded|^ *0 Error\(s\)|Passed! *-|Test Run Successful|Tests: +[0-9]+ passed|Test Suites: +[0-9]+ passed|Test Files +[0-9]+ passed|[0-9]+ passed \(|[0-9]+ passed in |[0-9]+ passed,? +[0-9]+ total|All checks passed!|Success: no issues found|test result: ok|^ *Finished |^ok[[:space:]]|^PASS([[:space:]]|$)|No issues found!|All tests passed!|BUILD SUCCESSFUL|BUILD SUCCESS)'; then
    VERDICT=passed
  fi
fi

UFILE="$FILE.unknown"

case "$VERDICT" in
  passed)
    # A real, recognized success → the spiral, if any, is broken.
    rm -f "$FILE" "$UFILE" 2>/dev/null
    exit 0
    ;;
  unknown)
    # The FAILURE counter is left exactly as it was: an unreadable or
    # unrecognized run adds no evidence about failure and must destroy none.
    #
    # But a run still happened, and the payload carries no exit code at all
    # (measured — see research.md M5: the Bash tool_response is stdout/stderr/
    # interrupted/isImage/noOutputExpected, so "Exit code: N" only ever matches
    # when the command's own output happens to print it). Classification is
    # therefore text-heuristic only, which makes "unrecognized" a normal case
    # rather than a rare one. Three identical runs in a row that this guard
    # cannot classify at all is itself the spiral it exists to interrupt, so it
    # is counted SEPARATELY and nudged with its own, weaker wording — never
    # folded into the failure count, which would assert a failure we did not
    # observe.
    UCOUNT=0
    [ -f "$UFILE" ] && UCOUNT=$(cat "$UFILE" 2>/dev/null | tr -dc '0-9')
    case "$UCOUNT" in (''|*[!0-9]*) UCOUNT=0 ;; esac
    UCOUNT=$((UCOUNT + 1))
    printf '%s' "$UCOUNT" > "$UFILE" 2>/dev/null

    [ "$UCOUNT" -lt "${ATTEMPT_LIMIT:-3}" ] && exit 0

    UMSG="UNCLASSIFIED REPEAT — \`$(printf '%s' "$NORM" | cut -c1-120)\` has run ${UCOUNT} times in a row and this guard could not tell, from the output, whether it passed or failed.

That is not a claim that it failed. It is a claim that nobody is checking — the attempt counter has been standing still while you re-ran the same command ${UCOUNT} times.

Do this before running it again:
  1. Read the actual output of the last run end-to-end. Decide yourself: did it pass?
  2. If it failed, CLAUDE.md's 3-attempt cap already applies — change strategy, not syntax.
  3. If it passed, stop re-running it.

(Counter resets when this command produces a recognizable pass or fail, or after ${TTL}s.)"
    jq -n --arg m "$UMSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}' 2>/dev/null || true
    exit 0
    ;;
esac

# A classified outcome ends any unclassified streak.
rm -f "$UFILE" 2>/dev/null

# ----------------------------------------------------------------- count up
COUNT=0
[ -f "$FILE" ] && COUNT=$(cat "$FILE" 2>/dev/null | tr -dc '0-9')
case "$COUNT" in (''|*[!0-9]*) COUNT=0 ;; esac
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$FILE" 2>/dev/null

LIMIT="${ATTEMPT_LIMIT:-3}"
ESCALATE="${ATTEMPT_ESCALATE:-5}"
[ "$COUNT" -lt "$LIMIT" ] && exit 0

SHORT=$(printf '%s' "$NORM" | cut -c1-120)

if [ "$COUNT" -ge "$ESCALATE" ]; then
  MSG="ATTEMPT LIMIT BREACHED — \`${SHORT}\` has now failed ${COUNT} times in a row.

Per CLAUDE.md (\"Max 3 attempts per problem\") this stopped being a fixable bug ${COUNT} runs ago and is now a HARD BLOCKER. Do NOT run this command again.

Required next step — pick one and say which:
  (a) Surface it to the developer as a blocker: what fails, what you tried, what you need.
  (b) If the session context is polluted from the failed attempts, say so and ask for /clear, then restart with a written-from-scratch approach.

Re-running the same command a ${COUNT}th time is the stagnation the rule forbids."
else
  MSG="REPEAT FAILURE — \`${SHORT}\` has failed ${COUNT} times in a row.

CLAUDE.md caps this at ${LIMIT} attempts per problem. The next move is NOT another run of the same command with a small tweak — that is the loop the rule exists to break.

Do this instead:
  1. State the actual hypothesis for WHY it fails (read the error, don't pattern-match it).
  2. Change strategy, not syntax — different layer, different tool, or read the failing code/test end-to-end first.
  3. If you cannot form a hypothesis, that is a blocker: surface it to the developer rather than burning a 4th attempt.

(Counter resets automatically when this command passes, or after ${TTL}s.)"
fi

jq -n --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}' 2>/dev/null || true
exit 0
