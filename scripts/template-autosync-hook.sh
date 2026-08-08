#!/bin/bash
# SessionStart hook: keeps a project's Claude Code config current with the
# template repo without anyone ever typing /project-update.
#
# Runs scripts/template-autosync.sh (deterministic file sync + core-hook
# rewiring + commit), then reports what happened as a systemMessage so the
# session opens knowing its own config just moved.
#
# Cheap by construction:
#   - rate-limited to once per TEMPLATE_AUTOSYNC_INTERVAL seconds (default 6h)
#     via the mtime of .claude/.template-sync-check, so opening five sessions
#     in an afternoon costs one network round-trip, not five;
#   - when a local template clone exists, the version check is a local
#     `git rev-parse` (no network at all);
#   - when only the remote exists, it is one `git ls-remote` and the tarball is
#     downloaded ONLY if the SHA actually moved.
#
# Fails open, always: any error exits 0 silently. A template sync problem must
# never stop a session from starting.
#
# Opt out per project:  export CLAUDE_TEMPLATE_AUTOSYNC=0
# Force a check now:    CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS=1

set -u

[ "${CLAUDE_TEMPLATE_AUTOSYNC:-1}" = "0" ] && exit 0

INTERVAL="${TEMPLATE_AUTOSYNC_INTERVAL:-21600}"   # 6h

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || exit 0
[ -d "$PROJECT_ROOT/.claude" ] || exit 0
[ -x "$PROJECT_ROOT/scripts/template-autosync.sh" ] || [ -f "$PROJECT_ROOT/scripts/template-autosync.sh" ] || exit 0

# The template repo itself is never a sync target (identified by remote URL —
# file markers get copied into every project by the sync itself).
case "$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)" in
  *johanolofsson72/Claude.git|*johanolofsson72/Claude|*:johanolofsson72/Claude*) exit 0 ;;
esac

# ------------------------------------------------------------- rate limiting
MARKER="$PROJECT_ROOT/.claude/.template-sync-check"
if [ "${CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS:-0}" != "1" ] && [ -f "$MARKER" ]; then
  NOW=$(date +%s)
  MT=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null || echo 0)
  [ $((NOW - MT)) -lt "$INTERVAL" ] && exit 0
fi
: > "$MARKER" 2>/dev/null

# ------------------------------------------------------------------ the sync
RUNNER="bash"
if command -v timeout >/dev/null 2>&1; then RUNNER="timeout 120 bash"
elif command -v gtimeout >/dev/null 2>&1; then RUNNER="gtimeout 120 bash"; fi

OUT=$(cd "$PROJECT_ROOT" && CLAUDE_PROJECT_DIR="$PROJECT_ROOT" \
      $RUNNER scripts/template-autosync.sh --quiet 2>&1)
RC=$?
[ "$RC" -ne 0 ] && exit 0            # fail open

case "$OUT" in
  *"[synced]"*) ;;                   # the sync ran
  *) exit 0 ;;                       # up to date / skipped — stay silent
esac

# A run that wrote nothing is not news. Only speak when files actually moved —
# otherwise every session start after a template no-op costs context for nothing.
case "$OUT" in
  *"0 updated, 0 added"*) exit 0 ;;
esac

MSG=$(printf '%s' "$OUT" | sed -e 's/"/\\"/g' -e 's/$/\\n/' | tr -d '\n')
printf '{"systemMessage": "Template auto-sync ran on this project.\\n%s\\nConfig files changed on disk. Hooks and rules reload at session start, so this session already has the new versions. If the summary lists locally-modified files that were skipped, run /project-update to merge those by hand."}\n' "$MSG"
exit 0
