#!/usr/bin/env bash
# PostToolUse Edit/Write hook. When .env / .env.local / .env.development is
# written, scan the repo for env-var references and produce a .env.example
# scaffold at .claude/.local-llm-env-example-draft.md.
#
# Helps Claude generate .env.example without re-greping the whole codebase.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
case "$FILE" in
  */.env|*/.env.local|*/.env.development|*/.env.production|.env|.env.*) ;;
  *) exit 0 ;;
esac

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$(dirname "$FILE")"

# Grep for env var references. Limit to source/config files; bound output.
REFS=$(grep -rhoE \
  -e 'process\.env\.[A-Z_][A-Z0-9_]+' \
  -e 'Environment\.GetEnvironmentVariable\("[A-Z_][A-Z0-9_]+"\)' \
  -e 'os\.environ\[?\.?[gG]et?\(?"?[A-Z_][A-Z0-9_]+' \
  -e 'ENV\["[A-Z_][A-Z0-9_]+"\]' \
  -e 'getenv\("[A-Z_][A-Z0-9_]+"\)' \
  --include='*.cs' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
  --include='*.py' --include='*.rb' --include='*.go' --include='*.php' \
  "$REPO_ROOT" 2>/dev/null \
  | grep -oE '[A-Z_][A-Z0-9_]+' \
  | grep -vE '^(GET|POST|PUT|DELETE|HEAD|TRUE|FALSE|NULL|NONE)$' \
  | sort -u \
  | head -80)

[ -n "$REFS" ] || exit 0

PAYLOAD=$(printf 'Env vars referenced in code:\n%s\n' "$REFS")

SYSTEM='Generate a .env.example file from the list of environment variables referenced in code.

Output ONLY the .env.example content — no preamble, no markdown.
Format:

# <Group label>
VAR_NAME=<placeholder describing expected shape>

Rules:
- Group related vars (DATABASE_*, AWS_*, STRIPE_*, etc.)
- Placeholder shows the expected format, not a real value: e.g. DATABASE_URL=postgres://user:pass@host:5432/dbname
- For secrets, use placeholders like sk_test_xxxxx or your_api_key_here
- One var per line
- Max 80 lines'

DRAFT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 1024 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-env-example-draft.md"
mkdir -p "$DRAFT_DIR"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM .env.example scaffold saved at " + $p + ". Read and refine before adopting — verify each var is actually needed and that placeholders document the expected format. Never copy real secrets into .env.example.")}'
