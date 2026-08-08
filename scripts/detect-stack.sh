#!/bin/bash
# Derive a project's stack from its manifests. Echoes exactly one of:
#   web · mobile · hybrid · (nothing, when nothing recognizable is found)
#
# Single source of truth for stack detection, used by BOTH:
#   - scripts/stack-marker-canary-hook.sh  (warns when .sync-stack disagrees)
#   - scripts/template-autosync.sh         (writes .sync-stack when it is missing)
# Two copies of this logic would drift, and drift in *this* logic is the exact bug
# the canary exists to catch.
#
# Usage: detect-stack.sh [project-root]     (defaults to $CLAUDE_PROJECT_DIR or $PWD)
#
# Detection rules:
#   native  — `expo` / `react-native` as dependency KEYS (never substrings, so a
#             web app carrying react-native-web is not mistaken for a native one),
#             a pubspec.yaml declaring the Flutter SDK, or eas.json/app.config.*
#   web     — any *.csproj / *.sln, or a browser-specific dependency key
#             (vite, next, @playwright/test, svelte, astro, nuxt, @angular/core, vue).
#             react-dom alone is deliberately NOT enough: Expo-web would then
#             misreport every Expo project as hybrid.
#   both → hybrid · native only → mobile · web only → web · neither → silence
#
# bash 3.2-safe, cross-platform. Never fails loudly; prints nothing when unsure.

set -u

ROOT="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[ -d "$ROOT" ] || exit 0

# Up to 3 levels deep (web/package.json, src/Api/Api.csproj, mobile/pubspec.yaml),
# never inside vendored or generated trees.
_find() {
  find "$ROOT" -maxdepth 3 -name "$1" \
    -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/dist/*' \
    -not -path '*/build/*' -not -path '*/.claude/worktrees/*' 2>/dev/null
}

NATIVE=""; WEB=""

for pj in $(_find package.json); do
  if grep -qE '"(expo|react-native)"[[:space:]]*:' "$pj" 2>/dev/null; then NATIVE="react-native"; break; fi
done
if [ -z "$NATIVE" ]; then
  for f in $(_find eas.json) $(_find app.config.js) $(_find app.config.ts); do
    [ -f "$f" ] && { NATIVE="react-native"; break; }
  done
fi
if [ -z "$NATIVE" ]; then
  for pub in $(_find pubspec.yaml); do
    if grep -qE '^[[:space:]]*(sdk:[[:space:]]*flutter|flutter:)' "$pub" 2>/dev/null; then NATIVE="flutter"; break; fi
  done
fi

for f in $(_find '*.csproj') $(_find '*.sln'); do
  [ -f "$f" ] && { WEB="dotnet"; break; }
done
if [ -z "$WEB" ]; then
  for pj in $(_find package.json); do
    if grep -qE '"(vite|next|@playwright/test|svelte|astro|nuxt|@angular/core|vue)"[[:space:]]*:' "$pj" 2>/dev/null; then WEB="web"; break; fi
  done
fi

# Second output line (optional, read by the canary for its evidence string).
EVIDENCE=""
[ -n "$NATIVE" ] && EVIDENCE="native client: $NATIVE"
[ -n "$WEB" ] && EVIDENCE="${EVIDENCE:+$EVIDENCE · }web/backend: $WEB"

if [ -n "$NATIVE" ] && [ -n "$WEB" ]; then printf 'hybrid\n%s\n' "$EVIDENCE"
elif [ -n "$NATIVE" ];                 then printf 'mobile\n%s\n' "$EVIDENCE"
elif [ -n "$WEB" ];                    then printf 'web\n%s\n' "$EVIDENCE"
fi
exit 0
