#!/bin/bash
# PostToolUse hook: detect browser / native-E2E test files and remind about TLA+ verification.
#
# Parity across platforms — the /tla reminder must fire whether the dev just wrote a
# Playwright spec OR a mobile native-E2E flow:
#   - Web:     Playwright / browser / destructive specs in .cs / .ts / .tsx / .js / .jsx
#   - RN/Expo: Maestro flows under .maestro/ (or *maestro*.yaml)
#   - Flutter: Patrol / integration_test / widget destructive specs in *.dart
#
# CHANNEL (spec 046): the reminder is addressed to the model, so it goes out as
# additionalContext and produces no transcript entry. It used to be a
# `systemMessage` — "Warning shown to user in UI" — which meant every pass over
# a spec file printed the same paragraph at the developer in red.
#
# ONCE PER FILE PER SESSION: a test file is written in several passes. The
# reminder is about the file, not about the edit, so it fires on the first pass
# and stays quiet for the rest.
set -u

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$HOOK_DIR/hook-notice.sh"

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

MATCH=""
# Web browser/E2E test: keyword + web test extension
if echo "$FILE" | grep -qiE '(test|spec).*(playwright|e2e|browser|destructive|ui)' && echo "$FILE" | grep -qiE '\.(cs|ts|tsx|js|jsx)$'; then
  MATCH=1
# Maestro flow (React Native / Expo): under .maestro/ or a *maestro* YAML file
elif echo "$FILE" | grep -qiE '(^|/)\.maestro/|maestro' && echo "$FILE" | grep -qiE '\.ya?ml$'; then
  MATCH=1
# Flutter native E2E / widget destructive: integration_test/, patrol, or a *_test.dart / destructive .dart
elif echo "$FILE" | grep -qiE '(integration_test|patrol|destructive|e2e|_test|test_)' && echo "$FILE" | grep -qiE '\.dart$'; then
  MATCH=1
fi

[ -z "$MATCH" ] && exit 0

SID=$(hn_session_id "$INPUT")
notice_once PostToolUse "$SID" "tla:$FILE" \
"E2E / destructive test file detected (web: Playwright; mobile: Maestro flow or Patrol/integration_test). After ALL functional + destructive tests for this feature are green, run TLA+ formal verification (/tla) to check for race conditions, state machine gaps, and missing invariants before considering the feature done."
exit 0
