#!/usr/bin/env bash
# "Is there anything for me to do on this project today?" — answered from the repo itself.
#
# Same parser as the session-start hook (scripts/lane_status.py), fuller rendering: your own
# row, the other lane's, what is unclaimed and actually runnable, what is held and why, which
# open questions are holding a row, the phase debt where a project keeps one, and who
# committed what this week.
#
# Everything it reads is a file git carries between machines, so the answer is the same on
# every machine — provided you have pulled, which it tells you when you have not.
#
# Usage:  bash scripts/lane-status.sh [--owner NAME] [--root DIR]
#
# The lane comes from SPEC_OWNER (.claude/settings.local.json, per machine). Override it
# with --owner to read the register through another developer's eyes. On a single-lane
# project it still answers — "what should I work on" is a fair question with one developer.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --owner) SPEC_OWNER="${2:-}"; export SPEC_OWNER; shift 2 ;;
    --root)  ROOT="${2:-$ROOT}"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 unavailable — cannot read the register." >&2
  exit 1
fi

OUT=$(python3 "$SCRIPT_DIR/lane_status.py" --root "$ROOT" --full)

if [ -z "$OUT" ]; then
  echo "No register at $ROOT/specs/INDEX.md — nothing to report."
  exit 0
fi

printf '%s\n' "$OUT"
