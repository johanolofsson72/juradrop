#!/bin/bash
# test-allium-census.sh — prove allium-census.sh counts errors, ignores warnings, and never
# reports "clean" when it could not tell.
#
# The warnings-only arm is the one that matters: the CLI exits 1 on a warning, and a census
# that trusts the pipeline's status (pipefail) reports every such file as unreadable. That
# happened in the first draft — 579 of 593 rocky baselines — and this arm pins it.
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CENSUS="$SCRIPT_DIR/allium-census.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

spec() { # spec <root> <name> <content>
  mkdir -p "$1/specs/$2"; printf -- "$3" > "$1/specs/$2/spec.allium"
}
CLEAN='-- allium: 3\n\nentity W {\n    ok: Boolean\n}\n\nrule R {\n    when: Go(w)\n    ensures: w.ok = true\n}\n'
WARN='-- allium: 3\n\nentity Lonely {\n    x: String\n}\n'
PARSE='-- allium: 3\n\nexternal entity User { id: String; role: String }\n'
SEMANTIC='-- allium: 3\n\nentity W {\n    v: Missing\n}\n'

if ! command -v allium >/dev/null 2>&1; then
  echo "  SKIP  allium CLI not installed — real-CLI arms not run"
else
  R="$TMP/clean"; spec "$R" 001-a "$CLEAN"; spec "$R" 002-b "$WARN"
  out=$(bash "$CENSUS" "$R"); rc=$?
  [ "$rc" -eq 0 ] && ok "clean + warnings-only → exit 0" || bad "clean: rc=$rc $out"
  grep -q '^allium-census: 2 files, 0 with errors (0 parse, 0 semantic)$' <<< "$out" \
    && ok "summary counts 2 files, 0 errors" || bad "clean summary: $out"

  R="$TMP/debt"; spec "$R" 001-a "$CLEAN"; spec "$R" 002-p "$PARSE"; spec "$R" 003-s "$SEMANTIC"
  out=$(bash "$CENSUS" "$R"); rc=$?
  [ "$rc" -eq 1 ] && ok "debt → exit 1" || bad "debt: rc=$rc $out"
  echo "$out" | grep -q $'^specs/002-p/spec.allium\tparse\t' && ok "parse error classified parse" || bad "parse class: $out"
  echo "$out" | grep -q $'^specs/003-s/spec.allium\tsemantic\t' && ok "checker error classified semantic" || bad "semantic class: $out"
  grep -q '001-a' <<< "$out" && bad "clean file listed" || ok "clean file not listed"
  echo "$out" | tail -1 | grep -q '3 files, 2 with errors (1 parse, 1 semantic)' && ok "debt summary" || bad "debt summary: $out"

  # Sabotage: trust the pipeline status. The warnings-only file must then stop reading clean.
  SAB="$TMP/sabotaged-census.sh"
  sed 's/; exit "\${PIPESTATUS\[1\]}")$/)/' "$CENSUS" > "$SAB"
  if cmp -s "$CENSUS" "$SAB"; then
    bad "sabotage: sed did not change the census — the arm is vacuous"
  else
    bash "$SAB" "$TMP/clean" >/dev/null 2>&1; rc=$?
    [ "$rc" -ne 0 ] && ok "sabotage: a pipefail census misreads warnings-only (rc=$rc) — the suite can tell" \
                    || bad "sabotage: pipefail census still exit 0 — suite is blind"
  fi
fi

FAKE="$TMP/fake"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho nope\n' > "$FAKE/garbage"; chmod +x "$FAKE/garbage"
R="$TMP/one"; spec "$R" 001-a "$CLEAN"
out=$(ALLIUM_BIN="$FAKE/garbage" bash "$CENSUS" "$R" 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && grep -q '1 unreadable' <<< "$out"; } && ok "unreadable report → exit 2" || bad "unreadable: rc=$rc $out"

mkdir -p "$TMP/empty/specs"
out=$(ALLIUM_BIN="$FAKE/garbage" bash "$CENSUS" "$TMP/empty" 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && grep -q '0 files' <<< "$out"; } && ok "zero baselines → exit 2, never clean" || bad "empty: rc=$rc $out"

out=$(ALLIUM_BIN="$FAKE/nope" bash "$CENSUS" "$R" 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && grep -q 'not installed' <<< "$out"; } && ok "missing CLI → exit 2" || bad "missing: rc=$rc $out"

echo
echo "allium-census: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
