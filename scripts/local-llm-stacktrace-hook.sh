#!/usr/bin/env bash
# PostToolUse hook for Bash. When a command output contains a stack
# trace or error pattern, ask the local LLM to extract three things:
# the error type and message, the first user-code frame (skipping
# framework noise), and a one-line likely cause.
#
# Complementary to local-llm-bash-tldr-hook.sh: that one fires on big
# outputs in general, this one fires on errors specifically and digs
# deeper into the diagnostic. Both can co-fire on the same Bash output
# if the output is both big and contains errors.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
STDERR=$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null)
COMBINED="${STDOUT}
${STDERR}"

LEN=${#COMBINED}
THRESHOLD="${LOCAL_LLM_STACKTRACE_MIN_CHARS:-3000}"
[ "$LEN" -gt "$THRESHOLD" ] || exit 0

# Cheap pre-filter: only fire if output looks like it has an error / stack trace.
echo "$COMBINED" | grep -qiE '(exception|error|panic:|fatal:|traceback|^[[:space:]]+at[[:space:]]+.+:[0-9]+|FAIL[!:]|System\.[A-Za-z]+Exception|Microsoft\.[A-Za-z.]+Exception)' || exit 0

# Cap input to keep the call under the 15s curl timeout. Asymmetric on
# purpose: head captures the failing command intent, tail keeps the
# deepest (and most useful) stack frames.
HEAD_CAP="${LOCAL_LLM_STACKTRACE_HEAD_CHARS:-1500}"
TAIL_CAP="${LOCAL_LLM_STACKTRACE_TAIL_CHARS:-2500}"
HEAD=$(printf '%s' "$COMBINED" | head -c "$HEAD_CAP")
TAIL=$(printf '%s' "$COMBINED" | tail -c "$TAIL_CAP")
PAYLOAD=$(printf '== HEAD ==\n%s\n\n== TAIL ==\n%s\n' "$HEAD" "$TAIL")

SYSTEM='Extract the actionable signal from a stack trace or error log for a coding assistant.
Output exactly three lines, no preamble, no markdown:
ERROR: <error type and one-line message>
LOCATION: <first user-code frame as file:line, skip framework/runtime frames>
CAUSE: <one-line hypothesis about likely root cause>

If you cannot identify a frame in user code, write LOCATION: unknown (only framework frames visible).
If the cause is genuinely unclear, write CAUSE: insufficient context — needs deeper investigation.
Never invent file paths or line numbers.'

REPORT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 128 2>/dev/null)

[ -n "$REPORT" ] || exit 0

jq -nc --arg r "$REPORT" --arg n "$LEN" \
  '{additionalContext: ("Local-LLM stack-trace distillation (" + $n + "-char output):\n" + $r)}'
