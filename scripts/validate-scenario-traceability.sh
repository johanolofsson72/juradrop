#!/bin/sh
# validate-scenario-traceability.sh — the SC-id traceability gate.
#
# WHY THIS EXISTS: four comments in this directory cited this script by name for months —
# archive-spec-history.sh:25 and test-archive-spec-history.sh:9,55,271 — and they did not cite it as
# something that ought to exist. They cited it as something that had run:
#
#     "…with validate-scenario-traceability.sh reporting 100% and exit 0 throughout"
#
# No such file had ever been written. Not in this repo's history, not in the template, not under any
# other name. So that sentence was not a report of a gate that failed to bite; it was a measurement
# attributed to an instrument that did not exist, and a reader had no way to tell those two silences
# apart. Spec 007bs built the instrument and corrected the citations. This is the instrument.
#
# WHAT IT CHECKS — both directions, because each catches a different lie:
#
#   uncovered  a row whose Status claims ✓ or ◐ but which no test under the reference roots names.
#              The map says the scenario is proven; nothing in the suite mentions it.
#   dangling   an SC-id a test names that is not a row in the map. The suite believes in a scenario
#              the map does not have — a typo, or a row deleted out from under a test.
#   duplicate  one id on more than one row. An id is a permanent handle (.claude/rules/scenarios.md),
#              so this is two scenarios wearing one name, and it makes both directions above
#              approximate: a reference cannot say which of the two it proves.
#   out-of-range
#              a reference to an SC-id BELOW the lowest id the map owns. Almost always the OTHER
#              SC- namespace: spec-kit's spec template numbers a spec's Success Criteria SC-001,
#              SC-002, ... with the same prefix scenario ids use, so a test citing its own spec's
#              criteria looks exactly like a test citing a scenario that does not exist. Measured
#              on one project: 387 of 458 spec.md files number criteria that way, and 41 of the
#              gate's 44 "dangling" ids were that and nothing else. Reported in its own bucket
#              rather than as dangling, because a list of 44 that is 41 false is a list nobody
#              reads — and the 3 real ones were invisible inside it.
#
#              THE SEPARATION IS ARITHMETIC, NOT DESIGN. It holds only while no spec numbers a
#              criterion up into the map's range, and on that same project one already had
#              (SC-1165, in a spec whose map block starts at SC-1170) — so that one stays
#              dangling, correctly, and is the standing evidence that the two namespaces need
#              separating at the source rather than told apart by a floor.
#
# A ☐ row is EXEMPT from coverage. It is mapped and not yet tested, which is a legitimate state for
# every scenario of every unbuilt spec; counting it as a failure would leave this gate permanently
# red on any project with a roadmap, and a gate that can never be green gets switched off. That is
# how the last one became a comment. A retired (struck, ~~SC-NNN~~) row is exempt from coverage too —
# nothing is expected to test a retired scenario — but its id still counts as REAL for the dangling
# check, because .claude/rules/scenarios.md makes an id a permanent handle that is never reused.
#
# ------------------------------------------------------------------------------------------------
# THE LOCALE TRAP — read this before "simplifying" the classification into one awk line.
#
# The natural way to classify delimited rows is awk. On macOS awk (version 20200816) under this
# developer's locale, awk's string EQUALITY operator says these three symbols are the same symbol:
#
#     $ printf 'a|✓\nb|◐\nc|☐\n' | awk -F'|' '$2=="✓"{print $1}'      # LANG=sv_SE.UTF-8
#     a
#     b
#     c
#     $ printf 'a|✓\nb|◐\nc|☐\n' | LC_ALL=C awk -F'|' '$2=="✓"{print $1}'
#     a
#
# It is specifically `==`, which goes through the locale's collation table; U+2713, U+25D0 and U+2610
# carry no distinguishing primary weight in the Swedish collation, so strcoll() calls them equal.
# Regex match ($2 ~ /✓/), index($2,"✓"), field splitting, shell `case`, `[ = ]` and `grep -F` are all
# byte-oriented and all correct. Only `==` lies.
#
# On the real map that one line selects 187 of 188 rows instead of 96 — every ☐ row and every struck
# row classified as a validated one. A gate built that way computes coverage over a denominator the
# map does not support and reports a clean run over a live gap: reporting 100% and exit 0 the whole
# time, which is the exact sentence this script exists to retire. The fix would have re-committed the
# defect it was written to fix.
#
# This is not hypothetical. The first draft of spec 007bs carried "62 uncovered, 88 of 150" in its
# own evidence table. Those numbers came from a scoping command that classified with awk `==` under
# the live shell; the true figures are 28 and 122 of 150. The wrong numbers survived into a written
# draft of the document arguing that these numbers go wrong.
#
# TWO defences, and neither is redundant:
#   1. LC_ALL=C is exported below — it protects any comparison a later maintainer adds without
#      reading this header.
#   2. The status decision is a shell `case`, never awk `==` — it protects against a caller that
#      exports a locale into a sub-invocation after the pin is read.
# scripts/test-validate-scenario-traceability.sh case 14 runs this gate under LANG=sv_SE.UTF-8 and
# checks its per-status counts against a `grep -c` oracle. A gate whose own tests only ever run under
# LC_ALL=C has not been tested on the machine it runs on.
# ------------------------------------------------------------------------------------------------
#
# WHAT IT DOES NOT DO: it never writes. It reads the map, reads the tests, and reports.
#
# Usage:
#   scripts/validate-scenario-traceability.sh                       # ./specs, roots discovered
#   scripts/validate-scenario-traceability.sh --dir path/to/specs
#   scripts/validate-scenario-traceability.sh --roots tests,src     # explicit; discovery is skipped
#   scripts/validate-scenario-traceability.sh --quiet               # totals + failures only
#
# THE REFERENCE ROOTS. With no --roots, the roots are DISCOVERED: the conventional test directories
# that actually exist at the top level of the project. With --roots, the caller's list is used
# verbatim and a root that does not exist is an error rather than something to look past. Which
# roots were used is always printed in the report's first line. See the `roots-discovery` region for
# the candidate list and for the two directories deliberately excluded from it.
#
# Exit codes — "I cannot answer" is never reported as "the answer is fine":
#   0  clean — nothing uncovered, nothing dangling
#   1  uncovered and/or dangling ids found
#   2  usage error
#   3  the map could not be read, the extractor refused entirely, or it yielded zero rows
#   4  no reference root to read — either one the caller NAMED does not exist, or discovery found
#      none of its candidates. Both are "I could not look", and neither is ever reported as clean.
#   5  checked, but part of the map was unreadable — never reported as clean
#   7  NOT APPLICABLE — the project has no scenario map at all. Distinct from 3,
#      which means a map exists and could not be read.
#   6  a duplicate id — one id naming more than one row. Split out of 1 because it is a
#      different kind of fact: an ambiguous handle breaks every consumer that resolves it
#      (spec_active.py, both PreToolUse guards, the archiver), where uncovered rows are a
#      backlog that is red on any project with a roadmap. Sharing one code made the
#      collision invisible behind a permanent red. A CALLER MUST TREAT 6 AS A VERDICT,
#      not as a failure to run.
#
# out-of-range does NOT fail the run. It is a collision between two naming conventions, not a defect
# in either the map or the suite, and there is nothing a reader could fix reference by reference. It
# is always PRINTED, because a bucket that is silent is a bucket that grows.
#
# Cross-platform: POSIX sh + POSIX awk + grep. Runs under macOS, Linux, and Git Bash/WSL.

# Defence 1 of 2 against the collation trap documented above. See defence 2 at `is_claimed`.
#
# The `>>> name` / `<<< name` markers below are sabotage targets. The harness swaps exactly one
# marked region at a time to prove which defence is carrying which case — a blind `sed` over the
# whole file could not tell "removed the pin" from "removed the pin and broke the parser".
# >>> locale-pin
LC_ALL=C
export LC_ALL
# <<< locale-pin

set -eu

SPECS_DIR=""
# Empty, not "tests". The default is DISCOVERED further down, once the project root is known — see
# the `roots-discovery` region. ROOTS_EXPLICIT is what keeps the two paths apart: a root the caller
# NAMED is a promise and must exist, a convention that happens to be absent is not.
ROOTS=""
ROOTS_EXPLICIT=0
QUIET=0

# Not configurable, and deliberately so: scenario-map-rows.sh hardcodes SC- in its row pattern, so a
# map using any other prefix extracts to zero rows. A --id-prefix flag here would let a caller ask
# for references to ids the extractor can never report as rows — every one of them dangling.
PREFIX="SC"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)       [ "$#" -ge 2 ] || { echo "--dir needs a path" >&2; exit 2; }; SPECS_DIR="$2"; shift 2 ;;
    --roots)     [ "$#" -ge 2 ] || { echo "--roots needs a value" >&2; exit 2; }; ROOTS="$2"; ROOTS_EXPLICIT=1; shift 2 ;;
    --quiet)     QUIET=1; shift ;;
    # Print the whole leading comment block rather than a hardcoded line range: this header will
    # grow, and a range silently truncates --help when it does (the project-maintenance.sh lesson).
    -h|--help)   awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *)           echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# scenario-map-rows.sh emits TAB-separated fields, and the tab is load-bearing: a scenario cell
# may contain a pipe (SC-436 quotes a formula-injection payload), so splitting on "|" pushes
# status into expected and the row stops counting as validated without anything erroring. Read
# that script's OUTPUT block before changing this.
TAB=$(printf '\t')

if [ -z "$SPECS_DIR" ]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
  SPECS_DIR="$ROOT/specs"
fi

if [ ! -d "$SPECS_DIR" ]; then
  echo "scenario-traceability: no specs directory at $SPECS_DIR" >&2
  exit 3
fi

PROJECT=$(CDPATH='' cd -- "$SPECS_DIR/.." && pwd)

# ------------------------------------------------------------------ the map, via the one predicate
# Sourced, not re-decided: five consumers already ask scenario-map-layout.sh where the rows live, and
# two of them disagreeing would be worse than either being wrong, because the disagreement is silent.
# shellcheck source=scripts/scenario-map-layout.sh
. "$HERE/scenario-map-layout.sh"
LAYOUT=$(scenario_map_layout "$PROJECT")

INDEX="$SPECS_DIR/SCENARIOS.md"
# NO MAP IS NOT A BROKEN MAP. Exit 3 means "the map could not be read, the
# extractor refused, or it yielded zero rows" -- a project whose map is damaged.
# A project that has never had one is a different fact: ighweld ships three specs
# and no scenarios, which is a legitimate state, and reporting it with the same
# code as a corrupt map makes a caller choose between treating a healthy project
# as broken or a broken one as healthy.
#
# Exit 7, and it says what to do about it rather than only what is absent. Same
# third-state discipline as rows H7t and 007br.
if [ ! -f "$INDEX" ]; then
  echo "scenario-traceability: NOT APPLICABLE — no scenario map at $INDEX." >&2
  echo "  A project with interactive behaviour should have one (.claude/rules/scenarios.md);" >&2
  echo "  a project without is a legitimate state and this is not a failure." >&2
  exit 7
fi

MAP_FILES="$INDEX"
if [ "$LAYOUT" = "split" ]; then
  for f in "$SPECS_DIR"/scenarios/*.md; do
    [ -f "$f" ] && MAP_FILES="$MAP_FILES
$f"
  done
fi
MAP_COUNT=$(printf '%s\n' "$MAP_FILES" | grep -c .)

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t scenario-traceability)
trap 'rm -rf "$TMP"' EXIT INT TERM

# ------------------------------------------------------------------------------ rows, via the one
# extractor. NOT a grep for bare ids: scenario-map-rows.sh anchors to five-column table rows, so
# prose mentions, flowchart labels and the SC2086 shellcheck lookalike cannot enter the id set. It
# also knows that a retired row is written ~~SC-NNN~~, which the obvious '^| SC-' pattern misses —
# and those are precisely the ids that must never be reused.
# --partial, and NOT through xargs. Two separate defects were fixed here; both were silent.
#
#   1. ALL-OR-NOTHING. Without --partial the extractor refuses the entire map when any ONE file has a
#      malformed row, and this gate turned that into `exit 3` having checked nothing. It did so for
#      over a year while 80 of 226 files were malformed — so neither the uncovered nor the dangling
#      direction was ever checked, which is the failure .claude/rules/scenarios.md names by name:
#      a gate nobody has watched fail is a report, not a gate.
#
#   2. xargs COULD NOT REPORT THE CHILD'S EXIT CODE ANYWAY. xargs collapses any child status in
#      1..125 to 123, so `exit 4` ("rows emitted, rows skipped") would have arrived here
#      indistinguishable from `exit 1` ("no readable input"). xargs is also free to SPLIT a long
#      argument list across several invocations, which would restart the extractor's table-context
#      state mid-map and silently drop the rows of any table whose header landed in the previous
#      batch. Building the argument list with `set --` removes both.
set --
OLDIFS=$IFS
IFS='
'
for f in $MAP_FILES; do [ -n "$f" ] && set -- "$@" "$f"; done
IFS=$OLDIFS

EXTRACT_RC=0
"$HERE/scenario-map-rows.sh" --partial "$@" > "$TMP/rows" 2>"$TMP/rows.err" || EXTRACT_RC=$?

PARTIAL_READ=0
if [ "$EXTRACT_RC" -eq 4 ]; then
  PARTIAL_READ=1
elif [ "$EXTRACT_RC" -ne 0 ]; then
  echo "scenario-traceability: scenario-map-rows.sh refused the map" >&2
  [ -s "$TMP/rows.err" ] && cat "$TMP/rows.err" >&2
  exit 3
fi

ROW_COUNT=$(grep -c . "$TMP/rows" || true)
if [ "$ROW_COUNT" -eq 0 ]; then
  # "0 of 0, all clear" is arithmetically clean and semantically empty. Reporting it as success is
  # the failure this script is named after.
  echo "scenario-traceability: the map yielded zero rows — nothing to check, and that is not a pass" >&2
  exit 3
fi

# The extractor promises six pipe-separated fields. If that ever stops being true, say so rather than
# silently mis-slicing the status column — a gate reading the wrong field is worse than no gate.
BADFIELDS=$(awk -F'\t' 'NF != 6 {c++} END {print c+0}' "$TMP/rows")
if [ "$BADFIELDS" -ne 0 ]; then
  echo "scenario-traceability: $BADFIELDS row(s) did not split into 6 fields — the extractor's format changed" >&2
  exit 3
fi

# ---------------------------------------------------------------------------------- classification
# Defence 2 of 2. Shell `case` on the status cell, by CONTAINMENT rather than an enumerated list of
# exact strings: `✓ *` is a validated row carrying a footnote (SC-155 today), not a third status, and
# an enumeration would need extending every time someone adds a marker — with silent exemption as the
# cost of forgetting.
#
# Deliberately a function, and deliberately marked: it is the single place the ✓/◐/☐ distinction is
# made, so it is the single place the collation trap could re-enter.
# >>> classify
is_claimed() { # <status-cell> — true when the row claims to be tested or validated
  case "$1" in
    *✓*|*◐*) return 0 ;;
  esac
  return 1
}
# <<< classify

: > "$TMP/claimed"
: > "$TMP/allids"
# The three fields this loop needs are the first, the fifth and the sixth, and they are cut out by
# suffix removal rather than by `IFS=<tab> read -r id kind scen expected status struck`. That reads
# better and is wrong: a tab is IFS WHITESPACE, so `read` collapses a run of them into one delimiter
# and an empty cell silently shifts every field after it — status would land in expected and the row
# would stop counting as claimed. The BADFIELDS guard above cannot see it, because awk with an
# explicit FS does NOT collapse, so the same line is six fields to awk and five to read. With "|" as
# the delimiter this could not happen; it is the cost of the delimiter change and it is paid here.
while IFS= read -r line; do
  id=${line%%"$TAB"*}
  [ -n "$id" ] || continue
  struck=${line##*"$TAB"}
  status=${line%"$TAB"*}; status=${status##*"$TAB"}
  printf '%s\n' "$id" >> "$TMP/allids"
  # >>> struck-exempt
  [ "$struck" = "1" ] && continue
  # <<< struck-exempt
  if is_claimed "$status"; then printf '%s\n' "$id" >> "$TMP/claimed"; fi
done < "$TMP/rows"

sort -u "$TMP/allids" -o "$TMP/allids"
sort -u "$TMP/claimed" -o "$TMP/claimed"

# Braces are load-bearing: bash decides where a variable name ends by the locale's notion of an
# identifier character, and under a UTF-8 locale "$TAB✓" parses as the variable TAB✓ — unbound,
# and with set -u that is an exit before a single row is counted. Under the LC_ALL=C pin above it
# parses as intended, so the bug is invisible until the pin is removed. The sabotage entry that
# removes the pin is what found this, which is the entry existing to prove the OTHER defence.
# Counted on the status cell's LEADING symbol, not on the whole cell. The status column is free
# text: "✓ validated", "◐ tested (IT-C-007)", "☐ mapped — needs the live pilot" are all real. An
# exact-cell match (${TAB}✓${TAB}) counts only the bare symbol, which on one real map left 165 rows
# in no bucket at all and printed a breakdown that did not add up to the row count — the summary
# line disagreeing with the classification two functions above it. index()==1 is the same leading-
# symbol rule is_claimed uses, so the two can no longer drift apart.
N_VALIDATED=$(awk -F'\t' 'index($5, "✓") == 1 {c++} END {print c+0}' "$TMP/rows")
N_TESTED=$(awk -F'\t' 'index($5, "◐") == 1 {c++} END {print c+0}' "$TMP/rows")
N_MAPPED=$(awk -F'\t' 'index($5, "☐") == 1 {c++} END {print c+0}' "$TMP/rows")
N_STRUCK=$(awk -F'\t' '$6 == "1" {c++} END {print c+0}' "$TMP/rows")

# >>> roots-discovery
# ------------------------------------------------------------------------------- the default roots
# DISCOVERED, never a constant. This read `ROOTS="tests"` for as long as the script existed, which is
# right on a project whose whole suite lives there and silently wrong on every project that keeps its
# browser tests anywhere else. On the project that found it, every Playwright spec lives in e2e/ and
# this gate had never read one: 37 rows reported uncovered, every one of them proven by a spec the
# gate could not see. The arithmetic closed exactly — the ids present in e2e/ and absent from tests/
# numbered 37, and they were the 37 it named — so this was not a gate finding a gap, it was a gate
# reporting the shape of its own blind spot.
#
# That is worse than it sounds. A gate permanently red for a reason outside both the map and the
# suite is a gate that gets switched off, and the header of this file records what that looks like:
# the last one became a comment, and the comment was then quoted as evidence.
#
# Same reasoning as the out-of-range floor two sections down, which derives itself from the map on
# every run so there is no constant to go stale. A per-project constant living in a fleet-wide file
# is wrong on every project it was not written for, and silent about it.
#
# A CANDIDATE IS NOT A ROOT UNTIL IT EXISTS, and an absent one is skipped rather than refused. Only
# a root the CALLER named can be missing, because only that is a promise — which is why the guard
# below stays exactly as it was and this region never touches it.
#
# WHAT IS DELIBERATELY ABSENT, and both exclusions are load-bearing:
#
#   specs/  The map names every id it owns. Admit it and every row is covered by its own map entry:
#           the gate reduced to a tautology, reporting clean forever, over itself. `spec` (RSpec's
#           convention) is excluded too rather than resting that exclusion on a singular/plural
#           distinction of one character — no Ruby project exists in this fleet to need it, and a
#           one-letter guard against a tautology is not a guard.
#
#   src/    A source comment naming an id is not a test. Counting one is the unbacked coverage claim
#           this gate exists to refuse — the same argument that prunes stale build output below. A
#           project that genuinely co-locates its tests can say `--roots src` and mean it.
#
# TOP LEVEL ONLY, no recursion: a nested test directory is in practice already inside one of these,
# and recursing would make the root set depend on how deep a tree happens to be. The `roots:` line in
# the report has to be something a reader can anticipate before running the command.
ROOTS_CANDIDATES="tests test e2e __tests__ cypress playwright"

# ----------------------------------------------------------- the per-project roots DECLARATION
# Discovery above is a fleet default and it is right for most projects. It is silently wrong for a
# project whose test trees are not top-level, and `src/` is deliberately not a candidate (a source
# comment naming an id is not a test), so such a project cannot be served by widening the list.
#
# ighweld keeps ~3,500 xUnit tests under src/welding/Welding.Api.Tests/ and ~1,345 vitest suites
# under src/welding/client/src/**/__tests__/. Discovery yielded `tests` alone, so 75 rows proven by
# those suites read as UNCOVERED — and, less obviously, SEVEN dangling ids stayed invisible, because
# an id named only by an unscanned test is not seen at all. That second direction was explicitly
# ruled out in writing ("the error is one-way") and measurement refuted it: 4 dangling under the
# narrow roots, 11 under the real ones.
#
# So a project may DECLARE its roots, in `specs/traceability-roots`: one root per line, `#` comments
# and blank lines ignored. Precedence, most specific first:
#
#   --roots            the caller's promise, for this one invocation
#   the declaration    the project's promise, for every invocation
#   discovery          the fleet default
#
# A DECLARED root that does not exist REFUSES, exactly as a --roots one does, via the same guard
# further down. That is the point of the distinction the guard already draws: discovery skips an
# absent candidate because a candidate is a guess, and both flags are promises. Nothing in that
# guard changed.
#
# The declaration cannot be a route to reporting clean over no evidence: a file that yields no roots
# falls through to the same refusal an empty discovery hits, rather than to a silent empty run.
#
# Additive by construction — a project without the file behaves exactly as it did before.
#
# The `>>> name` / `<<< name` markers make this region a sabotage target, like locale-pin,
# root-guard and roots-discovery above: the harness swaps exactly one marked region at a time so a
# red case proves WHICH defence carries it.
# >>> roots-declaration
ROOTS_DECL="$SPECS_DIR/traceability-roots"
ROOTS_DECLARED=0

if [ "$ROOTS_EXPLICIT" -eq 0 ] && [ -f "$ROOTS_DECL" ]; then
  DECL=""
  # Strip comments and blanks. No `read -r` loop with a pipe: this must work under `set -eu` on a
  # file whose last line has no newline, which a hand-edited config often does.
  for line in $(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ROOTS_DECL"); do
    [ -n "$line" ] || continue
    if [ -z "$DECL" ]; then DECL="$line"; else DECL="$DECL,$line"; fi
  done
  if [ -n "$DECL" ]; then
    ROOTS="$DECL"
    ROOTS_DECLARED=1
  else
    echo "scenario-traceability: $ROOTS_DECL exists but declares no roots" >&2
    echo "  Either list one root per line, or delete the file to fall back to discovery." >&2
    echo "  An empty declaration is not the same as no declaration, and must not read as clean." >&2
    exit 4
  fi
fi
# <<< roots-declaration

if [ "$ROOTS_EXPLICIT" -eq 0 ] && [ "$ROOTS_DECLARED" -eq 0 ]; then
  ROOTS=""
  # Iterated in the list's declared order, not by a glob: the printed `roots:` line is part of the
  # report and a test asserts on it, so it must not depend on filesystem enumeration order.
  for cand in $ROOTS_CANDIDATES; do
    [ -d "$PROJECT/$cand" ] || continue
    if [ -z "$ROOTS" ]; then ROOTS="$cand"; else ROOTS="$ROOTS,$cand"; fi
  done

  if [ -z "$ROOTS" ]; then
    # Not a warning, and not an empty run. No roots means no references, which renders either as
    # "every claimed scenario is uncovered" — catastrophic-looking, trivially caused — or, on a map
    # that claims nothing, as a clean run over no evidence at all. Both are the "0 of 0, all clear"
    # failure this script is named after, and neither may exit 0.
    #
    # Every candidate is named. "No reference root found" tells a reader that a gate failed and not
    # what would fix it, and a report a reader cannot act on is the thing this file refuses.
    echo "scenario-traceability: no reference root found under $PROJECT" >&2
    echo "  tried, in order: $ROOTS_CANDIDATES" >&2
    echo "  pass --roots explicitly if this project keeps its tests somewhere else." >&2
    exit 4
  fi
fi
# <<< roots-discovery

# ------------------------------------------------------------------------------------- references
# One tree walk emitting every id token, not one `grep -r` per id: 150 ids would be 150 walks.
: > "$TMP/refs"
OLDIFS=$IFS
IFS=,
for root in $ROOTS; do
  IFS=$OLDIFS
  [ -n "$root" ] || continue
  case "$root" in
    /*) rp="$root" ;;
    *)  rp="$PROJECT/$root" ;;
  esac
  # >>> root-guard
  if [ ! -d "$rp" ]; then
    # A missing root yields zero references, which renders as "every claimed scenario is uncovered" —
    # a catastrophic-looking report with a trivial cause. Silence here is the same class of defect
    # this whole script exists to remove.
    echo "scenario-traceability: reference root does not exist: $root (looked in $rp)" >&2
    exit 4
  fi
  # <<< root-guard
  # Match ids of ANY length. The keep-filter below used to be [0-9]{3} — see there.
  #
  # \b ON THE LEFT, and it is not decoration. Without it the pattern matches INSIDE a longer
  # identifier: a property reference "DESC-1" in a test reported a dangling SC-1 that no test ever
  # wrote. That is the harmless direction. The other one is not — a fixture named "DESC-741" would
  # have SILENTLY COVERED SC-741, and this gate exists to refuse exactly that kind of unbacked
  # coverage claim. Validated against known positives and negatives before it was believed:
  # SC-741, "SC-765" and "// SC-002." still match; DESC-1 and MISC-99 no longer do.
  #
  # \b AND [a-z]? ON THE RIGHT, and that half was missing until a project found it. A map is free
  # to insert a row between two allocated ids by suffixing a letter — SC-033b next to SC-033 — and
  # the row extractor has always accepted that. This one did not, so it read "SC-033b" in a test as
  # a reference to SC-033. Both directions are wrong at once, and they hide each other: SC-033b, a
  # rehearsal gate named in six places across two files, reported as UNCOVERED, while SC-033 was
  # reported covered on the evidence of a test that names a different scenario. The trailing \b is
  # what stops "SC-033abc" being read as SC-033a; it matches nothing, which is the safe answer.
  # BUILD OUTPUT IS PRUNED, and not only because it is slow (21.2 s -> 1.3 s on one repo whose
  # tests/ tree is 4.5 GB of which almost all is bin/obj). It is pruned because counting it is
  # WRONG. Every one of the 25 ids that a full walk found there and a pruned walk did not was inside
  # a stale Stryker mutation-report JSON under bin/Release/.../StrykerOutput/ — a two-month-old
  # snapshot quoting test source that no longer exists in the tree. Counting those means a DELETED
  # test still covers its scenario, on the evidence of a build artifact. A coverage claim backed by
  # nothing live is precisely the lie this gate was written to catch, so it must not be the gate
  # that tells it.
  # `-a`, NOT `-I`, and this is a defect that was live rather than theoretical.
  #
  # `-I` tells grep to skip binary files, and grep calls a file binary the moment it contains a
  # NUL. A destructive test suite is exactly the kind of file that has one: agentcrm's
  # create-agency.destructive.spec.ts carries a literal NUL inside its own hostile-input fixture
  # (`['a null byte', 'Agency\0name']`). Every scenario id cited only in that file was therefore
  # invisible to this gate, which reported them as claimed-but-uncovered — a gate wrong in the
  # direction that looks like diligence, so nobody questions it. Found on row A1, when SC-878 was
  # reported uncovered while the citation sat in plain sight on line 279 of that file.
  #
  # `-a` on its own is NOT the fix, and the first attempt at this proved it: with `-I` dropped and
  # nothing else changed, grep read the visual-regression PNGs as text and two of them contain
  # bytes that spell an id. The gate went from under-reporting coverage to inventing a dangling
  # reference — wrong in the other direction, and equally confident.
  #
  # So the images are excluded by NAME instead. `*-snapshots` directories hold nothing but PNGs,
  # and the extension list covers the rest. What is left is source, which `-a` now reads whether
  # or not it happens to contain a control byte.
  # >>> build-prune
  find "$rp" -type d \( -name bin -o -name obj -o -name node_modules -o -name TestResults \
       -o -name StrykerOutput -o -name playwright-report -o -name test-results -o -name dist \
       -o -name '*-snapshots' \) \
       -prune -o -type f \
       ! -name '*.png' ! -name '*.jpg' ! -name '*.jpeg' ! -name '*.gif' ! -name '*.webp' \
       ! -name '*.ico' ! -name '*.pdf' ! -name '*.zip' ! -name '*.webm' ! -name '*.mp4' \
       ! -name '*.woff' ! -name '*.woff2' ! -name '*.ttf' ! -name '*.otf' \
       -print0 2>/dev/null \
    | xargs -0 grep -hoaE "\\b${PREFIX}-[0-9]+[a-z]?\\b" 2>/dev/null >> "$TMP/refs" || true
  # <<< build-prune
  IFS=,
done
IFS=$OLDIFS

# ANY id length, not {3}. This filter used to keep only three-digit ids, which was right when it was
# written and silently wrong afterwards: once a map passes id 999 the four-digit rows are the
# majority, and on the map that found this it was discarding 1241 of the 1454 ids the tests actually
# name — 85% of the evidence — so the gate reported 179 of 2961 covered instead of 1316 of 3024.
# Nobody saw it, because the extractor was refusing the map long before this line ever ran. The `-o`
# match above is greedy, so the truncation the {3} was guarding against cannot occur anyway.
# >>> id-length-filter
grep -xE "${PREFIX}-[0-9]+[a-z]?" "$TMP/refs" 2>/dev/null | sort -u > "$TMP/refs.u" || : > "$TMP/refs.u"
# <<< id-length-filter

# --------------------------------------------------------------------------------- the two answers
comm -23 "$TMP/claimed" "$TMP/refs.u" > "$TMP/uncovered"
# >>> dangling
comm -13 "$TMP/allids"  "$TMP/refs.u" > "$TMP/dangling.all"
# <<< dangling

# >>> out-of-range
# Split the dangling set at the map's own floor. The floor is DERIVED from the map on every run, so
# it moves when the map does and there is no constant here to go stale. It is printed with the
# bucket for the same reason: a reader has to be able to see which rule reclassified what.
MAP_MIN=$(sed "s/^${PREFIX}-//" "$TMP/allids" | sort -n | head -1)
# The map's own DIGIT WIDTH, and it is the discriminator the floor could not be.
#
# A floor of "the map's lowest id" is useless on a map that starts at SC-001 — nothing can be
# below 1 — and that is the ordinary case, not a corner: msroute, film-i-vast and consultpilot
# all start there, and all three reported spec-kit Success Criteria (SC-01, SC-1, SC-02) as
# dangling scenario ids. The two namespaces are not separated by magnitude; they are separated
# by PADDING. This map's ids are zero-padded to a fixed width and spec-kit's criteria are not,
# so a reference with FEWER digits than the map's narrowest id belongs to the other sequence.
#
# Derived from the map on every run, exactly like the floor, so there is no constant to go stale.
# Both rules apply: width catches SC-01 against a 3-digit map, the floor still catches a genuinely
# low id on a map that starts high.
MAP_WIDTH=$(sed "s/^${PREFIX}-//" "$TMP/allids" | sed 's/[^0-9].*$//' | awk '{ print length($0) }' | sort -n | head -1)
if [ -n "$MAP_MIN" ]; then
  awk -v pre="$PREFIX" -v floor="$MAP_MIN" -v width="${MAP_WIDTH:-0}" '
    {
      n = $0; sub("^" pre "-", "", n)
      d = n; sub(/[^0-9].*$/, "", d)          # digits only, so 1404b measures as 1404
      if (length(d) > 0 && width > 0 && length(d) < width) { print > "/dev/stderr"; next }
      if (n + 0 < floor + 0) { print > "/dev/stderr"; next }
      print
    }
  ' "$TMP/dangling.all" > "$TMP/dangling" 2> "$TMP/outofrange"
else
  cp "$TMP/dangling.all" "$TMP/dangling"
  : > "$TMP/outofrange"
fi
# <<< out-of-range
N_OOR=$(grep -c . "$TMP/outofrange" || true)

# >>> duplicate-check
# A THIRD answer, and it is not about tests at all. .claude/rules/scenarios.md makes an id a
# permanent handle that is never reused, so one id on two rows is not a backlog item — it is two
# scenarios wearing one name, and every number above it silently becomes an approximation: the
# uncovered list cannot say WHICH of the two a test reference proves, and `sort -u` on the claimed
# set quietly counts them once. Reported like dangling rather than like uncovered, for the reason
# project-maintenance.sh gives: uncovered is a backlog, this is a mistake, and it is zero on a
# healthy map. It went unseen here because scenario-map-rows.sh does check uniqueness — but only
# under --summary, which this gate does not use and nothing else calls. agentcrm had 104 of them,
# one contiguous block allocated twice by two developers working different specs in parallel.
cut -f1 "$TMP/rows" | sort | uniq -d > "$TMP/duplicate"
# <<< duplicate-check
N_DUP=$(grep -c . "$TMP/duplicate" || true)

N_CLAIMED=$(grep -c . "$TMP/claimed" || true)
N_UNCOV=$(grep -c . "$TMP/uncovered" || true)
N_DANGL=$(grep -c . "$TMP/dangling" || true)
N_COVERED=$((N_CLAIMED - N_UNCOV))

# ----------------------------------------------------------------------------------------- report
row_detail() { # <id> — echo "  ID  status  scenario"
  awk -F'\t' -v want="$1" '$1 == want {printf "  %s  %s  %s\n", $1, $5, $3; exit}' "$TMP/rows"
}

# Say WHERE the roots came from, not just what they are. A reader looking at a coverage figure that
# seems too low needs to know whether they are seeing a project's declared roots or the fleet
# default having guessed — which is the exact confusion that let ighweld report 443 of 814 for as
# long as it did.
case "$ROOTS_EXPLICIT$ROOTS_DECLARED" in
  1*) ROOTS_SRC=" (--roots)" ;;
  01) ROOTS_SRC=" (declared in specs/traceability-roots)" ;;
  *)  ROOTS_SRC=" (discovered)" ;;
esac
echo "scenario traceability — $LAYOUT layout, $MAP_COUNT map file(s), roots: $ROOTS$ROOTS_SRC"
echo

if [ "$N_UNCOV" -gt 0 ]; then
  echo "uncovered — the row claims ✓/◐ but no test under the roots names it ($N_UNCOV):"
  if [ "$QUIET" -eq 0 ]; then
    while read -r id; do [ -n "$id" ] && row_detail "$id"; done < "$TMP/uncovered"
  fi
  echo
fi

if [ "$N_DANGL" -gt 0 ]; then
  echo "dangling — a test names an id the map does not have ($N_DANGL):"
  if [ "$QUIET" -eq 0 ]; then
    while read -r id; do [ -n "$id" ] && echo "  $id"; done < "$TMP/dangling"
  fi
  echo
fi

if [ "$N_OOR" -gt 0 ]; then
  echo "out-of-range — narrower than this map's ${MAP_WIDTH}-digit ids, or below ${PREFIX}-${MAP_MIN} ($N_OOR):"
  echo "  Almost certainly a spec's own Success Criteria, which spec-kit numbers with the same"
  echo "  ${PREFIX}- prefix. Not counted as dangling, and not a failure. See --help."
  if [ "$QUIET" -eq 0 ]; then
    while read -r id; do [ -n "$id" ] && echo "  $id"; done < "$TMP/outofrange"
  fi
  echo
fi

if [ "$N_DUP" -gt 0 ]; then
  echo "duplicate — one id on more than one row; an id is a permanent handle ($N_DUP):"
  if [ "$QUIET" -eq 0 ]; then
    while read -r id; do
      [ -n "$id" ] || continue
      # Every occurrence, not the first: the point is that they are different scenarios.
      awk -F'\t' -v want="$id" '$1 == want {printf "  %s  %s  %s\n", $1, $5, $3}' "$TMP/rows"
    done < "$TMP/duplicate"
  fi
  echo
fi

# BOTH numbers, never a bare percentage. "100%" with its denominator dropped is the sentence that
# started spec 007bs; a fraction that carries its denominator cannot be quoted into a claim about a
# different one.
echo "coverage: $N_COVERED of $N_CLAIMED claimed rows referenced by a test"
echo "  ($ROW_COUNT rows: $N_VALIDATED ✓ · $N_TESTED ◐ · $N_MAPPED ☐ exempt · $N_STRUCK retired exempt)"

# >>> partial-exit
if [ "$PARTIAL_READ" -eq 1 ]; then
  # "Clean over what I could read" reported as clean is the defect --partial exists to remove, so a
  # partial read gets its own code and can never be 0. It is reported AFTER the numbers, because the
  # numbers are still worth having — they are just not the whole map.
  echo "scenario-traceability: part of the map was unreadable (see above) — this reading is partial" >&2
  exit 5
fi
# <<< partial-exit

[ "$N_UNCOV" -eq 0 ] && [ "$N_DANGL" -eq 0 ] && [ "$N_DUP" -eq 0 ] && exit 0

# A DUPLICATE id is a different kind of fact from an uncovered row, and it used to share `exit 1`
# with it. An id naming two rows breaks the handle every consumer resolves — spec_active.py, both
# PreToolUse guards, the archiver — whereas uncovered rows are a backlog that is red on any project
# with a roadmap. Sharing one code meant the collision was invisible behind a permanent red, which
# is what row 007 recorded. Exit 6 says "an id is ambiguous"; exit 1 keeps its old meaning.
[ "$N_DUP" -gt 0 ] && exit 6
exit 1
