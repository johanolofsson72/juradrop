#!/bin/bash
# SessionStart hook: orients to specs/SCENARIOS.md (the living scenario map /
# "sprängskiss"). This is the PROACTIVE complement to the reactive PostToolUse
# scenario-map-reminder-hook.sh — that hook only fires while a spec/tasks/plan
# file is being edited, so an ALREADY-BUILT project that never created the map
# (the iskvalp case) would never be nudged. This one catches that retroactive
# gap at session start.
#
# Case 1: project has specs AND specs/SCENARIOS.md is MISSING → emit a
#         systemMessage telling Claude to START A SCENARIO INTERVIEW (the map
#         must come from the user; it is never invented silently).
# Case 2: map exists, or no specs yet, or no language marker → silent.
#
# Walk semantics match scripts/spec-register-orientation-hook.sh: walk up from
# $PWD collecting a language marker, stop at the first .git boundary. Never walk
# past a repo root, so a template/scratch dir cannot pick up a parent's marker.
#
# NEVER blocks (SessionStart cannot deny anyway). Advisory systemMessage only.
# See .claude/rules/scenarios.md for the artifact this guards.

set -u

DIR="$PWD"
LANG_MARKER=""
PROJECT_ROOT=""

while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -z "$LANG_MARKER" ]; then
    for marker in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile build.gradle build.gradle.kts pom.xml pubspec.yaml; do
      if [ -f "$DIR/$marker" ]; then LANG_MARKER="$marker"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"; break; fi
    done
  fi
  if [ -z "$LANG_MARKER" ] && ls "$DIR"/*.csproj >/dev/null 2>&1; then LANG_MARKER="*.csproj"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"; fi
  if [ -z "$LANG_MARKER" ] && ls "$DIR"/*.sln >/dev/null 2>&1; then LANG_MARKER="*.sln"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"; fi
  if [ -d "$DIR/.git" ]; then
    [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done

# No language marker → template/scratch repo → silent (matches the reactive hook's gate).
[ -z "$LANG_MARKER" ] && exit 0
[ -z "$PROJECT_ROOT" ] && exit 0

# Map already exists → nothing to nudge.
[ -f "$PROJECT_ROOT/specs/SCENARIOS.md" ] && exit 0

# Does the project actually have specs? (Past inception — otherwise there is
# nothing to map yet and the nudge would be noise.)
HAS_SPECS=0
if [ -f "$PROJECT_ROOT/specs/INDEX.md" ] && grep -qE '^- \[[ x/!]\]' "$PROJECT_ROOT/specs/INDEX.md" 2>/dev/null; then
  HAS_SPECS=1
fi
if [ "$HAS_SPECS" -eq 0 ]; then
  if ls "$PROJECT_ROOT"/specs/*/spec.md >/dev/null 2>&1 || ls "$PROJECT_ROOT"/.specify/specs/*/spec.md >/dev/null 2>&1; then
    HAS_SPECS=1
  fi
fi
[ "$HAS_SPECS" -eq 0 ] && exit 0

# Specs exist, no map. Nudge — but the map MUST be built from a user interview,
# never invented silently (.claude/rules/scenarios.md).
MSG="Scenario map gap: ${PROJECT_ROOT}/specs/SCENARIOS.md does not exist, but this project already has specs. CLAUDE.md and .claude/rules/scenarios.md treat the scenario map as a BLOCKING artifact — it is the source the functional inventory and destructive test suite derive from, so a missing map means every spec is being validated against nothing.

This is a retroactive gap (the reactive PostToolUse reminder only fires while a spec is being edited, so it was never triggered for already-built specs). To close it: START A SCENARIO INTERVIEW (AskUserQuestion, one feature at a time, recommended answers the user confirms) to capture every use case — happy / edge / adversarial / error / offline — with the user as the completeness check, then write specs/SCENARIOS.md with SC-id rows (Mermaid use-case diagram + per-feature flowcharts + SC-id ledger). Do NOT invent the scenarios silently. See .claude/rules/scenarios.md."
jq -n --arg m "$MSG" '{systemMessage: $m}'
exit 0
