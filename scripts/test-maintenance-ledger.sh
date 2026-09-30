#!/bin/bash
# Self-test for scripts/maintenance_ledger.py (row 074).
#
#   bash scripts/test-maintenance-ledger.sh
#
# What is under test: the wrapper is transparent (output and exit code pass through), a line has the
# documented shape, the cloud is told apart from local, a ledger that cannot be written changes
# nothing about the job, and the report never renders "unmeasured" as "measured zero".
#
# Fixture-only: every case runs in a throwaway git repo under mktemp. Nothing touches the network.
# bash 3.2-safe (macOS system bash).

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
LEDGER_PY="$DIR/maintenance_ledger.py"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/maintenance-ledger-test.$$")
PASS=0
FAIL=0
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
expect_contains() { if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "contains: $2" "$3"; fi; }
expect_absent()   { if grep -Fq -e "$2" <<< "$3"; then bad "$1" "absent: $2" "$3"; else ok "$1"; fi; }

command -v python3 >/dev/null 2>&1 || { echo "SKIP — python3 not installed; the ledger itself degrades to unmeasured runs."; exit 0; }

mkrepo() { # mkrepo NAME DONE_COUNT -> path
  local r="$TMP/$1"; mkdir -p "$r/specs"
  ( cd "$r" && git init -q . )
  : > "$r/specs/INDEX.md"
  local i=0; while [ "$i" -lt "$2" ]; do echo "- [x] 00$i — row" >> "$r/specs/INDEX.md"; i=$((i + 1)); done
  printf '%s' "$r"
}

echo "maintenance_ledger.py"

R=$(mkrepo a 3)
L="$R/.claude/state/maintenance-runs.tsv"

# L1-L2: exit code and output pass through untouched.
OUT=$(cd "$R" && python3 "$LEDGER_PY" run demo -- sh -c 'echo hello; echo oops >&2; exit 7' 2>&1); RC=$?
expect_eq       "L1 child exit code is the wrapper's exit code" "7" "$RC"
expect_contains "L2 child stdout passes through" "hello" "$OUT"
expect_contains "L2 child stderr passes through" "oops" "$OUT"

# L3: one line, nine tab-separated fields, job/rc/done where they belong.
LINE=$(tail -1 "$L" 2>/dev/null)
expect_eq "L3 nine fields" "9" "$(printf '%s' "$LINE" | awk -F'\t' '{print NF}')"
expect_eq "L3 job field"   "demo" "$(printf '%s' "$LINE" | cut -f3)"
expect_eq "L3 rc field"    "7" "$(printf '%s' "$LINE" | cut -f5)"
expect_eq "L3 done field"  "3" "$(printf '%s' "$LINE" | cut -f9)"
case "$(printf '%s' "$LINE" | cut -f2)" in local-*) ok "L3 place is local-<os> outside the cloud" ;;
  *) bad "L3 place is local-<os> outside the cloud" "local-*" "$(printf '%s' "$LINE" | cut -f2)" ;; esac

# L4: CLAUDE_CODE_REMOTE=true is the cloud.
( cd "$R" && CLAUDE_CODE_REMOTE=true python3 "$LEDGER_PY" run demo -- true )
expect_eq "L4 place is cloud when CLAUDE_CODE_REMOTE=true" "cloud" "$(tail -1 "$L" | cut -f2)"

# L5: a ledger that cannot be written warns and changes nothing about the job.
R2=$(mkrepo readonly 0)
mkdir -p "$R2/.claude/state" && chmod a-w "$R2/.claude/state"
OUT=$(cd "$R2" && python3 "$LEDGER_PY" run demo -- sh -c 'echo fine; exit 0' 2>&1); RC=$?
expect_eq       "L5 unwritable ledger keeps rc 0" "0" "$RC"
expect_contains "L5 unwritable ledger says so" "not recorded" "$OUT"
expect_contains "L5 output still passes through" "fine" "$OUT"

# L6: a command that cannot start is 127, recorded, not a crash.
( cd "$R" && python3 "$LEDGER_PY" run demo -- /nonexistent/binary >/dev/null 2>&1 ); RC=$?
expect_eq "L6 unstartable command exits 127" "127" "$RC"

# L7: record writes a caller-timed span with a blank RSS, never an invented one.
( cd "$R" && python3 "$LEDGER_PY" record pass 42 1 )
expect_eq "L7 record seconds" "42.0" "$(tail -1 "$L" | cut -f4)"
expect_eq "L7 record RSS left blank" "" "$(tail -1 "$L" | cut -f6)"
( cd "$R" && python3 "$LEDGER_PY" record pass notanumber 0 2>/dev/null ); RC=$?
expect_eq "L7 record rejects a non-number" "2" "$RC"

# L8: an empty ledger reports "no runs recorded", not a table of zeros.
R3=$(mkrepo empty 0)
OUT=$(cd "$R3" && python3 "$LEDGER_PY" report 2>&1)
expect_contains "L8 empty ledger says no runs recorded" "no runs recorded" "$OUT"
expect_absent   "L8 empty ledger prints no table" "median s" "$OUT"

# L9: aggregation per job and place, and the spec span against the five 075 needs.
R4=$(mkrepo agg 0); L4="$R4/.claude/state/maintenance-runs.tsv"; mkdir -p "$(dirname "$L4")"
printf '2026-09-29T10:00:00+02:00\tlocal-darwin\tmutation\t100.0\t0\t2000\t10\t1.0\t20\n'  >  "$L4"
printf '2026-09-30T10:00:00+02:00\tlocal-darwin\tmutation\t300.0\t1\t14000\t10\t1.0\t22\n' >> "$L4"
printf '2026-10-01T10:00:00+02:00\tlocal-darwin\tsuite\t50.0\t0\t\t10\t\t23\n'            >> "$L4"
printf 'garbage line with too few fields\n'                                                >> "$L4"
OUT=$(cd "$R4" && python3 "$LEDGER_PY" report 2>&1)
expect_contains "L9 span 3 of 5 and keep measuring" "spans 3 of 5 ticked specs needed (keep measuring)" "$OUT"
expect_contains "L9 median of two runs" "200.0" "$OUT"
expect_contains "L9 a 14 GB peak is too big for the VM" "TOO BIG for 16 GB" "$OUT"
expect_contains "L9 missing RSS is unknown, not zero" "unknown (no RSS)" "$OUT"
expect_contains "L9 three valid runs, garbage skipped" "3 runs" "$OUT"
expect_contains "L9 the failed mutation run is counted" "     1  TOO BIG for 16 GB" "$OUT"
printf '2026-10-05T10:00:00+02:00\tcloud\tmutation\t400.0\t0\t3000\t4\t0.5\t25\n' >> "$L4"
OUT=$(cd "$R4" && python3 "$LEDGER_PY" report 2>&1)
expect_contains "L9 five specs spanned is ready" "spans 5 of 5 ticked specs needed (ready for 075)" "$OUT"
expect_contains "L9 cloud runs group separately" "cloud" "$OUT"

# L10: --all reads sibling repos' ledgers.
OUT=$(cd "$R4" && python3 "$LEDGER_PY" report --all 2>&1)
expect_contains "L10 --all includes the sibling repo" "== a" "$OUT"
expect_contains "L10 --all includes this repo" "== agg" "$OUT"

# L11: peak RSS is the process TREE, not the largest single process. Three children hold ~150 MB
# each for 3 s; the sum must clear 350 MB while any one of them stays near 150.
R5=$(mkrepo tree 0)
( cd "$R5" && python3 "$LEDGER_PY" run tree -- sh -c '
  for i in 1 2 3; do python3 -c "import time; b = bytearray(150*1024*1024); b[::4096] = b\"x\" * len(b[::4096]); time.sleep(3)" & done; wait' )
TREE_MB=$(tail -1 "$R5/.claude/state/maintenance-runs.tsv" | cut -f6)
if [ -n "$TREE_MB" ] && [ "$TREE_MB" -ge 350 ]; then ok "L11 tree RSS sums the children ($TREE_MB MB)"
else bad "L11 tree RSS sums the children" ">= 350" "${TREE_MB:-empty}"; fi

echo
echo "maintenance_ledger: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
