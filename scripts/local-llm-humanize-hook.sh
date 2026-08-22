#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on documentation files. Run a humanizer
# pre-check via the local LLM and surface AI-tells as additionalContext.
# Does NOT modify the file — just flags issues so the humanizer skill (or
# the assistant directly) can address them before delivery.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

# Only fire on human-facing documentation, not source files or specs/configs.
case "$(basename "$FILE")" in
  README*|CHANGELOG*|CONTRIBUTING*|*.md) ;;
  *) exit 0 ;;
esac

# Skip CLAUDE.md / agents / skills / rules / docs internals — those are
# instructions for Claude itself, not human-facing copy that needs polishing.
case "$FILE" in
  *CLAUDE.md|*CLAUDE.local.md) exit 0 ;;
  */.claude/agents/*|*/.claude/skills/*|*/.claude/rules/*|*/.claude/docs/*) exit 0 ;;
  */.specify/*) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0      # too short to bother
[ "$SIZE" -lt 20000 ] || exit 0    # too long, skip for perf

CONTENT=$(head -c 8000 "$FILE")

SYSTEM='You are a humanizer pre-check. Scan the text for tells of AI-generated writing:
- Em-dash overuse (more than 1 per paragraph)
- Inflated/promotional vocabulary (delve, leverage, robust, comprehensive, seamlessly, navigate, landscape, realm, tapestry, journey)
- Rule of three (lists of three when fewer or more would read more naturally)
- Negative parallelism (not just X, but Y / not only … but also)
- Hollow openers (In todays world, It is important to note, In conclusion)
- Promotional summary closings

Output up to 5 specific issues, one per line, formatted exactly:
- "<short quote>" → <one-line fix suggestion>

If the text reads cleanly, output exactly: CLEAN
No preamble, no markdown headers, nothing else.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 320 2>/dev/null)

[ -n "$REPORT" ] || exit 0
echo "$REPORT" | grep -qE '^[[:space:]]*CLEAN[[:space:]]*$' && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM humanizer pre-check on " + $f + ":\n" + $r + "\nInvoke the humanizer skill (or fix directly) before delivering this text.")}'
