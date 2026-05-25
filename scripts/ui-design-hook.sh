#!/bin/bash
# PreToolUse hook: enforces frontend-design skill usage on UI file edits.
# Fires on Edit|Write. Injects additionalContext reminding the agent to:
#   1. Invoke frontend-design skill BEFORE writing UI code
#   2. Match existing design system (typography, spacing, colors, patterns)
#   3. Validate against frontend-design recommendations after the edit
#
# The skill enforcement itself cannot be verified from a shell hook (no session
# state), so this hook provides an unavoidable reminder via additionalContext.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0

# UI file extensions: React/Vue/Svelte, HTML, stylesheets, Razor/Blazor
if ! echo "$FILE" | grep -qiE '\.(tsx|jsx|vue|svelte|html|htm|css|scss|sass|less|razor|cshtml)$'; then
  exit 0
fi

# Skip node_modules, build output, and vendored files
if echo "$FILE" | grep -qE '(node_modules|/dist/|/build/|/\.next/|/wwwroot/.*\.min\.|/bin/|/obj/)'; then
  exit 0
fi

cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "UI FILE DETECTED — BLOCKING DESIGN REQUIREMENTS:\n\n(1) The frontend-design skill MUST have been invoked via the Skill tool in this session before writing UI code. If not invoked yet, STOP this edit, invoke frontend-design first, then retry the edit.\n\n(2) You MUST match the existing system design — inspect similar components/pages already in the repo and reuse their typography scale, spacing rhythm, color palette, component primitives, and naming conventions. Do NOT introduce a new design language.\n\n(3) After the edit, explicitly verify against frontend-design recommendations: distinctive design (no generic AI aesthetic), proper hierarchy, accessibility (WCAG AA contrast, keyboard nav, ARIA), responsive behavior, polished micro-interactions. Report compliance explicitly in your next message — state which checks passed and which failed.\n\n(4) If you cannot justify a design decision against (a) frontend-design recommendations AND (b) the existing system design, revert and reconsider."
  }
}
JSON
