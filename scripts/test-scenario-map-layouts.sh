#!/bin/sh
# test-scenario-map-layouts.sh — the predicate every 007bl consumer shares, under test.
#
# scenario_map_layout is three lines of shell, which is exactly why it is worth testing: it is
# small enough to look obviously right and be wrong. The empty-directory case in particular has
# a well-known wrong answer (a glob that matches nothing expands to itself, so a naive emptiness
# check reports a directory with contents), and getting it wrong sends every consumer looking
# for scenario rows in a directory that has none.
#
# Run: bash scripts/test-scenario-map-layouts.sh
# Exit: 0 all cases pass · 1 one or more failed

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/scenario-map-layout.sh"
. "$SCRIPT_DIR/test-scenario-map-fixtures.sh"

FAILED=0
ok()  { printf '  ok:   %s\n' "$1"; }
bad() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }

expect_layout() {
    _case="$1"; _root="$2"; _want="$3"
    _got=$(scenario_map_layout "$_root")
    if [ "$_got" = "$_want" ]; then ok "$_case  ($_got)"
    else bad "$_case" "expected $_want, got $_got"; fi
}

echo "scenario map layout predicate"

# --- the two real layouts -------------------------------------------------------------
SINGLE=$(make_single_file_fixture)
SPLIT=$(make_split_fixture)
EMPTY=$(make_empty_split_fixture)

expect_layout "single-file  (no specs/scenarios/)"        "$SINGLE" single_file
expect_layout "split        (two feature files)"          "$SPLIT"  split
expect_layout "empty-split  (dir exists, holds nothing)"  "$EMPTY"  single_file

# --- degenerate roots -----------------------------------------------------------------
# The hooks fail open on anything they cannot read. The predicate must never be the thing that
# turns a missing directory into an error, because it runs inside a SessionStart banner.
NOWHERE="$(_fixture_tmpdir)/does-not-exist-$$"
expect_layout "absent root" "$NOWHERE" single_file

BARE="$(_fixture_tmpdir)/bare-$$"; mkdir -p "$BARE"
expect_layout "bare dir, no specs/ at all" "$BARE" single_file

# A specs/scenarios that is a FILE, not a directory. Perverse, but -d is what distinguishes
# them and a check written with -e instead would answer `split` here.
ODD="$(_fixture_tmpdir)/odd-$$"; mkdir -p "$ODD/specs"; : > "$ODD/specs/scenarios"
expect_layout "specs/scenarios is a file" "$ODD" single_file

# A directory holding only a dotfile. `ls -A` counts it; a plain `ls` does not. Splitting on
# that difference is arbitrary, so the assertion records the choice rather than the accident:
# anything at all in the directory means somebody put it there.
DOTONLY="$(_fixture_tmpdir)/dot-$$"; mkdir -p "$DOTONLY/specs/scenarios"
: > "$DOTONLY/specs/scenarios/.gitkeep"
expect_layout "dir holds only .gitkeep" "$DOTONLY" split

# --- scenario_map_files ---------------------------------------------------------------
echo "scenario map file enumeration"

COUNT=$(scenario_map_files "$SINGLE" | grep -c .)
if [ "$COUNT" -eq 1 ]; then ok "single-file enumerates 1 file"
else bad "single-file enumerates 1 file" "got $COUNT"; fi

COUNT=$(scenario_map_files "$SPLIT" | grep -c .)
if [ "$COUNT" -eq 3 ]; then ok "split enumerates index + 2 feature files"
else bad "split enumerates index + 2 feature files" "got $COUNT"; fi

FIRST=$(scenario_map_files "$SPLIT" | head -1)
case "$FIRST" in
    */specs/SCENARIOS.md) ok "index is enumerated first" ;;
    *) bad "index is enumerated first" "got $FIRST" ;;
esac

# The rows must survive enumeration: extracting across the split fixture must find all three
# scenarios the single-file fixture holds. This is the same assertion the real map's gate makes,
# in miniature, and it proves the two scripts compose.
S_ROWS=$(sh "$SCRIPT_DIR/scenario-map-rows.sh" "$SINGLE/specs/SCENARIOS.md")
P_ROWS=$(sh "$SCRIPT_DIR/scenario-map-rows.sh" $(scenario_map_files "$SPLIT"))
if [ "$S_ROWS" = "$P_ROWS" ]; then ok "both layouts yield identical rows"
else
    bad "both layouts yield identical rows" "extraction differs"
    printf '%s\n' "$S_ROWS" > "$(_fixture_tmpdir)/single.rows"
    printf '%s\n' "$P_ROWS" > "$(_fixture_tmpdir)/split.rows"
    diff "$(_fixture_tmpdir)/single.rows" "$(_fixture_tmpdir)/split.rows" | sed 's/^/        /'
fi

fixture_cleanup

echo
if [ "$FAILED" -eq 0 ]; then
    echo "all layout cases pass"
    exit 0
fi
echo "$FAILED case(s) failed"
exit 1
