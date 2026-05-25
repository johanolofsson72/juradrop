#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on *.cs. Scans for LINQ patterns
# that look correct but cause hidden performance problems: multiple
# enumerations of the same IEnumerable, ToList()/ToArray() inside a
# loop, .Where(...).Count() instead of .Count(predicate), and similar.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

case "$FILE" in *.cs) ;; *) exit 0 ;; esac
case "$(basename "$FILE")" in
  *Tests.cs|*Test.cs) exit 0 ;;
esac
case "$FILE" in
  *Migrations/*|*/Migrations/*|*/bin/*|*/obj/*|*.g.cs|*.designer.cs) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are reviewing C#/.NET code for LINQ performance anti-patterns.

Scan for these specific issues:
- Same IEnumerable<T> enumerated multiple times in the same scope (each enumeration re-runs the query — should be materialized to a List once)
- ToList() / ToArray() called inside a loop (allocates per iteration)
- .Where(predicate).Count() instead of .Count(predicate) — same for First(), Single(), Any(), Last()
- .Where(predicate).FirstOrDefault() instead of .FirstOrDefault(predicate)
- .Select(...).Where(...) when filter could come first to reduce projected items
- .OrderBy(...).First() instead of .Min() / .MinBy()
- Calling .ToList() right before another LINQ chain (extra allocation)
- IEnumerable<T> from EF Core query that iterates over a DbSet without ToListAsync (sync database call in async context)

For each issue found, output one line:
- PERF: <one-line description with hint at the call site> | FIX: <concrete rewrite>

If no issues, output exactly: CLEAN
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*CLEAN[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM LINQ performance audit on " + $f + ":\n" + $r)}'
