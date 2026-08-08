#!/bin/bash
# PostToolUse hook on Bash: makes CLAUDE.md's "max 3 attempts per problem" real.
#
# The rule has always been prose ("if the same approach fails 3 times, /clear and
# try a different strategy"). Prose does not count. This does: it fingerprints
# every VERIFICATION command (build / test / lint / typecheck / e2e) and tracks
# consecutive failures per fingerprint. On the 3rd identical failure it injects a
# loud additionalContext telling Claude to stop re-running and change strategy;
# on the 5th it escalates to "surface this to the developer as a hard blocker".
# A success resets that fingerprint's counter to zero.
#
# Why only verification commands: those are the ones that get re-run in a tight
# loop when the model is stuck. `git status` failing twice is noise, not a spiral.
#
# State lives in $PROJECT_ROOT/.claude/state/attempts/ — one small file per
# fingerprint, gitignored. Entries older than ATTEMPT_TTL (default 6h) are pruned
# on each run so yesterday's failure never counts toward today's spiral.
#
# Failure detection is heuristic by necessity: the PostToolUse payload carries the
# command's combined output, not always an exit status. We match well-known
# failure signatures (see FAIL_RE) and, when present, an explicit non-zero
# "Exit code: N" line. False negatives are fine (the hook simply stays quiet);
# false positives are the thing to avoid, so the patterns are anchored and
# specific rather than a bare grep for "error".
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

# -------------------------------------------------------- did this run fail?
OUT=$(printf '%s' "$INPUT" | jq -r '[.tool_response.stdout?, .tool_response.stderr?, .tool_response.output?, .tool_response.error?] | map(select(. != null)) | join("\n")' 2>/dev/null) || OUT=""
TAIL=$(printf '%s' "$OUT" | tail -c 8000)

FAILED=0
if printf '%s' "$TAIL" | grep -qE 'Exit code: [1-9]'; then FAILED=1; fi
if printf '%s' "$TAIL" | grep -qE '(Build FAILED|error [A-Z]+[0-9]+:|Failed! *-|Failed: *[1-9]|npm ERR!|Test Run Failed|FAILED \(failures|[0-9]+ (test|spec)s? failed|=+ [0-9]+ failed|error TS[0-9]+|panic:|FAIL[[:space:]]|Compilation failed|BUILD FAILURE)'; then FAILED=1; fi

if [ "$FAILED" -eq 0 ]; then
  # Success (or unrecognized-as-failure) → the spiral, if any, is broken.
  rm -f "$FILE" 2>/dev/null
  exit 0
fi

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
