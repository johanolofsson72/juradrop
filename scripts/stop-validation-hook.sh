#!/bin/bash
# Stop hook: blocks session end until spec + design compliance are validated.
# Fires when the agent tries to stop. If UI files were modified this session
# (detected via git diff against HEAD), injects a blocking reminder that forces
# the agent to validate functions-against-spec AND design-against-recommendations
# before it can actually stop.
#
# Returns exit code 2 with reason to block stop; 0 to allow.

set -u

# Find repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && exit 0

cd "$REPO_ROOT" || exit 0

# Check for UI file changes in working tree (staged + unstaged)
UI_CHANGED=$(git diff --name-only HEAD 2>/dev/null | grep -iE '\.(tsx|jsx|vue|svelte|html|htm|css|scss|sass|less|razor|cshtml)$' | grep -vE '(node_modules|/dist/|/build/|/\.next/|/wwwroot/.*\.min\.|/bin/|/obj/)' | head -20)

# Also check untracked UI files
UI_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep -iE '\.(tsx|jsx|vue|svelte|html|htm|css|scss|sass|less|razor|cshtml)$' | grep -vE '(node_modules|/dist/|/build/|/\.next/)' | head -20)

ALL_UI="${UI_CHANGED}${UI_UNTRACKED}"

# No UI changes → allow stop
[ -z "$ALL_UI" ] && exit 0

# Check if a "validation complete" marker exists in the most recent commit
# message or in a .claude/validation/last-run file. If the agent has already
# validated this batch, allow stop.
MARKER=".claude/validation/last-validated"
if [ -f "$MARKER" ]; then
  MARKER_TIME=$(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0)
  # Find newest UI file mtime
  NEWEST=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ ! -f "$f" ] && continue
    MT=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    [ "$MT" -gt "$NEWEST" ] && NEWEST=$MT
  done <<< "$ALL_UI"

  if [ "$MARKER_TIME" -ge "$NEWEST" ]; then
    # Validation marker is newer than all UI changes → allow stop
    exit 0
  fi
fi

# Block stop with a forceful reminder
FILE_LIST=$(echo "$ALL_UI" | sed 's/^/  - /' | head -10)

cat <<EOF >&2
STOP BLOCKED — UI changes detected but no validation marker found.

Modified UI files this session:
$FILE_LIST

Before this session can end, you MUST complete ALL of the following:

(1) SPEC COMPLIANCE — Open the feature spec. Enumerate every implemented
    function in its FUNCTIONAL COVERAGE section. Confirm each function has
    a passing browser test AND that the assertion verifies real behavior
    (not just that the page rendered). Fix any gaps NOW.

(2) DESIGN COMPLIANCE — Invoke the frontend-design skill via the Skill tool.
    Validate the UI against its recommendations: typography scale, spacing
    rhythm, color palette, component polish, accessibility (WCAG AA),
    responsive behavior, distinctive design (no generic AI aesthetic).
    Also compare against existing system design — same primitives, same
    patterns. Fix violations NOW.

(3) When BOTH validations pass, record the marker:
       mkdir -p .claude/validation && touch .claude/validation/last-validated

    Then the Stop hook will allow the session to end.

Do NOT skip. Do NOT declare the task complete until both validations pass.
EOF

exit 2
