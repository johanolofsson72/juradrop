#!/bin/sh
# test-scenario-map-rows.sh — the parser harness for scenario-map-rows.sh.
#
# WHY THIS EXISTS: scenario-map-rows.sh was the single implementation of cell splitting for the
# whole scenario-map toolchain and it had no test of its own. test-scenario-map-layouts.sh calls
# it, but only to compare one layout against another — both sides run the same parser, so a
# parsing bug cancels out and the comparison stays green. That is precisely how trap 3 survived:
# on 2026-08-28 the traceability gate refused agentcrm's 482-row map over ONE row containing a
# markdown-escaped pipe, and every harness that touched the parser was passing at the time.
#
# WHAT IT ASSERTS, and why each case is here rather than being obvious:
#
#   - the escaped pipe (\|) is a cell's content, not a column break                    [trap 3]
#   - the OUTPUT is TAB-separated and every row still has exactly six fields. This is the half
#     the first attempt at the fix got wrong: it rejoined the cell and kept the pipe escaped,
#     reasoning that \| is not a delimiter. It is one — `cut -d'|'` and `IFS='|' read` see the
#     byte, not the backslash — so the emitted row split into seven, status landed in expected,
#     struck read "✓|0", and the row stopped counting as validated with nothing erroring. The
#     field-count case below is what caught it, one command after the change.
#   - an EVEN run of backslashes before a delimiter is a real column break. This is the case a
#     naive "field ends in a backslash" test gets wrong, and it cannot be found by staring at a
#     map that happens to contain no such row.
#   - a genuinely six-column row is STILL rejected. This is the known positive from trap 4 in
#     .claude/rules/mutation-timeouts.md: a fix that widens a guard must be shown to leave the
#     guard biting, or "no malformed rows" stops distinguishing a clean map from a blind parser.
#   - a retired (~~SC-NNN~~) row keeps its id and reports struck=1                     [trap 1]
#   - prose and flowchart mentions of an id are not rows                               [trap 2]
#
# FIXTURE IDS ARE DERIVED, NEVER WRITTEN (register row H7bd). Every id below comes from
# scenario-probe-ids.sh, which hands back ids no row in the project's real map owns, and the fixture
# bodies carry @IDn@ placeholders substituted on the way to disk. Spelling a real id here instead
# would be shorter and would be a false binding: the id-accounting gate scans scripts/, cannot tell a
# fixture from an assertion, and counts a probe map about column parsing as proof that the real
# scenario is tested. Measured in consultpilot — the id in the "prose is not a row" fixture below was
# the ONLY reference to a real ✓ scenario in that entire tree, so the gate reported it traced on the
# strength of a sentence written to prove sentences do not count. Do not "simplify" these back to
# literals; scenario-probe-ids.sh's header has the two alternatives and why neither works here.
#
# Run:  bash scripts/test-scenario-map-rows.sh
# Exit: 0 all cases pass · 1 one or more failed

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROWS="$SCRIPT_DIR/scenario-map-rows.sh"
FAILED=0

# shellcheck source=scripts/scenario-probe-ids.sh
. "$SCRIPT_DIR/scenario-probe-ids.sh"

# The project's map, if it has one. The template ships none, and that is a legitimate state rather
# than a broken one: with no map every id is free, which is exactly right for a tree that owns no
# scenarios. Resolved without scenario-map-layout.sh on purpose — a per-feature file cannot allocate
# an id the index does not also list, so the index alone is a sufficient owned set here, and this
# harness has no other reason to know what a layout is.
PROBE_MAP=$(git rev-parse --show-toplevel 2>/dev/null)/specs/SCENARIOS.md

PROBE_IDS=$(scenario_probe_checked 18 test-scenario-map-rows "$PROBE_MAP") || exit 1

# shellcheck disable=SC2086
set -- $PROBE_IDS
ID1=$1; ID2=$2; ID3=$3; ID4=$4; ID5=$5; ID6=$6; ID7=$7; ID8=$8; ID9=$9
# ${10} and up are not addressable in POSIX sh, so shift the first nine off rather than reaching
# for them. `$10` parses as `$1` followed by a literal 0, which would silently reuse ID1.
shift 9
ID10=$1; ID11=$2; ID12=$3; ID13=$4; ID14=$5; ID15=$6; ID16=$7; ID17=$8; ID18=$9
SUBST=$(scenario_probe_sed_script "$ID1" "$ID2" "$ID3" "$ID4" "$ID5" "$ID6" "$ID7" "$ID8" "$ID9" \
                                  "$ID10" "$ID11" "$ID12" "$ID13" "$ID14" "$ID15" "$ID16" "$ID17" "$ID18")

ok()  { printf '  ok:   %s\n' "$1"; }
bad() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t scenrows)
trap 'rm -rf "$TMP"' EXIT INT TERM

TAB=$(printf '\t')

# expect_row <label> <map-file> <id> <expected full output line>
expect_row() {
  _label=$1; _file=$2; _id=$3; _want=$4
  _got=$(sh "$ROWS" "$_file" 2>/dev/null | grep "^$_id$TAB")
  if [ "$_got" = "$_want" ]; then ok "$_label"
  else bad "$_label" "got [$_got] want [$_want]"
  fi
}

printf '== scenario-map-rows: cell splitting ==\n'

# --- trap 3: the escaped pipe ---------------------------------------------------------
sed "$SUBST" > "$TMP/escaped.md" <<'MAP'
| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| @ID1@ | adversarial | A note beginning `=cmd\|` shown in the preview | Rendered as text, never as a formula | ✓ |
| @ID2@ | happy | A plain row with no pipes at all | Extracted unchanged | ✓ |
| @ID3@ | edge | Two \| escaped \| pipes in one cell | Still one cell | ◐ |
| ~~@ID4@~~ | happy | A retired row | Its id stays reserved | ☐ |
MAP

expect_row 'escaped pipe is content, not a column break' "$TMP/escaped.md" "$ID1" \
  "${ID1}${TAB}adversarial${TAB}A note beginning \`=cmd\\|\` shown in the preview${TAB}Rendered as text, never as a formula${TAB}✓${TAB}0"
expect_row 'a row with no pipes is untouched' "$TMP/escaped.md" "$ID2" \
  "${ID2}${TAB}happy${TAB}A plain row with no pipes at all${TAB}Extracted unchanged${TAB}✓${TAB}0"
expect_row 'two escaped pipes in one cell' "$TMP/escaped.md" "$ID3" \
  "${ID3}${TAB}edge${TAB}Two \\| escaped \\| pipes in one cell${TAB}Still one cell${TAB}◐${TAB}0"
expect_row 'a retired row keeps its id and reports struck' "$TMP/escaped.md" "$ID4" \
  "${ID4}${TAB}happy${TAB}A retired row${TAB}Its id stays reserved${TAB}☐${TAB}1"

if sh "$ROWS" "$TMP/escaped.md" >/dev/null 2>&1; then
  ok 'a map whose only pipes are escaped exits 0'
else
  bad 'a map whose only pipes are escaped exits 0' "exit $?"
fi

# The output contract, asserted on the rows most able to break it. validate-scenario-traceability.sh
# refuses the whole run when any row is not six fields, and this is the case that caught the first
# fix keeping a pipe in the emitted cell: four rows out, one of them seven fields long.
_wrongwidth=$(sh "$ROWS" "$TMP/escaped.md" 2>/dev/null | awk -F'\t' 'NF != 6 { c++ } END { print c+0 }')
if [ "$_wrongwidth" = "0" ]; then
  ok 'every emitted row is exactly six tab-separated fields'
else
  bad 'every emitted row is exactly six tab-separated fields' "$_wrongwidth row(s) split wrong"
fi

# --- the even-backslash case ----------------------------------------------------------
# `\\` is a literal backslash in markdown; the pipe after it IS a column break. A parser that
# tests only "ends in a backslash" swallows that break and reports four columns.
sed "$SUBST" > "$TMP/evenslash.md" <<'MAP'
| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| @ID5@ | edge | Ends in a literal backslash \\ | Still five columns | ✓ |
MAP
expect_row 'an even backslash run leaves the column break alone' "$TMP/evenslash.md" "$ID5" \
  "${ID5}${TAB}edge${TAB}Ends in a literal backslash \\\\${TAB}Still five columns${TAB}✓${TAB}0"

# --- the known positive: the guard must still bite ------------------------------------
sed "$SUBST" > "$TMP/malformed.md" <<'MAP'
| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| @ID6@ | edge | A genuinely six-column row | With one cell too many | ✓ | oops |
MAP
_err=$(sh "$ROWS" "$TMP/malformed.md" 2>&1 >/dev/null)
_rc=$?
# `case`, not `printf | grep -q`: grep -q exits at the first match and the printf ahead of it
# then dies of SIGPIPE, which under pipefail is 141 — a true claim read as false. See
# validate-no-sigpipe-assertions.sh, which refuses that shape in this directory.
case "$_err" in *'has 6 columns, expected 5'*) _named=1 ;; *) _named=0 ;; esac
if [ "$_rc" -eq 2 ] && [ "$_named" -eq 1 ]; then
  ok 'a real six-column row is still rejected with exit 2'
else
  bad 'a real six-column row is still rejected with exit 2' "rc=$_rc err=[$_err]"
fi

# --- trap 2: only table rows count ----------------------------------------------------
sed "$SUBST" > "$TMP/prose.md" <<'MAP'
Some prose that mentions @ID7@ without being a row, and a flowchart node @ID8@.

| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| @ID9@ | happy | The only actual row | Counted once | ✓ |
MAP
_ids=$(sh "$ROWS" "$TMP/prose.md" 2>/dev/null | cut -d"$TAB" -f1 | tr '\n' ' ')
if [ "$_ids" = "$ID9 " ]; then
  ok 'prose and flowchart mentions are not rows'
else
  bad 'prose and flowchart mentions are not rows' "extracted [$_ids]"
fi

# --- --summary agrees with the rows it counted ----------------------------------------
_total=$(sh "$ROWS" --summary "$TMP/escaped.md" 2>/dev/null | awk '/^rows:/ { print $2 }')
if [ "$_total" = "4" ]; then
  ok '--summary counts the escaped-pipe rows it can now parse'
else
  bad '--summary counts the escaped-pipe rows it can now parse' "rows: $_total, want 4"
fi

printf '\n== scenario-map-rows: the ledger-header rule ==\n'

# --- a commentary table is not a ledger, and the real ledger below it still reads ------
#
# This is the case the whole header rule exists for. 492.md carries a promotion note whose rows
# cite ids that are ALSO rows in its real ledger further down the file, and 511.md carries two
# evidence summaries. Judged on arity they refuse the entire map; judged on arity when the arity
# happens to fit, they manufacture duplicate ids. Neither table was ever malformed.
sed "$SUBST" > "$TMP/commentary.md" <<'MAP'
Operator validated the following on the live build:

| SC | now | why |
|---|---|---|
| @ID10@ | ✓ validated | he reached his own sentence and edited it |

| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| @ID10@ | happy | The real ledger row | Counted once | ◐ |
MAP
_out=$(sh "$ROWS" "$TMP/commentary.md" 2>"$TMP/commentary.err"); _rc=$?
_n=$(printf '%s\n' "$_out" | grep -c "^$ID10$TAB" || true)
_kind=$(printf '%s\n' "$_out" | awk -F'\t' -v id="$ID10" '$1 == id { print $2 }')
if [ "$_rc" -eq 0 ] && [ "$_n" = "1" ] && [ "$_kind" = "happy" ]; then
  ok 'a commentary table is skipped and the ledger below it is read'
else
  bad 'a commentary table is skipped and the ledger below it is read' \
      "rc=$_rc rows=$_n kind=[$_kind] err=[$(cat "$TMP/commentary.err")]"
fi

# --- SABOTAGE: remove the ledger-context guard, and the same file breaks ---------------
#
# The arm is the argument for the case. Without it "one row, kind=happy" is a sentence that would
# also be true of a parser that reads every table row and got lucky.
sed 's/if (!in_ledger) { ignored\[FILENAME\]++; prev = \$0; next }/if (0) { }/' \
    "$ROWS" > "$TMP/sabotaged-context.sh"
_sab=$(sh "$TMP/sabotaged-context.sh" "$TMP/commentary.md" 2>&1); _sabrc=$?
if [ "$_sabrc" -ne 0 ] || [ "$(printf '%s\n' "$_sab" | grep -c "^$ID10$TAB" || true)" != "1" ]; then
  ok 'SABOTAGE: without the ledger-context guard, the commentary file no longer reads correctly'
else
  bad 'SABOTAGE: without the ledger-context guard, the commentary file no longer reads correctly' \
      "the guard is not carrying this case — rc=$_sabrc"
fi

# --- a REORDERED ledger header is an error, not a silent mis-slice ---------------------
#
# 518.md was written this way for months. Five columns, so arity accepted it; every row was parsed
# positionally into the wrong fields and its status landed in column five by luck, so nothing
# anywhere went red. Column ORDER is the contract.
sed "$SUBST" > "$TMP/reordered.md" <<'MAP'
| SC | Scenario | Type | Coverage | Status |
|---|---|---|---|---|
| @ID11@ | the scenario prose | adversarial | FC-001 | ✓ |
MAP
_err=$(sh "$ROWS" "$TMP/reordered.md" 2>&1 >/dev/null); _rc=$?
case "$_rc:$_err" in
  2:*canonical\ order*) ok 'a reordered ledger header is reported, not silently mis-sliced' ;;
  *) bad 'a reordered ledger header is reported, not silently mis-sliced' "rc=$_rc err=[$_err]" ;;
esac

# --- a RENAMED but correctly-ordered header is accepted --------------------------------
#
# The other half of the same rule, and the half a first draft got wrong: it enumerated acceptable
# column labels and condemned four real fixtures whose headers said "flow" and "st". Accepting a
# rename while rejecting a reorder is the point; refusing both is just a stricter kind of broken.
sed "$SUBST" > "$TMP/renamed.md" <<'MAP'
| id | type | flow | expected | st |
|---|---|---|---|---|
| @ID12@ | edge | Columns renamed, order kept | Still a ledger | ✓ |
MAP
expect_row 'a renamed but correctly-ordered header is still a ledger' "$TMP/renamed.md" "$ID12" \
  "${ID12}${TAB}edge${TAB}Columns renamed, order kept${TAB}Still a ledger${TAB}✓${TAB}0"

# --- five unknown column names is NOT a ledger -----------------------------------------
#
# The cost of permitting renames, bounded. A table whose first cell is an id and whose other four
# labels mean nothing to this script is a commentary table, not a ledger that renamed everything.
sed "$SUBST" > "$TMP/allunknown.md" <<'MAP'
| SC | now | why | evidence | note |
|---|---|---|---|---|
| @ID13@ | ✓ validated | operator saw it | a screenshot | — |
MAP
_out=$(sh "$ROWS" "$TMP/allunknown.md" 2>/dev/null || true)
if [ -z "$(printf '%s' "$_out" | tr -d '[:space:]')" ]; then
  ok 'a five-column table with no recognised column name is not a ledger'
else
  bad 'a five-column table with no recognised column name is not a ledger' "extracted [$_out]"
fi

printf '\n== scenario-map-rows: decorated ids ==\n'

# --- a bolded id is a row, not an invisible one ----------------------------------------
#
# 77 rows across three files were written `| **SC-nnnn** |`. They were not refused, they were
# INVISIBLE — worse, because a refusal is loud: their ✓ claims were never checked and a test naming
# one was reported dangling, since the map appeared not to have it.
sed "$SUBST" > "$TMP/bold.md" <<'MAP'
| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| **@ID14@** | happy | A bolded id | Emitted undecorated | ✓ |
MAP
expect_row 'a bolded id is parsed and emitted undecorated' "$TMP/bold.md" "$ID14" \
  "${ID14}${TAB}happy${TAB}A bolded id${TAB}Emitted undecorated${TAB}✓${TAB}0"

# --- the renumber form: the LIVE id is the second one ----------------------------------
#
# scenario-scid-renumber.py writes `~~SC-a~~ SC-b` and hundreds of rows carry it. Nothing parsed it,
# so the whole cell became the id: a test naming SC-b read as dangling, and the row status was
# attributed to an id that does not exist.
sed "$SUBST" > "$TMP/renumber.md" <<'MAP'
| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| ~~@ID15@~~ @ID16@ | happy | A renumbered row | The live id is the second | ◐ |
MAP
expect_row 'the renumber form emits the LIVE id as the row' "$TMP/renumber.md" "$ID16" \
  "${ID16}${TAB}happy${TAB}A renumbered row${TAB}The live id is the second${TAB}◐${TAB}0"
_alias=$(sh "$ROWS" "$TMP/renumber.md" 2>/dev/null | awk -F'\t' -v id="$ID15" '$1 == id { print $2 "/" $6 }')
if [ "$_alias" = "retired/1" ]; then
  ok 'a struck id with no keeper survives as its own retired row'
else
  bad 'a struck id with no keeper survives as its own retired row' "got [$_alias] want [retired/1]"
fi

# --- ...but NOT when the keeper exists --------------------------------------------------
#
# Read scenario-scid-renumber.py before touching this. `~~SC-a~~ SC-b` does not mean "SC-a retired
# here"; it means SC-a was defined twice, the lowest-numbered file KEEPS it, and this definition was
# reassigned. Emitting the struck id unconditionally re-creates the very duplicates that tool exists
# to remove — measured at 103 of them on one real map.
sed "$SUBST" > "$TMP/renumber-keeper.md" <<'MAP'
| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| @ID15@ | happy | The keeper still owns this id | Not re-emitted as retired | ✓ |
| ~~@ID15@~~ @ID16@ | happy | A renumbered row | The live id is the second | ◐ |
MAP
_rows=$(sh "$ROWS" "$TMP/renumber-keeper.md" 2>/dev/null | awk -F'\t' -v id="$ID15" '$1 == id')
_n=$(printf '%s\n' "$_rows" | grep -c . || true)
_struck=$(printf '%s\n' "$_rows" | awk -F'\t' '{ print $6 }')
if [ "$_n" = "1" ] && [ "$_struck" = "0" ]; then
  ok 'the alias row is dropped when the struck id has a keeper'
else
  bad 'the alias row is dropped when the struck id has a keeper' "rows=$_n struck=[$_struck]"
fi

printf '\n== scenario-map-rows: --partial, and silence ==\n'

# --- --partial emits what it can AND says it skipped something -------------------------
#
# Exit 4 is the state this flag exists to make sayable. Reporting it as 0 would be "clean over what
# I could read, reported as clean" — the defect. Reporting it as a refusal is the all-or-nothing
# behaviour it replaced. It has to be its own answer.
sed "$SUBST" > "$TMP/partial.md" <<'MAP'
| SC | Type | Scenario | Expected outcome | Status |
|---|---|---|---|---|
| @ID17@ | happy | A good row | Emitted | ✓ |
| @ID18@ | happy | A row missing a column | Skipped |
MAP
_out=$(sh "$ROWS" --partial "$TMP/partial.md" 2>"$TMP/partial.err"); _rc=$?
_n=$(printf '%s\n' "$_out" | grep -c . || true)
if [ "$_rc" -eq 4 ] && [ "$_n" = "1" ] && grep -q 'skipped 1 malformed row' "$TMP/partial.err"; then
  ok '--partial emits the good rows, reports the bad one, and exits 4'
else
  bad '--partial emits the good rows, reports the bad one, and exits 4' \
      "rc=$_rc rows=$_n err=[$(cat "$TMP/partial.err")]"
fi

# --- without --partial the same file is refused whole ----------------------------------
_out=$(sh "$ROWS" "$TMP/partial.md" 2>/dev/null); _rc=$?
if [ "$_rc" -eq 2 ]; then
  ok 'without --partial the same file is still refused whole (the harness needs that)'
else
  bad 'without --partial the same file is still refused whole (the harness needs that)' "rc=$_rc"
fi

# --- SABOTAGE: an exit-4 that kills the script at the assignment ------------------------
#
# Under `set -e` a bare `RAW=$(awk ...)` whose command substitution exits non-zero kills the script
# AT THE ASSIGNMENT, so --partial would report "rows emitted, rows skipped" and emit nothing. That
# is not hypothetical; it is what the first implementation did, and only a harness found it.
sed 's/RAW=$(awk -v PARTIAL="$PARTIAL" "$EXTRACT" "$@") || RC=$?/RAW=$(awk -v PARTIAL="$PARTIAL" "$EXTRACT" "$@")/' \
    "$ROWS" > "$TMP/sabotaged-setE.sh"
_sab=$(sh "$TMP/sabotaged-setE.sh" --partial "$TMP/partial.md" 2>/dev/null || true)
if [ -z "$(printf '%s' "$_sab" | tr -d '[:space:]')" ]; then
  ok 'SABOTAGE: without the || RC=$? capture, --partial emits nothing at all'
else
  bad 'SABOTAGE: without the || RC=$? capture, --partial emits nothing at all' "still emitted [$_sab]"
fi

# --- a file the header rule reads as ALL commentary says so out loud -------------------
#
# Requiring a header is right. "Wrong header, therefore silence" is the failure that cost a year:
# an invisible row is worse than a refused one, because a refusal is loud. This does not fail the
# run — a file may legitimately cite ids and carry no ledger — it says the whole file went unread.
sed "$SUBST" > "$TMP/headerless.md" <<'MAP'
| @ID17@ | happy | A ledger row with no header above it | Nothing reads this | ✓ |
| @ID18@ | happy | Nor this | Silently | ◐ |
MAP
_out=$(sh "$ROWS" "$TMP/headerless.md" 2>"$TMP/headerless.err" || true)
if [ -z "$(printf '%s' "$_out" | tr -d '[:space:]')" ] \
   && grep -q 'no recognised ledger header' "$TMP/headerless.err"; then
  ok 'a file with rows but no ledger header is reported, not silently empty'
else
  bad 'a file with rows but no ledger header is reported, not silently empty' \
      "out=[$_out] err=[$(cat "$TMP/headerless.err")]"
fi

printf '\n'
# ---------------------------------------------------- comment inside a ledger
# .claude/rules/scenarios.md shows comments inside a map in its own example, and
# this project uses them to record why a row carries the status it does. Treating
# one as "the table ended here" dropped every row after it, in silence: measured
# on consultpilot 2026-09-03 a five-line note cost 12 rows, and all 18 of that
# gate's dangling findings were this rather than one real one.
CT=$(mktemp -d)
{
  echo "# Scenario map"; echo
  echo "## Actor: X"; echo
  echo "### Feature: thing   (spec: 001-thing)"; echo
  echo "| ID     | Type  | Scenario   | Expected outcome | Status |"
  echo "|--------|-------|------------|------------------|--------|"
  echo "| SC-001 | happy | before     | it works         | ✓      |"
  echo "<!-- a one-line note about the row above -->"
  echo "| SC-002 | happy | after one  | it works         | ✓      |"
  echo "<!-- a note that spans"
  echo "     more than one line, which is"
  echo "     how the real map writes them -->"
  echo "| SC-003 | happy | after many | it works         | ✓      |"
} > "$CT/map.md"
N=$("$SCRIPT_DIR/scenario-map-rows.sh" --partial "$CT/map.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$N" = "3" ]; then
  ok "a comment inside a ledger does not end the table"
else
  bad "a comment inside a ledger ended the table" "got $N rows, want 3"
fi
# and the ids must be the right three, not any three
IDS=$("$SCRIPT_DIR/scenario-map-rows.sh" --partial "$CT/map.md" 2>/dev/null | cut -f1 | tr '\n' ' ')
[ "$IDS" = "SC-001 SC-002 SC-003 " ] \
  && ok "the rows after a comment are the rows that follow it" \
  || bad "the rows after a comment" "wrong ids: $IDS"
rm -rf "$CT"

if [ "$FAILED" -eq 0 ]; then
  printf 'scenario-map-rows: all cases pass\n'
  exit 0
fi
printf 'scenario-map-rows: %d case(s) failed\n' "$FAILED"
exit 1
