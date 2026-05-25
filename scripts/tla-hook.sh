#!/bin/bash
# PostToolUse hook: detect browser/E2E test files and remind about TLA+ verification
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [ -n "$FILE" ] && echo "$FILE" | grep -qiE '(test|spec).*(playwright|e2e|browser|destructive|ui)' && echo "$FILE" | grep -qiE '\.(cs|ts|js)$'; then
  echo '{"systemMessage": "Browser/E2E test file detected. After all browser tests for this feature are complete, run TLA+ formal verification (/tla) to check for race conditions, state machine gaps, and missing invariants before considering the feature done."}'
fi
