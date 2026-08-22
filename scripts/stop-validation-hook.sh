#!/bin/bash
# Stop hook: blocks session end until spec + design compliance are validated.
# Fires when the agent tries to stop. If UI files were modified BY THIS SESSION,
# injects a blocking reminder that forces the agent to validate
# functions-against-spec AND design-against-recommendations before it can stop.
#
# "By this session" is the load-bearing part. `git diff HEAD` describes the
# working tree, not the session, and this project routinely runs two terminals
# at once — a spec being implemented in one, documents in the other. Judged on
# the working tree alone, the documents session inherits the blame for the other
# terminal's uncommitted UI files and gets told to stamp a validation it never
# ran. A gate that fires on work you did not do is a gate you learn to stamp
# your way past, which is worse than no gate.
#
# So UI files are filtered by mtime against this session's start, taken from the
# transcript. If the start cannot be established the filter is skipped and the
# old working-tree behaviour applies — this hook fails toward blocking, never
# toward waving work through.
#
# Returns exit code 2 with reason to block stop; 0 to allow.

set -u

INPUT=$(cat 2>/dev/null || true)

# Loop breaker — see the same guard in continuous-execution-hook.sh. A Stop hook
# that exits 2 unconditionally re-blocks its own continuation forever. One block
# per stop chain; the validation instructions were already delivered on block #1.
if [ -n "$INPUT" ] && [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
  exit 0
fi

# Find repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && exit 0

cd "$REPO_ROOT" || exit 0

# Check for UI file changes in working tree (staged + unstaged)
# Includes native mobile UI: .tsx/.jsx (React Native) and .dart (Flutter widgets).
UI_CHANGED=$(git diff --name-only HEAD 2>/dev/null | grep -iE '\.(tsx|jsx|vue|svelte|html|htm|css|scss|sass|less|razor|cshtml|dart)$' | grep -vE '(node_modules|/dist/|/build/|/\.next/|/wwwroot/.*\.min\.|/bin/|/obj/|\.g\.dart$|\.freezed\.dart$)' | head -20)

# Also check untracked UI files
UI_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep -iE '\.(tsx|jsx|vue|svelte|html|htm|css|scss|sass|less|razor|cshtml|dart)$' | grep -vE '(node_modules|/dist/|/build/|/\.next/|\.g\.dart$|\.freezed\.dart$)' | head -20)

# Join on a newline. Command substitution strips the trailing one, so a bare
# "${UI_CHANGED}${UI_UNTRACKED}" glues the last tracked file to the first
# untracked one into a single nonexistent path — it produced
# "…/CreateAgency.tsxsrc/…/colour-field.tsx" in the block message, and it also
# hides both real files from any per-file matching done below.
ALL_UI=$(printf '%s\n%s' "$UI_CHANGED" "$UI_UNTRACKED" | grep -v '^$')

[ -z "$ALL_UI" ] && exit 0

# No UI changes → allow stop

# ---------------------------------------------------------------------------
# Narrow to what THIS session wrote, from the transcript's own edit history.
#
# File mtimes cannot do this job. They record when a file changed, never who
# changed it, so with a spec being implemented in one terminal while documents
# are written in another, every UI file the other terminal touches looks like
# it belongs to whichever session happens to stop first.
#
# The transcript is unambiguous: it lists every Edit/Write this session made.
# Known limitation — a file written by a shell command rather than by an edit
# tool is invisible here. That is the rare case, and the fallbacks below fail
# toward blocking, so it costs a needless validation rather than a missed one.
# ---------------------------------------------------------------------------
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # Recursive descent rather than a fixed path into the message envelope, so a
  # change in transcript nesting degrades to "found nothing" instead of a crash.
  TOOL_CALLS=$(jq -r '[.. | objects | select(has("name") and has("input"))] | length' \
    "$TRANSCRIPT" 2>/dev/null | awk '{s+=$1} END {print s+0}')

  # No parseable tool calls at all means the transcript is unreadable or in an
  # unexpected shape. Do not trust an empty result as "edited no UI files" —
  # fall through to the working-tree check.
  if [ "${TOOL_CALLS:-0}" -gt 0 ]; then
    EDITED=$(jq -r '[.. | objects
        | select((.name? // "") | test("^(Edit|Write|MultiEdit|NotebookEdit)$"))
        | .input?.file_path? // empty] | .[]' "$TRANSCRIPT" 2>/dev/null \
      | sed "s|^${REPO_ROOT}/||" | sort -u)

    SESSION_UI=""
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if printf '%s\n' "$EDITED" | grep -qxF "$f"; then
        SESSION_UI="${SESSION_UI}${f}"$'\n'
      fi
    done <<< "$ALL_UI"

    # UI files are dirty in the working tree, but this session wrote none of
    # them. They belong to whoever is editing them, and that session carries
    # the gate.
    [ -z "$SESSION_UI" ] && exit 0

    ALL_UI="$SESSION_UI"
  fi
fi

# Check if a "validation complete" marker exists in the most recent commit
# message or in a .claude/validation/last-run file. If the agent has already
# validated this batch, allow stop.
MARKER=".claude/validation/last-validated"
if [ -f "$MARKER" ]; then
  # Cross-platform mtime: GNU stat (-c %Y) first, BSD/macOS (-f %m) fallback.
  # On GNU coreutils `-f` means --file-system, so trying it first prints a
  # filesystem block instead of an mtime and the numeric comparisons below
  # break with "integer expected" — hence GNU-first ordering + numeric guard.
  MARKER_TIME=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null || echo 0)
  case "$MARKER_TIME" in (*[!0-9]*|'') MARKER_TIME=0 ;; esac
  # Find newest UI file mtime
  NEWEST=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ ! -f "$f" ] && continue
    MT=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    case "$MT" in (*[!0-9]*|'') MT=0 ;; esac
    [ "$MT" -gt "$NEWEST" ] && NEWEST=$MT
  done <<< "$ALL_UI"

  if [ "$MARKER_TIME" -ge "$NEWEST" ]; then
    # Validation marker is newer than all UI changes → allow stop
    exit 0
  fi
fi

# Block stop with a forceful reminder
FILE_LIST=$(printf '%s\n' "$ALL_UI" | grep -v '^$' | sed 's/^/  - /' | head -10)

cat <<EOF >&2
STOP BLOCKED — UI changes detected but no validation marker found.

Modified UI files this session:
$FILE_LIST

Before this session can end, you MUST complete ALL of the following:

(1) SPEC COMPLIANCE — Open the feature spec. Enumerate every implemented
    function in its FUNCTIONAL COVERAGE section. Confirm each function has
    a passing UI/E2E test (browser / Maestro / Patrol / widget) AND that the
    assertion verifies real behavior (not just that the screen rendered).
    Fix any gaps NOW.

(2) DESIGN COMPLIANCE — Invoke the frontend-design skill via the Skill tool.
    Validate the UI against its recommendations: typography scale, spacing
    rhythm, color palette, component polish, accessibility (WCAG AA / mobile
    a11y), responsive / safe-area behavior, distinctive design (no generic
    AI aesthetic). Also compare against existing system design — same
    primitives, same patterns. Fix violations NOW.

(3) When BOTH validations pass, record the marker:
       mkdir -p .claude/validation && touch .claude/validation/last-validated

    Then the Stop hook will allow the session to end.

Do NOT skip. Do NOT declare the task complete until both validations pass.
EOF

exit 2
