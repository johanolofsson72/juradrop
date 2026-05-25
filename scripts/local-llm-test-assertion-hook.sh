#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on test files. For each test method
# (xUnit [Fact]/[Theory], MSTest [TestMethod], NUnit [Test], Jest/Vitest
# test()/it()), verify the body contains at least one assertion call.
# Catches the common early-draft pattern where a test exercises code
# but never verifies an outcome.

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

SYSTEM='You are reviewing a test file for tests that do not actually assert anything.

For each test method (decorated with [Fact], [Theory], [Test], [TestMethod], or wrapped in test()/it() in JS/TS), check the body contains at least one assertion call:
- xUnit/NUnit/MSTest: Assert.*, .Should() (FluentAssertions), Verify (Moq verification)
- Jest/Vitest: expect(), assert(), expect.assertions()
- Mock verification (Moq .Verify, NSubstitute .Received) counts as assertion when paired with a setup
- Throws assertions: Assert.Throws, expect().toThrow()

A test with only Arrange + Act and no Assert is a coverage placebo — it runs but proves nothing.

Output one line per test without assertions:
- NO_ASSERT: <test name> | <one-line description of what the test body does, hint at what assertion would verify the intended behavior>

If every test has at least one real assertion, output exactly: ALL_ASSERT
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*ALL_ASSERT[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM test assertion check on " + $f + ":\n" + $r + "\nA test without an assertion is a coverage placebo — it runs but proves nothing.")}'
