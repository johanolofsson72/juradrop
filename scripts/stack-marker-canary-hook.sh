#!/bin/bash
# SessionStart canary: does .claude/.sync-stack still describe what this project
# actually is?
#
# WHY THIS EXISTS. `.claude/.sync-stack` holds one line — `testing=web|mobile|hybrid`
# — and `template-autosync.sh` reads it as a GATE: on `testing=mobile` it refuses to
# stamp the browser `testing.md` / `spec-testing-checklist.md`, and vice versa. The
# marker is written once (wizard or first sync) and nothing ever re-derives it. So
# when a project changes stack, the gate keeps handing it the wrong doc set forever,
# and — because the wrong docs then get hand-edited — the sync starts skipping them
# as "locally modified" too. Both failure modes are silent.
#
# That is not hypothetical: puck pivoted from Flutter native to a React web client
# in July 2026 and kept `testing=mobile` for a month. Its destructive-test checklist
# prescribed Maestro flows, Patrol and native permission dialogs for an app that
# ships in a browser, and every spec after the pivot was sized from it.
#
# ATTENTION MODE. Silent when the marker matches reality — which is almost every
# session, on almost every project. It speaks only when the marker is wrong or
# missing, so when it does speak it is worth reading.
#
# Never blocks, fails open, silent on template/scratch repos. bash 3.2-safe,
# cross-platform. Disable with STACK_CANARY_DISABLE=1.

set -u

[ "${STACK_CANARY_DISABLE:-0}" = "1" ] && exit 0

# ------------------------------------------------------------- project root
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$ROOT" ] || exit 0
[ -d "$ROOT/.claude" ] || exit 0

# Manifests worth inspecting: up to 3 levels deep (web/package.json,
# src/Api/Api.csproj, mobile/pubspec.yaml), never inside vendored trees.
find_manifests() {
  find "$ROOT" -maxdepth 3 -name "$1" \
    -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/dist/*' \
    -not -path '*/build/*' -not -path '*/.claude/worktrees/*' 2>/dev/null
}

NATIVE=""; WEB=""

# ---------------------------------------------------------------- native side
# Match dependency KEYS, not substrings: a web app carrying `react-native-web`
# must not read as a native app.
for pj in $(find_manifests package.json); do
  if grep -qE '"(expo|react-native)"[[:space:]]*:' "$pj" 2>/dev/null; then NATIVE="react-native"; break; fi
done
if [ -z "$NATIVE" ]; then
  for f in $(find_manifests eas.json) $(find_manifests app.config.js) $(find_manifests app.config.ts); do
    [ -f "$f" ] && { NATIVE="react-native"; break; }
  done
fi
if [ -z "$NATIVE" ]; then
  for pub in $(find_manifests pubspec.yaml); do
    if grep -qE '^[[:space:]]*(sdk:[[:space:]]*flutter|flutter:)' "$pub" 2>/dev/null; then NATIVE="flutter"; break; fi
  done
fi

# ------------------------------------------------------------------- web side
# Browser-specific signals only. `react-dom` alone is deliberately NOT enough:
# an Expo project doing Expo-web would otherwise misread as hybrid.
for f in $(find_manifests '*.csproj') $(find_manifests '*.sln'); do
  [ -f "$f" ] && { WEB="dotnet"; break; }
done
if [ -z "$WEB" ]; then
  for pj in $(find_manifests package.json); do
    if grep -qE '"(vite|next|@playwright/test|svelte|astro|nuxt|@angular/core|vue)"[[:space:]]*:' "$pj" 2>/dev/null; then WEB="web"; break; fi
  done
fi

# ------------------------------------------------------------------- verdict
if [ -n "$NATIVE" ] && [ -n "$WEB" ]; then EXPECTED="hybrid"
elif [ -n "$NATIVE" ];                 then EXPECTED="mobile"
elif [ -n "$WEB" ];                    then EXPECTED="web"
else exit 0                            # nothing recognizable — say nothing
fi

MARKER_FILE="$ROOT/.claude/.sync-stack"
ACTUAL=$(sed -n 's/^testing=//p' "$MARKER_FILE" 2>/dev/null | head -1 | tr -d '[:space:]')

[ "$ACTUAL" = "$EXPECTED" ] && exit 0          # consistent → silent (the usual case)

# A hybrid project legitimately keeps both doc sets, so a `hybrid` marker on a
# repo where only one side is detectable is a deliberate choice, not drift
# (the other client may simply not live in this repo yet).
[ "$ACTUAL" = "hybrid" ] && exit 0

EVIDENCE=""
[ -n "$NATIVE" ] && EVIDENCE="native client: $NATIVE"
[ -n "$WEB" ] && EVIDENCE="${EVIDENCE:+$EVIDENCE · }web/backend: $WEB"

if [ -z "$ACTUAL" ]; then
  MSG="STACK MARKER MISSING — .claude/.sync-stack does not exist (or has no testing= line), but this project looks like: ${EXPECTED} (${EVIDENCE}).

template-autosync.sh reads that marker to decide which testing docs to install. With no marker it stamps BOTH the web and the mobile doc set, so the project carries instructions for a platform it does not ship.

Fix: printf 'testing=%s\\n' ${EXPECTED} > .claude/.sync-stack
Then check .claude/docs/testing.md + spec-testing-checklist.md are the ${EXPECTED} set."
else
  MSG="STACK MARKER STALE — .claude/.sync-stack says testing=${ACTUAL}, but this project looks like ${EXPECTED} (${EVIDENCE}).

This is load-bearing, not cosmetic: template-autosync.sh uses the marker as a GATE. While it reads '${ACTUAL}', this project is being handed the ${ACTUAL} testing docs and the ${EXPECTED} ones are withheld — so .claude/docs/testing.md and spec-testing-checklist.md describe a platform it does not ship, and every destructive-test suite gets sized from the wrong checklist. Nothing re-derives the marker on its own; that is why this canary exists.

Fix it deliberately, NOT with a blind flip — changing the marker makes the next sync overwrite those two docs, discarding any local edits made to paper over the mismatch:
  1. Read .claude/docs/testing.md and spec-testing-checklist.md; note anything genuinely project-specific.
  2. printf 'testing=%s\\n' ${EXPECTED} > .claude/.sync-stack
  3. Copy the matching template docs into place (\`hybrid\` keeps both sets; a deferred second client is a reason to choose hybrid).
  4. Re-run the sync and confirm it reports 0 skips for those files — that proves they now track the template instead of being frozen.

If the marker is right and this detection is wrong, say so and leave it: the marker wins."
fi

if command -v jq >/dev/null 2>&1; then
  jq -n --arg m "$MSG" '{systemMessage: $m}'
else
  printf '%s\n' "$MSG" >&2
fi
exit 0
