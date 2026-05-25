#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on speckit spec.md files. Compares
# the scope statement (or scope-equivalent section) against the listed
# acceptance criteria and flags criteria that fall outside scope —
# i.e. scope creep that snuck into the spec without being declared
# as an expansion.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

case "$FILE" in
  */specs/*/spec.md|*/.specify/specs/*/spec.md|*/specs/spec.md) ;;
  *) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 500 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

# Pre-filter: only fire if the spec actually has a scope-like section AND criteria.
grep -qiE '^[[:space:]]*##[[:space:]]+(scope|out[[:space:]]*of[[:space:]]*scope|in[[:space:]]*scope|goals?|non[-[:space:]]*goals?)' "$FILE" || exit 0
grep -qiE '^[[:space:]]*##[[:space:]]+(acceptance[[:space:]]+criteria|scenarios?|requirements?|user[[:space:]]+stories)' "$FILE" || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are checking a feature specification for scope creep.

The spec has both a scope-style section (Scope / Goals / Non-goals / In Scope / Out of Scope) and a list of acceptance criteria (Acceptance Criteria / Scenarios / Requirements). Compare them.

For each acceptance criterion, decide whether it falls within the declared scope or extends beyond it. Scope creep often appears as:
- New entities or features mentioned in criteria but not in scope
- Quality attributes (security, performance, accessibility) added in criteria but not in scope
- Integration points (other services, third-party APIs) appearing in criteria but not in scope
- User roles or workflows that the scope did not promise

Be strict but fair: if scope says "user authentication" and criterion mentions "OAuth integration", that is creep. If scope says "user authentication including OAuth", it is not.

Output one line per creep:
- CREEP: "<criterion text>" | not covered by scope statement; spec says scope is "<short scope phrase>" | FIX: either expand scope explicitly OR move criterion to a follow-up spec

After listing creeps, end with:
VERDICT: <SCOPE_DRIFT — <count> criteria fall outside declared scope> OR <ALIGNED — every criterion fits the declared scope>

If the spec is clean, output exactly: ALIGNED
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 512 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*ALIGNED[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM spec scope-creep check on " + $f + ":\n" + $r + "\nUndeclared scope expansion is the most common cause of spec/impl drift.")}'
