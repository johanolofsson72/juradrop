#!/bin/sh
# test-scenario-map-canary.sh — the context-cost canary, at both sites, under both map layouts.
#
# WHAT THE CANARY IS FOR: specs/INDEX.md and the scenario map are read on every spec, so every
# byte in them is re-billed for the life of the project. The canary is the only thing that
# notices them growing, because no single edit ever looks large — msroute's map reached 85 KB
# one feature at a time, with every commit looking reasonable.
#
# WHY 007bl COULD HAVE BROKEN IT SILENTLY: after the split, specs/SCENARIOS.md is small by
# construction. A canary that measures only the index would report a healthy 9 KB forever while
# the feature files grew unwatched — the same failure the canary exists to catch, reintroduced
# by the fix for it, and invisible because the warning it stops printing is a warning nobody
# expects to see. Hence the per-file cases below.
#
# Run: bash scripts/test-scenario-map-canary.sh
# Exit: 0 all cases pass · 1 one or more failed

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/test-scenario-map-fixtures.sh"

FAILED=0
ok()  { printf '  ok:   %s\n' "$1"; }
bad() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }

FIXTURE_TMPDIR=$(_fixture_tmpdir); export FIXTURE_TMPDIR

THRESH=25600

# pad_past_threshold <file> — grow a file past the canary threshold with filler that is
# unmistakably filler, so a human reading a failed fixture is not misled.
pad_past_threshold() {
    _p_file="$1"
    while [ "$(wc -c < "$_p_file" | tr -d ' ')" -le "$THRESH" ]; do
        printf -- '- 2026-08-26 — padding, present only to exceed the canary threshold so the warning path runs\n' >> "$_p_file"
    done
    unset _p_file
}

# orientation_warns <root> — the file names the SessionStart canary reports, one per line.
orientation_warns() {
    ( cd "$1" && bash "$SCRIPT_DIR/spec-register-orientation-hook.sh" </dev/null 2>&1 ) \
      | grep -oE '(INDEX\.md|SCENARIOS\.md|scenarios/[A-Za-z0-9._-]+\.md) \([0-9]+ KB\)' \
      | sed 's/ ([0-9]* KB)//' | sort
}

# maintenance_warns <root> — the same, from the recurring maintenance pass.
maintenance_warns() {
    ( cd "$1" && bash "$SCRIPT_DIR/project-maintenance.sh" 2>&1 ) \
      | grep -oE '\[CONTEXT-COST\] [^ ]+' | sed 's/\[CONTEXT-COST\] //' | sort
}

# expect_warns <case> <root> <site> <newline-separated expected>
expect_warns() {
    _case="$1"; _root="$2"; _site="$3"; _want="$4"
    if [ "$_site" = orientation ]; then _got=$(orientation_warns "$_root")
    else _got=$(maintenance_warns "$_root"); fi
    _want=$(printf '%s' "$_want" | sed '/^$/d' | sort)
    if [ "$_got" = "$_want" ]; then
        ok "$_case [$_site]"
    else
        bad "$_case [$_site]" "expected [$(printf '%s' "$_want" | tr '\n' ' ')] got [$(printf '%s' "$_got" | tr '\n' ' ')]"
    fi
}

# ============================================================ single-file layout
echo "single-file layout — behaviour must be unchanged by 007bl"

SINGLE=$(make_single_file_fixture)
expect_warns "small map, small register: silent" "$SINGLE" orientation ""
expect_warns "small map, small register: silent" "$SINGLE" maintenance ""

BIG=$(make_single_file_fixture)
pad_past_threshold "$BIG/specs/SCENARIOS.md"
expect_warns "oversized map is named" "$BIG" orientation "SCENARIOS.md"
expect_warns "oversized map is named" "$BIG" maintenance "specs/SCENARIOS.md"

BIGIDX=$(make_single_file_fixture)
pad_past_threshold "$BIGIDX/specs/INDEX.md"
expect_warns "oversized register is named" "$BIGIDX" orientation "INDEX.md"
expect_warns "oversized register is named" "$BIGIDX" maintenance "specs/INDEX.md"

# ============================================================ split layout
echo "split layout — the index alone is no longer the whole cost"

SPLIT=$(make_split_fixture)
expect_warns "everything under threshold: silent" "$SPLIT" orientation ""
expect_warns "everything under threshold: silent" "$SPLIT" maintenance ""

# THE CASE 007bl COULD HAVE BROKEN SILENTLY. The index is small — as it will always be after a
# split — and a feature file has grown past the threshold. A canary measuring only the index
# reports nothing here, forever.
ONEBIG=$(make_split_fixture)
pad_past_threshold "$ONEBIG/specs/scenarios/001-alpha.md"
expect_warns "one oversized feature file is named" "$ONEBIG" orientation "scenarios/001-alpha.md"
expect_warns "one oversized feature file is named" "$ONEBIG" maintenance "specs/scenarios/001-alpha.md"

# The index really is small in that case — asserted rather than assumed, so the case above
# cannot pass for the wrong reason (e.g. the index tripping the warning instead).
IDX_BYTES=$(wc -c < "$ONEBIG/specs/SCENARIOS.md" | tr -d ' ')
if [ "$IDX_BYTES" -le "$THRESH" ]; then
    ok "the index in that case is genuinely under threshold ($IDX_BYTES bytes)"
else
    bad "the index in that case is genuinely under threshold" "index is $IDX_BYTES bytes — the case proves nothing"
fi

# The resolved AMBIGUITY from spec.allium: where two files are over, BOTH are named. Naming
# only the largest sends the reader back for the next one after each fix.
TWOBIG=$(make_split_fixture)
pad_past_threshold "$TWOBIG/specs/scenarios/001-alpha.md"
pad_past_threshold "$TWOBIG/specs/scenarios/002-beta.md"
expect_warns "two oversized feature files: BOTH named" "$TWOBIG" orientation \
    "scenarios/001-alpha.md
scenarios/002-beta.md"
expect_warns "two oversized feature files: BOTH named" "$TWOBIG" maintenance \
    "specs/scenarios/001-alpha.md
specs/scenarios/002-beta.md"

# Index and a feature file both over: the report is additive, not either/or.
BOTH=$(make_split_fixture)
pad_past_threshold "$BOTH/specs/SCENARIOS.md"
pad_past_threshold "$BOTH/specs/scenarios/002-beta.md"
expect_warns "index AND a feature file: both named" "$BOTH" orientation \
    "SCENARIOS.md
scenarios/002-beta.md"
expect_warns "index AND a feature file: both named" "$BOTH" maintenance \
    "specs/SCENARIOS.md
specs/scenarios/002-beta.md"

# NEVER SUMMED. Two feature files that are each comfortably under the threshold but together
# exceed it must produce silence. A sum would fire permanently on a healthy map, and an alarm
# that is always on is an alarm that is off.
SUM=$(make_split_fixture)
i=0
while [ "$i" -lt 200 ]; do
    printf -- '- filler line to build bulk without crossing the per-file threshold\n' >> "$SUM/specs/scenarios/001-alpha.md"
    printf -- '- filler line to build bulk without crossing the per-file threshold\n' >> "$SUM/specs/scenarios/002-beta.md"
    i=$((i + 1))
done
A=$(wc -c < "$SUM/specs/scenarios/001-alpha.md" | tr -d ' ')
B=$(wc -c < "$SUM/specs/scenarios/002-beta.md" | tr -d ' ')
if [ "$A" -le "$THRESH" ] && [ "$B" -le "$THRESH" ] && [ "$((A + B))" -gt "$THRESH" ]; then
    expect_warns "two files under, sum over: silent (never summed)" "$SUM" orientation ""
    expect_warns "two files under, sum over: silent (never summed)" "$SUM" maintenance ""
else
    bad "two files under, sum over" "fixture is wrong: A=$A B=$B sum=$((A + B)) thresh=$THRESH"
fi

# An empty specs/scenarios/ reads as single-file everywhere else; the canary must not trip on
# the directory's mere existence.
EMPTY=$(make_empty_split_fixture)
expect_warns "empty specs/scenarios/: silent" "$EMPTY" orientation ""
expect_warns "empty specs/scenarios/: silent" "$EMPTY" maintenance ""

fixture_cleanup

echo
if [ "$FAILED" -eq 0 ]; then
    echo "all canary cases pass"
    exit 0
fi
echo "$FAILED case(s) failed"
exit 1
