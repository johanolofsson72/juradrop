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

# ============================================================ the remedy fits the file (row 008)
echo "remedy — a map is not shrunk by the INDEX.md archivers"

# orientation_says <root> <needle> — 0 when the SessionStart banner contains the needle.
orientation_says() {
    _banner=$( cd "$1" && bash "$SCRIPT_DIR/spec-register-orientation-hook.sh" </dev/null 2>&1 )
    grep -Fq -e "$2" <<< "$_banner"
}
if orientation_says "$BIG" "the archivers do not shrink it"; then
    ok "oversized map: the banner names the map remedy"
else
    bad "oversized map: the banner names the map remedy" "no 'the archivers do not shrink it' line"
fi
if orientation_says "$BIGIDX" "the archivers do not shrink it"; then
    bad "oversized register only: no map remedy" "the map line appeared for INDEX.md alone"
else
    ok "oversized register only: no map remedy"
fi

# The fixtures are not git repos, so finding.sh must resolve to the fixture and never climb into
# the template's own ledger. Hashed rather than trusted.
TEMPLATE_LEDGER="$SCRIPT_DIR/../specs/FINDINGS.md"
LEDGER_BEFORE=$(cat "$TEMPLATE_LEDGER" 2>/dev/null | cksum)
cp "$SCRIPT_DIR/finding.sh" "$BIG/scripts/finding.sh" 2>/dev/null || { mkdir -p "$BIG/scripts"; cp "$SCRIPT_DIR/finding.sh" "$BIG/scripts/finding.sh"; }
( cd "$BIG" && bash "$SCRIPT_DIR/project-maintenance.sh" >/dev/null 2>&1 )
if grep -Fq "scenario-map canary: specs/SCENARIOS.md " "$BIG/specs/FINDINGS.md" 2>/dev/null; then
    ok "oversized map: recorded in the fixture's own ledger"
else
    bad "oversized map: recorded in the fixture's own ledger" "no scenario-map canary line in $BIG/specs/FINDINGS.md"
fi
if [ "$(cat "$TEMPLATE_LEDGER" 2>/dev/null | cksum)" = "$LEDGER_BEFORE" ]; then
    ok "the template's own specs/FINDINGS.md is untouched"
else
    bad "the template's own specs/FINDINGS.md is untouched" "it changed during the run"
fi

# ============================================================ the register is measured by part (row 017)
echo "register — the advice follows the bytes"

# orientation_raw <root> — the SessionStart banner text, whole.
orientation_raw() { ( cd "$1" && bash "$SCRIPT_DIR/spec-register-orientation-hook.sh" </dev/null 2>&1 ); }
maintenance_raw() { ( cd "$1" && bash "$SCRIPT_DIR/project-maintenance.sh" 2>&1 ); }
says()    { if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "no '$2'"; fi; }
silent_on() { if grep -Fq -e "$2" <<< "$3"; then bad "$1" "unexpected '$2'"; else ok "$1"; fi; }

# The fixtures' INDEX.md must reach the helper the way a synced project does: in scripts/.
with_helper() { mkdir -p "$1/scripts"; cp "$SCRIPT_DIR/register-bytes.sh" "$1/scripts/"; }

# agentcrm's shape: the bytes are prose inside ## Specs. The old canary named the row archiver.
PROSE=$(make_single_file_fixture); with_helper "$PROSE"
while [ "$(wc -c < "$PROSE/specs/INDEX.md" | tr -d ' ')" -le "$THRESH" ]; do
    printf '| lane | owner | depends on | a dependency table written inside the Specs section |\n' >> "$PROSE/specs/INDEX.md"
done
expect_warns "prose-heavy register is named" "$PROSE" orientation "INDEX.md"
BANNER=$(orientation_raw "$PROSE")
says      "prose-heavy: the banner names the prose move"           "· prose: move the notes" "$BANNER"
silent_on "prose-heavy: the banner does not name the row archiver" "archive-completed-rows" "$BANNER"
MOUT=$(maintenance_raw "$PROSE")
says      "prose-heavy: maintenance names the prose move"          "prose: move the notes" "$MOUT"
silent_on "prose-heavy: maintenance does not name the row archiver" "archive-completed-rows" "$MOUT"

# msroute's shape: every row inside budget, nothing left to archive. No move exists, so the
# register is not actionable: no attention-mode canary, one info line, no red finding.
# The rows go ABOVE the fixture's history heading: appended below it they are history entries,
# and a register with 200 history entries has a move (the history archiver).
ROWS=$(make_single_file_fixture); with_helper "$ROWS"
ROWLINE='- [x] 001 — done-row — spec-only — a compliant ticked row, archived verbatim elsewhere'
NROWS=$(( THRESH / ${#ROWLINE} + 1 ))
awk -v row="$ROWLINE" -v n="$NROWS" '/^## Register history/ && !done { for (i = 0; i < n; i++) print row; print ""; done = 1 } { print }' \
    "$ROWS/specs/INDEX.md" > "$ROWS/specs/INDEX.tmp" && mv "$ROWS/specs/INDEX.tmp" "$ROWS/specs/INDEX.md"
if [ "$(wc -c < "$ROWS/specs/INDEX.md" | tr -d ' ')" -le "$THRESH" ]; then
    bad "compliant register fixture" "INDEX.md did not pass the threshold — the cases below would prove nothing"
fi
expect_warns "compliant register: no canary" "$ROWS" orientation ""
BANNER=$(orientation_raw "$ROWS")
silent_on "compliant register: no CONTEXT-COST CANARY" "CONTEXT-COST CANARY" "$BANNER"
says      "compliant register: the info line says why"   "every part complies; nothing archives it further" "$BANNER"
MOUT=$(maintenance_raw "$ROWS")
says      "compliant register: maintenance notes it"      "every part complies" "$MOUT"
expect_warns "compliant register: not a maintenance finding" "$ROWS" maintenance ""

# Helper absent (a partial sync): the canary keeps its old wording instead of going quiet.
NOHELP=$(make_single_file_fixture)
cp "$ROWS/specs/INDEX.md" "$NOHELP/specs/INDEX.md"
# The hook resolves the helper from its own directory, so run a copy of the hook from a directory
# that has no helper next to it.
HOOKCOPY=$(mktemp -d "${FIXTURE_TMPDIR}/hook.XXXXXX")
cp "$SCRIPT_DIR/spec-register-orientation-hook.sh" "$HOOKCOPY/"
for dep in hook-notice.sh resolve-active-spec.sh spec_active.py; do
    [ -f "$SCRIPT_DIR/$dep" ] && cp "$SCRIPT_DIR/$dep" "$HOOKCOPY/"
done
BANNER=$( cd "$NOHELP" && bash "$HOOKCOPY/spec-register-orientation-hook.sh" </dev/null 2>&1 )
says "helper missing: the canary still fires"        "CONTEXT-COST CANARY" "$BANNER"
says "helper missing: the old archiver advice stays" "archive-completed-rows" "$BANNER"
MOUT=$(maintenance_raw "$NOHELP")
says "helper missing: maintenance keeps the finding" "[CONTEXT-COST] specs/INDEX.md" "$MOUT"

fixture_cleanup

echo
if [ "$FAILED" -eq 0 ]; then
    echo "all canary cases pass"
    exit 0
fi
echo "$FAILED case(s) failed"
exit 1
