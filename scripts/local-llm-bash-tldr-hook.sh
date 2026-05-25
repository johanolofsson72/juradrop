#!/usr/bin/env bash
# PostToolUse hook for Bash. When a command produces a wall of output,
# ask the local LLM for a 3-line TLDR and inject it as additionalContext
# so the assistant has a pre-digested handle on what just happened.
#
# Cheap pre-filters keep this from firing on small outputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
STDERR=$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null)
COMBINED="${STDOUT}
${STDERR}"

LEN=${#COMBINED}
THRESHOLD="${LOCAL_LLM_TLDR_MIN_CHARS:-6000}"
[ "$LEN" -gt "$THRESHOLD" ] || exit 0

# Cap input to keep the call under the 15s curl timeout. Asymmetric on
# purpose: head gets just enough to capture the command intent, tail
# gets the bulk because verdicts and errors live there.
HEAD_CAP="${LOCAL_LLM_TLDR_HEAD_CHARS:-1500}"
TAIL_CAP="${LOCAL_LLM_TLDR_TAIL_CHARS:-2500}"
TRUNCATED=$(printf '%s' "$COMBINED" | head -c "$HEAD_CAP")
TAIL=$(printf '%s' "$COMBINED" | tail -c "$TAIL_CAP")
PAYLOAD=$(printf '== HEAD ==\n%s\n\n== TAIL ==\n%s\n' "$TRUNCATED" "$TAIL")

SYSTEM='Summarize command output for a coding assistant. Output exactly three lines:
WHAT: <one-line description of what the command did>
KEY:  <most important facts, numbers, or error messages>
VERDICT: <success | failure | partial>
No preamble, no markdown, no extra lines.'

SUMMARY=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 96 2>/dev/null)

[ -n "$SUMMARY" ] || exit 0

jq -nc --arg s "$SUMMARY" --arg n "$LEN" \
  '{additionalContext: ("Local-LLM TLDR of " + $n + "-char Bash output:\n" + $s)}'
