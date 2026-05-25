#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on ASP.NET controllers. Scans HTTP
# action methods (decorated with [HttpGet], [HttpPost], etc.) and
# verifies each has an explicit auth declaration: [Authorize] (with
# any roles/policies) or [AllowAnonymous]. Surfaces endpoints that
# silently inherit auth from elsewhere or have no declaration at all.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

# Only fire on controller files.
case "$(basename "$FILE")" in
  *Controller.cs) ;;
  *) case "$FILE" in
       */Controllers/*) ;;
       *) exit 0 ;;
     esac ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are reviewing an ASP.NET Core controller for authorization coverage.

For each HTTP action method (any method decorated with [HttpGet], [HttpPost], [HttpPut], [HttpPatch], [HttpDelete], [HttpHead], or [Route] used as endpoint), check that one of these is explicitly declared on the method or its containing class:
- [Authorize] (with or without roles/policies)
- [AllowAnonymous]

Note: a class-level [Authorize] covers all methods inside unless overridden by [AllowAnonymous] on a specific method. Inheriting from a base controller with [Authorize] also covers methods (mention this assumption if you cannot see the base).

Report each endpoint without an explicit auth declaration. Output one line per endpoint:
- UNGUARDED: <method name and HTTP verb> | FIX: <add [Authorize] or [AllowAnonymous]>

If every endpoint has explicit auth declaration (or class-level [Authorize] covers them), output exactly: GUARDED
If you cannot determine auth because the file does not contain endpoint methods, output exactly: NOT_AN_ENDPOINT_FILE
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 320 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*(GUARDED|NOT_AN_ENDPOINT_FILE)[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM auth-attribute audit on " + $f + ":\n" + $r + "\nSilent inheritance is risky — be explicit per endpoint.")}'
