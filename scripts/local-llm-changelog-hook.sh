#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on CHANGELOG.md. When the user (or
# assistant) opens the changelog, the local LLM reads commits since the
# previous git tag, groups them by Conventional Commit type, and drafts
# entries in keep-a-changelog format. Saved to a sibling draft file so
# the assistant can splice the relevant section into the real CHANGELOG.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0

# Only fire on files literally named CHANGELOG.md (case-insensitive, any path).
case "$(basename "$FILE")" in
  CHANGELOG.md|CHANGELOG.MD|changelog.md|Changelog.md) ;;
  *) exit 0 ;;
esac

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Find previous tag. If none exists, use first commit.
PREV_TAG=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null) || PREV_TAG=""
if [ -n "$PREV_TAG" ]; then
  RANGE="${PREV_TAG}..HEAD"
  RANGE_LABEL="since tag $PREV_TAG"
else
  RANGE="HEAD"
  RANGE_LABEL="full history (no tags found)"
fi

COMMIT_LOG=$(git -C "$REPO_ROOT" log --oneline --no-merges "$RANGE" 2>/dev/null | head -100)
[ -n "$COMMIT_LOG" ] || exit 0

# Sample some commit bodies for richer context (first 20 commits with full message).
COMMIT_DETAIL=$(git -C "$REPO_ROOT" log --pretty=format:'%h %s%n%n%b%n---' --no-merges "$RANGE" 2>/dev/null | head -c 6000)

SYSTEM='Draft CHANGELOG entries from a list of commits in keep-a-changelog format.

Group commits under these headings (omit empty groups):
### Added       — for new features (feat:)
### Changed     — for changes to existing functionality (refactor:, perf:)
### Fixed       — for bug fixes (fix:)
### Removed     — for removed features (revert:, removed: in body)
### Security    — for security-related changes
### Documentation — for docs-only changes (docs:)

Rules:
- One bullet per commit, imperative mood, ≤90 chars per bullet
- Strip the conventional prefix (feat:, fix:, etc.) — the heading conveys the type
- Include commit short SHA at end in parens: "Add user export (a1b2c3d)"
- Skip chore: and ci: commits unless they are user-visible
- Squash near-duplicate commits (e.g. multiple "fix typo" → one bullet)
- No marketing language, no emoji

Output ONLY the grouped bullet list under headings. No preamble, no top-level title, no version header.'

DRAFT=$(printf 'Range: %s\n\nCommit log (subjects):\n%s\n\nCommit details (subjects + bodies):\n%s\n' \
  "$RANGE_LABEL" "$COMMIT_LOG" "$COMMIT_DETAIL" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-changelog-draft.md"
mkdir -p "$DRAFT_DIR"
{
  echo "# CHANGELOG draft ($RANGE_LABEL)"
  echo ""
  echo "$DRAFT"
} > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" --arg r "$RANGE_LABEL" \
  '{additionalContext: ("Local-LLM CHANGELOG draft prepared at " + $p + " (" + $r + "). Read and splice relevant entries into CHANGELOG.md — sanity-check against actual commits, do not paste verbatim.")}'
