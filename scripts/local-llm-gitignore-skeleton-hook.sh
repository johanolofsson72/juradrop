#!/usr/bin/env bash
# PostToolUse Edit/Write hook. When a brand-new (essentially empty)
# .gitignore is created, scaffold language-appropriate ignores from
# detected repo signals to .claude/.local-llm-gitignore-draft.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
case "$FILE" in
  */.gitignore|.gitignore) ;;
  *) exit 0 ;;
esac
[ -r "$FILE" ] || exit 0

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -lt 200 ] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$(dirname "$FILE")"

LANGS=""
[ -f "$REPO_ROOT/package.json" ] && LANGS="$LANGS node"
[ -n "$(find "$REPO_ROOT" -maxdepth 3 -name '*.csproj' 2>/dev/null | head -1)" ] && LANGS="$LANGS dotnet"
[ -f "$REPO_ROOT/Cargo.toml" ] && LANGS="$LANGS rust"
[ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/setup.py" ] && LANGS="$LANGS python"
[ -f "$REPO_ROOT/go.mod" ] && LANGS="$LANGS go"
[ -f "$REPO_ROOT/Gemfile" ] && LANGS="$LANGS ruby"
[ -f "$REPO_ROOT/composer.json" ] && LANGS="$LANGS php"
[ -f "$REPO_ROOT/Dockerfile" ] && LANGS="$LANGS docker"

[ -n "$LANGS" ] || LANGS="generic"

PAYLOAD=$(printf 'Detected stacks: %s\n' "$LANGS")

SYSTEM='Generate a .gitignore for a software repository.

Output ONLY the .gitignore content — no preamble, no explanation, no code fences.
Group ignores by stack with a single-line section comment per group, e.g.:

# Node
node_modules/
dist/

# .NET
bin/
obj/

Rules:
- Cover only the detected stacks
- Always include OS noise (.DS_Store, Thumbs.db) and editor noise (.vscode/, .idea/, *.swp) as their own sections
- Do not include exotic patterns the project clearly does not use
- Max 60 lines'

DRAFT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 768 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-gitignore-draft.md"
mkdir -p "$DRAFT_DIR"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM .gitignore scaffold saved at " + $p + ". Read and adapt before adopting — strip patterns for stacks the project does not use, add project-specific build/cache dirs.")}'
