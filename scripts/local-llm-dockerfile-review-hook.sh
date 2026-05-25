#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on Dockerfiles. Scans for production
# safety and image-quality issues: missing HEALTHCHECK, running as
# root, FROM ...:latest, secrets baked into ENV, missing .dockerignore.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

case "$(basename "$FILE")" in
  Dockerfile|Dockerfile.*|*.dockerfile|*.Dockerfile) ;;
  *) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 50 ] || exit 0
[ "$SIZE" -lt 20000 ] || exit 0

CONTENT=$(head -c 8000 "$FILE")

# Check for sibling .dockerignore (mention if missing).
DIR=$(dirname "$FILE")
HAS_DOCKERIGNORE="no"
[ -r "$DIR/.dockerignore" ] && HAS_DOCKERIGNORE="yes"

PAYLOAD=$(printf 'Dockerfile content:\n%s\n\nSibling .dockerignore present: %s\n' "$CONTENT" "$HAS_DOCKERIGNORE")

SYSTEM='You are reviewing a Dockerfile for production safety and image hygiene.

Scan for these specific issues:
- Missing HEALTHCHECK directive (orchestrator cannot detect unhealthy containers)
- No USER directive, or USER root explicitly (containers should run as non-root)
- FROM <image>:latest (non-pinned base image causes silent breakage)
- Secrets in ENV (API keys, passwords, tokens — should use build-time --secret or runtime env injection)
- COPY . . without a sibling .dockerignore (bloats image with .git, node_modules, build artifacts, secrets)
- apt-get update without && apt-get install in same RUN (cache invalidation issues)
- apt-get without --no-install-recommends (bloat)
- Missing rm -rf /var/lib/apt/lists/* after apt-get install (cache bloat)
- ADD when COPY would suffice (ADD has implicit unzip and URL-fetch surprises)
- Multiple RUN commands that could be chained (each RUN creates a layer)
- Missing CMD or ENTRYPOINT
- EXPOSE without specifying a port

For each issue found, output one line:
- RISK: <one-line description> | FIX: <concrete remediation, often a Dockerfile snippet>

If the Dockerfile follows good practices, output exactly: SAFE
No preamble, no markdown.'

REPORT=$(printf '%s' "$PAYLOAD" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 512 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*SAFE[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM Dockerfile review on " + $f + ":\n" + $r + "\nReview before building production image.")}'
