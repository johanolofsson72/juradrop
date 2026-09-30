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

# --freeze (row 077): the exit contract its three readers branch on. Deep cases live in test-finding.sh.
fz() { # fz <label> <expected rc> <register body> [engine present: 1|0]
  d="$TMP/fz-$RANDOM"; mkdir -p "$d/specs" "$d/scripts"; ( cd "$d" && git init -q . )
  cp "$SUT" "$d/scripts/"; [ "${4:-1}" = 1 ] && cp "$SCRIPT_DIR/register_freeze.py" "$d/scripts/"
  printf '%s\n' "$3" > "$d/specs/INDEX.md"
  ( cd "$d" && bash scripts/register-convergence.sh --freeze >/dev/null 2>&1 ); rc=$?
  if [ "$rc" = "$2" ]; then echo "  PASS  --freeze $1 -> rc$rc"; PASS=$((PASS+1))
  else echo "  FAIL  --freeze $1 -> rc$rc (want $2)"; FAIL=$((FAIL+1)); fi
}
ROWS='- [ ] 001 — a — b
- [ ] 002 — c — d'
fz "no freeze line"        1 "$ROWS"
fz "frozen, clean"         0 "Freeze: since 2026-09-29 · last row 002 · lifts below 1 open
$ROWS"
fz "unapproved row"        2 "Freeze: since 2026-09-29 · last row 001 · lifts below 1 open
$ROWS"
fz "below target"          3 "Freeze: since 2026-09-29 · last row 002 · lifts below 5 open
$ROWS"
fz "malformed line"        4 "Freeze: someday
$ROWS"
fz "engine missing"        5 "Freeze: since 2026-09-29 · last row 002 · lifts below 1 open
$ROWS" 0

# R2: the SessionStart banner. A freeze replaces the three-ways-out prompt; a malformed line does not.
banner() { # banner <label> <want substring> <reject substring> <register body>
  d="$TMP/bn-$RANDOM"; mkdir -p "$d/specs" "$d/scripts"; ( cd "$d" && git init -q . )
  cp "$SUT" "$SCRIPT_DIR/register_freeze.py" "$d/scripts/"; chmod +x "$d/scripts/register-convergence.sh"
  printf '%s\n' "$4" > "$d/specs/INDEX.md"
  # The hook walks up from the WORKING DIRECTORY, not CLAUDE_PROJECT_DIR: run it from inside the
  # fixture, or it reads whatever register encloses the caller (a false pass, measured 2026-09-29).
  out=$(cd "$d" && printf '{"hook_event_name":"SessionStart","source":"startup"}' |
        CLAUDE_PROJECT_DIR="$d" bash "$SCRIPT_DIR/spec-register-orientation-hook.sh" 2>/dev/null)
  case "$out" in *"$d/specs/INDEX.md"*) ;; *) echo "  FAIL  banner $1 read a register other than its fixture"; FAIL=$((FAIL+1)); return ;; esac
  case "$out" in *"$2"*) case "$out" in *"$3"*) echo "  FAIL  banner $1 carries '$3'"; FAIL=$((FAIL+1)) ;;
                                      *) echo "  PASS  banner $1"; PASS=$((PASS+1)) ;; esac ;;
    *) echo "  FAIL  banner $1 lacks '$2'"; FAIL=$((FAIL+1)) ;; esac
}
banner "frozen shows the freeze" "FREEZE (carve-budget.md" "three ways out" "# R

Freeze: since 2026-09-29 · last row 002 · lifts below 1 open

## Specs

$ROWS"
banner "malformed says fix it, not frozen" "fix the line" "FREEZE (carve-budget.md" "# R

Freeze: someday

## Specs

$ROWS"

# --carves (row 027): zero attributions is not "clean". The verdict and the exit code must say what
# was measured, because project-maintenance.sh branches on the code and lane-catchup.sh on the words.
cv() { # cv <label> <expected rc> <want substring> <reject substring> <register body>
  d="$TMP/cv-$RANDOM"; mkdir -p "$d/specs" "$d/scripts"
  cp "$SUT" "$SCRIPT_DIR/carve_audit.py" "$d/scripts/"
  printf '%s\n' "$5" > "$d/specs/INDEX.md"
  out=$(cd "$d" && bash scripts/register-convergence.sh --carves 2>&1); rc=$?
  if [ "$rc" != "$2" ]; then echo "  FAIL  --carves $1 -> rc$rc (want $2)"; FAIL=$((FAIL+1)); return; fi
  case "$out" in *"$3"*) ;; *) echo "  FAIL  --carves $1 lacks '$3'"; FAIL=$((FAIL+1)); return ;; esac
  case "$out" in *"$4"*) echo "  FAIL  --carves $1 carries '$4'"; FAIL=$((FAIL+1)); return ;; esac
  echo "  PASS  --carves $1 -> rc$rc"; PASS=$((PASS+1))
}
cvrows() { # cvrows <ticked> <open> -- unattributed rows 001.., ticked first
  i=1; while [ "$i" -le "$(( $1 + $2 ))" ]; do
    [ "$i" -le "$1" ] && m=x || m=' '
    echo "- [$m] $(printf '%03d' $i) — s$i — spec-only — goal"; i=$((i+1)); done
}
cv "attributed, within limits" 0 "carve shape: clean — 1 attributed" "unmeasurable" "$(cvrows 12 0)
- [ ] 013 — c — spec-only — goal — carved by 001"
cv "over budget"               1 "[CARVE BUDGET]" "carve shape: clean" "$(cvrows 12 0)
- [ ] 013 — a — carved by 001
- [ ] 014 — b — carved by 001
- [ ] 015 — c — carved by 001"
cv "none attributed, 10+ ticked" 3 "carve shape: unmeasurable — 0 attributed row(s) of 12 (10 ticked)" "clean" "$(cvrows 10 2)"
cv "none attributed, young"    0 "too young to measure" "clean" "$(cvrows 9 5)"
cv "only unresolved, 10+ ticked" 3 "1 cite a row this register does not hold" "clean" "$(cvrows 10 0)
- [ ] 011 — a — carved by 999"

echo "register-convergence: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
