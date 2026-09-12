#!/bin/bash
# PostToolUse hook: advisory reminder to keep specs/SCENARIOS.md (the living
# scenario map / "sprängskiss") in sync when a spec/tasks file gains
# interactive behaviour.
#
# Behavior contract:
#   - NEVER blocks. Output is advisory context for the model, or nothing.
#   - Fires only on spec*.md / tasks*.md / plan*.md that mention interactive UI.
#   - Silent on template/scratch repos (no language marker at the .git root).
#   - Suppresses when specs/SCENARIOS.md already references this spec's slug.
#
# See .claude/rules/scenarios.md for the artifact this guards.

# SPEC 046 — the reminder tells Claude to start a scenario interview, so it goes
# to Claude. As a systemMessage it was a paragraph of red warning at the
# developer, repeated on every pass over the same spec file.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hook-notice.sh"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
SID=$(hn_session_id "$INPUT")

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
  notice_once PostToolUse "$SID" "scenario:no-map" "Scenario gap: specs/SCENARIOS.md does not exist yet and this spec has interactive behaviour. START A SCENARIO INTERVIEW now (AskUserQuestion, one feature at a time) to capture every use case — happy / edge / adversarial / error / offline — with the user as the completeness check, then write the map with SC-ids. Do NOT invent the scenarios silently and proceed. See .claude/rules/scenarios.md (Scenario gap or drift → START AN INTERVIEW)."
  exit 0
fi

# Suppress if the map already references this spec slug. Anchor on non-alphanumeric
# boundaries so a short slug (003-api) is not falsely matched inside a longer one.
#
# THE MAP IS NOT ALWAYS ONE FILE (spec 007bl). On a project whose map outgrew a single
# document, specs/SCENARIOS.md keeps the use-case diagram and a per-feature index, and each
# feature's rows live in specs/scenarios/<slug>.md. Searching only the index there would fire
# a "scenario gap" for every feature whose rows moved — i.e. for almost every spec, on a
# project whose map is in perfect shape. An advisory that cries wolf on every spec is worse
# than no advisory: it trains the reader to dismiss the one signal that catches a genuinely
# missed user-case, which is the entire reason this hook exists.
#
# scenario_map_files resolves the layout and lists every file that can hold rows — the index
# alone under the single-file layout, so projects that never split behave exactly as before.
_SMR_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -r "$_SMR_DIR/scenario-map-layout.sh" ]; then
  . "$_SMR_DIR/scenario-map-layout.sh"
  MAP_FILES=$(scenario_map_files "$ROOT")
else
  # Fail open to the pre-007bl behaviour rather than erroring inside a PostToolUse hook.
  MAP_FILES="$MAP"
fi

if [ -n "$SLUG" ]; then
  # A loop rather than `grep -q ... $MAP_FILES`, so a path containing whitespace cannot
  # split into two filenames and quietly search the wrong thing.
  printf '%s\n' "$MAP_FILES" | while IFS= read -r _mf; do
    [ -n "$_mf" ] || continue
    [ -f "$_mf" ] || continue
    grep -qE "(^|[^A-Za-z0-9])$SLUG([^A-Za-z0-9]|\$)" "$_mf" 2>/dev/null && exit 17
  done
  # 17 escapes the subshell as the pipeline's status; anything else means no file matched.
  [ "$?" -eq 17 ] && exit 0
fi

notice_once PostToolUse "$SID" "scenario:no-rows:$SLUG" "Scenario gap: specs/SCENARIOS.md has no rows for this spec ($SLUG). This is the failure mode where a missed user-case slips into the code. START A SCENARIO INTERVIEW now (AskUserQuestion, one feature at a time; recommended answers the user confirms) to capture happy / edge / adversarial / error / offline scenarios, then write the SC-id rows. The map is the source the functional inventory and destructive suite derive from. See .claude/rules/scenarios.md."
exit 0
