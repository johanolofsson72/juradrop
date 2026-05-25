#!/usr/bin/env bash
# PostToolUse Edit/Write hook. When a brand-new (essentially empty) README.md
# is created, draft standard sections from surrounding repo state to
# .claude/.local-llm-readme-draft.md.
#
# Skips when README already has substantial content — only fires on
# first creation / placeholder files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
case "$FILE" in
  *README.md|*README) ;;
  *) exit 0 ;;
esac
[ -r "$FILE" ] || exit 0

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -lt 400 ] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$(dirname "$FILE")"

# Gather lightweight repo signals: name from package.json/csproj/Cargo.toml,
# top-level layout, license file presence.
SIGNALS=""
if [ -f "$REPO_ROOT/package.json" ]; then
  SIGNALS="$SIGNALS\npackage.json: $(jq -r '{name, description, scripts: (.scripts // {} | keys)}' "$REPO_ROOT/package.json" 2>/dev/null | head -c 1500)"
fi
CSPROJ=$(find "$REPO_ROOT" -maxdepth 3 -name '*.csproj' 2>/dev/null | head -3)
[ -n "$CSPROJ" ] && SIGNALS="$SIGNALS\ncsproj: $CSPROJ"
[ -f "$REPO_ROOT/Cargo.toml" ] && SIGNALS="$SIGNALS\nCargo.toml present"
[ -f "$REPO_ROOT/pyproject.toml" ] && SIGNALS="$SIGNALS\npyproject.toml present"
[ -f "$REPO_ROOT/Dockerfile" ] && SIGNALS="$SIGNALS\nDockerfile present"
[ -f "$REPO_ROOT/LICENSE" ] && SIGNALS="$SIGNALS\nLICENSE present"
TOP=$(ls -1 "$REPO_ROOT" 2>/dev/null | head -30)
SIGNALS="$SIGNALS\nTop-level entries:\n$TOP"

PAYLOAD=$(printf 'Repo signals:\n%s\n' "$SIGNALS")

SYSTEM='Draft a README.md skeleton for a software repository based on the signals provided.

Output sections (omit any that have no support in the signals):

# <project name from signals, or [Project Name] if unknown>

<one-line description>

## Overview
<2-4 sentences on what the project does>

## Setup
<bullet steps with placeholders>

## Usage
<bullet steps or short example>

## Configuration
<env vars or config files referenced in signals — bullets>

## Project structure
<short tree of top-level directories with one-line descriptions>

## Development
<test/build commands inferred from signals>

## License
<reference LICENSE file if present, else placeholder>

Rules:
- Use placeholders [LIKE THIS] only when you genuinely cannot infer from signals
- Do not invent commands or features
- Plain markdown, no emojis, no badges
- Max 100 lines'

DRAFT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 2048 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-readme-draft.md"
mkdir -p "$DRAFT_DIR"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM README skeleton saved at " + $p + ". Read and refine this draft when filling out README.md — verify every command and feature claim against the actual codebase before adopting.")}'
