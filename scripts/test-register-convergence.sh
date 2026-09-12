#!/bin/bash
# test-register-convergence.sh — the convergence check against synthetic registers.
#
# Two of these cases are regressions from the day the script was written:
# `mapfile` (bash 4+) on a macOS bash 3.2, and a comma-decimal locale that made
# awk print 1,23 and read it back as 1 — so a flat register reported "converging".
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$SCRIPT_DIR/register-convergence.sh"
PASS=0; FAIL=0

mk() { # mk <dir> then a series of "total done" pairs, oldest first
  local d="$1"; shift
  rm -rf "$d"; mkdir -p "$d/specs"; git -C "$d" init -q
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  local day=1
  for pair in "$@"; do
    local total="${pair%% *}" done_n="${pair##* }"
    { echo "# Spec register"; echo; echo "## Specs"; echo
      local i=1
      while [ "$i" -le "$done_n" ]; do echo "- [x] $(printf '%03d' $i) — s$i — spec-only — goal"; i=$((i+1)); done
      while [ "$i" -le "$total" ]; do echo "- [ ] $(printf '%03d' $i) — s$i — spec-only — goal"; i=$((i+1)); done
    } > "$d/specs/INDEX.md"
    git -C "$d" add -A
    GIT_AUTHOR_DATE="2026-08-$(printf '%02d' $day)T12:00:00" \
    GIT_COMMITTER_DATE="2026-08-$(printf '%02d' $day)T12:00:00" \
      git -C "$d" commit -qm "day $day"
    day=$((day+1))
  done
}

check() { # check <label> <dir> <expected verdict> <expected exit>
  local label="$1" d="$2" want="$3" wantrc="$4"
  local out rc
  out=$(bash "$SUT" --dir "$d" --json 2>&1); rc=$?
  if grep -q "\"verdict\":\"$want\"" <<< "$out" && [ "$rc" = "$wantrc" ]; then
    echo "  PASS  $label"; PASS=$((PASS+1))
  else
    echo "  FAIL  $label — want $want/rc$wantrc, got rc$rc: $out"; FAIL=$((FAIL+1))
  fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Draining: 20 rows added, 30 ticked.
mk "$TMP/conv" "10 0" "20 10" "25 20" "30 30"
check "converging register" "$TMP/conv" converging 0

# Flat: 12 added against 10 ticked = 1.20. This is the locale regression's home —
# under a comma-decimal locale awk printed 1,20 and read it back as 1, which lands
# on the wrong side of BOTH thresholds and reported "converging".
mk "$TMP/flat" "20 0" "26 5" "32 10" "38 15"
check "flat register (locale-sensitive ratio)" "$TMP/flat" flat 1

# 13 added against 10 ticked = exactly 1.30, the diverging threshold. Pinned because
# a >= that quietly became > would let the worst still-reported register through.
mk "$TMP/edge" "20 0" "26 5" "33 10" "39 15"
check "ratio exactly at the 1.30 threshold diverges" "$TMP/edge" diverging 2

# Diverging: every tick brings three rows.
mk "$TMP/div" "20 0" "35 5" "50 10" "65 15"
check "diverging register" "$TMP/div" diverging 2

# Under the 10-tick window the threshold must not fire, however bad the ratio.
mk "$TMP/thin" "10 0" "40 3"
check "thin window stays quiet" "$TMP/thin" thin 0

# A quiet week ticks nothing; dividing by zero would print infinity and cry wolf.
mk "$TMP/noticks" "10 5" "14 5" "18 5"
out=$(bash "$SUT" --dir "$TMP/noticks" 2>&1); rc=$?
if [ "$rc" = 3 ] && grep -q "nothing to measure" <<< "$out"; then
  echo "  PASS  no ticks in window -> rc3"; PASS=$((PASS+1))
else echo "  FAIL  no ticks in window — got rc$rc: $out"; FAIL=$((FAIL+1)); fi

# A repo with no register is a usage error, not a verdict.
rm -rf "$TMP/bare"; mkdir -p "$TMP/bare"; git -C "$TMP/bare" init -q
bash "$SUT" --dir "$TMP/bare" >/dev/null 2>&1; rc=$?
if [ "$rc" = 4 ]; then echo "  PASS  no register -> rc4"; PASS=$((PASS+1))
else echo "  FAIL  no register -> rc$rc"; FAIL=$((FAIL+1)); fi

# Bad --window is refused rather than silently defaulted.
bash "$SUT" --dir "$TMP/conv" --window abc >/dev/null 2>&1; rc=$?
if [ "$rc" = 4 ]; then echo "  PASS  non-numeric --window -> rc4"; PASS=$((PASS+1))
else echo "  FAIL  non-numeric --window -> rc$rc"; FAIL=$((FAIL+1)); fi

# bash 3.2 is the floor: macOS ships it and cross-platform is a base requirement.
if grep -qE '^\s*mapfile|readarray' "$SUT"; then  # portability-ok — this line IS the check
  echo "  FAIL  uses mapfile/readarray (bash 4+); macOS ships bash 3.2"; FAIL=$((FAIL+1))  # portability-ok
else echo "  PASS  no bash-4-only builtins"; PASS=$((PASS+1)); fi

echo "register-convergence: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
