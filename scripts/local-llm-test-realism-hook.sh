#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on test files. Flags mock/stub setups
# and test data that use placeholder values ("", null, 0, "test", "x")
# instead of realistic inputs. Tests with placeholder data often pass
# while production data exposes bugs (length limits, encoding, FK
# constraints, format validation).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

case "$(basename "$FILE")" in
  *Tests.cs|*Test.cs|*.test.tsx|*.test.ts|*.spec.ts|*.spec.tsx) ;;
  *) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

CONTENT=$(head -c 10000 "$FILE")

SYSTEM='You are reviewing a test file for unrealistic test data.

Scan setup/arrange sections for placeholder values that look like tests but do not exercise realistic scenarios:
- Empty strings "" used as inputs to fields that have length, format, or encoding constraints in production (emails, URLs, names, IDs)
- null used where production code may set a real value (DTO properties, ID fields)
- Zero numerics where realistic values would be positive integers (Age, Count, Quantity, Price)
- Magic strings like "test", "x", "abc", "foo", "bar" for fields that have format requirements
- Single-character or very short inputs for fields where length matters

Be lenient about boundary tests — a test specifically named "Empty_String" or "Null_Input" SHOULD use those values. Only flag when the placeholder is incidental.

Output one line per unrealistic input:
- UNREALISTIC: <field/parameter and value> | <one-line note on why this is suspect> | FIX: <suggest a realistic value or a builder pattern>

If test data looks realistic (or all placeholders are intentional boundary tests), output exactly: REALISTIC
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*REALISTIC[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM test data realism review on " + $f + ":\n" + $r)}'
