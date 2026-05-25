#!/usr/bin/env bash
# Cross-check: verify this project's wired local-LLM hook set matches
# the template's exactly, and that every wired hook has its script
# file on disk.
#
# Catches regressions that one-grep verification misses:
# - Trim regex bugs (e.g. character class missing digits) leaving an
#   off-by-one stale entry
# - Manual edits to settings.json that drift from the template
# - Wired hooks whose script file is missing (broken state)
# - Script files on disk that should be wired but are not
#
# Usage:
#   scripts/verify-local-llm-hooks.sh <template-settings.json>
#
# Run from the project root (where .claude/settings.json lives).
# Exits 0 on full match, 1 on any mismatch, 2 on usage error.

set -uo pipefail

TEMPLATE_SETTINGS="${1:-}"
[ -n "$TEMPLATE_SETTINGS" ] || {
  echo "usage: $0 <template-settings.json>" >&2
  exit 2
}
[ -f "$TEMPLATE_SETTINGS" ] || {
  echo "template not found: $TEMPLATE_SETTINGS" >&2
  exit 2
}

PROJECT_SETTINGS=".claude/settings.json"
[ -f "$PROJECT_SETTINGS" ] || {
  echo "project settings not found: $PROJECT_SETTINGS — run from project root" >&2
  exit 2
}

# Match the regex used by sync-local-llm-hooks.py exactly. If you change
# one, change both — keeping them in sync is the whole point of this
# check (the n1-query escape was caused by drift between the two).
HOOK_RE='local-llm-[a-z0-9-]+-hook\.sh'

extract_wired() {
  grep -oE "$HOOK_RE" "$1" | sort -u
}

TEMPLATE_WIRED=$(extract_wired "$TEMPLATE_SETTINGS")
PROJECT_WIRED=$(extract_wired "$PROJECT_SETTINGS")

EXIT=0

# Check 1: wired-set match
if [ "$TEMPLATE_WIRED" = "$PROJECT_WIRED" ]; then
  N=$(echo "$TEMPLATE_WIRED" | grep -c .)
  echo "[OK] wired set matches template ($N hooks)"
else
  echo "[FAIL] wired set differs from template:"
  diff <(echo "$TEMPLATE_WIRED" | sed 's/^/  /') \
       <(echo "$PROJECT_WIRED"  | sed 's/^/  /')
  echo ""
  echo "  Fix: python3 scripts/sync-local-llm-hooks.py $TEMPLATE_SETTINGS"
  EXIT=1
fi

# Check 2: every wired hook has its script file on disk
MISSING=""
while IFS= read -r hook; do
  [ -n "$hook" ] || continue
  [ -f "scripts/$hook" ] || MISSING="$MISSING $hook"
done <<< "$PROJECT_WIRED"
if [ -n "$MISSING" ]; then
  echo "[FAIL] wired hooks missing their script file in scripts/:$MISSING"
  echo "       (re-run /project-update or copy the scripts manually from the template)"
  EXIT=1
fi

# Check 3: count cross-validation against template (catches mass-corruption)
T_COUNT=$(echo "$TEMPLATE_WIRED" | grep -c .)
P_COUNT=$(echo "$PROJECT_WIRED"  | grep -c .)
if [ "$T_COUNT" -ne "$P_COUNT" ]; then
  echo "[FAIL] count mismatch — template=$T_COUNT, project=$P_COUNT"
  EXIT=1
fi

if [ "$EXIT" -eq 0 ]; then
  echo ""
  echo "All cross-checks passed. Local-LLM wiring is in sync with the template."
fi

exit $EXIT
