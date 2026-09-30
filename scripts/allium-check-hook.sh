#!/bin/bash
# PostToolUse hook: validate every written .allium file with `allium check`.
#
# Measured in rocky 2026-09-26: 136 of 592 spec.allium baselines carried errors (130 did not
# parse), and nothing noticed, because the only validation step was a sentence in the allium
# skill. /tla compares its distilled spec against that baseline, so a baseline the tool cannot
# read turns the drift report into a report about a document nobody parsed.
#
# Decisions:
# - Blocks on severity == "error" only, never on the CLI's exit code. The CLI exits 1 on
#   warnings, and warnings are advice.
# - A CLI older than 3.3.0 gets one model note per session (template row 050). Before 3.3.0 the
#   deferred location-hint lint read the parsed path, which drops comments, so every `deferred`
#   warned whatever it said. A version that does not parse gets no note: advice, not a verdict.
# - A report it cannot read (crash, non-JSON, unexpected shape, timeout) blocks. An unreadable
#   report is not a clean one.
# - No CLI on PATH passes, with a once-per-session notice, so a missing tool never reads as a
#   clean file.
set -u

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hook-notice.sh"

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
SID=$(hn_session_id "$INPUT")

case "$FILE" in
  *.allium) ;;
  *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

ALLIUM_BIN="${ALLIUM_BIN:-allium}"
TIMEOUT="${ALLIUM_CHECK_TIMEOUT:-30}"

if ! command -v "$ALLIUM_BIN" >/dev/null 2>&1; then
  notice_once PostToolUse "$SID" "allium-cli-missing" \
"allium CLI not installed — .allium files are NOT being validated. Install it (brew tap juxt/allium && brew install allium) or check the file by hand against the allium skill's grammar."
  exit 0
fi

ALLIUM_MIN_MAJOR=3
ALLIUM_MIN_MINOR=3
OLD_NOTE=""
VER=$(perl -e 'alarm shift; exec @ARGV' 5 "$ALLIUM_BIN" --version 2>/dev/null \
  | sed -n '1s/^[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
if [ -n "$VER" ]; then
  IFS=. read -r VMAJ VMIN _ <<< "$VER"
  if [ "$VMAJ" -lt "$ALLIUM_MIN_MAJOR" ] \
     || { [ "$VMAJ" -eq "$ALLIUM_MIN_MAJOR" ] && [ "$VMIN" -lt "$ALLIUM_MIN_MINOR" ]; }; then
    OLD_NOTE="allium $VER is older than $ALLIUM_MIN_MAJOR.$ALLIUM_MIN_MINOR.0. On this CLI the deferred location-hint lint cannot be satisfied: every \`deferred\` warns, even the documented \`deferred X -- see: path.allium\`. Treat allium.deferred.missingLocationHint as noise here (every other warning still means something), keep writing the -- see: form, and tell the developer to upgrade: brew upgrade juxt/allium/allium, or cargo install allium-cli --force."
  fi
fi

# macOS has no timeout(1); perl's alarm kills the child after TIMEOUT seconds (exit 142).
OUT=$(perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$ALLIUM_BIN" check "$FILE" 2>/dev/null)
RC=$?

REASON=$(printf '%s' "$OUT" | python3 -c '
import json, sys
file, rc, timeout = sys.argv[1], int(sys.argv[2]), sys.argv[3]
if rc == 142:
    print(f"allium check timed out after {timeout}s on {file} - the file could not be validated. Fix or simplify it and write it again.")
    sys.exit(0)
try:
    d = json.load(sys.stdin)
    diags = d["diagnostics"]
    if not isinstance(diags, list):
        raise ValueError("diagnostics is not a list")
    errs = [x for x in diags if x.get("severity") == "error"]
except Exception as ex:
    print(f"allium check produced no readable report for {file} (exit {rc}: {ex}) - the file could not be validated.")
    sys.exit(0)
if not errs:
    sys.exit(0)
cap = 20
lines = []
for x in errs[:cap]:
    loc = x.get("location") or {}
    line, col, msg = loc.get("line", "?"), loc.get("col", "?"), x.get("message", "")
    lines.append(f"  {line}:{col} {msg}")
if len(errs) > cap:
    lines.append(f"  ... and {len(errs) - cap} more")
print(f"{file} does not pass allium check: {len(errs)} error(s). Fix them before moving on (warnings do not block):\n" + "\n".join(lines))
' "$FILE" "$RC" "$TIMEOUT")
PY=$?

# The reader itself failing must never read as a clean file.
if [ "$PY" -ne 0 ]; then
  REASON="allium-check-hook could not read the allium check report for $FILE (reader exit $PY) - the file could not be validated."
fi

if [ -n "$OLD_NOTE" ]; then
  # One JSON object on stdout: a block carries the note, a pass says it once per session.
  if [ -n "$REASON" ]; then
    REASON="$REASON

$OLD_NOTE"
  else
    notice_once PostToolUse "$SID" "allium-cli-old" "$OLD_NOTE"
  fi
fi

[ -z "$REASON" ] && exit 0

jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
exit 0
