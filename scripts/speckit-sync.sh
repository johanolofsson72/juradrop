#!/bin/bash
# Bring spec-kit — the CLI on this machine and the project's .specify/ — to the pinned version.
#
# Spec 073. Until this existed, three places installed spec-kit with
#   uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git
# i.e. whatever `main` was that day. Two developers ran different pipelines without knowing it,
# and projects stamped themselves with untagged snapshots (1.0.2.dev0, 1.0.5.dev0) that no release
# note describes. The wizard also re-initialised unconditionally, which /project-update had
# already learned not to do: `specify init --force` is not idempotent — it regenerates the two
# skills whose pipeline stops speckit-extension-policy.sh removes.
#
# So: one pin (scripts/speckit-version, one tag), one script that reads it, and a re-init only
# when the project's recorded version differs from the pin. Bumping spec-kit for every project is
# a one-line commit to the template; autosync carries the pin, and this script carries it out.
#
# Usage: speckit-sync.sh [--check] [--cli-only] [--init-new] [--repo <path>]
#   --check      report what would change; install and write nothing
#   --cli-only   bring the CLI to the pin and stop (no project)
#   --init-new   initialise a project that has no .specify/ yet (the wizard's first run).
#                Without it a project with no .specify/ is left alone: not every synced
#                project runs the pipeline (WordPress and content repos, for instance).
#   --repo       project root (default: the git toplevel of $PWD)
# Exit: 0 = at the pin (or nothing to do), 1 = could not install or initialise,
#       2 = initialised, but the stop-patch anchor moved (see speckit-extension-policy.sh),
#       3 = --check found something out of date.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
CHECK=0; CLI_ONLY=0; INIT_NEW=0; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check)    CHECK=1 ;;
    --cli-only) CLI_ONLY=1 ;;
    --init-new) INIT_NEW=1 ;;
    --repo)     shift; REPO="${1:-}" ;;
    -h|--help)  grep -E '^#( |$)' "$0" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

PIN=$(grep -v '^[[:space:]]*#' "$HERE/speckit-version" 2>/dev/null | tr -d '[:space:]' | head -c 64)
[ -n "$PIN" ] || { echo "[FAIL] no pin in $HERE/speckit-version" >&2; exit 1; }
PIN_VER=${PIN#v}

version_of_cli() {
  specify --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+([._a-z0-9]*)?' | sed -n 1p
}

OUTDATED=0

# A project that does not run spec-kit is left alone BEFORE the CLI is looked at: the sync calls
# this on every project, and a WordPress repo on a machine without uv must not fail — or pay for a
# network install of a CLI it will never use — just because the pipeline exists elsewhere.
[ -n "$REPO" ] || REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
if [ "$CLI_ONLY" -eq 0 ] && [ ! -d "$REPO/.specify" ] && [ "$INIT_NEW" -eq 0 ]; then
  echo "[skip] no .specify/ in $REPO — not a spec-kit project (use --init-new to create one)"
  exit 0
fi

# ------------------------------------------------------------------ CLI
CLI_VER=$(command -v specify >/dev/null 2>&1 && version_of_cli)
if [ "$CLI_VER" = "$PIN_VER" ]; then
  echo "[ok] specify CLI $CLI_VER (pinned $PIN)"
elif [ "$CHECK" -eq 1 ]; then
  echo "[out of date] specify CLI ${CLI_VER:-missing} — pin is $PIN"
  OUTDATED=1
else
  command -v uv >/dev/null 2>&1 || {
    echo "[FAIL] uv is not installed — install it first: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
    echo "       (Windows PowerShell: irm https://astral.sh/uv/install.ps1 | iex)" >&2
    exit 1
  }
  echo "[install] specify CLI ${CLI_VER:-missing} -> $PIN"
  uv tool install specify-cli --force --quiet --from "git+https://github.com/github/spec-kit.git@$PIN" >/dev/null 2>&1 || {
    echo "[FAIL] uv could not install specify-cli@$PIN (offline? tag removed?)" >&2
    exit 1
  }
  CLI_VER=$(version_of_cli)
  [ "$CLI_VER" = "$PIN_VER" ] || {
    echo "[FAIL] installed, but \`specify --version\` reports ${CLI_VER:-nothing}, not $PIN_VER." >&2
    echo "       Another specify earlier on PATH? $(command -v specify 2>/dev/null)" >&2
    exit 1
  }
fi
[ "$CLI_ONLY" -eq 1 ] && { [ "$OUTDATED" -eq 1 ] && exit 3; exit 0; }

# -------------------------------------------------------------- project
cd "$REPO" || { echo "[FAIL] cannot enter $REPO" >&2; exit 1; }

PROJ_VER=""; SCRIPT_TYPE="sh"
if [ -f .specify/init-options.json ] && command -v python3 >/dev/null 2>&1; then
  PROJ_VER=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("speckit_version",""))' .specify/init-options.json 2>/dev/null)
  SCRIPT_TYPE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("script","") or "sh")' .specify/init-options.json 2>/dev/null)
fi
[ -n "$SCRIPT_TYPE" ] || SCRIPT_TYPE="sh"

if [ "$PROJ_VER" = "$PIN_VER" ]; then
  echo "[ok] project .specify/ at $PROJ_VER"
  [ "$OUTDATED" -eq 1 ] && exit 3; exit 0
fi
if [ "$CHECK" -eq 1 ]; then
  echo "[out of date] project .specify/ ${PROJ_VER:-none} — pin is $PIN"
  exit 3
fi

# The constitution is the project's, not spec-kit's. 1.0.12's init leaves it alone (measured), but
# a release that starts seeding it would overwrite the one file nobody can regenerate.
CONST=.specify/memory/constitution.md
CONST_BAK=""
if [ -f "$CONST" ]; then
  CONST_BAK=$(mktemp 2>/dev/null || mktemp -t constitution) && cp "$CONST" "$CONST_BAK"
fi

echo "[init] project .specify/ ${PROJ_VER:-none} -> $PIN_VER"
# </dev/null: init must never wait on a prompt — this runs from skills and from the rollout loop.
if ! specify init --here --force --integration claude --script "$SCRIPT_TYPE" </dev/null >/dev/null 2>&1; then
  echo "[FAIL] specify init failed in $REPO — run it by hand to see why:" >&2
  echo "       specify init --here --force --integration claude --script $SCRIPT_TYPE" >&2
  [ -n "$CONST_BAK" ] && cp "$CONST_BAK" "$CONST" && rm -f "$CONST_BAK"
  exit 1
fi
if [ -n "$CONST_BAK" ]; then
  cmp -s "$CONST_BAK" "$CONST" || echo "[restored] $CONST (init had replaced it)"
  cp "$CONST_BAK" "$CONST" && rm -f "$CONST_BAK"
fi

# Every init restores the pipeline stops and re-enables extensions; the policy takes them out.
POLICY="$REPO/scripts/speckit-extension-policy.sh"
[ -f "$POLICY" ] || POLICY="$HERE/speckit-extension-policy.sh"
bash "$POLICY" --repo "$REPO"
RC=$?
case "$RC" in
  0) echo "[ok] spec-kit $PIN_VER initialised, extension policy applied" ;;
  2) exit 2 ;;
  *) echo "[FAIL] speckit-extension-policy.sh exited $RC" >&2; exit 1 ;;
esac
exit 0
