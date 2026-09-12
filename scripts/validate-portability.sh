#!/bin/bash
# validate-portability.sh — every CORE script must run on Johan's macOS and David's Linux.
#
# Until 2026-09-04 exactly one script was checked for this: test-register-convergence.sh:87 greps
# its own subject for mapfile/readarray. Everything else was covered by whoever happened to run it,
# which is how agentcrm's test-order-varied.sh spent months enumerating 0 of 135 test classes on
# macOS while passing on Linux.
#
# The engine is scripts/portability_audit.py -- the pairing rule that keeps this from crying wolf
# lives there, with the reasoning. A first draft did the same work in shell and took over ten
# minutes on the CORE set, because a per-line × per-check loop spawns a process per hit.
#
# Usage:
#   bash scripts/validate-portability.sh            # CORE scripts (all of scripts/*.sh upstream)
#   bash scripts/validate-portability.sh --all      # every scripts/*.sh regardless of CORE
#   bash scripts/validate-portability.sh <file>...  # just these
#
# Exit: 0 clean · 1 findings · 2 could not run
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
ENGINE="$SCRIPT_DIR/portability_audit.py"
[ -f "$ENGINE" ] || { echo "validate-portability.sh: scripts/portability_audit.py is missing" >&2; exit 2; }

ALL=0; FILES=""
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "validate-portability.sh: unknown argument '$a'" >&2; exit 2 ;;
    *) FILES="$FILES $a" ;;
  esac
done

if [ -z "$FILES" ]; then
  # CORE only when there is a manifest to ask: a portability break in a CORE script ships to every
  # project, which is the population worth gating. With no manifest, scan everything.
  CORE_LIST=""
  [ "$ALL" -eq 0 ] && [ -f "$SCRIPT_DIR/template-autosync.sh" ] && \
    CORE_LIST=$(bash "$SCRIPT_DIR/template-autosync.sh" --list-core-scripts 2>/dev/null | grep '\.sh$')
  if [ -n "$CORE_LIST" ]; then
    while IFS= read -r s; do
      [ -f "$SCRIPT_DIR/$s" ] && FILES="$FILES $SCRIPT_DIR/$s"
    done <<< "$CORE_LIST"
  else
    FILES=$(ls "$SCRIPT_DIR"/*.sh 2>/dev/null | tr '\n' ' ')
  fi
fi
[ -n "$FILES" ] || { echo "validate-portability.sh: no scripts to scan" >&2; exit 2; }

PORT_ROOT="$ROOT" python3 "$ENGINE" $FILES
