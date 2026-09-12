#!/bin/sh
# test-scenario-map-reminder.sh — the scenario-map reminder hook, under both map layouts.
#
# WHAT IS AT STAKE: this hook is the only automatic check that a spec's user-cases reached the
# scenario map. It is advisory, so nothing forces anyone to act on it — which means its value
# rests entirely on being believed. Spec 007bl gave the map a second shape, and a hook that
# still searched only the index would report a gap for every feature whose rows had moved. That
# is not a small bug: an advisory that fires on every spec is indistinguishable from noise, and
# after the third false alarm nobody reads the fourth. The real gap then slips through the
# hook that was built to catch it.
#
# So the cases below are weighted toward silence: proving the hook stays quiet when it should
# is more important here than proving it speaks when it should, because a false positive costs
# the hook its credibility while a false negative costs one advisory.
#
# Run: bash scripts/test-scenario-map-reminder.sh
# Exit: 0 all cases pass · 1 one or more failed

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/test-scenario-map-fixtures.sh"

HOOK="$SCRIPT_DIR/scenario-map-reminder-hook.sh"
FAILED=0
ok()  { printf '  ok:   %s\n' "$1"; }
bad() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }

FIXTURE_TMPDIR=$(_fixture_tmpdir); export FIXTURE_TMPDIR

# write_spec <root> <slug> <interactive|inert>
write_spec() {
    mkdir -p "$1/specs/$2"
    if [ "$3" = "interactive" ]; then
        printf '# %s\n\nThe user submits a form with an input field and a button.\n' "$2" > "$1/specs/$2/spec.md"
    else
        printf '# %s\n\nA pure refactor. No user-facing surface.\n' "$2" > "$1/specs/$2/spec.md"
    fi
    echo "$1/specs/$2/spec.md"
}

run_hook() {
    printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOK" 2>/dev/null
}

# expect_silent <case> <spec-file>
expect_silent() {
    _out=$(run_hook "$2")
    if [ -z "$_out" ]; then ok "$1"
    else bad "$1" "expected silence, got: $(printf '%s' "$_out" | head -c 120)"; fi
}

# expect_advisory <case> <spec-file> <slug-that-must-be-named>
expect_advisory() {
    _out=$(run_hook "$2")
    if [ -z "$_out" ]; then
        bad "$1" "expected an advisory, got silence"
    elif grep -q "$3" <<< "$_out"; then
        ok "$1"
    else
        bad "$1" "advisory fired but does not name $3"
    fi
}

# ============================================================ split layout
echo "split layout (index + feature files)"
SPLIT=$(make_split_fixture)

# THE CASE 007bl EXISTS TO PROTECT. 001a-alpha-detail is a nested sub-feature: its slug is
# named inside specs/scenarios/001-alpha.md and in no index row — the shape of msroute's real
# 007c-jwks-port-lifetime. Searching the index alone reports a scenario gap for a feature that
# is completely mapped.
F=$(write_spec "$SPLIT" 001a-alpha-detail interactive)
expect_silent "nested slug lives ONLY in a feature file, not the index" "$F"

# The assertion above is only worth anything if the old logic would have failed it. Rather
# than trusting that, run the old logic — an index-only grep — and require that it DOES fail.
# A regression test that would have passed before the fix is not a regression test.
if grep -qE "(^|[^A-Za-z0-9])001a-alpha-detail([^A-Za-z0-9]|\$)" "$SPLIT/specs/SCENARIOS.md" 2>/dev/null; then
    bad "the nested-slug case actually bites" \
        "index-only grep FINDS 001a-alpha-detail, so the case above passes either way and proves nothing"
else
    ok "the nested-slug case actually bites (index-only grep misses it)"
fi

# 002-beta IS named in the index (its row's Spec column and its link both carry the slug), so
# this passes with or without the fix. Kept as a guard against the opposite error: a
# multi-file search that somehow stops finding what the index plainly says.
F=$(write_spec "$SPLIT" 002-beta interactive)
expect_silent "slug named in the index and in a feature file" "$F"

# 001-alpha is named in the index's table AND in a feature file. Belt and braces.
F=$(write_spec "$SPLIT" 001-alpha interactive)
expect_silent "slug lives in both the index and a feature file" "$F"

# Genuinely unmapped. The hook must still speak — the split must not buy silence for
# everything, or it would have disabled the check rather than relocated it.
F=$(write_spec "$SPLIT" 003-gamma interactive)
expect_advisory "slug lives nowhere (advisory fires)" "$F" "003-gamma"

# No interactive behaviour: silent regardless of the map, in either layout.
F=$(write_spec "$SPLIT" 004-delta inert)
expect_silent "spec has no interactive behaviour" "$F"

# Boundary anchoring must survive the multi-file search. A short slug that is a substring of
# a mapped one must NOT be suppressed — otherwise 002-bet would inherit 002-beta's coverage.
F=$(write_spec "$SPLIT" 002-bet interactive)
expect_advisory "short slug is not matched inside a longer one" "$F" "002-bet"

# ============================================================ single-file layout
echo "single-file layout (the 41 unsplit projects)"
SINGLE=$(make_single_file_fixture)

F=$(write_spec "$SINGLE" 001-alpha interactive)
expect_silent "slug is in the map" "$F"

F=$(write_spec "$SINGLE" 003-gamma interactive)
expect_advisory "slug is not in the map (advisory fires)" "$F" "003-gamma"

F=$(write_spec "$SINGLE" 004-delta inert)
expect_silent "spec has no interactive behaviour" "$F"

# ============================================================ degenerate layouts
echo "degenerate layouts"

# An interrupted split: the directory exists and is empty. Must behave as single-file. If it
# were read as `split`, scenario_map_files would still list the index, so the hook stays
# correct — this asserts that, rather than assuming it.
EMPTY=$(make_empty_split_fixture)
F=$(write_spec "$EMPTY" 003-gamma interactive)
expect_advisory "empty specs/scenarios/ behaves as single-file" "$F" "003-gamma"

# No map at all: the hook has its own message for this, and it must survive the refactor.
NOMAP=$(make_single_file_fixture)
rm -f "$NOMAP/specs/SCENARIOS.md"
F=$(write_spec "$NOMAP" 003-gamma interactive)
OUT=$(run_hook "$F")
if grep -q 'does not exist yet' <<< "$OUT"; then
    ok "no map at all — the 'does not exist yet' message still fires"
else
    bad "no map at all" "expected the does-not-exist message, got: $(printf '%s' "$OUT" | head -c 120)"
fi

# A path with a space in it. The multi-file search must not word-split the file list into two
# names and silently search neither.
SPACED="$FIXTURE_TMPDIR/has space-$$"
cp -R "$SPLIT" "$SPACED"
F=$(write_spec "$SPACED" 002-beta interactive)
expect_silent "map path contains a space" "$F"

fixture_cleanup

echo
if [ "$FAILED" -eq 0 ]; then
    echo "all reminder cases pass"
    exit 0
fi
echo "$FAILED case(s) failed"
exit 1
