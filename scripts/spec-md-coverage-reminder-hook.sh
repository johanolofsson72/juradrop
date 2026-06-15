#!/bin/bash
# PostToolUse hook: deterministic reminder for spec/plan/tasks/feature .md files.
# Replaces the type:"prompt" hook that was incorrectly issuing block decisions.
#
# Behavior contract:
#   - NEVER blocks. Output is always a systemMessage (advisory) or nothing.
#   - Only fires on .md files whose path contains spec, tasks, plan, or feature.
#   - Only fires when the file mentions interactive-UI patterns.
#   - Suppresses the destructive-test reminder when the slice explicitly carves
#     destructive scenarios to another slice (the model was blocking on this).
#
# Why deterministic (not type:"prompt"):
#   - The prompt-hook lets the session LLM decide the verdict. Even when the
#     prompt says "Do NOT block — always approve and use systemMessage", the
#     model has been observed overriding that instruction under pressure from
#     CLAUDE.md + memory rules about destructive tests. Deterministic bash
#     cannot be overridden.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Only .md files
case "$FILE" in
  *.md) ;;
  *) exit 0 ;;
esac

# Only paths containing spec, tasks, plan, or feature (case-insensitive)
if ! echo "$FILE" | grep -qiE '(spec|tasks|plan|feature)'; then
  exit 0
fi

CONTENT=$(cat "$FILE" 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

# --- Detect interactive-UI patterns ---
# Forms, input fields, buttons that mutate state, multi-step flows, auth,
# file upload, search/filter, drag-and-drop. Static content / styling / i18n
# do not count.
INTERACTIVE_RE='(\bform\b|\binput\b|\bbutton\b|\bsubmit\b|click|\bmodal\b|drawer|dialog|approval|multi-?step|wizard|authenticate|sign[ -]?in|sign[ -]?up|login|logout|upload|drag[ -]?and[ -]?drop|search|filter|create.*edit.*delete|CRUD)'

if ! echo "$CONTENT" | grep -qiE "$INTERACTIVE_RE"; then
  # Non-interactive spec — nothing to remind about
  exit 0
fi

# --- Carve-out detection ---
# If the spec text explicitly defers destructive tests to a different slice,
# suppress the reminder. Look for phrases near "destructive" or "DT-".
CARVED=0
if echo "$CONTENT" | grep -qiE '(carved (out )?to|carved to|out[ -]of[ -]scope|deferred to|moved to|tracked in|covered (in|by)|see slice|in slice [0-9])'; then
  # Cross-check: the carve-out must be in proximity to destructive-test context.
  # Conservative: only suppress if BOTH a carve phrase AND a destructive-test
  # reference appear in the file.
  if echo "$CONTENT" | grep -qiE '(destructive|DT-?[0-9]+|attack categor)'; then
    CARVED=1
  fi
fi

# --- Check (1): functional coverage section ---
HAS_FUNCTIONAL=0
if echo "$CONTENT" | grep -qiE '(functional coverage|coverage inventory|functions? (covered|under test)|test (matrix|inventory))'; then
  HAS_FUNCTIONAL=1
fi

# --- Check (2): destructive tests ---
HAS_DESTRUCTIVE=0
if echo "$CONTENT" | grep -qiE '(destructive (test|scenario|sweep)|DT-?[0-9]+|attack categor|adversarial test|negative test)'; then
  HAS_DESTRUCTIVE=1
fi

# Build reminder, but ONLY for what is actually missing.
REMINDERS=""

if [ "$HAS_FUNCTIONAL" -eq 0 ]; then
  REMINDERS="${REMINDERS}- Missing FUNCTIONAL COVERAGE: list EVERY implemented function, one test per function. Listing 3 of 12 is not acceptable.\n"
fi

if [ "$HAS_DESTRUCTIVE" -eq 0 ] && [ "$CARVED" -eq 0 ]; then
  REMINDERS="${REMINDERS}- Missing DESTRUCTIVE tests: add a destructive suite PER interactive UI function, sized to its input domain (ISTQB equivalence partitioning + boundary-value analysis), NOT a flat count for the whole spec. Floor scales with shape: trivial toggle ~3, simple form ~8, multi-step/auth ~20-30+. Cover the relevant attack categories (invalid input, wrong order, skip steps, boundary, race/timing, accessibility). The real gate is mutation kill rate, not the count.\n"
fi

if [ -z "$REMINDERS" ]; then
  # Nothing to remind — exit silently (approval is implicit)
  exit 0
fi

# Emit advisory systemMessage. NEVER a permissionDecision.
MSG="Spec coverage reminder for $(basename "$FILE"):\n${REMINDERS}"
if [ "$CARVED" -eq 1 ]; then
  MSG="${MSG}(Destructive tests appear to be carved to another slice — reminder suppressed.)"
fi

# Use jq to safely JSON-encode the message
jq -n --arg msg "$(printf '%b' "$MSG")" '{systemMessage: $msg}'
exit 0
