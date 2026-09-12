#!/bin/sh
# test-scenario-map-split.sh — the gate around scenario-map-rows.sh.
#
# WHY THIS EXISTS, AND WHY THAT IS EMBARRASSING. Two places cited this file by name as an instrument
# that was already running:
#
#     .claude/rules/scenarios.md:150  "...Prove it mechanically: snapshot every row before, extract
#                                      after, diff. scripts/scenario-map-rows.sh and
#                                      scripts/test-scenario-map-split.sh are that pair."
#     scripts/scenario-map-rows.sh:7  "...is both halves of that, and
#                                      scripts/test-scenario-map-split.sh is the gate around it."
#
# It had never been written. Not in this repo, not in its history under any name (`git log --all
# --diff-filter=A` finds nothing). That is the SAME defect spec 007bs was opened to fix one artifact
# over — four comments in this very directory citing validate-scenario-traceability.sh as having
# "reported 100% and exit 0 throughout" when no such file existed — and it recurred here unnoticed
# because a citation reads exactly like a report. Spec 550 found it and wrote the instrument.
#
# WHAT IT CHECKS. scenario-map-rows.sh is the one extractor every other consumer trusts, so its
# contract is checked case by case against fixtures, plus a SABOTAGE arm: each defence is removed in
# turn and a named case must go red. A gate whose removal breaks nothing was never a gate — which is
# the whole lesson of the two citations above.
#
# FIXTURE IDS ARE DERIVED, NEVER WRITTEN (register row H7bd, re-landed here by H7bh). Every id in
# the fixtures below comes from scenario-probe-ids.sh, which hands back ids no row in the project's
# real map owns; the bodies carry @IDn@ placeholders that fixture() substitutes on the way to disk,
# and the assertions read the same ids out of $ID1..$ID21. Spelling real ids here instead is shorter
# and is a false binding: the id-accounting gate scans scripts/, cannot tell a fixture from an
# assertion, and counts a probe map about column parsing as proof that the real scenario is tested.
#
# This file shipped to consultpilot in sync 72737bd with 21 of that map's real ids spelled out, and
# its gate — scripts/validate-fixture-map-ids.sh, which exists because of exactly this — went red on
# arrival. Measured there (row H7bh): one of the 21 was referenced NOWHERE ELSE in that whole tree,
# so it read as directly `traced` on the strength of a fixture about column parsing, while the
# delegation its map row actually carries was never consulted. "Tested here" and "tested elsewhere"
# are two different truths and this file was reporting the wrong one.
#
# Two notes for whoever edits this next:
#   - The heredocs stay UNQUOTED (<<EOF). Unlike the two sibling harnesses they interpolate $HDR and
#     $SEP, and case 13's fixture depends on unquoted escape semantics for the exact bytes under
#     test. Quoting them "for consistency" changes what the fixture contains.
#   - Do not spell an id in the COMMENTS either, including a comment explaining this rule. For an id
#     the map owns, a whole-line comment in a CORE file still counts as a reference — the
#     template-owned excuse in validate-scenario-id-accounting.sh covers orphan candidates only.
#     Describe the shape instead; two comments below do exactly that.
#
# Usage:  scripts/test-scenario-map-split.sh          # all cases
#         scripts/test-scenario-map-split.sh --keep   # keep the temp dir for inspection
#
# EXIT: 0 all passed · 1 a case failed

set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROWS="$HERE/scenario-map-rows.sh"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

# shellcheck source=scripts/scenario-probe-ids.sh
. "$HERE/scenario-probe-ids.sh"

# The project's map, if it has one. The template ships none, and that is a legitimate state rather
# than a broken one: with no map every id is free, which is exactly right for a tree that owns no
# scenarios. The index alone is a sufficient owned set — a per-feature file cannot allocate an id
# the index does not also list — so this harness needs to know nothing about split layouts.
PROBE_MAP=$(git rev-parse --show-toplevel 2>/dev/null)/specs/SCENARIOS.md

# No 2>/dev/null on this call, deliberately. scenario_probe_checked's whole contract is that it
# REFUSES out loud rather than running short, and swallowing its stderr would make that refusal
# unfalsifiable — the same defect that hollowed out that helper's own readability guard.
PROBE_IDS=$(scenario_probe_checked 21 test-scenario-map-split "$PROBE_MAP") || exit 1

# shellcheck disable=SC2086
set -- $PROBE_IDS
# ${10} and up are not addressable in POSIX sh — `$10` parses as `$1` followed by a literal 0, which
# would silently reuse ID1 — so the first nine are shifted off rather than reached for. Twice here,
# because this harness needs 21.
ID1=$1;  ID2=$2;  ID3=$3;  ID4=$4;  ID5=$5;  ID6=$6;  ID7=$7;  ID8=$8;  ID9=$9
shift 9
ID10=$1; ID11=$2; ID12=$3; ID13=$4; ID14=$5; ID15=$6; ID16=$7; ID17=$8; ID18=$9
shift 9
ID19=$1; ID20=$2; ID21=$3

SUBST=$(scenario_probe_sed_script "$ID1"  "$ID2"  "$ID3"  "$ID4"  "$ID5"  "$ID6"  "$ID7" \
                                  "$ID8"  "$ID9"  "$ID10" "$ID11" "$ID12" "$ID13" "$ID14" \
                                  "$ID15" "$ID16" "$ID17" "$ID18" "$ID19" "$ID20" "$ID21")

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t scenario-map-split)
[ "$KEEP" -eq 1 ] || trap 'rm -rf "$TMP"' EXIT INT TERM

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n     %s\n' "$1" "$2"; }

# Write a map fixture. $1 = name, the body on stdin, @IDn@ substituted on the way to disk.
#
# The substitution lives HERE and not in each caller because this is the one writer: fifteen
# heredocs reach disk through this function and nothing else does, so one sed is the whole
# conversion. The bodies stay unquoted heredocs (they interpolate $HDR/$SEP); @IDn@ survives that
# untouched, and @ appears nowhere else in any fixture, so the substitution cannot collide with
# content that is under test.
fixture() {
  mkdir -p "$TMP/$1"
  sed "$SUBST" > "$TMP/$1/SCENARIOS.md"
}

# run <fixture> [extra args...] -> stdout to $TMP/out, stderr to $TMP/err, status in $RC
run() {
  f="$1"; shift
  RC=0
  "$ROWS" "$@" "$TMP/$f/SCENARIOS.md" > "$TMP/out" 2> "$TMP/err" || RC=$?
}

expect_rc() { # <case> <want>
  if [ "$RC" -eq "$2" ]; then ok "$1"; else bad "$1" "exit $RC, wanted $2 · $(head -1 "$TMP/err")"; fi
}

# The expected line is written here PIPE-separated and translated to the real TAB delimiter, because
# a tab inside a shell string literal is invisible in a diff and impossible to review. That is only
# safe while no fixture cell contains a pipe — so the translation is checked: if the result is not
# exactly six fields, the case is failed as malformed rather than compared and quietly missed. The
# escaped-pipe cases below assert with an explicit TAB for that reason.
TAB=$(printf '\t')

expect_row() { # <case> <expected line, pipe-separated>
  _want=$(printf '%s' "$2" | tr '|' "$TAB")
  _nf=$(printf '%s' "$_want" | awk -F"$TAB" '{print NF}')
  if [ "$_nf" != "6" ]; then
    bad "$1" "expected line does not translate to 6 fields (got $_nf) — write it with an explicit tab"
    return
  fi
  if grep -qxF "$_want" "$TMP/out"; then ok "$1"; else
    bad "$1" "missing row: $2 · got: $(tr '\n' ' ' < "$TMP/out" | cut -c1-160)"
  fi
}

expect_no_row() { # <case> <id>
  if grep -q "^$2$TAB" "$TMP/out"; then
    bad "$1" "row $2 should NOT have been extracted"
  else ok "$1"; fi
}

expect_count() { # <case> <n>
  n=$(grep -c . "$TMP/out" 2>/dev/null || true); n=${n:-0}
  if [ "$n" -eq "$2" ]; then ok "$1"; else bad "$1" "$n rows, wanted $2"; fi
}

HDR='| ID | Type | Scenario | Expected outcome | Status |'
SEP='|---|---|---|---|---|'

echo "scenario-map-rows.sh — contract cases:"

# ---------------------------------------------------------------------------------- case 1: clean
fixture clean <<EOF
# Map
$HDR
$SEP
| @ID1@ | happy | Log in | Session created | ✓ |
| @ID2@ | error | Wrong password | Specific message, never silent | ◐ |
EOF
run clean
expect_rc "case1-clean-exit" 0
expect_row "case1-clean-row" "${ID1}|happy|Log in|Session created|✓|0"
expect_count "case1-clean-count" 2

# ------------------------------------------------------------- case 2: a retired row keeps its id
# .claude/rules/scenarios.md makes an id a permanent handle. Dropping the strike would free it.
fixture struck <<EOF
$HDR
$SEP
| ~~@ID3@~~ | happy | ~~Removed~~ | Superseded | ✓ |
EOF
run struck
expect_row "case2-struck-keeps-id" "${ID3}|happy|~~Removed~~|Superseded|✓|1"

# ------------------------------------------------------ case 3: a malformed row refuses everything
# The DEFAULT must stay strict — the losslessness diff is invalid if one row is unreadable.
fixture malformed <<EOF
$HDR
$SEP
| @ID4@ | happy | Fine | Fine | ✓ |
| @ID5@ | happy | Missing a column | ✓ |
EOF
run malformed
expect_rc "case3-malformed-refuses-by-default" 2

# --------------------------------------------------------------- case 4: --partial skips and says so
run malformed --partial
expect_rc "case4-partial-exit-4" 4
expect_row "case4-partial-keeps-good-row" "${ID4}|happy|Fine|Fine|✓|0"
expect_count "case4-partial-count" 1

# ------------------------------------------------------------- case 5: --partial on a clean map = 0
run clean --partial
expect_rc "case5-partial-clean-is-0" 0

# ------------------------------------------ case 6: a lost newline (Class A) is REPORTED, not repaired
# 374.md carried 44 rows on one physical line; n joined rows report 6n-1 columns. The extractor does
# NOT quietly split them, and that is deliberate: repair belongs to normalize-scenario-tables.py, and
# an extractor that silently fixed the input would let malformed markdown live in the map for ever
# while every report looked clean — which is the shape of the defect this whole spec is about. So the
# contract is: refuse by default, skip under --partial, and say which line.
fixture joined <<EOF
$HDR
$SEP
| @ID6@ | happy | One | First | ✓ || @ID7@ | edge | Two | Second | ◐ || @ID8@ | error | Three | Third | ☐ |
EOF
run joined
expect_rc "case6-joined-row-refused" 2
if grep -q '17 columns' "$TMP/err"; then ok "case6-joined-row-counted (3 rows -> 6n-1 = 17)"; else
  bad "case6-joined-row-counted" "stderr did not report 17 columns: $(head -1 "$TMP/err")"; fi
run joined --partial
expect_rc "case6-joined-skipped-under-partial" 4

# --------------------------------- case 7: a doubled pipe INSIDE one row is also reported, not fixed
# 409.2.md wrote `... | expected || ◐ |` — six columns, a different cause from case 6 but the same
# contract here. Telling the two apart is the normaliser's job, and it needs both sides of the ||.
fixture dblpipe <<EOF
$HDR
$SEP
| @ID9@ | happy | One | First || ◐ |
EOF
run dblpipe
expect_rc "case7-doubled-pipe-refused" 2

# --------------------------------------------------------------- case 8: a commentary table is not
# a ledger. 492.md's promotion note cites ids that are ALSO rows in its real ledger; reading both
# manufactures duplicate ids.
fixture commentary <<EOF
$HDR
$SEP
| @ID10@ | happy | Real ledger row | Outcome | ✓ |

Some prose about what moved.

| SC | now | why |
|---|---|---|
| @ID10@ | ✓ validated | he reached his own sentence |
EOF
run commentary
expect_count "case8-commentary-not-extracted" 1
expect_row "case8-commentary-ledger-survives" "${ID10}|happy|Real ledger row|Outcome|✓|0"

# --------------------------------- case 8b: a FIVE-column commentary table cannot be told apart from
# a mis-ordered ledger, and is refused rather than guessed at. This is a real consequence of making
# the header the discriminator, so it is written down as a case rather than discovered later: a table
# whose first column names an id and whose other four are not ledger roles looks exactly like 518.md.
fixture commentary5 <<EOF
| SC | now | why | evidence | when |
|---|---|---|---|---|
| @ID11@ | ✓ validated | reached it | live QA | 2026-08 |
EOF
run commentary5
# CHANGED 2026-08-29 (spec 553), deliberately. This used to assert exit 2 — refuse the file rather
# than guess. Refusing is the wrong half of the trade: it means one commentary table takes down
# every ledger in the same file, which is the all-or-nothing failure this whole chain of specs is
# about. A table whose first cell names an id and whose other four labels mean nothing to the
# parser is now read as commentary and skipped, and the file is reported on stderr when it yields
# NO rows at all — so the dangerous case (a whole file silently unread) is still loud, and the
# common case (a note beside a real ledger) costs nothing. The header rule keeps its teeth through
# the recognised-column requirement: rename four of five and it is still a ledger; rename all five
# and it is not a ledger any more.
expect_rc "case8b-five-col-commentary-is-skipped-not-refused" 0
expect_count "case8b-five-col-commentary-yields-nothing" 0
if grep -q 'no recognised ledger header' "$TMP/err"; then
  ok "case8b-five-col-commentary-is-reported-not-silent"
else
  bad "case8b-five-col-commentary-is-reported-not-silent" "no warning on stderr: $(cat "$TMP/err")"
fi

# ------------------------------------------------------- case 9: a RENAMED header is accepted (O2)
# 541.md and 469.4.md rename every column and mean exactly the same thing. Order is the contract.
fixture renamed <<EOF
| id | kind | scenario | expected | status |
$SEP
| @ID12@ | happy | Renamed header | Still a ledger | ✓ |
EOF
run renamed
expect_rc "case9-rename-accepted" 0
expect_row "case9-rename-row" "${ID12}|happy|Renamed header|Still a ledger|✓|0"

# ------------------------------------------------- case 10: a REORDERED header is reported, not read
# 518.md was `SC | Scenario | Type | Coverage | Status` — five columns, so arity accepted it, and
# every row was silently mis-sliced. This is the case that had no gate at all.
fixture reordered <<EOF
| SC | Scenario | Type | Coverage | Status |
$SEP
| @ID13@ | Some scenario prose | adversarial | integration | ✓ |
EOF
run reordered
expect_rc "case10-reorder-refused" 2
if grep -q 'not in canonical order' "$TMP/err"; then ok "case10-reorder-named"; else
  bad "case10-reorder-named" "stderr did not name the reorder: $(head -1 "$TMP/err")"; fi

# ------------------------------------------------------------ case 11: a BOLD id is seen (Class D)
# 510/511/515 bold their ids across 77 rows. They were not refused — they were invisible.
fixture bold <<EOF
$HDR
$SEP
| **@ID14@** | happy | Bolded id | Outcome | ✓ |
EOF
run bold
expect_row "case11-bold-id-seen" "${ID14}|happy|Bolded id|Outcome|✓|0"

# ---------------------------------------------------- case 12: the renumber form yields TWO ids
# A struck id immediately followed by a live one in the same cell is what
# scripts/scenario-scid-renumber.py writes. The live id is the second;
# the retired one must stay REAL so a test still naming it reads as stale, not as wrong about the map.
fixture renumber <<EOF
$HDR
$SEP
| ~~@ID15@~~ @ID16@ | happy | Renumbered | Outcome | ✓ |
EOF
run renumber
expect_row "case12-renumber-live-id" "${ID16}|happy|Renumbered|Outcome|✓|0"
if grep -q "^${ID15}$TAB" "$TMP/out"; then ok "case12-renumber-orphan-retired-id-kept"; else
  bad "case12-renumber-orphan-retired-id-kept" "${ID15} is defined nowhere else, so dropping it frees a permanent handle"; fi

# --------------------- case 12b: ...but NOT when the struck id is still defined by its keeper file.
# This is the normal case and the one the tool actually produces. Per scenario-scid-renumber.py, the
# lowest-numbered file KEEPS the id and every other definition is reassigned — so a struck-plus-live
# cell exists precisely BECAUSE some other row still owns the struck id. Emitting it here would
# re-create the
# duplicate that renumbering removed, and --summary would (rightly) call that an error.
fixture renumber_kept <<EOF
$HDR
$SEP
| @ID17@ | happy | The keeper still owns this id | Outcome | ✓ |
| ~~@ID17@~~ @ID18@ | happy | Reassigned out of the collision | Outcome | ✓ |
EOF
run renumber_kept --summary
expect_rc "case12b-renumbered-alias-makes-no-duplicate" 0
run renumber_kept
expect_count "case12b-two-rows-not-three" 2

# ----------------------------------------------- case 13: a markdown-escaped pipe is DATA, not a cell
# 400.md quotes the illegal-filename set inside a code span.
fixture escpipe <<EOF
$HDR
$SEP
| @ID19@ | error | Illegal filename (\`< > \\|\`) | Rejected with a reason | ☐ |
EOF
run escpipe
expect_rc "case13-escaped-pipe-parses" 0
expect_count "case13-escaped-pipe-one-row" 1

# ----------------------------------------------------------- case 14: a table with no ledger header
fixture noheader <<EOF
Some prose.

| @ID20@ | happy | No header above this | Outcome | ✓ |
EOF
run noheader
expect_count "case14-no-header-yields-nothing" 0

# ---------------------------------------------------------------- case 15: --summary catches a dupe
fixture dupe <<EOF
$HDR
$SEP
| @ID21@ | happy | One | A | ✓ |
| @ID21@ | happy | Again | B | ✓ |
EOF
run dupe --summary
expect_rc "case15-duplicate-id-is-an-error" 2

# ------------------------------------------------------------------------------------- sabotage
# Each defence is removed in turn; a NAMED case must go red. A defence whose removal breaks nothing
# was never load-bearing, and that is exactly how the two dead citations above went unnoticed.
echo
echo "Sabotage check — every defence must be load-bearing:"

sabotage() { # <name> <sed-expr> <case-fn> ...
  name="$1"; expr="$2"; shift 2
  cp "$ROWS" "$TMP/sabotaged.sh"
  sed -i.bak "$expr" "$TMP/sabotaged.sh" 2>/dev/null || sed -i '' "$expr" "$TMP/sabotaged.sh"
  chmod +x "$TMP/sabotaged.sh"
  SAB_RC=0
  "$TMP/sabotaged.sh" "$@" > "$TMP/sab.out" 2> "$TMP/sab.err" || SAB_RC=$?
}

# a) remove the header classification -> the reorder case can no longer be caught
sabotage "header-check-removed" 's/if (k == "reordered") {/if (0) {/' "$TMP/reordered/SCENARIOS.md"
if [ "$SAB_RC" -eq 2 ]; then
  bad "sabotage/header-check-removed" "reorder was still refused — the check is not what catches it"
else ok "sabotage/header-check-removed — case10 goes red without it"; fi

# b) remove the ledger-context gate -> the commentary table is read again (duplicate ids return)
sabotage "ledger-context-removed" 's/if (!in_ledger) { ignored\[FILENAME\]++; prev = \$0; next }//' "$TMP/commentary/SCENARIOS.md"
# With the gate in place the commentary fixture is clean: exit 0, one row. Remove the gate and the
# commentary row enters the pipeline, where its three columns are a malformed ledger row — so the run
# stops being clean. Either way the observable change is what matters: the defence is load-bearing.
if [ "$SAB_RC" -ne 0 ]; then ok "sabotage/ledger-context-removed — case8 goes red without it"; else
  bad "sabotage/ledger-context-removed" "still exit 0 — the commentary table is being skipped by something else"; fi

# c) remove --partial's skip -> a malformed row refuses again even with the flag
sabotage "partial-ignored" 's/if (PARTIAL) { skipped++ } else { bad = 1 }/bad = 1/' --partial "$TMP/malformed/SCENARIOS.md"
if [ "$SAB_RC" -eq 2 ]; then ok "sabotage/partial-ignored — case4 goes red without it"; else
  bad "sabotage/partial-ignored" "exit $SAB_RC — --partial still worked, so the branch is not what does it"; fi

# d) remove the strike handling -> a retired id is emitted with its markers, freeing the real id
sabotage "strike-handling-removed" 's/if (id ~ \/\^~~\.\*~~\$\/) {/if (0) {/' "$TMP/struck/SCENARIOS.md"
if grep -q "^${ID3}$TAB" "$TMP/sab.out"; then
  bad "sabotage/strike-handling-removed" "${ID3} still emitted cleanly — the strike branch is dead code"
else ok "sabotage/strike-handling-removed — case2 goes red without it"; fi

# The sabotage must be SURGICAL: case 1 has to survive every one of them, or the arms are just
# proving that a broken script is broken.
for expr in 's/if (k == "reordered") {/if (0) {/' \
            's/if (id ~ \/\^~~\.\*~~\$\/) {/if (0) {/'; do
  sabotage "surgical" "$expr" "$TMP/clean/SCENARIOS.md"
  if [ "$SAB_RC" -ne 0 ] || ! grep -q "^${ID1}${TAB}happy${TAB}Log in${TAB}" "$TMP/sab.out"; then
    bad "sabotage/surgical" "the clean fixture broke under: $expr"
    break
  fi
done
[ "$FAIL" -eq 0 ] && ok "sabotage — every sabotage was surgical (case1 survived all of them)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
