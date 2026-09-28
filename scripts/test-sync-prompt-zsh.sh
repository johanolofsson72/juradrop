#!/usr/bin/env bash
#
# test-sync-prompt-zsh.sh — Step 5c's CORE mirror must copy every script in bash AND zsh (row 037).
#
# WHY THIS EXISTS. sync-prompt.md is executed by Claude in whatever shell the developer runs, and
# on macOS that is zsh. Step 5c iterated `for s in $CORE_SCRIPTS_LIST`; zsh does not word-split an
# unquoted parameter, so the loop saw one 105-name "filename", copied nothing, and printed
# `[OK] 0 core enforcement script(s) mirrored`. Nothing tested the block, because the block lives
# in a markdown file. This test extracts it from the markdown — the document IS the code under test —
# and runs it under each shell against a throwaway template and project.

set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
DOC="$SELF_DIR/sync-prompt.md"
TMP="${TMPDIR:-/tmp}/sync-prompt-zsh.$$"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n         expected: %s\n         actual:   %s\n' "$1" "$2" "$3"; }
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"

# The block runs from `CORE_SCRIPTS_LIST=$(` to the `[OK] ... mirrored` line.
BLOCK="$TMP/block.sh"
awk '/^CORE_SCRIPTS_LIST=\$\(bash/ {on=1} on {print} on && /core enforcement script\(s\) mirrored/ {exit}' "$DOC" > "$BLOCK"
if ! grep -q 'mirrored' "$BLOCK"; then
  bad "extract Step 5c from sync-prompt.md" "a block ending in the [OK] line" "$(wc -l < "$BLOCK") lines"
  echo; echo "$PASS passed, $FAIL failed"; exit 1
fi

# A fake template: an autosync stub answering --list-core-scripts with names that include a
# space-free list of 5, one of which is absent from the clone (the [WARN] path).
mkfixture() {
  T="$TMP/$1/template"; P="$TMP/$1/project"
  mkdir -p "$T/scripts" "$P/scripts"
  cat > "$T/scripts/template-autosync.sh" <<'STUB'
#!/bin/bash
[ "$1" = "--list-core-scripts" ] && printf '%s\n' a.sh b.sh c.py d.sh missing.sh
STUB
  for f in a.sh b.sh c.py d.sh; do printf '#!/bin/sh\necho %s\n' "$f" > "$T/scripts/$f"; chmod +x "$T/scripts/$f"; done
}

for SH in bash zsh; do
  if ! command -v "$SH" >/dev/null 2>&1; then
    echo "  skip $SH not installed"; continue
  fi
  mkfixture "$SH"
  OUT=$(cd "$P" && TEMPLATE="$T" "$SH" -c ". '$BLOCK'" 2>&1); RC=$?
  N=$(ls "$P/scripts" | wc -l | tr -d ' ')
  [ "$N" = 4 ] && ok "$SH: all 4 present CORE scripts copied" || bad "$SH copies" "4 files" "$N files; $OUT"
  case "$OUT" in *"[OK] 4 of 5"*) ok "$SH: reports 4 of 5 honestly" ;; *) bad "$SH report" "[OK] 4 of 5" "$OUT" ;; esac
  case "$OUT" in *"missing.sh"*) ok "$SH: names the absent script" ;; *) bad "$SH absent" "missing.sh named" "$OUT" ;; esac
  [ -x "$P/scripts/a.sh" ] && ok "$SH: exec bit mirrored" || bad "$SH exec bit" "+x" "not executable"
  [ "$RC" = 0 ] && ok "$SH: exit 0" || bad "$SH exit" 0 "$RC"
done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
