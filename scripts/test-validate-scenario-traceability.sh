#!/bin/bash
# test-validate-scenario-traceability.sh — harness for scripts/validate-scenario-traceability.sh.
#
# WHY THIS EXISTS: the gate it tests was, for months, a name in four comments and nothing else —
# cited as a tool that "reported 100% and exit 0 the whole time" while no such file had ever been
# written. A gate that is only described is worse than no gate, because the description is quoted as
# evidence. So the gate built by spec 007bs ships with a harness that has been watched failing.
#
# It runs the gate against generated fixtures in a temp dir — never against the repo's real specs/ —
# and it checks its own teeth: the final step sabotages a COPY of the gate, one marked region at a
# time, and requires the named cases to go red. A gate nobody has watched fail is a report, not a
# gate — the H5b lesson, restated by H5g, where a harness sat green and unrun for months. (That
# sentence is quoted from the sibling harness with its id removed; the id is exactly what must not
# appear here.)
#
# ------------------------------------------------------------------------------------------------
# THE LITERAL ID TOKEN DOES NOT APPEAR IN THIS FILE. Fixture ids are composed at runtime from $P.
#
# The sibling harness (test-archive-spec-history.sh:55) solves the same problem by prefixing its
# fixture ids `ID-`, because a real id written into a file under scripts/ would be picked up as a
# reference and would bind a real scenario to a fixture that never exercises it — the false-binding
# trap H5c and H5g each spent a row unpicking.
#
# That trick is unavailable here: scenario-map-rows.sh hardcodes the real prefix in its row pattern,
# so a fixture row using any other prefix extracts to NOTHING and every case below would be quietly
# testing an empty map. Verified 2026-08-28 — a fixture holding one row of each yields only the
# real-prefixed one, silently, exit 0.
#
# So this file goes one better: the ids are built by concatenation at runtime, which removes the
# literal token from the source altogether rather than choosing a prefix nothing matches. Case 15
# greps this file for the literal and fails if it finds one, so the property cannot rot. Do not
# "tidy" the concatenation back into literals.
# ------------------------------------------------------------------------------------------------
#
# Usage:
#   bash scripts/test-validate-scenario-traceability.sh              # test the shipped script
#   bash scripts/test-validate-scenario-traceability.sh --script X   # test some other copy
#   bash scripts/test-validate-scenario-traceability.sh --no-sabotage
#
# Exit: 0 all cases passed · 1 one or more failed · 2 a case could not be run (inconclusive).
#
# INCONCLUSIVE IS NOT PASS. Case 14 needs a Swedish UTF-8 locale to exist on the host. Where it does
# not, the case reports itself by name and this harness exits 2 — the 007br precedent: a precondition
# nobody can meet is a third state, and collapsing it into PASS is exactly how a gate becomes
# decorative.

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/scripts/validate-scenario-traceability.sh"
RUN_SABOTAGE=1
SKIP_CORE_CENSUS=0   # a FLAG, never an environment variable: an exported one would switch case40 off invisibly

while [ $# -gt 0 ]; do
  case "$1" in
    --script) SCRIPT="$2"; shift 2 ;;
    --no-sabotage) RUN_SABOTAGE=0; shift ;;
    --skip-core-census) SKIP_CORE_CENSUS=1; shift ;;   # internal: sab_run only, see there
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -f "$SCRIPT" ] || { echo "script under test not found: $SCRIPT" >&2; exit 2; }

PASS=0; FAIL=0; INCONCL=0; FAILED_CASES=""
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_CASES="$FAILED_CASES $1"; printf '  FAIL  %s — %s\n' "$1" "$2"; }
skip() { INCONCL=$((INCONCL+1)); printf '  INCONCLUSIVE  %s — %s\n' "$1" "$2"; }

# The prefix, never written as part of an id literal. See the header.
P="SC"
V='✓'   # validated
T='◐'   # tested
M='☐'   # mapped, not yet tested

id() { printf '%s-%s' "$P" "$1"; }

# ---------------------------------------------------------------- fixtures --

new_project() { # → echoes a project root with specs/ and tests/ under it
  d=$(mktemp -d)
  mkdir -p "$d/specs" "$d/tests"
  echo "$d"
}

map_header() {
  printf '# Scenario map\n\n## Actor: Someone\n\n### Feature: Something   (spec: 001-something)\n\n'
  printf '| ID     | Type  | Scenario        | Expected outcome | Status |\n'
  printf '|--------|-------|-----------------|------------------|--------|\n'
}

# row <num> <status> [struck]
row() {
  if [ "${3:-}" = "struck" ]; then
    printf '| ~~%s~~ | happy | A thing happens | It works | %s |\n' "$(id "$1")" "$2"
  else
    printf '| %s | happy | A thing happens | It works | %s |\n' "$(id "$1")" "$2"
  fi
}

# write_test <project> <name> <num>...
write_test() {
  proj="$1"; name="$2"; shift 2
  {
    printf 'test file %s\n' "$name"
    for n in "$@"; do printf 'it covers %s\n' "$(id "$n")"; done
  } > "$proj/tests/$name"
}

# anchor <project> — a second validated row, 902, and a test citing it. A fixture whose whole suite
# names no id at all is what the zero-refs guard refuses (case41), so a case that proves one token is
# NOT a reference needs one real reference beside it, or it would be testing the refusal instead.
anchor() {
  row 902 "$V" >> "$1/specs/SCENARIOS.md"
  write_test "$1" "anchor.test.ts" 902
}

# Run the gate; capture output and exit code without tripping anything.
run_gate() { # <project> [extra args...]
  proj="$1"; shift
  OUT=$(bash "$SCRIPT" --dir "$proj/specs" "$@" 2>&1)
  RC=$?
  return 0
}

echo "Testing: $SCRIPT"
echo

# -------------------------------------------------------------------- cases --

# case1 — a clean map: every claimed row is referenced, nothing dangles.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$T"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 902
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case1-clean"; else bad "case1-clean" "expected exit 0, got $RC: $OUT"; fi

# case2 — a validated row nothing references. The gate's primary job.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 902)" <<< "$OUT" && grep -q 'uncovered' <<< "$OUT"; then
  ok "case2-uncovered-validated"
else
  bad "case2-uncovered-validated" "expected exit 1 naming the id under uncovered, got $RC: $OUT"
fi

# case3 — a test naming an id the map does not have.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 907
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q 'dangling' <<< "$OUT" && grep -q "$(id 907)" <<< "$OUT"; then
  ok "case3-dangling"
else
  bad "case3-dangling" "expected exit 1 naming the id under dangling, got $RC: $OUT"
fi

# case4 — both directions at once; both sections must appear.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 907
run_gate "$proj"
if [ "$RC" -eq 1 ] \
   && grep -q 'uncovered' <<< "$OUT" && grep -q "$(id 902)" <<< "$OUT" \
   && grep -q 'dangling' <<< "$OUT"  && grep -q "$(id 907)" <<< "$OUT"; then
  ok "case4-both-directions"
else
  bad "case4-both-directions" "expected both sections populated, got $RC: $OUT"
fi

# case5 — a mapped-but-untested row with no test is EXEMPT. This is the case that keeps the gate
# usable on a project with a roadmap; without it the gate is permanently red and gets switched off.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$M"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case5-mapped-exempt"; else bad "case5-mapped-exempt" "expected exit 0, got $RC: $OUT"; fi

# case6 — a retired row with no test is exempt. Nothing is expected to test a retired scenario.
proj=$(new_project)
{ map_header; row 901 "$V"; row 903 "$V" struck; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case6-struck-exempt"; else bad "case6-struck-exempt" "expected exit 0, got $RC: $OUT"; fi

# case7 — a validated row carrying a footnote marker is still a claim. Classification is by
# containment for exactly this reason; an enumerated list of exact statuses would exempt it silently.
proj=$(new_project)
{ map_header; row 901 "$V"; printf '| %s | happy | A thing happens | It works | %s * |\n' "$(id 902)" "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 902)" <<< "$OUT"; then
  ok "case7-footnoted-validated-is-claimed"
else
  bad "case7-footnoted-validated-is-claimed" "expected the footnoted row to be uncovered, got $RC: $OUT"
fi

# case8 — a test still naming a RETIRED id is not dangling. The id is a permanent handle; reporting
# it would push the developer toward deleting a reference to a reserved name.
proj=$(new_project)
{ map_header; row 901 "$V"; row 903 "$V" struck; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 903
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case8-struck-reference-not-dangling"; else bad "case8-struck-reference-not-dangling" "expected exit 0, got $RC: $OUT"; fi

# case9 — a configured reference root that does not exist. Zero references would render as "every
# claimed scenario is uncovered": a catastrophic report with a trivial cause.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
run_gate "$proj" --roots nosuchdir
if [ "$RC" -eq 4 ] && grep -q 'nosuchdir' <<< "$OUT"; then
  ok "case9-missing-root"
else
  bad "case9-missing-root" "expected exit 4 naming the root, got $RC: $OUT"
fi

# case10 — the map file is absent. That is NOT APPLICABLE (7), not "could not be
# read" (3). A project that has never owned scenarios is a legitimate state —
# ighweld ships three specs and no map — and giving it the same code as a corrupt
# map forces every caller to treat one of the two wrongly. case11 below keeps 3
# for the map that EXISTS and yields nothing, which is the real defect.
proj=$(new_project)
run_gate "$proj"
if [ "$RC" -eq 7 ]; then ok "case10-absent-map"; else bad "case10-absent-map" "expected exit 7, got $RC: $OUT"; fi
case "$OUT" in *"NOT APPLICABLE"*) ok "case10-absent-map says not-applicable, not broken" ;;
               *) bad "case10-absent-map wording" "no NOT APPLICABLE in: $OUT" ;; esac

# case11 — a map with no rows. "0 of 0, all clear" is arithmetically clean and semantically empty;
# reporting it as success is the failure this whole script is named after.
proj=$(new_project)
printf '# Scenario map\n\nNo rows yet.\n' > "$proj/specs/SCENARIOS.md"
run_gate "$proj"
if [ "$RC" -eq 3 ]; then ok "case11-zero-rows-is-not-a-pass"; else bad "case11-zero-rows-is-not-a-pass" "expected exit 3, got $RC: $OUT"; fi

# case12 — usage error is its own code, so a test asserting a refusal cannot pass because the script
# died of something unrelated.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
run_gate "$proj" --not-a-flag
if [ "$RC" -eq 2 ]; then ok "case12-usage-error"; else bad "case12-usage-error" "expected exit 2, got $RC: $OUT"; fi

# case13 — the split layout classifies identically to the single-file one. Same rows, different
# shape; the answer must not depend on where the rows live.
proj=$(new_project)
mkdir -p "$proj/specs/scenarios"
{ map_header; } > "$proj/specs/SCENARIOS.md"
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/scenarios/001-feature.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q 'split' <<< "$OUT" && grep -q "$(id 902)" <<< "$OUT"; then
  ok "case13-split-layout"
else
  bad "case13-split-layout" "expected the split layout to report the same uncovered id, got $RC: $OUT"
fi

# case14 — THE LOCALE CASE. The point of this harness.
#
# macOS awk's string equality goes through the locale's collation table, and under a Swedish UTF-8
# locale the validated / tested / mapped symbols all compare EQUAL. A gate that classified with
# `awk ==` would therefore count every row as claimed, compute coverage over a denominator the map
# does not support, and report a clean run over a live gap — which is precisely the sentence
# ("100% and exit 0 the whole time") this gate was built to retire.
#
# So the gate must be immune under the locale the developer actually runs, not only under the one it
# pins for itself. The oracle is grep -c, which is byte-oriented and unaffected.
SVLOC=$(locale -a 2>/dev/null | grep -ix 'sv_SE.UTF-8' | head -1)
if [ -z "$SVLOC" ]; then
  skip "case14-locale-immunity" "no Swedish UTF-8 locale on this host — the immunity is untested here, which is not the same as proven"
else
  proj=$(new_project)
  { map_header; row 901 "$V"; row 902 "$T"; row 903 "$M"; row 904 "$V"; } > "$proj/specs/SCENARIOS.md"
  write_test "$proj" "a.test.ts" 901 902 904

  # The assertion is on the COVERAGE DENOMINATOR, not on the per-status tallies printed beside it.
  # Those tallies are counted with grep, which is byte-oriented and would survive a broken
  # classification untouched — an earlier draft of this case asserted on them and stayed green
  # through the sabotage that removes both defences, i.e. it tested grep rather than the gate.
  # The denominator is `is_claimed` counting rows, and it is the number the trap actually corrupts:
  # correct is 3 of 3 (the mapped row exempt); with the symbols collapsed it becomes 3 of 4.
  # The oracle splits on TAB because that is what the extractor emits — see the OUTPUT block in
  # scenario-map-rows.sh. It was "|" until 2026-08-28, and when the delimiter moved this oracle
  # returned 0 while the gate returned the right answer: the case went red naming the gate, which
  # is the honest failure mode for a harness that pins a format it does not own.
  ORACLE_TAB=$(printf '\t')
  rows_out=$("$REPO_ROOT/scripts/scenario-map-rows.sh" "$proj/specs/SCENARIOS.md")
  o_claimed=$(printf '%s\n' "$rows_out" | grep -cE "$ORACLE_TAB($V|$T)${ORACLE_TAB}0$")

  # LC_ALL is unset deliberately: with it set, the caller's environment would mask whether the gate
  # pins the locale itself, and the case would pass for the wrong reason.
  OUT=$(env -u LC_ALL LANG="$SVLOC" bash "$SCRIPT" --dir "$proj/specs" --quiet 2>&1)
  RC=$?
  g_claimed=$(printf '%s\n' "$OUT" | sed -n 's/^coverage: [0-9]* of \([0-9]*\) .*/\1/p')

  if [ "$g_claimed" = "$o_claimed" ] && [ "$RC" -eq 0 ]; then
    ok "case14-locale-immunity (denominator $o_claimed under $SVLOC)"
  else
    bad "case14-locale-immunity" "under $SVLOC the gate claimed ${g_claimed:-?} rows (exit $RC), oracle says $o_claimed — the status distinction collapsed"
  fi
fi

# case17 — one id on two rows. .claude/rules/scenarios.md makes an id a permanent handle, so this
# is two scenarios wearing one name — and it is the shape that hid in agentcrm for two specs: a
# 104-id block allocated twice by two developers working in parallel. Both rows are referenced by
# the test below, so uncovered and dangling are both empty and every other check here says clean.
# That is the point of the case: the gate must be red for a reason none of its other answers see.
proj=$(new_project)
{ map_header
  printf '| %s | happy | The first meaning | It works | %s |\n' "$(id 917)" "$V"
  printf '| %s | happy | A different scenario entirely | It also works | %s |\n' "$(id 917)" "$V"
} > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 917
run_gate "$proj"
# Exit 6, not 1: a duplicate id breaks the handle every consumer resolves, where an uncovered row
# is a backlog that is red on any project with a roadmap. They shared `exit 1` and the collision was
# therefore invisible behind a permanent red — row 007.
if [ "$RC" -eq 6 ] && grep -q 'duplicate' <<< "$OUT" && grep -q "$(id 917)" <<< "$OUT"; then
  ok "case17-duplicate-id"
else
  bad "case17-duplicate-id" "expected exit 6 naming the id under duplicate, got $RC: $OUT"
fi

# case16 — an EMPTY cell, which is the trap the tab delimiter brought with it. A tab is IFS
# whitespace, so `IFS=<tab> read -r a b c d e f` collapses the empty Type cell below and shifts
# every field after it: status would be read as "0" and the row would quietly stop counting as
# claimed, i.e. the gate would report clean over exactly the gap it exists to find. awk sees six
# fields on the same line and the field-count guard stays green, so nothing else here catches it.
# The row is validated and referenced by nothing, so a gate reading status correctly says exit 1.
proj=$(new_project)
{ map_header; printf '| %s |  | A thing happens | It works | %s |\n' "$(id 916)" "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 916)" <<< "$OUT" && grep -q 'uncovered' <<< "$OUT"; then
  ok "case16-empty-cell-does-not-shift-status"
else
  bad "case16-empty-cell-does-not-shift-status" "expected exit 1 naming the id as uncovered, got $RC: $OUT"
fi

# case15 — this file must not contain a literal id token. See the header: the fixture ids are built
# at runtime precisely so that greping the repo for a real scenario id can never land here.
if grep -qE "$P-[0-9]" "$0"; then
  bad "case15-no-literal-id-in-source" "a literal id token appears in this harness — it would bind a real scenario to a fixture"
else
  ok "case15-no-literal-id-in-source"
fi

# case18 — a FOUR-DIGIT id is a reference. The keep-filter here read [0-9]{3} for as long as ids
# were three digits, and stayed that way after they were not: on the map that found it, 1241 of the
# 1454 ids the tests actually named were being discarded, so the gate reported 179 of 2961 covered
# instead of 1316 of 3024. Invisible, because the extractor was refusing the map before this line
# ever ran. Every id below has four digits, so the {3} filter reports both as uncovered.
proj=$(new_project)
{ map_header; row 9101 "$V"; row 9102 "$T"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 9101 9102
run_gate "$proj"
if [ "$RC" -eq 0 ]; then
  ok "case18-four-digit-ids-are-references"
else
  bad "case18-four-digit-ids-are-references" "expected exit 0, got $RC: $OUT"
fi

# case19 — BUILD OUTPUT IS NOT EVIDENCE. A stale Stryker report under bin/ quotes test source that
# no longer exists in the tree; counting it means a DELETED test still covers its scenario, on the
# strength of a build artifact. Speed was the reason this was noticed (21.2 s of a 22.9 s run) and
# correctness is the reason it stayed: all 25 ids the unpruned walk found and the pruned walk did
# not were inside such a report.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
anchor "$proj"
mkdir -p "$proj/tests/Unit/bin/Release/StrykerOutput/2026-07-01"
printf 'a deleted test that used to cover %s\n' "$(id 901)" \
  > "$proj/tests/Unit/bin/Release/StrykerOutput/2026-07-01/mutation-report.json"
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 901)" <<< "$OUT" && grep -q 'uncovered' <<< "$OUT"; then
  ok "case19-build-output-is-not-a-reference"
else
  bad "case19-build-output-is-not-a-reference" "expected the id to be uncovered, got $RC: $OUT"
fi

# case20 — a live reference in the SAME tree still counts. The pruning must remove build output and
# nothing else; a prune that also swallowed real test files would make every row uncovered and look
# exactly like a project with no tests.
write_test "$proj" "live.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 0 ]; then
  ok "case20-pruning-does-not-eat-real-tests"
else
  bad "case20-pruning-does-not-eat-real-tests" "expected exit 0, got $RC: $OUT"
fi

# case21 — a PARTIALLY unreadable map is never reported as clean. This is the whole argument for
# exit 5: the numbers below are real and worth printing, and they are not the whole map, and a gate
# that says 0 for "clean over what I could read" is the defect --partial was added to remove.
proj=$(new_project)
{ map_header; row 901 "$V"; printf '| %s | happy | missing a column |\n' "$(id 902)"; } \
  > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 5 ] && grep -q 'partial' <<< "$OUT"; then
  ok "case21-partial-read-is-never-clean"
else
  bad "case21-partial-read-is-never-clean" "expected exit 5 saying so, got $RC: $OUT"
fi

# case22 — ...but it still CHECKS what it could read. A partial read that stopped counting would be
# the all-or-nothing behaviour wearing a different exit code.
proj=$(new_project)
{ map_header; row 901 "$V"; row 903 "$V"; printf '| %s | happy | missing a column |\n' "$(id 902)"; } \
  > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 5 ] && grep -q "$(id 903)" <<< "$OUT" && grep -q 'uncovered' <<< "$OUT"; then
  ok "case22-partial-read-still-reports-uncovered"
else
  bad "case22-partial-read-still-reports-uncovered" "expected the readable row to be judged, got $RC: $OUT"
fi

# case23 — a commentary table does not manufacture a duplicate. The map file below cites one id in a
# promotion note and then carries it as a real ledger row, which is how two real feature files are
# written. Read without the header rule, that is one id on two rows — and this gate would report the
# map as corrupt on the strength of its own parser.
proj=$(new_project)
{
  map_header
  row 901 "$V"
  printf '\n| SC | now | why |\n|---|---|---|\n| %s | validated | operator confirmed it |\n' "$(id 901)"
} > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 0 ]; then
  ok "case23-commentary-table-is-not-a-duplicate"
else
  bad "case23-commentary-table-is-not-a-duplicate" "expected exit 0, got $RC: $OUT"
fi

# case24 — the NEGATIVE CONTROL on the instrument itself, both directions at once. A gate whose
# number never moves reads exactly like a gate that passes; 506.1 called that a vacuous invariant.
# Remove the only reference to a covered row and it must become uncovered; name an id the map does
# not have and it must become dangling. Same project, one edit each way.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
anchor "$proj"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
_clean=$RC
rm -f "$proj/tests/a.test.ts"
run_gate "$proj"
_removed=$RC; _removed_out=$OUT
write_test "$proj" "a.test.ts" 901 999
run_gate "$proj"
_added=$RC; _added_out=$OUT
if [ "$_clean" -eq 0 ] \
   && [ "$_removed" -eq 1 ] && grep -q 'uncovered' <<< "$_removed_out" \
   && [ "$_added" -eq 1 ] && grep -q "$(id 999)" <<< "$_added_out" && grep -q 'dangling' <<< "$_added_out"; then
  ok "case24-negative-control-both-directions"
else
  bad "case24-negative-control-both-directions" \
      "clean=$_clean removed=$_removed added=$_added — the gate does not move when the evidence does"
fi

# case25 — a reference BELOW the map's lowest id is not dangling. spec-kit's spec template numbers a
# spec's Success Criteria with the same two-letter prefix scenario ids use, counting from one — so a
# test citing its own spec criteria is indistinguishable from one citing a scenario that never existed.
# Measured on one project: 387 of 458 spec.md files number criteria that way, and 41 of 44 reported
# "dangling" ids were that. A list that is 93% false is a list nobody reads, and the three real
# entries were invisible inside it.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
# The criterion id is BUILT, never spelled — case15 refuses a literal id token anywhere in this
# file, prose included, and it caught this very case being written with two of them. That guard is the fixture-map-ids lesson
# holding on its own harness, which is the only place it could be proved.
write_test "$proj" "a.test.ts" 901
printf 'and this spec own success criterion %s\n' "$(id 2)" >> "$proj/tests/a.test.ts"
run_gate "$proj"
# Exit 0, deliberately: out-of-range is a collision between two naming conventions, not a defect in
# the map or the suite, so it is printed and does not fail. Asserting exit 1 here would be asserting
# the opposite of the decision.
if [ "$RC" -eq 0 ] && grep -q 'out-of-range' <<< "$OUT" && ! grep -q '^dangling' <<< "$OUT"; then
  ok "case25-below-the-floor-is-not-dangling"
else
  bad "case25-below-the-floor-is-not-dangling" "expected an out-of-range bucket and no dangling, got $RC: $OUT"
fi

# case26 — ...and a reference ABOVE the floor that the map lacks is still dangling. The floor must
# separate the two namespaces, not swallow the direction the gate exists for. This is the half that
# would go unnoticed: a bucket that quietly absorbs real defects looks exactly like a clean gate.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 999
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 999)" <<< "$OUT" && grep -q 'dangling' <<< "$OUT"; then
  ok "case26-above-the-floor-still-dangles"
else
  bad "case26-above-the-floor-still-dangles" "expected the id under dangling, got $RC: $OUT"
fi

# case27 — the floor is DERIVED, not a constant. Raise the map's lowest id and the same reference
# that was dangling becomes out-of-range, with no edit to the gate. A hardcoded floor would be a
# number that goes stale the first time a map is renumbered, silently and in the unsafe direction.
proj=$(new_project)
{ map_header; row 9500 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 9500 999
run_gate "$proj"
if [ "$RC" -eq 0 ] && grep -q 'out-of-range' <<< "$OUT" && ! grep -q '^dangling' <<< "$OUT"; then
  ok "case27-the-floor-follows-the-map"
else
  bad "case27-the-floor-follows-the-map" "expected $(id 999) to be out-of-range against a map starting at $(id 9500), got $RC: $OUT"
fi

# case28 — a SUFFIXED id is its own scenario, and a reference to it does not credit its neighbour.
# A map inserts a row between two allocated ids by suffixing a letter, and the row extractor has
# always accepted that. The reference extractor did not, so both halves were wrong at once and each
# hid the other: the suffixed row read as uncovered however many tests named it, while the bare row
# read as covered on the evidence of a test that names a different scenario. Found on a real map
# where the suffixed row was the no-network rehearsal gate, named in six places across two files.
proj=$(new_project)
{ map_header; printf '| %sb | happy | A thing happens | It works | %s |\n' "$(id 901)" "$V"; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
# Only the suffixed id is written. The bare row must therefore be the uncovered one.
{ printf 'test file a.test.ts\n'; printf 'it covers %sb\n' "$(id 901)"; } > "$proj/tests/a.test.ts"
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -qE "^  $(id 901) " <<< "$OUT" && ! grep -qE "^  $(id 901)b " <<< "$OUT"; then
  ok "case28-a-suffixed-id-is-its-own-scenario"
else
  bad "case28-a-suffixed-id-is-its-own-scenario" "expected the bare id uncovered and the suffixed one covered, got $RC: $OUT"
fi

# case29 — ...and the suffix is one letter, not the start of a word. Without the trailing boundary
# the same greed that reads the suffix reads the first letter of an unrelated identifier, and a
# fixture named for something else would silently cover a scenario. Matching nothing is the safe
# answer here: an unbacked coverage claim is the one thing this gate exists to refuse.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
anchor "$proj"
{ printf 'test file a.test.ts\n'; printf 'a fixture named %sabc\n' "$(id 901)"; } > "$proj/tests/a.test.ts"
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -qE "^  $(id 901) " <<< "$OUT" && grep -q 'uncovered' <<< "$OUT"; then
  ok "case29-a-longer-word-is-not-a-reference"
else
  bad "case29-a-longer-word-is-not-a-reference" "expected the id to stay uncovered, got $RC: $OUT"
fi

# case30 — THE ROOTS ARE DISCOVERED. A browser suite that does not live in tests/ is still evidence.
# The default read `tests` for as long as this script existed; on the project that found it every
# Playwright spec lives in e2e/ and this gate had never read one, so 37 rows stood reported as
# uncovered while a spec proved each of them. The header must also SAY what it read — a verdict
# whose reference set is invisible is a verdict nobody can check.
proj=$(new_project)
mkdir -p "$proj/e2e"
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
{ printf 'browser spec\n'; printf 'it covers %s\n' "$(id 902)"; } > "$proj/e2e/b.spec.ts"
run_gate "$proj"
if [ "$RC" -eq 0 ] && grep -q 'roots: tests,e2e' <<< "$OUT"; then
  ok "case30-discovery-reads-e2e"
else
  bad "case30-discovery-reads-e2e" "expected exit 0 with both roots in the header, got $RC: $OUT"
fi

# case31 — ...and tests/ is not privileged. A project whose only suite is a browser suite must be
# read too; the old constant would exit 4 here, having found nothing to look at and calling that a
# missing root rather than a wrong default.
proj=$(new_project)
rmdir "$proj/tests"
mkdir -p "$proj/e2e"
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
{ printf 'browser spec\n'; printf 'it covers %s\n' "$(id 901)"; } > "$proj/e2e/b.spec.ts"
run_gate "$proj"
if [ "$RC" -eq 0 ] && grep -q 'roots: e2e' <<< "$OUT"; then
  ok "case31-discovery-without-a-tests-dir"
else
  bad "case31-discovery-without-a-tests-dir" "expected exit 0 reading e2e, got $RC: $OUT"
fi

# case32 — an EXPLICIT --roots is not widened by discovery. The caller narrowing the reference set on
# purpose is a legitimate thing to do, and a default that quietly re-broadened it would make the flag
# a suggestion. The id below is proven only from e2e/, which the caller did not ask for.
proj=$(new_project)
mkdir -p "$proj/e2e"
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
{ printf 'browser spec\n'; printf 'it covers %s\n' "$(id 902)"; } > "$proj/e2e/b.spec.ts"
run_gate "$proj" --roots tests
if [ "$RC" -eq 1 ] && grep -q "$(id 902)" <<< "$OUT" && grep -q 'uncovered' <<< "$OUT"; then
  ok "case32-explicit-roots-are-not-widened"
else
  bad "case32-explicit-roots-are-not-widened" "expected exit 1 with the e2e-only id uncovered, got $RC: $OUT"
fi

# case33 — discovery finding NOTHING is not a pass. Zero roots means zero references, which on a map
# claiming nothing renders as a clean run over no evidence at all — the "0 of 0, all clear" failure
# this whole script is named after, arriving by a different door. The candidates must be named:
# "no reference root found" says a gate failed and not what would fix it.
proj=$(mktemp -d)
mkdir -p "$proj/specs"
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
run_gate "$proj"
if [ "$RC" -eq 4 ] && grep -q 'tried' <<< "$OUT" && grep -q 'e2e' <<< "$OUT"; then
  ok "case33-no-root-found-is-not-a-pass"
else
  bad "case33-no-root-found-is-not-a-pass" "expected exit 4 naming the candidates, got $RC: $OUT"
fi

# case35 — A PROJECT MAY DECLARE ITS ROOTS. Discovery is a fleet default and it is silently wrong on
# a project whose test trees are not top-level. ighweld keeps ~3,500 xUnit tests under
# src/welding/Welding.Api.Tests/, which discovery cannot reach and must not reach by widening (a
# source comment naming an id is not a test). 75 rows read as uncovered for as long as that stood.
proj=$(new_project)
mkdir -p "$proj/src/backend.Tests"
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
{ printf 'backend test\n'; printf 'it covers %s\n' "$(id 901)"; } > "$proj/src/backend.Tests/a.cs"
printf 'tests\nsrc/backend.Tests\n' > "$proj/specs/traceability-roots"
run_gate "$proj"
if [ "$RC" -eq 0 ] && grep -q 'src/backend.Tests' <<< "$OUT" && grep -q 'declared in specs/traceability-roots' <<< "$OUT"; then
  ok "case35-declaration-is-honoured"
else
  bad "case35-declaration-is-honoured" "expected exit 0 reading the declared root, got $RC: $OUT"
fi

# case36 — ...and --roots still wins over it. The flag is the caller's promise for one invocation;
# the file is the project's standing one. A file that could override the flag would make the flag a
# suggestion, which is the same defect case32 pins for discovery.
proj=$(new_project)
mkdir -p "$proj/src/backend.Tests"
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
{ printf 'in tests\n'; printf 'it covers %s\n' "$(id 901)"; } > "$proj/tests/a.spec.ts"
{ printf 'backend\n'; printf 'it covers %s\n' "$(id 902)"; } > "$proj/src/backend.Tests/a.cs"
printf 'tests\nsrc/backend.Tests\n' > "$proj/specs/traceability-roots"
run_gate "$proj" --roots tests
if [ "$RC" -eq 1 ] && grep -q "$(id 902)" <<< "$OUT" && grep -q -- '(--roots)' <<< "$OUT"; then
  ok "case36-explicit-roots-beat-the-declaration"
else
  bad "case36-explicit-roots-beat-the-declaration" "expected exit 1 with 902 uncovered under --roots, got $RC: $OUT"
fi

# case37 — A DECLARED ROOT THAT DOES NOT EXIST REFUSES. This is the distinction the root-guard
# already draws and the reason it is not touched here: discovery SKIPS an absent candidate because a
# candidate is a guess, while --roots and the declaration are both promises. A project that renames
# its test tree and forgets the file must be told, not quietly given a coverage figure computed over
# less than it asked for.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
{ printf 'spec\n'; printf 'it covers %s\n' "$(id 901)"; } > "$proj/tests/a.spec.ts"
printf 'tests\nsrc/gone\n' > "$proj/specs/traceability-roots"
run_gate "$proj"
if [ "$RC" -eq 4 ] && grep -q 'src/gone' <<< "$OUT"; then
  ok "case37-absent-declared-root-refuses"
else
  bad "case37-absent-declared-root-refuses" "expected exit 4 naming src/gone, got $RC: $OUT"
fi

# case38 — AN EMPTY DECLARATION IS NOT NO DECLARATION. A file of nothing but comments must not fall
# through to discovery, and must certainly not yield a clean run over no roots at all. This is the
# sabotage direction that matters: the whole point of a per-project override is that it cannot
# become a route to the "0 of 0, all clear" report this script is named after.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
{ printf 'spec\n'; printf 'it covers %s\n' "$(id 901)"; } > "$proj/tests/a.spec.ts"
printf '# only a comment\n\n' > "$proj/specs/traceability-roots"
run_gate "$proj"
if [ "$RC" -eq 4 ] && grep -q 'declares no roots' <<< "$OUT"; then
  ok "case38-empty-declaration-refuses"
else
  bad "case38-empty-declaration-refuses" "expected exit 4 for an empty declaration, got $RC: $OUT"
fi

# case39 — NO DECLARATION MEANS NOTHING CHANGED. The additive property, asserted rather than
# assumed: every project in the fleet that does not carry the file must behave exactly as it did
# before this feature existed.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
{ printf 'spec\n'; printf 'it covers %s\n' "$(id 901)"; } > "$proj/tests/a.spec.ts"
run_gate "$proj"
if [ "$RC" -eq 0 ] && grep -q '(discovered)' <<< "$OUT"; then
  ok "case39-no-declaration-is-unchanged"
else
  bad "case39-no-declaration-is-unchanged" "expected exit 0 via discovery, got $RC: $OUT"
fi

# case34 — THE MAP IS NOT EVIDENCE FOR ITSELF. specs/ holds a row for every id it owns, so a
# candidate list admitting it would mark every row covered by its own map entry: the gate reduced to
# a tautology, green forever, over nothing. The row below is named in SCENARIOS.md and nowhere else,
# and must still be uncovered. This is the same argument as case19 — a coverage claim backed by
# something that is not a live test is the one thing this gate exists to refuse.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
anchor "$proj"
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 901)" <<< "$OUT" && grep -q 'uncovered' <<< "$OUT" \
   && ! grep -q 'roots: .*specs' <<< "$OUT"; then
  ok "case34-the-map-is-not-its-own-evidence"
else
  bad "case34-the-map-is-not-its-own-evidence" "expected the row uncovered and specs/ not a root, got $RC: $OUT"
fi

# case40 — NO CORE PRODUCTION SCRIPT NAMES A SCENARIO ID (row 012, found as consultpilot H7bp).
#
# The sync writes every CORE script into every project, unconditionally. A comment in one of them
# naming an id is read as a REFERENCE by any gate whose roots include scripts/ — consultpilot's
# accounting gate reads scripts/ by design, and a project may declare it. On the project the id came
# from, that comment keeps a row covered after the test proving it is deleted: consultpilot's
# validated "sweep over the self-tests" row was traced by nothing but a `Covers:` line in
# validate-no-sigpipe-assertions.sh. On every other project the same id covers an unrelated row or
# dangles where nobody can fix it.
#
# TEST files are not in the population: in a test, naming an id IS the proof (spec 012, R6).
#
# The check runs THIS GATE over copies of the scripts, rather than grepping with a copy of its
# pattern: what counts as a reference is whatever the gate reads, so the two cannot drift apart.
# The map holds one validated row. Clean means exactly: that row uncovered, nothing dangling,
# nothing out-of-range. An id in a CORE comment shows up as one of the last two — or, if it happens
# to be the row's own id, as the row going covered. All three directions are sabotaged below.
AUTOSYNC="$REPO_ROOT/scripts/template-autosync.sh"

core_prod_fixture() { # <project> [list-file] → copies CORE production scripts into <project>/core
  mkdir -p "$1/core"
  CORE_COPIED=0
  CORE_COPY_FAILED=""
  while IFS= read -r n; do
    case "$n" in ''|test-*|test_*) continue ;; esac
    # A name with no file is --unlisted's defect to report, not an id; skip it here.
    [ -f "$REPO_ROOT/scripts/$n" ] || continue
    # A failed copy is a file the census never read; count it as a failure, not as coverage.
    cp "$REPO_ROOT/scripts/$n" "$1/core/$n" || { CORE_COPY_FAILED="$CORE_COPY_FAILED $n"; continue; }
    CORE_COPIED=$((CORE_COPIED+1))
  done < "$2"
}

core_id_census() { # <project> → 0 clean, 1 with CENSUS_WHY set
  CENSUS_WHY=""
  if [ -n "$CORE_COPY_FAILED" ]; then
    CENSUS_WHY="could not copy, so could not read:$CORE_COPY_FAILED"
    return 1
  fi
  if [ "$CORE_COPIED" -eq 0 ]; then
    CENSUS_WHY="no CORE production script was found to read — an empty census is not a clean one"
    return 1
  fi
  run_gate "$1" --roots core
  found=$(grep -E "^  ${P}-[0-9]+[a-z]?\$" <<< "$OUT" || true)
  grep -q 'coverage: 1 of 1' <<< "$OUT" && found="$found
$(id 900)"
  if [ -z "$(printf '%s' "$found" | tr -d '[:space:]')" ]; then
    # Clean is the gate's zero-refs refusal, and it must say it read every copied file: "no id in
    # any of N files" is the census's clean reading exactly, and the count is what tells it apart
    # from a walk that read nothing (spec 044).
    if [ "$RC" -eq 4 ] && grep -q 'no scenario id found' <<< "$OUT" \
       && grep -q "core: $CORE_COPIED file(s)" <<< "$OUT"; then return 0; fi
    CENSUS_WHY="the gate did not give the expected reading (exit $RC): $OUT"
    return 1
  fi
  while IFS= read -r ref; do
    ref=$(printf '%s' "$ref" | tr -d ' ')
    [ -n "$ref" ] || continue
    bare=$(printf '%s' "$ref" | tr -d '-')
    files=$(grep -rlE -- "$ref|${bare}_" "$1/core" 2>/dev/null | sed "s#^$1/core/#scripts/#" | tr '\n' ' ')
    CENSUS_WHY="$CENSUS_WHY $ref in: ${files:-?};"
  done <<< "$found"
  return 1
}

# run_gate assigns the global `proj`, so the fixture lives in its own variable.
c40=$(new_project)
{ map_header; row 900 "$V"; } > "$c40/specs/SCENARIOS.md"
if [ "$SKIP_CORE_CENSUS" -eq 1 ]; then
  :  # inside a sabotage arm — see sab_run
elif bash "$AUTOSYNC" --list-core-scripts > "$c40/core.list" 2>/dev/null; then
  core_prod_fixture "$c40" "$c40/core.list"
  if core_id_census "$c40"; then
    ok "case40a-core-production-scripts-name-no-scenario-id ($CORE_COPIED files)"
  else
    bad "case40a-core-production-scripts-name-no-scenario-id" "$CENSUS_WHY"
  fi

  # Sabotage, three directions, each on its own copy of the fixture. The file planted into is the
  # first one copied, and it must be NAMED — a census that only says "something" hands the hunt back.
  PLANT=$(find "$c40/core" -type f | sort | head -1)
  PLANT_REL="scripts/${PLANT##*/}"
  for arm in b c e; do
    sp=$(new_project)
    cp "$c40/specs/SCENARIOS.md" "$sp/specs/"
    core_prod_fixture "$sp" "$c40/core.list"
    case "$arm" in
      b) printf '# Covers: %s\n' "$(id 4242)" >> "$sp/core/${PLANT##*/}" ;;   # dangling
      c) printf '# Covers: %s\n' "$(id 900)"  >> "$sp/core/${PLANT##*/}" ;;   # covers the row
      e) printf '# see Checkout_%s%s_Twice\n' "$P" 4242 >> "$sp/core/${PLANT##*/}" ;;   # underscore form
    esac
    if core_id_census "$sp"; then
      bad "case40$arm-a-planted-id-is-caught" "an id planted in $PLANT_REL left the census green"
    elif grep -qF "$PLANT_REL" <<< "$CENSUS_WHY"; then
      ok "case40$arm-a-planted-id-is-caught and named ($PLANT_REL)"
    else
      bad "case40$arm-a-planted-id-is-caught" "red, but did not name $PLANT_REL: $CENSUS_WHY"
    fi
    rm -rf "$sp"
  done

  # An empty CORE list must not read as clean.
  sp=$(new_project)
  cp "$c40/specs/SCENARIOS.md" "$sp/specs/"
  : > "$sp/empty.list"
  core_prod_fixture "$sp" "$sp/empty.list"
  if core_id_census "$sp"; then
    bad "case40d-an-empty-census-is-not-clean" "zero files read, reported clean"
  else
    ok "case40d-an-empty-census-is-not-clean"
  fi
  rm -rf "$sp"
else
  bad "case40a-core-production-scripts-name-no-scenario-id" "template-autosync.sh --list-core-scripts failed — could not list CORE"
fi
rm -rf "$c40"

# case41 — ZERO IDS FROM A SCAN THAT RAN is not coverage. Every root exists, the map claims a row,
# and no file under the roots names any id. That renders as "every claimed scenario is uncovered",
# the same catastrophic-looking report the missing-root guard refuses — fundit read 0 of 182 and
# then 175 of 182 minutes later with nothing changed. Exit 4, never 1.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$T"; } > "$proj/specs/SCENARIOS.md"
printf 'no ids in here\n' > "$proj/tests/a.test.ts"
printf 'nor here\n' > "$proj/tests/b.test.ts"
run_gate "$proj"
if [ "$RC" -eq 4 ] && grep -q 'no scenario id' <<< "$OUT" && ! grep -q '^coverage:' <<< "$OUT"; then
  ok "case41-zero-ids-with-claims-refuses"
else
  bad "case41-zero-ids-with-claims-refuses" "expected exit 4 and no coverage line, got $RC: $OUT"
fi

# case42 — ...and the refusal names every root with the number of files it read under it. A reader
# told "the scan found nothing" needs to see whether it read 2 files or 2146.
if grep -q 'tests: 2 file' <<< "$OUT"; then
  ok "case42-refusal-names-roots-and-file-counts"
else
  bad "case42-refusal-names-roots-and-file-counts" "expected 'tests: 2 file(s)' in: $OUT"
fi
rm -rf "$proj"

# case43 — ...but a map that CLAIMS NOTHING with nothing found stays a normal run. No claim goes
# unbacked, so there is no catastrophic report to refuse, and an all-mapped roadmap is legitimate
# (case5's argument).
proj=$(new_project)
{ map_header; row 901 "$M"; row 902 "$M"; } > "$proj/specs/SCENARIOS.md"
printf 'no ids in here\n' > "$proj/tests/a.test.ts"
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case43-zero-ids-without-claims-is-a-normal-run"; else bad "case43-zero-ids-without-claims-is-a-normal-run" "expected exit 0, got $RC: $OUT"; fi
rm -rf "$proj"

# case44 — A PARTIAL READ NAMES WHAT IT DROPPED. The extractor names every refused row as file:line
# on stderr; the gate captured that and printed "see above" over nothing (agentcrm F316: 31 rows
# lost to one doubled pipe, and no way to find them).
proj=$(new_project)
{ map_header; row 901 "$V"; printf '| %s | happy | missing a column |\n' "$(id 902)"; } \
  > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 5 ] && grep -q 'SCENARIOS.md:10' <<< "$OUT" && grep -q '1 row(s) refused' <<< "$OUT"; then
  ok "case44-partial-read-names-refused-rows"
else
  bad "case44-partial-read-names-refused-rows" "expected exit 5 naming SCENARIOS.md:10 and the count, got $RC: $OUT"
fi
rm -rf "$proj"

# case45 — a clean read says nothing about "see above". The pointer is printed only when something
# above it exists.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 0 ] && ! grep -q 'see above' <<< "$OUT"; then
  ok "case45-no-see-above-on-a-clean-read"
else
  bad "case45-no-see-above-on-a-clean-read" "expected exit 0 with no 'see above', got $RC: $OUT"
fi
rm -rf "$proj"

# case46 — A CHAINED UNDERSCORE FORM NAMES EVERY ID IN IT, not just the first. A C# or Java method
# cannot carry a hyphen, so a test covering two adjacent rows is written `SCNNN_SCNNN_WhatItDoes`
# — and `grep -o` takes NON-OVERLAPPING matches, so the separator that opened the second id was
# already eaten by the first. The second id was invisible, and the row it covers was reported
# uncovered: a gate wrong in the direction that looks like diligence. Measured on one project
# 2026-09-30: 8 of its 58 "uncovered" rows were this one shape, each with a passing test naming it.
#
# THE SINGLE FORM IS ASSERTED IN THE SAME CASE, as a known positive. Without it a pattern that had
# stopped matching the underscore form altogether would pass this case by reporting both rows
# uncovered for a different reason, which is how an enumeration lies about having looked.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$V"; row 903 "$V"; } > "$proj/specs/SCENARIOS.md"
{
  printf 'public async Task %s901_%s902_TwoAdjacentRowsInOneTest()\n' "$P" "$P"
  printf 'public async Task %s903_TheSingleFormStillWorks()\n' "$P"
} > "$proj/tests/Chained.cs"
run_gate "$proj"
if [ "$RC" -eq 0 ]; then
  ok "case46-chained-underscore-ids-both-count"
else
  bad "case46-chained-underscore-ids-both-count" "expected exit 0, got $RC: $OUT"
fi
rm -rf "$proj"

# case47 — A SPEC'S OWN CRITERION NUMBER IS NOT A SCENARIO ID (row 061). agentcrm spec 044 numbered
# its success criteria SC-NNN-NN; `-` is not a word character, so `\b` fired after the first number
# and the gate read a reference to SC-NNN — a row the map did not have, reported dangling.
# Two directions, one case: the criterion must neither dangle (47a) nor cover the row whose number
# it happens to share (47b). The plain row citation in 47a is the known positive, so a pattern that stopped reading
# hyphenated ids altogether cannot pass 47a by finding nothing.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
printf '// %s-901 is the row; %s-944-01 and %s-944-02a are criteria\n' "$P" "$P" "$P" > "$proj/tests/a.test.ts"
run_gate "$proj"
if [ "$RC" -eq 0 ]; then
  ok "case47a-a-criterion-number-does-not-dangle"
else
  bad "case47a-a-criterion-number-does-not-dangle" "expected exit 0, got $RC: $OUT"
fi
rm -rf "$proj"
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
# 902 is cited for real so the scan finds an id: with none at all the zero-refs guard answers first.
printf '// %s-902, and criterion %s-901-01\n' "$P" "$P" > "$proj/tests/a.test.ts"
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "${P}-901" <<< "$OUT"; then
  ok "case47b-a-criterion-number-does-not-cover-its-namesake"
else
  bad "case47b-a-criterion-number-does-not-cover-its-namesake" "expected the row reported uncovered, got $RC: $OUT"
fi
rm -rf "$proj"

# case48 — A MAP THAT GREW PAST THREE DIGITS KEEPS ITS NAMESPACE LINE (row 048). The out-of-range
# split tells a spec's criteria from scenario ids by digit width, and a grown map holds ids of two
# widths. The width is the NARROWEST id's, so growth does not move the line. Measured from the widest
# id instead, a three-digit citation of a scenario the map LACKS would be filed as a criterion and
# never dangle (48b). The map starts at one on purpose: there the floor catches nothing, so only the
# width rule can bucket the two-digit criterion (48a). Before this case nothing tested the width
# rule at all.
proj=$(new_project)
{ map_header; row 001 "$V"; row 1001 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 001 1001
printf 'and this spec own success criterion %s\n' "$(id 12)" >> "$proj/tests/a.test.ts"
run_gate "$proj"
if [ "$RC" -eq 0 ] && grep -q 'out-of-range' <<< "$OUT" && ! grep -q '^dangling' <<< "$OUT"; then
  ok "case48a-mixed-width-map-keeps-the-width-line"
else
  bad "case48a-mixed-width-map-keeps-the-width-line" "expected both rows covered and the criterion out-of-range, got $RC: $OUT"
fi
rm -rf "$proj"
# 48b: the other direction. A missing three-digit id above the floor is a scenario id the map lacks,
# so it dangles on a grown map exactly as it would on a three-digit one.
proj=$(new_project)
{ map_header; row 001 "$V"; row 1001 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 001 1001 950
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 950)" <<< "$OUT" && grep -q 'dangling' <<< "$OUT"; then
  ok "case48b-mixed-width-map-still-dangles-three-digits"
else
  bad "case48b-mixed-width-map-still-dangles-three-digits" "expected $(id 950) under dangling, got $RC: $OUT"
fi
rm -rf "$proj"

# case49 — A WALK THAT ERRORED IS NOT A COVERAGE RESULT (row 067). fundit read 141, 0 and 0 of 148 on
# identical input while Playwright rewrote files under the roots. 044 made the zero case refuse; the
# partial one still printed "141 of 148" over seven rows the walk never reached. chmod 000 stands in
# for the vanished directory: find and grep report both the same way, and this one is deterministic.
# Root reads through chmod 000, so the case cannot run as root and says so rather than passing.
if [ "$(command id -u)" -eq 0 ]; then
  skip "case49-errored-walk-refuses" "running as root; chmod 000 does not make a path unreadable"
else
  # (a) an unreadable directory: find cannot descend, and the id under it is lost.
  proj=$(new_project)
  { map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
  write_test "$proj" "a.test.ts" 901
  mkdir -p "$proj/tests/sub"
  write_test "$proj" "sub/b.test.ts" 902
  chmod 000 "$proj/tests/sub"
  run_gate "$proj"
  chmod 755 "$proj/tests/sub"
  if [ "$RC" -eq 4 ] && ! grep -q '^coverage:' <<< "$OUT" && grep -q 'sub' <<< "$OUT" \
     && grep -qi 'denied' <<< "$OUT"; then
    ok "case49a-unreadable-directory-refuses"
  else
    bad "case49a-unreadable-directory-refuses" "expected exit 4 quoting the error, no coverage line, got $RC: $OUT"
  fi
  # (c) ...and the refusal says how many files each root DID read.
  if grep -q 'tests: 1 file' <<< "$OUT"; then
    ok "case49c-errored-walk-names-file-counts"
  else
    bad "case49c-errored-walk-names-file-counts" "expected 'tests: 1 file(s)' in: $OUT"
  fi
  rm -rf "$proj"

  # (b) an unreadable file: find lists it, grep cannot open it.
  proj=$(new_project)
  { map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
  write_test "$proj" "a.test.ts" 901
  write_test "$proj" "b.test.ts" 902
  chmod 000 "$proj/tests/b.test.ts"
  run_gate "$proj"
  chmod 644 "$proj/tests/b.test.ts"
  if [ "$RC" -eq 4 ] && ! grep -q '^coverage:' <<< "$OUT" && grep -q 'b.test.ts' <<< "$OUT"; then
    ok "case49b-unreadable-file-refuses"
  else
    bad "case49b-unreadable-file-refuses" "expected exit 4 naming b.test.ts, no coverage line, got $RC: $OUT"
  fi
  rm -rf "$proj"
fi

# case50 — PLAYWRIGHT'S OTHER OUTPUT IS BUILD OUTPUT TOO (row 067). test-results/ was already pruned;
# blob-report/ is written by the same run, and allure-results/ and .nyc_output/ by the reporters
# beside it. An id quoted in a report is neither coverage (the covering row stays uncovered) nor a
# dangling reference (the id nobody wrote stays out of the list).
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
for dir in blob-report allure-results .nyc_output; do
  mkdir -p "$proj/tests/$dir"
  printf 'report quotes %s and %s\n' "$(id 902)" "$(id 907)" > "$proj/tests/$dir/report.json"
done
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "uncovered" <<< "$OUT" && grep -q "$(id 902)" <<< "$OUT" \
   && ! grep -q "$(id 907)" <<< "$OUT"; then
  ok "case50-report-directories-are-pruned"
else
  bad "case50-report-directories-are-pruned" "expected $(id 902) uncovered and no $(id 907), got $RC: $OUT"
fi
rm -rf "$proj"

# ------------------------------------------------------------- sabotage ----
#
# One marked region at a time, on a COPY. Asserting only "the sabotaged run exits non-zero" would be
# satisfied by a copy that died of a syntax error, which is the false-green shape this row exists to
# remove — so every entry names the cases it must turn red, and the clean cases must stay green.
#
# GREEN BASELINE FIRST. With the shipped gate already red, every entry below would report "live" on
# breakage it did not cause. That is the defect 007br's FR-08 found in the register-ids falsification
# arm, and it is cheap to not repeat.
#
# TWO of the entries are "must stay GREEN". The gate carries two independent defences against the
# collation trap — the LC_ALL pin and the shell classification — and removing either one alone must
# still leave case14 passing. That is what defence in depth means, and asserting it is the only way
# to know the second defence is not decorative. Only removing BOTH may turn case14 red.

# The replacement texts passed to this are SINGLE-quoted on purpose: they are source code for the
# sabotaged copy, so `$1` and `$TMP` must reach that copy unexpanded. shellcheck's SC2016 is exactly
# backwards at those call sites, which each carry a disable directive.
replace_region() { # <src> <dst> <marker> <replacement-text>
  awk -v m="$3" -v rep="$4" '
    $0 ~ ("^[[:space:]]*# >>> " m "$") { print rep; skip = 1; next }
    $0 ~ ("^[[:space:]]*# <<< " m "$") { skip = 0; next }
    !skip { print }
  ' "$1" > "$2"
}

sab_run() { # <sabotaged-script> → SAB_OUT
  # --skip-core-census: case40 reads CORE scripts, not the gate's marked regions, so no arm here
  # can turn it red — and at ~5 s a run, repeating it in all 13 arms would put this harness past the
  # timeout it already sits close to (consultpilot H7bq).
  SAB_OUT=$(bash "$0" --script "$1" --no-sabotage --skip-core-census 2>&1)
  return 0
}

expect_red() { # <label> <output> <case>...
  lbl="$1"; out="$2"; shift 2
  missing=""
  for c in "$@"; do
    grep -q "FAIL  $c" <<< "$out" || missing="$missing $c"
  done
  if [ -n "$missing" ]; then
    echo "  FAIL  sabotage/$lbl — these cases stayed GREEN:$missing"
    echo "        They therefore prove nothing about the shipped gate."
    return 1
  fi
  echo "  PASS  sabotage/$lbl — $* went red"
  return 0
}

expect_green() { # <label> <output> <case>...
  lbl="$1"; out="$2"; shift 2
  broke=""
  for c in "$@"; do
    grep -q "FAIL  $c" <<< "$out" && broke="$broke $c"
  done
  if [ -n "$broke" ]; then
    echo "  FAIL  sabotage/$lbl — these cases broke when they should not have:$broke"
    return 1
  fi
  echo "  PASS  sabotage/$lbl — $* stayed green, as defence in depth requires"
  return 0
}

if [ "$RUN_SABOTAGE" -eq 1 ] && [ "$FAIL" -eq 0 ]; then
  echo
  echo "Sabotage check — every defence must be load-bearing:"

  proj=$(new_project)
  { map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
  write_test "$proj" "a.test.ts" 901
  if ! bash "$SCRIPT" --dir "$proj/specs" >/dev/null 2>&1; then
    echo "  FAIL  sabotage/baseline — the shipped gate is not green on a clean fixture."
    echo "        Without a green baseline every entry below would report breakage it did not cause."
    exit 1
  fi
  echo "  PASS  sabotage/baseline — the shipped gate is green on a clean fixture"

  SABDIR=$(mktemp -d)
  SAB_FAIL=0

  # The gate resolves its two dependencies relative to its own directory, so a copy dropped in a bare
  # temp dir dies before it classifies anything — and every entry below would then report "red" on a
  # missing file rather than on the defence it removed. That is the same false attribution the green
  # baseline above exists to prevent, one level down. Link the dependencies in; the sabotage targets
  # the gate, not its neighbours.
  ln -s "$REPO_ROOT/scripts/scenario-map-layout.sh" "$SABDIR/scenario-map-layout.sh"
  ln -s "$REPO_ROOT/scripts/scenario-map-rows.sh"   "$SABDIR/scenario-map-rows.sh"

  # (a) the classification rewritten with awk's equality operator, pin intact.
  # shellcheck disable=SC2016
  replace_region "$SCRIPT" "$SABDIR/a.sh" classify \
'is_claimed() { awk -v s="$1" -v v="✓" -v t="◐" "BEGIN { exit !(s == v || s == t) }"; }'
  sab_run "$SABDIR/a.sh"
  expect_green "awk-equality-with-pin" "$SAB_OUT" case14-locale-immunity case5-mapped-exempt || SAB_FAIL=1

  # (b) the pin removed, shell classification intact.
  replace_region "$SCRIPT" "$SABDIR/b.sh" locale-pin ':'
  sab_run "$SABDIR/b.sh"
  expect_green "pin-removed-shell-intact" "$SAB_OUT" case14-locale-immunity case5-mapped-exempt || SAB_FAIL=1

  # (c) BOTH defences removed — the collation trap is live and case14 must catch it.
  replace_region "$SCRIPT" "$SABDIR/c0.sh" locale-pin ':'
  # shellcheck disable=SC2016
  replace_region "$SABDIR/c0.sh" "$SABDIR/c.sh" classify \
'is_claimed() { awk -v s="$1" -v v="✓" -v t="◐" "BEGIN { exit !(s == v || s == t) }"; }'
  sab_run "$SABDIR/c.sh"
  if [ -z "$SVLOC" ]; then
    skip "sabotage/both-defences-removed" "no Swedish UTF-8 locale — the one entry that proves the trap is real cannot run here"
  else
    expect_red "both-defences-removed" "$SAB_OUT" case14-locale-immunity || SAB_FAIL=1
  fi

  # (d) the dangling comparison deleted.
  # shellcheck disable=SC2016
  # The region now writes dangling.all, which the out-of-range split consumes — a replacement that
  # still wrote "dangling" would leave that split reading a file nobody created, and the arm would
  # report "not surgical" on a gate it had simply broken. It did exactly that once.
  replace_region "$SCRIPT" "$SABDIR/d.sh" dangling ': > "$TMP/dangling.all"'
  sab_run "$SABDIR/d.sh"
  expect_red "dangling-check-deleted" "$SAB_OUT" case3-dangling case4-both-directions || SAB_FAIL=1

  # (e) the struck exemption deleted — a retired row starts demanding a test.
  replace_region "$SCRIPT" "$SABDIR/e.sh" struck-exempt ':'
  sab_run "$SABDIR/e.sh"
  expect_red "struck-exemption-deleted" "$SAB_OUT" case6-struck-exempt || SAB_FAIL=1

  # (h) the id-length filter narrowed back to {3} — the shape it had while the extractor was
  # refusing the map, so nobody ever saw it discard 85% of the evidence.
  # shellcheck disable=SC2016
  replace_region "$SCRIPT" "$SABDIR/h.sh" id-length-filter \
'grep -xE "${PREFIX}-[0-9]{3}" "$TMP/refs" 2>/dev/null | sort -u > "$TMP/refs.u" || : > "$TMP/refs.u"'
  sab_run "$SABDIR/h.sh"
  expect_red "id-length-filter-narrowed" "$SAB_OUT" case18-four-digit-ids-are-references || SAB_FAIL=1

  # (i) the build-output prune removed — a stale mutation report becomes coverage evidence.
  # shellcheck disable=SC2016
  replace_region "$SCRIPT" "$SABDIR/i.sh" build-prune \
'  grep -rhoIE "${PREFIX}-[0-9]+" "$rp" 2>/dev/null >> "$TMP/refs" || true'
  sab_run "$SABDIR/i.sh"
  expect_red "build-prune-removed" "$SAB_OUT" case19-build-output-is-not-a-reference || SAB_FAIL=1

  # (j) the partial-read exit removed — "clean over what I could read" reported as clean.
  replace_region "$SCRIPT" "$SABDIR/j.sh" partial-exit ':'
  sab_run "$SABDIR/j.sh"
  expect_red "partial-exit-removed" "$SAB_OUT" case21-partial-read-is-never-clean || SAB_FAIL=1

  # (k) the out-of-range split removed — the other SC- namespace floods the dangling list again.
  replace_region "$SCRIPT" "$SABDIR/k.sh" out-of-range 'cp "$TMP/dangling.all" "$TMP/dangling"; : > "$TMP/outofrange"'
  sab_run "$SABDIR/k.sh"
  expect_red "out-of-range-split-removed" "$SAB_OUT" case25-below-the-floor-is-not-dangling || SAB_FAIL=1

  # (p) the width measured from the WIDEST id — the natural "fix" once a map holds four-digit ids.
  # (q) the width rule dropped, leaving only the floor. Both are one-token edits inside the
  # out-of-range region, so they are sed on a copy, and a copy sed did not change is a failed arm.
  sed 's/awk .{ print length(\$0) }. | sort -n | head -1)/awk '"'"'{ print length($0) }'"'"' | sort -n | tail -1)/' \
    "$SCRIPT" > "$SABDIR/p.sh"
  sed 's/-v width="\${MAP_WIDTH:-0}"/-v width=0/' "$SCRIPT" > "$SABDIR/q.sh"
  for arm in p q; do
    if cmp -s "$SCRIPT" "$SABDIR/$arm.sh"; then
      echo "  FAIL  sabotage/$arm — the sed matched nothing; the width line has moved"
      SAB_FAIL=1
    fi
  done
  sab_run "$SABDIR/p.sh"
  expect_red "width-from-widest-id" "$SAB_OUT" case48b-mixed-width-map-still-dangles-three-digits || SAB_FAIL=1
  sab_run "$SABDIR/q.sh"
  expect_red "width-rule-removed" "$SAB_OUT" case48a-mixed-width-map-keeps-the-width-line || SAB_FAIL=1

  # (f) the missing-root guard removed. Since spec 044 a missing root has more than one defence: this
  # guard, the zero-refs guard (the empty scan it causes, naming the root with its 0 files), and since
  # row 067 the walk-error guard (find's own complaint about the path). So removing this one alone
  # must leave case9 green, and only removing all three (o2) may turn it red.
  replace_region "$SCRIPT" "$SABDIR/f.sh" root-guard ':'
  sab_run "$SABDIR/f.sh"
  expect_green "root-guard-removed-zero-refs-intact" "$SAB_OUT" case9-missing-root || SAB_FAIL=1

  # (n) the zero-refs guard removed — a scan that found no id anywhere prints "0 of N" again.
  replace_region "$SCRIPT" "$SABDIR/n.sh" zero-refs-guard ':'
  sab_run "$SABDIR/n.sh"
  expect_red "zero-refs-guard-removed" "$SAB_OUT" \
    case41-zero-ids-with-claims-refuses case42-refusal-names-roots-and-file-counts || SAB_FAIL=1

  # (r) the walk-error guard removed (row 067) — a walk that lost part of the tree prints a partial
  # coverage number again. case49c goes too: the file counts are only printed by the refusal.
  replace_region "$SCRIPT" "$SABDIR/r.sh" walk-error-guard ':'
  sab_run "$SABDIR/r.sh"
  if [ "$(command id -u)" -ne 0 ]; then
    expect_red "walk-error-guard-removed" "$SAB_OUT" \
      case49a-unreadable-directory-refuses case49b-unreadable-file-refuses \
      case49c-errored-walk-names-file-counts || SAB_FAIL=1
  fi

  # (s) the report directories row 067 added to the prune dropped — their quoted ids count again.
  sed 's/ -o -name blob-report -o -name allure-results -o -name .nyc_output//' "$SCRIPT" > "$SABDIR/s.sh"
  if cmp -s "$SCRIPT" "$SABDIR/s.sh"; then
    echo "  FAIL  sabotage/s — the sed matched nothing; the prune line has moved"
    SAB_FAIL=1
  fi
  sab_run "$SABDIR/s.sh"
  expect_red "report-dirs-unpruned" "$SAB_OUT" case50-report-directories-are-pruned || SAB_FAIL=1

  # (o) Since row 067 a missing root has a THIRD defence: find reports the path it cannot walk, and
  # the walk-error guard refuses. So removing root-guard and zero-refs together must still leave
  # case9 green (o), and only removing all three (o2) may turn it red.
  replace_region "$SCRIPT" "$SABDIR/o0.sh" root-guard ':'
  replace_region "$SABDIR/o0.sh" "$SABDIR/o.sh" zero-refs-guard ':'
  sab_run "$SABDIR/o.sh"
  expect_green "root-guard-and-zero-refs-removed-walk-error-intact" "$SAB_OUT" case9-missing-root || SAB_FAIL=1

  # (o2) ALL THREE removed — a typo'd root reports every scenario as uncovered, and case9 must catch it.
  replace_region "$SABDIR/o.sh" "$SABDIR/o2.sh" walk-error-guard ':'
  sab_run "$SABDIR/o2.sh"
  expect_red "root-guard-zero-refs-and-walk-error-removed" "$SAB_OUT" case9-missing-root || SAB_FAIL=1

  # (l) discovery replaced by the constant it grew out of. This is the shape the gate shipped with
  # for its whole life, and the reason it went unseen is worth stating: on a project whose tests all
  # live in tests/ the constant is indistinguishable from the discovery, so every case above except
  # these two stays green either way. The defect only appears where the suite is somewhere else,
  # which is exactly where nobody was looking.
  # Single-quoted like its siblings, but with no disable directive: the replacement holds no
  # expansion for SC2016 to warn about, and a directive that guards nothing is the kind of noise
  # this file is otherwise careful to keep out.
  replace_region "$SCRIPT" "$SABDIR/l.sh" roots-discovery 'ROOTS="tests"'
  sab_run "$SABDIR/l.sh"
  expect_red "roots-discovery-replaced-by-constant" "$SAB_OUT" \
    case30-discovery-reads-e2e case31-discovery-without-a-tests-dir || SAB_FAIL=1

  # (m) the roots DECLARATION neutralised — the file is read and then ignored, so a project whose
  # tests are not top-level silently falls back to discovery and under-reports its own coverage.
  # That is the state ighweld was in, and the reason it survived is that on every project whose
  # tests DO live in tests/ this sabotage is invisible.
  # shellcheck disable=SC2016
  replace_region "$SCRIPT" "$SABDIR/m.sh" roots-declaration 'ROOTS_DECL=""; ROOTS_DECLARED=0'
  sab_run "$SABDIR/m.sh"
  expect_red "roots-declaration-neutralised" "$SAB_OUT" \
    case35-declaration-is-honoured case38-empty-declaration-refuses || SAB_FAIL=1

  # (g) the duplicate-id check deleted — two scenarios under one handle stop being reported.
  # shellcheck disable=SC2016
  replace_region "$SCRIPT" "$SABDIR/g.sh" duplicate-check ': > "$TMP/duplicate"'
  sab_run "$SABDIR/g.sh"
  expect_red "duplicate-check-deleted" "$SAB_OUT" case17-duplicate-id || SAB_FAIL=1

  # The clean case must survive every surgical sabotage. If it broke, the sabotage was wholesale and
  # the reds above would be meaningless.
  for s in a b c d e f g l m n o; do
    sab_run "$SABDIR/$s.sh"
    if grep -q "FAIL  case1-clean" <<< "$SAB_OUT"; then
      echo "  FAIL  sabotage/$s — case1-clean also broke, so the sabotage was not surgical"
      SAB_FAIL=1
    fi
  done
  # Counted, not spelled out. The line said "all seven" while ten arms were running — a hardcoded
  # tally in a message about thoroughness is the one number nobody re-reads when they add an arm.
  # `! -type l` excludes the two dependency SYMLINKS linked into this directory above, which a
  # plain *.sh count includes — it reported 12 arms for 10, which is how a derived number goes
  # wrong in the same direction a hardcoded one does. c0.sh and o0.sh are intermediates, not arms.
  SAB_COUNT=$(find "$SABDIR" -maxdepth 1 -name '*.sh' ! -type l ! -name 'c0.sh' ! -name 'o0.sh' | wc -l | tr -d ' ')
  [ "$SAB_FAIL" -eq 0 ] && echo "  PASS  sabotage — every sabotage was surgical (case1-clean survived all $SAB_COUNT)"

  rm -rf "$SABDIR"
  [ "$SAB_FAIL" -eq 0 ] || FAIL=$((FAIL+1))
fi

echo
echo "$PASS passed, $FAIL failed, $INCONCL inconclusive"
[ "$FAIL" -gt 0 ] && { echo "failed:$FAILED_CASES"; exit 1; }
[ "$INCONCL" -gt 0 ] && exit 2
exit 0
