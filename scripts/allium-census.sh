#!/bin/bash
# allium-census.sh [root] — which spec.allium baselines does `allium check` reject?
#
# One TSV row per baseline with at least one severity=error diagnostic:
#   <path>  parse|semantic  <error_count>  <first error>
# then:  allium-census: N files, E with errors (P parse, S semantic)
#
# parse    = at least one error carries a null code (the parser's diagnostics have none)
# semantic = every error carries a checker code (allium.type.undefinedReference, ...)
#
# Exit: 0 clean · 1 at least one baseline has errors · 2 cannot tell (no CLI, an unreadable
# report, or zero baselines found). Zero files is never "clean" — a census that read nothing
# and a census of a healthy project must not print the same thing.
#
# Warnings are ignored, like the write-time hook (allium-check-hook.sh): the CLI exits 1 on
# them and the deferred location-hint lint fires on nearly every spec.
set -uo pipefail

ROOT="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
ALLIUM_BIN="${ALLIUM_BIN:-allium}"

if ! command -v "$ALLIUM_BIN" >/dev/null 2>&1; then
  echo "allium-census: allium CLI not installed — cannot tell" >&2
  exit 2
fi

shopt -s nullglob
FILES=("$ROOT"/specs/*/spec.allium)
shopt -u nullglob
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "allium-census: 0 files under $ROOT/specs/*/spec.allium — cannot tell" >&2
  exit 2
fi

TOTAL=0; WITH=0; PARSE=0; SEM=0; UNREADABLE=0
for f in "${FILES[@]}"; do
  TOTAL=$((TOTAL + 1))
  rel="${f#"$ROOT"/}"
  # The CLI exits 1 on warnings, so only the READER's status means anything here.
  row=$("$ALLIUM_BIN" check "$f" 2>/dev/null | python3 -c '
import json, sys
try:
    diags = json.load(sys.stdin)["diagnostics"]
    assert isinstance(diags, list)
except Exception:
    print("UNREADABLE"); sys.exit(0)
errs = [x for x in diags if x.get("severity") == "error"]
if not errs:
    sys.exit(0)
kind = "parse" if any(x.get("code") is None for x in errs) else "semantic"
loc = errs[0].get("location") or {}
msg = errs[0].get("message", "").replace("\t", " ").replace("\n", " ")[:120]
first = str(loc.get("line", "?")) + ": " + msg
print(f"{kind}\t{len(errs)}\t{first}")
'; exit "${PIPESTATUS[1]}")
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$row" = "UNREADABLE" ]; then
    UNREADABLE=$((UNREADABLE + 1))
    printf '%s\tunreadable\t-\tallium check produced no readable report\n' "$rel"
    continue
  fi
  [ -z "$row" ] && continue
  WITH=$((WITH + 1))
  case "$row" in parse*) PARSE=$((PARSE + 1)) ;; *) SEM=$((SEM + 1)) ;; esac
  printf '%s\t%s\n' "$rel" "$row"
done

SUMMARY="allium-census: $TOTAL files, $WITH with errors ($PARSE parse, $SEM semantic)"
[ "$UNREADABLE" -gt 0 ] && SUMMARY="$SUMMARY, $UNREADABLE unreadable"
echo "$SUMMARY"
[ "$UNREADABLE" -gt 0 ] && exit 2
[ "$WITH" -gt 0 ] && exit 1
exit 0
