#!/usr/bin/env bash
# PostToolUse hook for Bash matching `allium distill` (or other Allium
# drift-producing commands). Reads the drift findings from stdout,
# ranks each by release-blocking severity (HIGH / MEDIUM / LOW), and
# suggests which to fix before release vs which can land as follow-ups.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

# Per-hook timeout override — drift reports up to 12KB get ranked with
# num_predict=768. On a 32b model that comfortably exceeds the global 15s
# default. 45s is enough headroom without blocking the conversation for
# absurd lengths if ollama is sluggish.
LOCAL_LLM_TIMEOUT="${LOCAL_LLM_ALLIUM_DRIFT_RANK_TIMEOUT:-45}"
export LOCAL_LLM_TIMEOUT

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Fire on allium distill or similar drift-producing commands.
echo "$CMD" | grep -qiE '(allium[[:space:]]+(distill|drift|check)|/allium:?distill)' || exit 0

STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
STDERR=$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null)
COMBINED="${STDOUT}
${STDERR}"

LEN=${#COMBINED}
[ "$LEN" -gt 500 ] || exit 0

# Look for drift markers.
echo "$COMBINED" | grep -qiE '(drift|specified-but-not-implemented|implemented-but-not-specified|behavioral.+drift|open[[:space:]]+question|AMBIGUITY|deferred|GAP-)' || exit 0

REPORT=$(printf '%s' "$COMBINED" | head -c 12000)

SYSTEM='You are ranking Allium drift findings by release-blocking severity for a developer who needs to decide what to fix now versus what can land as a follow-up PR.

For each drift finding in the report (specified-but-not-implemented, implemented-but-not-specified, behavioral drift, open questions, ambiguities, deferred items), assign a severity:

HIGH   — blocks release. Examples: implemented behavior that violates the spec, security/auth gap, data-loss path, an invariant the system assumes is true is actually false.
MEDIUM — should fix before next release but does not block this one. Examples: behavior drift in a non-critical path, undocumented edge cases, deferred items that have a workaround.
LOW    — can be tracked as a follow-up. Examples: cosmetic spec/code mismatch, open questions that have a sensible default, ambiguities in non-load-bearing areas.

Output format (one line per finding, ordered HIGH → MEDIUM → LOW):
- HIGH: <one-line finding summary> | <one-line release-blocking reason>
- MEDIUM: <one-line finding summary> | <one-line follow-up window>
- LOW: <one-line finding summary> | <one-line why-can-defer>

End with a one-line verdict:
RELEASE_GATE: <BLOCKED if any HIGH, OR PROCEED-WITH-FOLLOWUPS if only MEDIUM/LOW>

No preamble, no markdown.'

RANKED=$(printf '%s' "$REPORT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$RANKED" ] || exit 0

jq -nc --arg r "$RANKED" \
  '{additionalContext: ("Local-LLM Allium drift severity ranking:\n" + $r + "\nUse the RELEASE_GATE line as input to your release decision.")}'
