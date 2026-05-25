#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on source/config files. Combines a
# cheap regex pre-filter (catch likely secrets) with a local LLM
# review (filter out false positives like test data, variable names,
# type annotations). Keeps real secrets out of commits without
# drowning the developer in false alarms.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

# Skip lock files, vendored, build output, and obvious binary directories.
case "$FILE" in
  *node_modules/*|*/bin/*|*/obj/*|*/dist/*|*/build/*|*.lock|*-lock.json|*.lock.json|*.png|*.jpg|*.gif|*.pdf) exit 0 ;;
esac

# Whitelist source/config extensions where secrets typically appear.
case "$FILE" in
  *.cs|*.ts|*.tsx|*.js|*.jsx|*.py|*.rb|*.go|*.rs|*.java|*.kt|*.swift|*.php|*.sh|*.bash|*.zsh) ;;
  *.json|*.yaml|*.yml|*.toml|*.env|*.env.*|*.properties|*.conf|*.config) ;;
  *.dockerfile|Dockerfile|Dockerfile.*) ;;
  *) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 50 ] || exit 0
[ "$SIZE" -lt 50000 ] || exit 0

# Pre-filter: cheap regex catches likely secret patterns. Common ones first.
SECRET_HITS=$(grep -nE '(api[_-]?key|secret|password|passwd|token|bearer|authorization|aws_access|aws_secret|AKIA[A-Z0-9]{16}|sk_live_[A-Za-z0-9]{20,}|sk_test_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]+|-----BEGIN[[:space:]]+(RSA|EC|DSA|OPENSSH)[[:space:]]+PRIVATE[[:space:]]+KEY)' "$FILE" 2>/dev/null | head -20)
[ -n "$SECRET_HITS" ] || exit 0

PAYLOAD=$(printf 'File: %s\n\nMatched lines (line:content):\n%s\n' "$FILE" "$SECRET_HITS")

SYSTEM='You are reviewing potential secret leaks. A regex pre-filter has matched lines containing secret-like keywords. Your job: distinguish real secrets from false positives.

REAL secret examples (FLAG these — high-entropy values directly assigned to secret-shaped names):
- api_key assigned a long random-looking string of mixed alnum chars
- DATABASE_PASSWORD assigned a non-placeholder password value
- aws_secret_access_key assigned a 40-char base64-ish string
- private_key containing PEM-format key blocks
- bearer/token assigned a long opaque string in source code (not env)
- Hardcoded JWT (header.payload.signature triplet) in JS/TS

FALSE positives (DO NOT flag):
- Variable name only: `string apiKey;`, `password: string;`, `let token = ...`
- Type/interface declaration: `interface Auth { token: string; }`
- Test data with obvious placeholder: `password = "test"`, `apiKey = "fake_key_for_test"`, `secret = "x"`, `password = ""`
- Reading from env: `process.env.API_KEY`, `Environment.GetEnvironmentVariable("PASSWORD")`, `os.environ["TOKEN"]`
- Documentation/comment showing format: `// api_key format: sk_live_...`
- Constants for env var NAMES: `const API_KEY_ENV = "API_KEY"`
- Function/parameter names: `void SetPassword(string password)`
- Schema/migration column definitions: `Column("password_hash")`

For each REAL secret, output one line:
- LEAK: <line number>: <truncated content> | <one-line reason this looks real>

If all matches are false positives, output exactly: NO_LEAKS
No preamble, no markdown.'

REPORT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*NO_LEAKS[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM secret-leak scan on " + $f + ":\n" + $r + "\nVerify before committing — secrets in git history persist forever.")}'
