#!/bin/bash
# skill-reachable.sh — can the Skill tool load this skill, on this machine, for this project?
#
# WHY THIS EXISTS (spec 006). CLAUDE.md calls two skills BLOCKING by bare name, and neither ships
# with the template: `frontend-design` is a plugin, `humanizer` is a git clone under ~/.claude/skills.
# Every caller is prose telling a model to invoke them, and none of them checked that it could. On a
# machine without the skill (fresh clone, second lane, a cleared plugin cache, a disabled plugin)
# the Skill call fails and the BLOCKING gate becomes nothing, with a clean run log.
#
# The bare name is fine. The harness resolves it against project skills, user skills and installed
# plugins (measured 2026-09-03), and this script looks in the same three places:
#   <project>/.claude/skills/<name>/SKILL.md
#   <cfg>/skills/<name>/SKILL.md
#   <installPath>/skills/<name>/SKILL.md   for every plugin in <cfg>/plugins/installed_plugins.json
# where <cfg> is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}. A plugin whose key is `false` in
# enabledPlugins (local > project > user settings) does not count: the Skill tool would not load it.
# Only registry installPaths count. A leftover hash dir in the cache is not an installed plugin.
#
# Usage:
#   bash scripts/skill-reachable.sh <name> [<name> ...]   # `plugin:skill` searches only that plugin
#   bash scripts/skill-reachable.sh --required            # the BLOCKING external set, below
#   bash scripts/skill-reachable.sh --list-required
#
# Prints one `missing: <name> — <how to install>` line per missing skill, nothing when all are there.
# Exit codes: 0 all reachable · 1 at least one missing · 2 usage · 3 cannot tell (no python3 to read
# the plugin registry, and the skill was not found without it). 3 is never "reachable".
#
# bash 3.2-safe (macOS system bash), cross-platform (macOS / Linux / Windows Git Bash). Read-only.

set -uo pipefail

# The BLOCKING skills the template names but does not ship. A skill shipped in .claude/skills/
# arrives with the sync, and spec-kit's are checked by project-maintenance.sh §3b, so neither belongs here.
REQUIRED="frontend-design humanizer"

install_hint() {
  case "$1" in
    frontend-design) echo "/plugin install frontend-design@claude-plugins-official (and make sure it is not disabled in enabledPlugins)" ;;
    humanizer)       echo "git clone https://github.com/blader/humanizer.git \"${CFG}/skills/humanizer\"" ;;
    *:*)             echo "/plugin install ${1%%:*} (and make sure it is not disabled in enabledPlugins)" ;;
    *)               echo "install it under .claude/skills/$1/ or ${CFG}/skills/$1/" ;;
  esac
}

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECT="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJECT" ] || PROJECT=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")

NAMES=""
[ $# -eq 0 ] && { usage >&2; exit 2; }
for arg in "$@"; do
  case "$arg" in
    --required)      NAMES="$NAMES $REQUIRED" ;;
    --list-required) printf '%s\n' $REQUIRED; exit 0 ;;
    -h|--help)       usage; exit 0 ;;
    -*)              echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
    */*|*..*|'')     echo "not a skill name: '$arg'" >&2; exit 2 ;;
    *)               NAMES="$NAMES $arg" ;;
  esac
done

# Prints the install paths of enabled plugins, one per line, each followed by a tab and the plugin
# name (the part before '@'). Exit 3 when python3 is not there to read the JSON.
enabled_plugin_paths() {
  [ -f "$CFG/plugins/installed_plugins.json" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 3
  python3 - "$CFG" "$PROJECT" <<'PY' 2>/dev/null || return 3
import json, os, sys
cfg, project = sys.argv[1], sys.argv[2]

def load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception:
        return {}

# Later files win: user < project < project-local, the order Claude Code applies settings in.
enabled = {}
for path in (os.path.join(cfg, "settings.json"),
             os.path.join(project, ".claude", "settings.json"),
             os.path.join(project, ".claude", "settings.local.json")):
    ep = load(path).get("enabledPlugins")
    if isinstance(ep, dict):
        enabled.update(ep)

registry = load(os.path.join(cfg, "plugins", "installed_plugins.json")).get("plugins") or {}
for key, installs in registry.items():
    if enabled.get(key) is False:
        continue
    for inst in installs if isinstance(installs, list) else []:
        path = isinstance(inst, dict) and inst.get("installPath")
        if path:
            print(path + "\t" + key.split("@", 1)[0])
PY
}

PLUGINS=""
PLUGINS_RC=0
PLUGINS_READ=0

MISSING=0
UNKNOWN=0
for name in $NAMES; do
  plugin=""
  skill="$name"
  case "$name" in *:*) plugin="${name%%:*}"; skill="${name#*:}" ;; esac

  if [ -z "$plugin" ]; then
    [ -f "$PROJECT/.claude/skills/$skill/SKILL.md" ] && continue
    [ -f "$CFG/skills/$skill/SKILL.md" ] && continue
  fi

  if [ "$PLUGINS_READ" -eq 0 ]; then
    PLUGINS=$(enabled_plugin_paths)
    PLUGINS_RC=$?
    PLUGINS_READ=1
  fi
  found=0
  if [ -n "$PLUGINS" ]; then
    while IFS="$(printf '\t')" read -r path pname; do
      [ -n "$plugin" ] && [ "$pname" != "$plugin" ] && continue
      [ -f "$path/skills/$skill/SKILL.md" ] && { found=1; break; }
    done <<EOF
$PLUGINS
EOF
  fi
  [ "$found" -eq 1 ] && continue

  if [ "$PLUGINS_RC" -eq 3 ]; then
    echo "unknown: $name — python3 is needed to read $CFG/plugins/installed_plugins.json"
    UNKNOWN=1
  else
    echo "missing: $name — $(install_hint "$name")"
    MISSING=1
  fi
done

[ "$MISSING" -eq 1 ] && exit 1
[ "$UNKNOWN" -eq 1 ] && exit 3
exit 0
