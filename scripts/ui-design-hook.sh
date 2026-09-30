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

# Cheapest exit first (spec 073, R9): a path ending in a UI extension appears in the raw JSON as
# `.<ext>"` (escaping leaves letters, dots and the closing quote alone), so an input without one of
# these cannot pass the extension test below. That saves a jq and two greps on every non-UI edit. A
# match only means "look properly" — the tests below still decide.
# Bounded to small payloads: bash's matchers are slow on long strings (a 200 KB Write took longer to
# scan than jq takes to start), so a large payload skips this and pays exactly what it paid before.
if [ "${#INPUT}" -le 4096 ]; then
  shopt -s nocasematch
  [[ $INPUT =~ \.(tsx|jsx|vue|svelte|html|htm|css|scss|sass|less|razor|cshtml)\" ]] || exit 0
  shopt -u nocasematch
fi
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0

# UI file extensions: React/Vue/Svelte, HTML, stylesheets, Razor/Blazor
if ! grep -qiE '\.(tsx|jsx|vue|svelte|html|htm|css|scss|sass|less|razor|cshtml)$' <<< "$FILE"; then
  exit 0
fi

# Skip node_modules, build output, and vendored files
if grep -qE '(node_modules|/dist/|/build/|/\.next/|/wwwroot/.*\.min\.|/bin/|/obj/)' <<< "$FILE"; then
  exit 0
fi

# Is the gate this reminder demands reachable at all (spec 006)? Without the plugin the Skill call
# fails, and the reminder below would tell the model to do something it cannot do, with nobody told.
# Exit 1 only: "cannot tell" (3) and an absent checker fall through to today's reminder.
HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$HOOK_DIR/skill-reachable.sh" ]; then
  MISSING_LINE=$(bash "$HOOK_DIR/skill-reachable.sh" frontend-design 2>/dev/null)
  if [ "$?" -eq 1 ] && [ -f "$HOOK_DIR/hook-notice.sh" ]; then
    . "$HOOK_DIR/hook-notice.sh"
    HINT=${MISSING_LINE#*— }
    notice_both PreToolUse \
      "Design gate unreachable: the frontend-design skill is not installed on this machine. Install: $HINT" \
      "UI FILE DETECTED, BUT THE BLOCKING DESIGN GATE CANNOT BE MET: the frontend-design skill is not reachable on this machine (scripts/skill-reachable.sh: $MISSING_LINE). Invoking it via the Skill tool will fail. Do NOT claim it was applied. Tell the developer it is missing and how to install it ($HINT), and hold UI work until they install it or explicitly waive the gate for this change. Everything else still applies: match the existing design system (typography, spacing, colors, component primitives) and report accessibility and responsive checks explicitly."
    exit 0
  fi
fi

cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "UI FILE DETECTED — BLOCKING DESIGN REQUIREMENTS:\n\n(1) The frontend-design skill MUST have been invoked via the Skill tool in this session before writing UI code. If not invoked yet, STOP this edit, invoke frontend-design first, then retry the edit.\n\n(2) You MUST match the existing system design — inspect similar components/pages already in the repo and reuse their typography scale, spacing rhythm, color palette, component primitives, and naming conventions. Do NOT introduce a new design language.\n\n(3) After the edit, explicitly verify against frontend-design recommendations: distinctive design (no generic AI aesthetic), proper hierarchy, accessibility (WCAG AA contrast, keyboard nav, ARIA), responsive behavior, polished micro-interactions. Report compliance explicitly in your next message — state which checks passed and which failed.\n\n(4) If you cannot justify a design decision against (a) frontend-design recommendations AND (b) the existing system design, revert and reconsider."
  }
}
JSON
