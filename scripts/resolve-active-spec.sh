#!/usr/bin/env bash
# Thin shell wrapper over scripts/spec_active.py — THE canonical resolver for
# "which spec is active?" (spec 007m). All the reasoning, the id grammar, and
# the exit-code contract live in spec_active.py; this file exists purely so that
# shell callers (the orientation hook, the run-log hook, ad-hoc terminal use)
# can ask the same question the Python callers ask, of the same code.
#
# The two PreToolUse guards deliberately do NOT go through this wrapper: they
# already run a python3 interpreter, and on this machine `python3 -c pass` costs
# 50 ms while the resolution itself costs ~2 ms. They import spec_active.py into
# the process they were already paying for. Same implementation, no second
# interpreter on the path that fires for every source edit.
#
# Usage:  resolve-active-spec.sh [--root DIR] [--sync-feature-json]
# Output: one JSON object on stdout.
# Exit:   0 resolved · 3 no active row (an ANSWER — callers ALLOW)
#         4 cannot answer (callers DENY) · 2 usage error

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/spec_active.py"

if [ ! -f "$MODULE" ]; then
  echo '{"error":"spec_active.py missing"}'
  exit 4
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo '{"error":"python3 unavailable"}'
  exit 4
fi

exec python3 "$MODULE" "$@"
