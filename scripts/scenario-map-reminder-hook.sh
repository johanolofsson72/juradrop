#!/bin/bash
# PostToolUse hook: advisory reminder to keep specs/SCENARIOS.md (the living
# scenario map / "sprängskiss") in sync when a spec/tasks file gains
# interactive behaviour.
#
# Behavior contract:
#   - NEVER blocks. Output is always a systemMessage (advisory) or nothing.
#   - Fires only on spec*.md / tasks*.md / plan*.md that mention interactive UI.
#   - Silent on template/scratch repos (no language marker at the .git root).
#   - Suppresses when specs/SCENARIOS.md already references this spec's slug.
#
# See .claude/rules/scenarios.md for the artifact this guards.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Only spec/tasks/plan markdown
case "$FILE" in
  *.md) ;;
  *) exit 0 ;;
esac
if ! echo "$FILE" | grep -qiE '(spec|tasks|plan)'; then
  exit 0
fi

# --- Walk up to project root (stop at .git boundary) ---
DIR=$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)
ROOT=""
while [ -n "$DIR" ] && [ "$DIR" != "/" ]; do
  if [ -d "$DIR/.git" ]; then ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -z "$ROOT" ] && exit 0

# --- Language marker gate (skip template/scratch repos) ---
HAS_MARKER=0
for m in package.json pyproject.toml requirements.txt go.mod Cargo.toml composer.json Gemfile pom.xml pubspec.yaml; do
  [ -f "$ROOT/$m" ] && HAS_MARKER=1 && break
done
if [ "$HAS_MARKER" -eq 0 ]; then
  # .NET: accept a .sln OR .csproj at the repo root. Test the two globs
  # SEPARATELY — a single `ls "$ROOT"/*.sln "$ROOT"/*.csproj` exits non-zero
  # when only one glob matches (the other stays an unexpanded literal), which
  # made the hook silently skip solution-only .NET repos (root .sln, nested .csproj).
  if ls "$ROOT"/*.sln >/dev/null 2>&1 || ls "$ROOT"/*.csproj >/dev/null 2>&1; then
    HAS_MARKER=1
  fi
fi
if [ "$HAS_MARKER" -eq 0 ]; then
  exit 0
fi

# --- Only remind for interactive behaviour ---
CONTENT=$(cat "$FILE" 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
INTERACTIVE_RE='(\bform\b|\binput\b|\bbutton\b|\bsubmit\b|click|tap|\bmodal\b|drawer|dialog|multi-?step|wizard|authenticate|sign[ -]?in|sign[ -]?up|login|logout|upload|drag[ -]?and[ -]?drop|search|filter|create.*edit.*delete|CRUD|checkout|payment)'
if ! echo "$CONTENT" | grep -qiE "$INTERACTIVE_RE"; then
  exit 0
fi

MAP="$ROOT/specs/SCENARIOS.md"

# Derive this spec's slug from its parent directory (e.g. specs/003-search/spec.md -> 003-search)
SLUG=$(basename "$(dirname "$FILE")")

if [ ! -f "$MAP" ]; then
  jq -n '{systemMessage: "Scenario gap: specs/SCENARIOS.md does not exist yet and this spec has interactive behaviour. START A SCENARIO INTERVIEW now (AskUserQuestion, one feature at a time) to capture every use case — happy / edge / adversarial / error / offline — with the user as the completeness check, then write the map with SC-ids. Do NOT invent the scenarios silently and proceed. See .claude/rules/scenarios.md (Scenario gap or drift → START AN INTERVIEW)."}'
  exit 0
fi

# Suppress if the map already references this spec slug. Anchor on non-alphanumeric
# boundaries so a short slug (003-api) is not falsely matched inside a longer one.
if [ -n "$SLUG" ] && grep -qE "(^|[^A-Za-z0-9])$SLUG([^A-Za-z0-9]|\$)" "$MAP" 2>/dev/null; then
  exit 0
fi

jq -n --arg slug "$SLUG" '{systemMessage: ("Scenario gap: specs/SCENARIOS.md has no rows for this spec (" + $slug + "). This is the failure mode where a missed user-case slips into the code. START A SCENARIO INTERVIEW now (AskUserQuestion, one feature at a time; recommended answers the user confirms) to capture happy / edge / adversarial / error / offline scenarios, then write the SC-id rows. The map is the source the functional inventory and destructive suite derive from. See .claude/rules/scenarios.md.")}'
exit 0
