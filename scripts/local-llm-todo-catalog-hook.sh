#!/usr/bin/env bash
# PostToolUse hook for Edit/Write. When a file accumulates more than
# a threshold of TODO/FIXME/HACK/XXX markers, the local LLM catalogs
# them with priority and category so the user can decide which to
# act on now versus track separately.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

# Skip vendored, generated, lock files.
case "$FILE" in
  *node_modules/*|*/bin/*|*/obj/*|*/dist/*|*/build/*|*.lock|*-lock.json) exit 0 ;;
  *.g.cs|*.designer.cs|*.d.ts) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 100 ] || exit 0
[ "$SIZE" -lt 50000 ] || exit 0

# Count TODO-class markers; only fire when accumulation is meaningful.
TODO_COUNT=$(grep -cE '\b(TODO|FIXME|HACK|XXX|TBD)\b' "$FILE" 2>/dev/null || echo 0)
THRESHOLD="${LOCAL_LLM_TODO_MIN_COUNT:-3}"
[ "$TODO_COUNT" -ge "$THRESHOLD" ] || exit 0

# Extract the markers with surrounding context (line number + the line itself).
MARKERS=$(grep -nE '\b(TODO|FIXME|HACK|XXX|TBD)\b' "$FILE" 2>/dev/null | head -30)

SYSTEM='You are cataloging accumulated TODO / FIXME / HACK / XXX / TBD markers in a single file.

For each marker, output one line in this format:
- <KIND>: <line>: "<short summary of what the marker is about>" | <CATEGORY> | <PRIORITY>

Where:
- KIND = TODO | FIXME | HACK | XXX | TBD (preserve from source)
- CATEGORY = bug | feature | refactor | doc | perf | security | test | unclear
- PRIORITY = high | medium | low based on:
  - high: bugs, security, anything with words like "broken", "crash", "leak", "race", "wrong"
  - medium: refactor, perf, missing tests, deferred design decisions
  - low: cosmetic, doc, "nice to have", "consider"

After the list, output one summary line:
SUMMARY: <count> markers, <high-count> high-priority — <one-line recommendation>

If somehow no markers are present despite the pre-filter, output exactly: NO_MARKERS
No preamble, no markdown.'

REPORT=$(printf 'File: %s\nTotal markers: %s\n\nMarkers (line:content):\n%s\n' "$FILE" "$TODO_COUNT" "$MARKERS" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 512 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*NO_MARKERS[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg n "$TODO_COUNT" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM TODO catalog (" + $n + " markers in " + $f + "):\n" + $r)}'
