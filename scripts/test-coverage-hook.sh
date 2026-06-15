#!/bin/bash
# PostToolUse hook: deterministic enforcement of functional test coverage
# Fires on Edit|Write of test files. Blocks if inventory is missing or tests < inventory items.
#
# Supports: C# (.cs), TypeScript/JavaScript (.ts, .tsx, .js, .jsx), Dart (.dart)
# Covers web (Playwright), React Native (RNTL/Maestro), and Flutter (widget/Patrol) UI tests.
# Inventory format: comment block with "FUNCTIONAL COVERAGE INVENTORY" header
# and numbered items like "// 1. Feature name — description"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Exit silently if no file path
[ -z "$FILE" ] && exit 0

# Check if this is a test file (case-insensitive match on path)
IS_TEST=$(echo "$FILE" | grep -ciE '(test|spec|e2e|playwright|\.tests)' 2>/dev/null)
[ "$IS_TEST" -eq 0 ] 2>/dev/null && exit 0

# Check file extension — only process code files
EXT=$(echo "$FILE" | grep -oE '\.(cs|ts|tsx|js|jsx|dart)$' 2>/dev/null)
[ -z "$EXT" ] && exit 0

# File must exist
[ ! -f "$FILE" ] && exit 0

CONTENT=$(cat "$FILE")

# --- Detect if this is a UI test file (web OR native mobile) ---
# Web (Playwright): page/locator/goto patterns.
# React Native (RNTL): render/fireEvent/userEvent/screen.getBy/testing-library.
# Flutter (widget/Patrol): testWidgets/pumpWidget/WidgetTester/find.by/tester./patrol.
IS_UI_TEST=$(echo "$CONTENT" | grep -ciE '(playwright|browser|\.page\.|page\.|locator|getby|goto|navigate|waitfor|expect.*tobevisible|expect.*tohavetext|\.click|\.fill|\.type|render\(|fireevent|userevent|@testing-library/react-native|screen\.|testwidgets|pumpwidget|widgettester|find\.by|tester\.|patrol)' 2>/dev/null)

# If no UI test patterns found, exit silently (pure unit/logic tests don't need inventory)
[ "$IS_UI_TEST" -eq 0 ] 2>/dev/null && exit 0

# --- Check for functional inventory ---
HAS_INVENTORY=$(echo "$CONTENT" | grep -c 'FUNCTIONAL COVERAGE INVENTORY' 2>/dev/null)

if [ "$HAS_INVENTORY" -eq 0 ] 2>/dev/null; then
  echo '{"systemMessage": "BLOCKED: This UI test file has no FUNCTIONAL COVERAGE INVENTORY. Before writing tests, add a comment block listing EVERY user-facing function that was implemented. Format:\n\n// ===== FUNCTIONAL COVERAGE INVENTORY =====\n// 1. Feature name — description\n// 2. Feature name — description\n// ...\n// =============================================\n\nThen write at least one test per inventory item. Read .claude/docs/testing.md for details."}'
  exit 0
fi

# --- Count inventory items ---
# Match lines like: // 1. Feature, // 2. Feature, //  3. Feature
# Also match: //  1: Feature, // 1) Feature
# Support both // (C#/JS) and # (Python) comment styles
INVENTORY_COUNT=$(echo "$CONTENT" | grep -cE '^\s*(//|#)\s*[0-9]+[\.\):\-]' 2>/dev/null)

# If inventory exists but has 0 items, it's just the header with no items yet
if [ "$INVENTORY_COUNT" -eq 0 ] 2>/dev/null; then
  echo '{"systemMessage": "BLOCKED: FUNCTIONAL COVERAGE INVENTORY header exists but contains no numbered items. Add numbered items like:\n// 1. Search — user can search by keyword\n// 2. Filter — dropdown filters results\nList EVERY function, then write a test for each one."}'
  exit 0
fi

# --- Count test methods ---
case "$EXT" in
  .cs)
    # C#: count [Fact], [Theory], and test method signatures
    TEST_COUNT=$(echo "$CONTENT" | grep -cE '^\s*\[(Fact|Theory|Test|TestMethod)\]' 2>/dev/null)
    # Fallback: count public methods with Test/Should/When in name
    if [ "$TEST_COUNT" -eq 0 ] 2>/dev/null; then
      TEST_COUNT=$(echo "$CONTENT" | grep -cE '^\s*public\s+(async\s+)?Task\s+\w*(Test|Should|When|_)' 2>/dev/null)
    fi
    ;;
  .ts|.tsx|.js|.jsx)
    # JS/TS: count test() and it() calls (Jest / RNTL)
    TEST_COUNT=$(echo "$CONTENT" | grep -cE '^\s*(test|it)\s*\(' 2>/dev/null)
    # Also count test.describe blocks' children aren't tests themselves, so skip describe
    ;;
  .dart)
    # Flutter: count testWidgets(), test(), and patrolTest()/patrol() entries
    TEST_COUNT=$(echo "$CONTENT" | grep -cE '^\s*(testWidgets|test|patrolTest|patrol)\s*\(' 2>/dev/null)
    ;;
  *)
    exit 0
    ;;
esac

# --- Compare ---
if [ "$TEST_COUNT" -lt "$INVENTORY_COUNT" ] 2>/dev/null; then
  MISSING=$((INVENTORY_COUNT - TEST_COUNT))
  echo "{\"systemMessage\": \"BLOCKED: Functional coverage gap detected. Inventory lists $INVENTORY_COUNT functions but only $TEST_COUNT test methods found. $MISSING functions have NO test coverage. Write at least one test per inventory item before proceeding. Do NOT skip functions — testing ${TEST_COUNT}/${INVENTORY_COUNT} is not acceptable.\"}"
  exit 0
fi

# All good — silent approval
exit 0
