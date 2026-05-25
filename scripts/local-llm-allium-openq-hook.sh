#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on .allium files. Extracts every
# `open question "..."` marker and -- AMBIGUITY: comment from the spec
# and lists them as actionable items so the user can decide each one
# rather than letting them quietly accumulate.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

case "$FILE" in *.allium) ;; *) exit 0 ;; esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

# Cheap pre-filter: only call LLM if the file actually has questions/ambiguities.
grep -qiE '(open[[:space:]]+question|--[[:space:]]*AMBIGUITY|deferred)' "$FILE" || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are extracting unresolved questions from an Allium specification.

Find every instance of:
- `open question "..."` markers (formal Allium open-question syntax)
- `-- AMBIGUITY: ...` line comments (informal annotations)
- `deferred` markers attached to definitions or behaviors

For each, output one line with the question/ambiguity verbatim plus actionable framing:

- OPEN: "<exact question text>" | DECISION_NEEDED: <one-line framing of what choosing requires>
- AMBIGUITY: "<exact ambiguity comment>" | DECISION_NEEDED: <one-line framing>
- DEFERRED: "<the deferred construct>" | DECISION_NEEDED: <one-line framing of when this becomes load-bearing>

If the spec is clean (no markers at all, despite the pre-filter), output exactly: RESOLVED
Order findings by file order (top to bottom). No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 512 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*RESOLVED[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM open-question extraction from " + $f + ":\n" + $r + "\nEvery open question is a future bug — surface for explicit decision per validation-followup rule.")}'
