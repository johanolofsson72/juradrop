#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on speckit spec files. Scans the
# Acceptance Criteria / Scenarios sections for vague, untestable
# language and suggests concrete measurable replacements.
#
# Fits the speckit → Allium → TLA+ pipeline: criteria that pass this
# pre-check are far more likely to elicit cleanly into a formal spec.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

# Only fire on speckit spec files (specs/<id>/spec.md or .specify/specs/<id>/spec.md).
case "$FILE" in
  */specs/*/spec.md|*/.specify/specs/*/spec.md|*/specs/spec.md) ;;
  *) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are reviewing acceptance criteria in a feature specification for testability.

Scan for vague, subjective, or unmeasurable language:
- "should work well", "is fast", "handles errors gracefully", "user-friendly", "intuitive"
- "appropriate", "reasonable", "as needed", "where applicable"
- Subjective qualities without measurable thresholds ("performant", "scalable", "secure")
- Hedge words that hide untested behavior ("typically", "usually", "in most cases")
- Untestable conjunctions ("works correctly under load" without a load number)

For each problematic phrase, suggest a concrete measurable version. Output up to 5 issues, one per line:
- "<exact vague phrase from spec>" → <concrete testable version with numbers, error codes, or specific behaviors>

Examples of good fixes:
- "should be fast" → "p95 response time < 200ms under 100 concurrent users"
- "handles errors gracefully" → "returns HTTP 422 with {error, field, message} JSON body on validation failure; logs warning, no stack trace to client"
- "scales well" → "sustains 1000 req/s on 4-core 8GB instance with <1% error rate"

If all criteria are already measurable, output exactly: TESTABLE
No preamble, no markdown headers, nothing else.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
echo "$REPORT" | grep -qE '^[[:space:]]*TESTABLE[[:space:]]*$' && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM spec-criteria pre-check on " + $f + ":\n" + $r + "\nMake criteria concrete before running /allium:elicit — vague criteria produce vague specs.")}'
