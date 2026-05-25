#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on *.cs. Scans for the N+1 query
# anti-pattern: a foreach (or LINQ enumeration) over a collection
# where each iteration awaits a database call. Causes one query for
# the parent + one query per child = O(N) queries instead of one JOIN.

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

# Pre-filter: only call LLM if file has both an enumeration AND an await of a db/repo call.
grep -qE '\b(foreach|\.Select|\.Where|\.ForEach|for[[:space:]]*\()' "$FILE" || exit 0
grep -qE '\bawait[[:space:]]+(_?(db|context|repo|repository)\b|.*\b(LoadAsync|FindAsync|FirstOrDefaultAsync|SingleOrDefaultAsync|CountAsync|AnyAsync|ToListAsync))' "$FILE" || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are reviewing C#/.NET code for the N+1 query anti-pattern.

The pattern: a foreach (or LINQ enumeration, or any loop) over a collection where the body calls an awaited database operation. This causes 1 query for the parent collection + N queries for the children = O(N) database round-trips.

Examples of N+1:
- foreach (var order in orders) { var items = await _db.OrderItems.Where(i => i.OrderId == order.Id).ToListAsync(); }
- orders.ForEach(async o => await _db.LoadAsync(o.UserId));
- users.Select(async u => await _repo.GetProfileAsync(u.Id))

Examples of NOT N+1 (do not flag):
- Single await before the loop, then iterate over result
- Bulk loading with Include() / .Where(o => orderIds.Contains(o.OrderId))
- await Task.WhenAll(orders.Select(o => _db.LoadAsync(o.UserId))) — still N queries but parallel
- Loops without await of a repository/db call (e.g., over DTOs in memory)

For each N+1 found, output one line:
- N+1: <description of the loop and what is awaited inside> at <method name if visible> | FIX: <suggest Include / IN-clause batch load / Task.WhenAll if parallelism is acceptable>

If no N+1 patterns found, output exactly: NO_N1
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*NO_N1[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM N+1 query detector on " + $f + ":\n" + $r + "\nN+1 looks fine in dev with 5 rows — kills production with 5000.")}'
