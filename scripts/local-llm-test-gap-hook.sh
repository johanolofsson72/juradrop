#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on source files. After a non-test
# source file is modified, the local LLM looks for a matching test
# file and lists public methods/functions that lack corresponding
# tests. Fits CLAUDE.md's "every implemented function needs a test"
# rule by surfacing gaps in real time, not at PR review.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

# Source files only.
case "$FILE" in
  *.cs|*.tsx|*.ts) ;;
  *) exit 0 ;;
esac

# Skip test files themselves.
case "$(basename "$FILE")" in
  *Tests.cs|*Test.cs|*.test.tsx|*.test.ts|*.spec.ts|*.spec.tsx) exit 0 ;;
esac

# Skip generated, vendored, build output, and migrations.
case "$FILE" in
  *Migrations/*|*/Migrations/*) exit 0 ;;
  *node_modules/*|*/bin/*|*/obj/*|*/dist/*|*/build/*) exit 0 ;;
  *.g.cs|*.designer.cs|*.d.ts) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$(dirname "$FILE")"
EXT="${FILE##*.}"
BASE=$(basename "$FILE" ".$EXT")

# Try common test file conventions.
TEST_FILES=""
case "$EXT" in
  cs)
    TEST_FILES=$(find "$REPO_ROOT" \( -name "${BASE}Tests.cs" -o -name "${BASE}Test.cs" \) -not -path '*/bin/*' -not -path '*/obj/*' 2>/dev/null | head -3)
    ;;
  tsx|ts)
    TEST_FILES=$(find "$REPO_ROOT" \( -name "${BASE}.test.${EXT}" -o -name "${BASE}.spec.${EXT}" \) -not -path '*/node_modules/*' -not -path '*/dist/*' 2>/dev/null | head -3)
    ;;
esac

CONTENT=$(head -c 8000 "$FILE")

if [ -n "$TEST_FILES" ]; then
  TEST_BLOB=""
  for tf in $TEST_FILES; do
    TEST_BLOB=$(printf '%s\n\n== %s ==\n%s' "$TEST_BLOB" "$tf" "$(head -c 4000 "$tf")")
  done
  PAYLOAD=$(printf 'Source file (%s):\n%s\n\nFound test file(s):%s\n' "$FILE" "$CONTENT" "$TEST_BLOB")
  SYSTEM='You are checking test coverage gaps. Compare the source file with its test file(s) and list public methods/functions that have NO matching test.

Skip:
- Trivial property getters/setters with no logic
- Constructors that only assign fields
- Methods marked private/internal/protected
- Override methods that only call base implementation
- Auto-generated boilerplate (Equals, GetHashCode, ToString trivial)

Output up to 5 gaps, one per line:
- GAP: <method or function signature> | <one-line reason this should be tested>

If every public method has at least one test that exercises its behavior (not just instantiates the class), output exactly: COVERED
If the file has no testable surface (pure DTOs, constants, type definitions), output exactly: NO_TESTABLE_SURFACE
No preamble, no markdown.'
else
  PAYLOAD=$(printf 'Source file (%s):\n%s\n\nNo companion test file found.\n' "$FILE" "$CONTENT")
  SYSTEM='You are checking test coverage. The source file has NO companion test file at the conventional path.

List up to 5 public methods/functions that should have tests. Skip:
- Trivial property getters/setters
- Constructors that only assign fields
- Private/internal methods
- Pure DTOs and type definitions

Output format (no preamble):
- GAP: <method or function signature> | <one-line reason>

If the file has no testable surface (pure DTOs, constants, type definitions, only re-exports), output exactly: NO_TESTABLE_SURFACE
No preamble, no markdown.'
fi

REPORT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
echo "$REPORT" | grep -qE '^[[:space:]]*(COVERED|NO_TESTABLE_SURFACE)[[:space:]]*$' && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM test coverage gap analysis on " + $f + ":\n" + $r)}'
