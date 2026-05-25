#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on test files. Scans for vague test
# method names (Test1, MethodTest, Foo, BasicTest) and suggests
# descriptive replacements following the Method_Scenario_Expected
# convention or its TS/Jest equivalent.

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

SYSTEM='You are reviewing a test file for vague test names.

Scan for test methods with names that do not describe what is being tested. Vague patterns include:
- Test1, Test2, TestMethod, TestFoo
- MethodTest, FunctionTest (just the function name + Test suffix)
- It_works, ItWorks, BasicTest, SimpleTest, HappyPath
- Single-word generic names (Run, Check, Verify, DoIt)
- Test names that could apply to anything ("returns correctly", "works as expected")

For each vague name found, suggest a descriptive replacement:
- C# / xUnit: Method_Scenario_ExpectedBehavior (e.g. GetUser_WhenIdNegative_ThrowsArgumentException)
- TS / Jest / Vitest: should-style descriptions ("should throw ArgumentException when id is negative")

Output one line per vague test:
- VAGUE: <current name> → <suggested descriptive name based on what the test body actually does>

If all test names are descriptive, output exactly: CLEAR
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*CLEAR[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM test name review on " + $f + ":\n" + $r)}'
