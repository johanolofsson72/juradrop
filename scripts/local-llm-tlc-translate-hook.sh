#!/usr/bin/env bash
# PostToolUse hook for Bash. When TLC (TLA+ model checker) produces a
# counterexample trace or invariant violation, ask the local LLM to
# translate the TLA+-syntax state trace into plain English step-by-step.
# Saves the assistant from parsing TLA+ records, primed variables,
# and set notation to understand what the violation actually is.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Fire only on TLC invocations.
echo "$CMD" | grep -qiE '(tlc2\.TLC|tla2tools|^[[:space:]]*tlc[[:space:]]|/tlc[[:space:]]|/tla\b)' || exit 0

STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
STDERR=$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null)
COMBINED="${STDOUT}
${STDERR}"

# Look for counterexample / failure markers. Skip if TLC ran clean.
echo "$COMBINED" | grep -qiE '(counterexample|invariant.+violated|deadlock|error: invariant|behavior of length|state[[:space:]]+[0-9]+:|action[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]])' || exit 0

# TLC traces can be long; sample the relevant slice.
TRACE=$(printf '%s' "$COMBINED" | head -c 12000)

read -r -d '' SYSTEM <<'TLC_SYSTEM_EOF'
You are translating a TLA+ TLC counterexample trace into plain English for a developer who needs to fix the bug behind the violation.

The TLC trace shows model states leading to an invariant violation, deadlock, or property failure. Each state has variable assignments in TLA+ syntax (records like [field |-> value], primed variables like x'=..., set notation, tuples).

Output format (no markdown headers, no preamble):

VIOLATION: <one line stating which invariant/property failed and the high-level scenario>

STEP 1: <plain-English description of initial state>
STEP 2: <next transition — what action fired, what variables changed>
...
STEP N: <final state where the property breaks, with concrete values>

ROOT CAUSE: <one-line hypothesis: which spec assumption is wrong, or which code path the spec models is missing a guard>

NEXT ACTION: <one concrete suggestion: tighten an invariant, add a precondition, fix the modeled behavior to match code, or fix the code to match the spec>

Translate TLA+ syntax to natural English (e.g. [status |-> "pending", retries |-> 0] → "the order is pending with zero retries"). Skip any TLC machinery (state count, depth, stuttering steps). Keep it concrete and short.
TLC_SYSTEM_EOF

TRANSLATION=$(printf '%s' "$TRACE" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$TRANSLATION" ] || exit 0

jq -nc --arg t "$TRANSLATION" \
  '{additionalContext: ("Local-LLM TLC counterexample translation:\n" + $t)}'
