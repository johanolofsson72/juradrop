#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on React/TS/JS files. Scans for
# useEffect / useCallback / useMemo / useLayoutEffect calls where the
# dependency array is missing variables referenced in the body. The
# canonical React bug source.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

case "$FILE" in
  *.tsx|*.jsx|*.ts|*.js) ;;
  *) exit 0 ;;
esac

case "$(basename "$FILE")" in
  *.test.tsx|*.test.ts|*.spec.tsx|*.spec.ts|*.test.jsx|*.spec.jsx) exit 0 ;;
esac

case "$FILE" in
  *node_modules/*|*/dist/*|*/build/*|*.d.ts) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

# Pre-filter: only call LLM if file actually uses React hooks.
grep -qE '\b(useEffect|useCallback|useMemo|useLayoutEffect|useImperativeHandle)\b' "$FILE" || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are reviewing React code for the most common bug pattern: missing dependencies in useEffect/useCallback/useMemo/useLayoutEffect/useImperativeHandle dependency arrays.

For each call, list the variables referenced in the body that are NOT in the dependency array (excluding stable references: setState setters from useState, refs from useRef, dispatch from useReducer, anything imported as a constant, primitive literals).

Output one line per missing dependency:
- MISSING_DEP: <hook name> at <approximate line context> | refs <variable> but deps array does not include it | FIX: add <variable> to deps array OR wrap callback with useCallback / value with useMemo if it would cause infinite re-render

Other patterns to flag (one line each):
- EMPTY_DEPS: <hook name> at <line> with [] but body references <variable> — should run only on mount, but variable might be stale
- MISSING_DEPS_ARRAY: <hook name> with no second argument — runs on every render, almost always wrong
- CONDITIONAL_HOOK: hook called inside if/loop/switch — violates Rules of Hooks

If all hooks have correct deps, output exactly: HOOKS_OK
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*HOOKS_OK[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM React hooks audit on " + $f + ":\n" + $r + "\nMissing deps cause stale closures — the #1 React bug source.")}'
