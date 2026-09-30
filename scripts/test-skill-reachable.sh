#!/bin/bash
# Self-test for scripts/skill-reachable.sh and the two places that call it (spec 006):
# scripts/ui-design-hook.sh and section 3h of scripts/project-maintenance.sh.
#
#   bash scripts/test-skill-reachable.sh
#
# Every case runs against a fixture config dir (CLAUDE_CONFIG_DIR) and a fixture project
# (CLAUDE_PROJECT_DIR), never the real ~/.claude, so the result does not depend on what this
# machine happens to have installed. No network. Runs in about a second.
#
# bash 3.2-safe (macOS system bash): no associative arrays, no mapfile, no ${var,,}.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
SR="$DIR/skill-reachable.sh"
HOOK="$DIR/ui-design-hook.sh"
MAINT="$DIR/project-maintenance.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/skill-reachable-test.$$")
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }
expect_rc()       { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "rc=$2" "rc=$3"; fi; }
expect_contains() { if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "contains '$2'" "$3"; fi; }
expect_absent()   { if grep -Fq -e "$2" <<< "$3"; then bad "$1" "no '$2'" "$3"; else ok "$1"; fi; }

# A fresh config dir + project per case, so no case can pass on another's leftovers.
N=0
fresh() {
  N=$((N + 1))
  CFG="$TMP/cfg$N"; PROJ="$TMP/proj$N"
  mkdir -p "$CFG" "$PROJ/.claude"
}
skill_at() { mkdir -p "$1/$2"; printf -- '---\nname: %s\n---\n' "$2" > "$1/$2/SKILL.md"; }
# plugin <key> <skill> — installs a plugin in the registry with that one skill
plugin() {
  local dir="$CFG/plugins/cache/mkt/${1%%@*}/abc123"
  skill_at "$dir/skills" "$2"
  PLUGIN_ENTRIES="${PLUGIN_ENTRIES:+$PLUGIN_ENTRIES,}\"$1\":[{\"scope\":\"user\",\"installPath\":\"$dir\"}]"
  printf '{"version":2,"plugins":{%s}}\n' "$PLUGIN_ENTRIES" > "$CFG/plugins/installed_plugins.json"
}
run() { CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$PROJ" bash "$SR" "$@" 2>&1; }

echo "skill-reachable.sh"

fresh; PLUGIN_ENTRIES=""; skill_at "$PROJ/.claude/skills" alpha
OUT=$(run alpha); expect_rc "S1 project skill is reachable" 0 $?

fresh; PLUGIN_ENTRIES=""; skill_at "$CFG/skills" humanizer
OUT=$(run humanizer); expect_rc "S2 user skill is reachable" 0 $?

fresh; PLUGIN_ENTRIES=""; plugin "frontend-design@mkt" frontend-design
OUT=$(run frontend-design); expect_rc "S3 plugin skill is reachable by bare name" 0 $?
OUT=$(run frontend-design:frontend-design); expect_rc "S3b plugin skill is reachable by qualified name" 0 $?
OUT=$(run other:frontend-design); expect_rc "S3c qualified name searches only its own plugin" 1 $?

printf '{"enabledPlugins":{"frontend-design@mkt":false}}\n' > "$CFG/settings.json"
OUT=$(run frontend-design); expect_rc "S4 plugin disabled in user settings is missing" 1 $?
expect_contains "S4b the missing line names the plugin install" "/plugin install frontend-design@claude-plugins-official" "$OUT"

printf '{"enabledPlugins":{"frontend-design@mkt":true}}\n' > "$PROJ/.claude/settings.local.json"
OUT=$(run frontend-design); expect_rc "S5 project-local settings re-enable it (local wins)" 0 $?
printf '{"enabledPlugins":{"frontend-design@mkt":false}}\n' > "$PROJ/.claude/settings.json"
OUT=$(run frontend-design); expect_rc "S5b local still wins over project" 0 $?
rm "$PROJ/.claude/settings.local.json"
OUT=$(run frontend-design); expect_rc "S5c project disable wins over user enable" 1 $?

fresh; PLUGIN_ENTRIES=""
skill_at "$CFG/plugins/cache/mkt/frontend-design/stalehash/skills" frontend-design
OUT=$(run frontend-design); expect_rc "S6 a cache dir the registry does not list is not installed" 1 $?

fresh; PLUGIN_ENTRIES=""
OUT=$(run --required); expect_rc "S7 --required on an empty machine is missing" 1 $?
expect_contains "S7b frontend-design reported" "missing: frontend-design" "$OUT"
expect_contains "S7c humanizer reported with its clone command" "git clone https://github.com/blader/humanizer.git" "$OUT"
skill_at "$CFG/skills" humanizer; plugin "frontend-design@mkt" frontend-design
OUT=$(run --required); expect_rc "S7d --required with both installed is clean" 0 $?
expect_rc "S7e ...and prints nothing" "" "$OUT"

printf '{not json' > "$CFG/plugins/installed_plugins.json"
OUT=$(run frontend-design); expect_rc "S8 unreadable registry is missing, not a crash" 1 $?

OUT=$(run); expect_rc "S9 no arguments is a usage error" 2 $?
OUT=$(run --bogus); expect_rc "S9b unknown flag is a usage error" 2 $?
OUT=$(run ../etc); expect_rc "S9c a path is not a skill name" 2 $?

# No python3: build a PATH that holds bash and nothing else.
fresh; PLUGIN_ENTRIES=""; plugin "frontend-design@mkt" frontend-design
mkdir -p "$TMP/nopy"; ln -sf "$(command -v bash)" "$TMP/nopy/bash"
BASH_BIN=$(command -v bash)
OUT=$(PATH="$TMP/nopy" CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$PROJ" "$BASH_BIN" "$SR" frontend-design 2>&1)
expect_rc "S10 no python3 is 'cannot tell', never 'reachable'" 3 $?
expect_contains "S10b and says why" "python3 is needed" "$OUT"
skill_at "$CFG/skills" humanizer
OUT=$(PATH="$TMP/nopy" CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$PROJ" "$BASH_BIN" "$SR" humanizer 2>&1)
expect_rc "S10c a user skill needs no python3" 0 $?

echo "ui-design-hook.sh"
hook() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" |
  CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" 2>&1; }

fresh; PLUGIN_ENTRIES=""
OUT=$(hook "$PROJ/src/App.tsx")
expect_contains "H1 missing plugin: the developer is told" '"systemMessage":"Design gate unreachable' "$OUT"
expect_contains "H1b ...with the install command" "/plugin install frontend-design@claude-plugins-official" "$OUT"
expect_contains "H1c the model is told on the PreToolUse channel" '"hookEventName":"PreToolUse"' "$OUT"
expect_contains "H1d ...that the gate cannot be met" "CANNOT BE MET" "$OUT"
if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "H1e payload is valid JSON"; else bad "H1e payload is valid JSON" "json" "$OUT"; fi

plugin "frontend-design@mkt" frontend-design
OUT=$(hook "$PROJ/src/App.tsx")
expect_contains "H2 plugin present: today's reminder" "UI FILE DETECTED — BLOCKING DESIGN REQUIREMENTS" "$OUT"
expect_absent   "H2b ...and no user notice" "systemMessage" "$OUT"

OUT=$(hook "$PROJ/src/Program.cs"); expect_rc "H3 non-UI edit stays silent" "" "$OUT"

echo "project-maintenance.sh §3h"
# A bare repo holding only what the section needs: the checker, and a freshness stub that passes.
fresh; PLUGIN_ENTRIES=""
M="$TMP/maint$N"; mkdir -p "$M/scripts"
( cd "$M" && git init -q . )
cp "$SR" "$M/scripts/"; printf '#!/bin/bash\nexit 0\n' > "$M/scripts/project-freshness.sh"
# A passing portability pair too: without it section 6c reports [SETUP] (row 033) and M1a counts three.
printf '#!/bin/bash\nexit 0\n' > "$M/scripts/validate-portability.sh"; : > "$M/scripts/portability_audit.py"
chmod +x "$M/scripts/skill-reachable.sh" "$M/scripts/project-freshness.sh" "$M/scripts/validate-portability.sh"
OUT=$(cd "$M" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$M" bash "$MAINT" 2>&1)
expect_rc "M1 missing skills make the pass report findings" 1 $?
expect_contains "M1a ...exactly the two, so a note would not pass for a finding" "project-maintenance: 2 finding(s)" "$OUT"
expect_contains "M1b each one is a [SKILLS] finding" "[SKILLS] BLOCKING skill not reachable on this machine — frontend-design" "$OUT"
expect_contains "M1c humanizer too" "[SKILLS] BLOCKING skill not reachable on this machine — humanizer" "$OUT"
skill_at "$CFG/skills" humanizer; plugin "frontend-design@mkt" frontend-design
OUT=$(cd "$M" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$M" bash "$MAINT" 2>&1)
expect_rc "M2a both installed: the fixture pass is clean" 0 $?
expect_absent "M2 both installed: no [SKILLS] line" "[SKILLS]" "$OUT"
rm "$M/scripts/skill-reachable.sh"; rm -rf "$CFG/skills" "$CFG/plugins"
OUT=$(cd "$M" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$M" bash "$MAINT" 2>&1)
expect_absent "M3 no checker in the project: section is silent" "[SKILLS]" "$OUT"

echo
echo "skill-reachable: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
