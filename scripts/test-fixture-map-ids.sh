#!/bin/sh
# test-fixture-map-ids.sh — harness for scripts/validate-fixture-map-ids.sh.
#
# WHY THIS EXISTS. The gate's job is to refuse something that looks completely ordinary — an id
# written in a test fixture — so the only way to trust it is to watch it refuse, and to watch it
# NOT refuse the neighbouring shapes that are fine. Half the cases below are the second kind. A gate
# that fired on every id in scripts/ would be turned off within a week, and the ids it would fire on
# are the ones that make the whole traceability scheme work.
#
# EVERYTHING RUNS IN A SANDBOX. The gate is driven with --map and --root against a throwaway tree,
# never against the repository it lives in. That is not fastidiousness: a sibling harness in this
# family drives the real runner against the real scripts/ directory, deleting registered gates to see
# what happens, and a killed run has left registered gates missing from the working tree. A harness
# whose subject is the tree it runs in can lose the tree.
#
# IDS ARE COMPOSED, NEVER SPELLED. A literal id here that a project's map owns would falsely trace
# that scenario through the id-accounting gate; one it does not own becomes an orphan reference and
# fails the same gate from the other side. There is no safe literal, so the prefix is a variable and
# the digits are text — the shape neither gate's pattern matches.
#
# Run:  sh scripts/test-fixture-map-ids.sh
# Exit: 0 all cases pass · 1 one or more failed
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
GATE="$HERE/validate-fixture-map-ids.sh"

FAILED=0
ok()  { printf '  ok:   %s\n' "$1"; }
bad() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }

[ -f "$GATE" ] || { echo "gate under test not found: $GATE" >&2; exit 2; }

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t fixmapids)
trap 'rm -rf "$TMP"' EXIT INT TERM

P="SC-"
OWNED_A="${P}9999"; OWNED_B="${P}9998"; RETIRED="${P}9997"
FREE="${P}9990"; WIDE="${P}99991"

# One sandbox map, reused. It owns three ids; FREE and WIDE are deliberately absent from it, because
# the gate's whole discrimination is "does the map own this", not "is this shaped like an id".
MAP="$TMP/SCENARIOS.md"
{ printf '# Scenario map\n\n## Actor: User\n\n### Feature: Thing   (spec: 001-thing)\n\n'
  printf '| ID | Type | Scenario | Expected outcome | Status |\n'
  printf '|----|------|----------|------------------|--------|\n'
  printf '| %s | happy | a real scenario | a real outcome | ✓ |\n' "$OWNED_A"
  printf '| %s | edge  | another one     | another outcome | ◐ |\n' "$OWNED_B"
  printf '| ~~%s~~ | happy | a retired one | its id stays reserved | ☐ |\n' "$RETIRED"
} > "$MAP"

# run_gate <root> — set OUT and RC. Deliberately NOT `OUT=$(run_gate ...)`: a command substitution is
# a subshell, so an rc assigned inside it never reaches the caller and `set -u` turns the read into a
# crash. That crash is the lucky version; the unlucky one is a stale RC from the previous case, which
# would make a case pass by inheriting an earlier verdict.
run_gate() {
  RC=0
  OUT=$(sh "$GATE" --map "$MAP" --root "$1" 2>&1) || RC=$?
}

# fresh_root <name> — an empty sandbox scripts/ directory.
fresh_root() { mkdir -p "$TMP/$1"; printf '%s' "$TMP/$1"; }

# `case`, never `printf | grep -q`: grep exits at the first match, printf dies of SIGPIPE, and under
# pipefail the pipeline returns 141 — a true claim read as false. This project has a gate that
# refuses that idiom in exactly these files.
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

printf '== validate-fixture-map-ids ==\n'

# --- C1: the defect this gate exists for -------------------------------------------------------
# A harness that writes a probe map out of ids the real map owns. Three occurrences on three lines,
# the shape found in the wild.
R=$(fresh_root c1)
{ printf '#!/bin/sh\n# a harness that writes a probe map\n'
  printf "cat > \"\$TMP/probe.md\" <<'MAP'\n"
  printf '| %s | happy | probe | probe outcome | ✓ |\n' "$OWNED_A"
  printf '| %s | edge  | probe | probe outcome | ◐ |\n' "$OWNED_B"
  printf 'And a sentence naming %s, which is fixture text all the same.\n' "$RETIRED"
  printf 'MAP\n'
  printf 'expect_row "$TMP/probe.md" %s\n' "$OWNED_A"
} > "$R/test-thing.sh"
run_gate "$R"
_n=$(printf '%s\n' "$OUT" | grep -c 'test-thing.sh:')
# THREE fixture occurrences, and the assertion argument on the last line is NOT one of them — it is a
# label, and labels are how a test binds to the map. A count of four here would mean the gate had
# started refusing the tracing mechanism.
if [ "$RC" -eq 1 ] && [ "$_n" -eq 3 ]; then
  ok 'a fixture map built from owned ids is refused, every occurrence named'
else
  bad 'a fixture map built from owned ids is refused, every occurrence named' "rc=$RC named=$_n want rc=1 named=3"
fi

# The occurrences carry a LINE, not just a filename. A finding a reader cannot navigate to is a
# finding that gets skimmed — the failure mode the sibling row H7az spent itself on.
# The expected line is READ OUT OF THE FIXTURE, not hardcoded. A hardcoded number goes stale the
# moment anyone adds a line to the fixture above it, and it goes stale by passing for the wrong
# reason exactly as often as by failing.
_wantline=$(grep -n -- "$OWNED_B" "$R/test-thing.sh" | head -1 | cut -d: -f1)
if contains "$OUT" "test-thing.sh:${_wantline}	${OWNED_B}"; then
  ok 'each finding names file, line and id'
else
  bad 'each finding names file, line and id' "[$OUT]"
fi

# --- C2: the converted shape passes --------------------------------------------------------------
R=$(fresh_root c2)
{ printf '#!/bin/sh\n'
  printf '. "$SCRIPT_DIR/scenario-probe-ids.sh"\n'
  printf "sed \"\$SUBST\" > \"\$TMP/probe.md\" <<'MAP'\n"
  printf '| @ID1@ | happy | probe | probe outcome | ✓ |\n'
  printf 'MAP\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 0 ]; then
  ok 'a converted harness with placeholder ids is clean'
else
  bad 'a converted harness with placeholder ids is clean' "rc=$RC [$OUT]"
fi

# --- C3: an id the map does NOT own is fine -------------------------------------------------------
# The gate is about COLLISION, not about the letters SC. A fixture id outside the map's allocation
# binds nothing, and refusing it would leave a harness with no legal way to write a map at all.
R=$(fresh_root c3)
{ printf '#!/bin/sh\n'
  printf '| %s | happy | probe | probe outcome | ✓ |\n' "$FREE"
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 0 ]; then
  ok 'an id the map does not own is not a finding'
else
  bad 'an id the map does not own is not a finding' "rc=$RC [$OUT]"
fi

# --- C4: a RETIRED id is still owned ---------------------------------------------------------------
# An id is a permanent handle that is never reused, so a struck row's number is occupied forever. A
# fixture taking it collides with a row that still exists and is still read.
R=$(fresh_root c4)
{ printf '#!/bin/sh\n'
  printf '| %s | happy | probe | probe outcome | ✓ |\n' "$RETIRED"
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 1 ] && contains "$OUT" "$RETIRED"; then
  ok 'a retired row still owns its id, so a fixture taking it is refused'
else
  bad 'a retired row still owns its id, so a fixture taking it is refused' "rc=$RC [$OUT]"
fi

# --- C5: prose inside a fixture-bearing harness ------------------------------------------------------
# The exact live defect: the id sat in a sentence, not in a table cell, and the sentence existed to
# prove that sentences are not rows. A line-scoped rule would have walked straight past it.
R=$(fresh_root c5)
{ printf '#!/bin/sh\n'
  printf "cat > \"\$TMP/probe.md\" <<'MAP'\n"
  printf '| @ID1@ | happy | probe | probe outcome | ✓ |\n'
  printf 'Some prose that mentions %s without being a row.\n' "$OWNED_B"
  printf 'MAP\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 1 ] && contains "$OUT" "$OWNED_B"; then
  ok 'an owned id in fixture PROSE is refused, not only in a cell'
else
  bad 'an owned id in fixture PROSE is refused, not only in a cell' "rc=$RC [$OUT]"
fi

# --- C5b: a SECOND heredoc in the same file is fixture text too --------------------------------------
# A map fixture is written in pieces. The split layout has an index heredoc whose rows are feature
# names, not ids, so a per-heredoc rule reads it as "not a map" — and walked past two live bindings
# in the file this row was written about. The rule is per FILE for that reason.
R=$(fresh_root c5b)
{ printf '#!/bin/sh\n'
  printf "cat > \"\$TMP/probe.md\" <<'MAP'\n"
  printf '| @ID1@ | happy | probe | probe outcome | ✓ |\n'
  printf 'MAP\n'
  printf "cat > \"\$TMP/index.md\" <<'INDEX'\n"
  printf '| Feature | Spec | Scenarios | Status |\n'
  printf '| Alpha | 001-alpha | [%s](scenarios/001-alpha.md) | 1 ✓ |\n' "$OWNED_B"
  printf 'INDEX\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 1 ] && contains "$OUT" "$OWNED_B"; then
  ok 'a second heredoc in a map-writing file is fixture text as well'
else
  bad 'a second heredoc in a map-writing file is fixture text as well' "rc=$RC [$OUT]"
fi

# --- C6: prose OUTSIDE the population is left alone -----------------------------------------------
# The boundary, and it is deliberate. Naming the scenario a case asserts is how a test binds to the
# map; a gate that refused that would be refusing the mechanism. Whether a PROSE mention in an
# ordinary harness should count as a reference at all is a real question and a different one.
R=$(fresh_root c6)
{ printf '#!/bin/sh\n'
  printf '# this harness asserts scenario %s and embeds no map at all\n' "$OWNED_A"
  printf 'echo "  ok  the thing works (%s)"\n' "$OWNED_B"
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 0 ]; then
  ok 'an assertion label in a harness with no fixture map is not a finding'
else
  bad 'an assertion label in a harness with no fixture map is not a finding' "rc=$RC [$OUT]"
fi

# --- C7: a converted harness does not fall out of scope ------------------------------------------
# THE LOAD-BEARING ONE, and the reason the row pattern accepts @IDn@ as well as a literal id. Once a
# harness is fixed its fixture rows are placeholders; a rule that recognised only literal rows would
# stop watching the one file most likely to regress, and would report clean for the same reason a
# deleted gate does. Here the placeholder row keeps the file in scope and the owned id in the
# fixture prose beside it is still refused.
R=$(fresh_root c7)
{ printf '#!/bin/sh\n'
  printf '. "$SCRIPT_DIR/scenario-probe-ids.sh"\n'
  printf "sed \"\$SUBST\" > \"\$TMP/probe.md\" <<'MAP'\n"
  printf '| @ID1@ | happy | probe | probe outcome | ✓ |\n'
  printf 'and someone later added a sentence naming %s\n' "$OWNED_A"
  printf 'MAP\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 1 ] && contains "$OUT" "$OWNED_A"; then
  ok 'a converted harness stays in scope through its placeholder rows'
else
  bad 'a converted harness stays in scope through its placeholder rows' "rc=$RC [$OUT]"
fi

# --- C7b: a comment is not fixture text, even in a fixture harness ----------------------------------
# The boundary this gate does NOT cross, and the first draft crossed it. File-scoped, it condemned 60
# assertion labels in one harness on its first honest run — a gate whose opening verdict is "your
# tracing scheme is the bug" has misidentified the bug. Whether a prose id anywhere in scripts/ should
# count as a reference is a real question with a different answer; it is not this one.
R=$(fresh_root c7b)
{ printf '#!/bin/sh\n'
  printf '# ids are derived here; %s is named only to explain why\n' "$OWNED_A"
  printf "sed \"\$SUBST\" > \"\$TMP/probe.md\" <<'MAP'\n"
  printf '| @ID1@ | happy | probe | probe outcome | ✓ |\n'
  printf 'MAP\n'
  printf 'echo "  ok  the thing works (%s)"\n' "$OWNED_B"
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 0 ]; then
  ok 'a comment and an assertion label are not fixture text'
else
  bad 'a comment and an assertion label are not fixture text' "rc=$RC [$OUT]"
fi

# --- C8: no map is NOT RUN, never clean -------------------------------------------------------------
R=$(fresh_root c8)
printf '#!/bin/sh\ntrue\n' > "$R/test-thing.sh"
RC=0
OUT=$(sh "$GATE" --map "$TMP/there-is-no-map.md" --root "$R" 2>&1) || RC=$?
if [ "$RC" -eq 3 ] && contains "$OUT" "NOT RUN" && ! contains "$OUT" "clean"; then
  ok 'no map reports NOT RUN and never the word clean'
else
  bad 'no map reports NOT RUN and never the word clean' "rc=$RC [$OUT]"
fi

# --- C9: a map that yields zero rows is NOT RUN, not an empty pass ------------------------------------
# "0 owned ids, nothing can collide, clean" is arithmetically true and semantically empty. A map file
# that parses to nothing is an unreadable map, not a project without scenarios.
printf '# Scenario map\n\nNo rows here at all.\n' > "$TMP/norows.md"
RC=0
OUT=$(sh "$GATE" --map "$TMP/norows.md" --root "$R" 2>&1) || RC=$?
if [ "$RC" -eq 3 ] && contains "$OUT" "NOT RUN" && ! contains "$OUT" "clean"; then
  ok 'a map with zero rows reports NOT RUN, not a clean run'
else
  bad 'a map with zero rows reports NOT RUN, not a clean run' "rc=$RC [$OUT]"
fi

# --- C10: a missing scan root is NOT RUN ---------------------------------------------------------------
RC=0
OUT=$(sh "$GATE" --map "$MAP" --root "$TMP/there-is-no-root" 2>&1) || RC=$?
if [ "$RC" -eq 3 ]; then
  ok 'a missing scan root reports NOT RUN'
else
  bad 'a missing scan root reports NOT RUN' "rc=$RC [$OUT]"
fi

# --- C11: a wider token is not read as its own first four digits -----------------------------------------
# Matching four digits directly would truncate a five-digit token and invent a collision with a real
# scenario — the same trap the coverage gate documents at its reference filter.
R=$(fresh_root c11)
{ printf '#!/bin/sh\n'
  printf '| %s | happy | probe | probe outcome | ✓ |\n' "$OWNED_A"
  printf '# a wider token: %s\n' "$WIDE"
} > "$R/test-thing.sh"
run_gate "$R"
_n=$(printf '%s\n' "$OUT" | grep -c 'test-thing.sh:')
if [ "$RC" -eq 1 ] && [ "$_n" -eq 1 ]; then
  ok 'a five-digit token is not read as an owned four-digit id'
else
  bad 'a five-digit token is not read as an owned four-digit id' "rc=$RC named=$_n want 1"
fi

# --- C12: the gate and its own harness are exempt ----------------------------------------------------
# Both have to be able to spell the shapes they describe. Without the exemption the gate refuses
# itself and there is no way to document what it refuses.
R=$(fresh_root c12)
cp "$GATE" "$R/validate-fixture-map-ids.sh"
{ printf '#!/bin/sh\n'
  printf '| %s | happy | an example inside the harness itself | it is exempt | ✓ |\n' "$OWNED_A"
} > "$R/test-fixture-map-ids.sh"
run_gate "$R"
if [ "$RC" -eq 0 ]; then
  ok 'the gate and its own harness are exempt from their own rule'
else
  bad 'the gate and its own harness are exempt from their own rule' "rc=$RC [$OUT]"
fi

# --- C13b: the sync manifest is not a harness ---------------------------------------------------------
# It lists every CORE filename and it names ids in its own comments. An earlier draft keyed the
# population on "mentions the helper" and swept it in, so the clean line claimed one more harness than
# it examined — an overstatement of what was checked, which is the direction that reads as
# reassurance. Writing a map row is what makes a file a fixture harness; naming things is not.
R=$(fresh_root c13b)
{ printf '#!/bin/sh\n'
  printf 'CORE_SCRIPTS="a.sh scenario-probe-ids.sh b.sh"\n'
  printf '# this manifest mentions %s and is not a harness\n' "$OWNED_A"
} > "$R/manifest.sh"
run_gate "$R"
if [ "$RC" -eq 0 ] && contains "$OUT" "0 fixture-map harness"; then
  ok 'a manifest that names ids and the helper is not in the population'
else
  bad 'a manifest that names ids and the helper is not in the population' "rc=$RC [$OUT]"
fi

# --- C13c: a printf-built probe map with derived ids is clean --------------------------------------
# The third way a harness in this family writes a map: no heredoc at all, a format string with the id
# substituted in. It has been doing that correctly for a year, and a gate that flagged it would be
# flagging the one file that already got this right.
R=$(fresh_root c13c)
{ printf '#!/bin/sh\n'
  printf "printf '| %%%%s | happy | probe: an unbound row | it must fail the gate | ☐ |\\n' \"\$UNBOUND\"\n"
  printf 'echo "  ok    an unbound row is refused (%s)"\n' "$OWNED_A"
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 0 ]; then
  ok 'a printf-built probe map with a derived id is clean'
else
  bad 'a printf-built probe map with a derived id is clean' "rc=$RC [$OUT]"
fi

# --- C14: a clean run says what it looked at -----------------------------------------------------------
# A bare "clean" is the sentence this family of gates exists to retire. The population size is what
# separates "checked four harnesses and found nothing" from "found no harnesses".
R=$(fresh_root c13)
{ printf '#!/bin/sh\n'
  printf '| %s | happy | probe | probe outcome | ✓ |\n' "$FREE"
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 0 ] && contains "$OUT" "1 fixture-map harness"; then
  ok 'a clean run names how many harnesses it examined'
else
  bad 'a clean run names how many harnesses it examined' "rc=$RC [$OUT]"
fi

# --- C15: R3 — a DECORATED id in a comment is refused ------------------------------------------------
# The rule H7bi added, and the reason it is not the prose carve-out: this id is not merely named, it
# is displayed AS A ROW FORM. Note the sandbox file writes no fixture row at all — R3 scans the whole
# root, because two of the three real files that carry this shape are not fixture harnesses.
R=$(fresh_root c15)
{ printf '#!/bin/sh\n'
  printf '# a bolded id is how some maps write theirs: **%s**\n' "$OWNED_A"
  printf 'true\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 1 ] && contains "$OUT" "$OWNED_A" && contains "$OUT" "map syntax in a comment"; then
  ok 'a decorated id in a comment is refused'
else
  bad 'a decorated id in a comment is refused' "rc=$RC [$OUT]"
fi

# --- C15b: R3 — a PIPE-CELLED id in a comment is refused, and the whole line is reported -------------
# The second marker, and the reason every id on the line is reported rather than only the marked one:
# the renumber form decorates the retired id and leaves the live one bare, so a rule that reports the
# decorated half tells you to fix half a line.
R=$(fresh_root c15b)
{ printf '#!/bin/sh\n'
  printf '# rows are written `| ~~%s~~ %s |` when renumbered\n' "$RETIRED" "$OWNED_B"
  printf 'true\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 1 ] && contains "$OUT" "$RETIRED" && contains "$OUT" "$OWNED_B"; then
  ok 'a pipe-celled comment reports every id on the line, not just the decorated one'
else
  bad 'a pipe-celled comment reports every id on the line, not just the decorated one' "rc=$RC [$OUT]"
fi

# --- C15b2: R3 — an UNDECORATED id in a pipe cell is refused ----------------------------------------
# The pipe marker on its own. Without this case the pipe branch is unfalsifiable: C15b's fixture is
# struck as well as celled, so the decoration marker fires first and turning the pipe branch off
# reddens nothing. Measured — the control experiment that found this is why the case exists. The
# shape is real: the accounting gate's own header quotes a plain `| id |` row twice.
R=$(fresh_root c15b2)
{ printf '#!/bin/sh\n'
  printf '# the old pattern matched the row `| %s |` and truncated it\n' "$OWNED_A"
  printf 'true\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 1 ] && contains "$OUT" "$OWNED_A"; then
  ok 'an undecorated id in a pipe cell is refused'
else
  bad 'an undecorated id in a pipe cell is refused' "rc=$RC [$OUT]"
fi

# --- C15c: R3 does NOT touch a bare id in prose ------------------------------------------------------
# The boundary. C7b asserts this for a fixture harness; this asserts it for R3, whose scan root is
# every file. If this case ever goes red, R3 has grown into the rule the gate spent a measurement
# refusing: 261 ids in the carving project have every reference in a comment, and all are correct.
R=$(fresh_root c15c)
{ printf '#!/bin/sh\n'
  printf '# Covers: %s %s — and %s is named here only to explain why\n' "$OWNED_A" "$OWNED_B" "$RETIRED"
  printf '# --- case 3: the thing works (%s) ---\n' "$OWNED_A"
  printf 'true\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 0 ]; then
  ok 'a bare id in prose is not map syntax'
else
  bad 'a bare id in prose is not map syntax' "rc=$RC [$OUT]"
fi

# --- C15d: R3 has a verdict with NO MAP, and it is a finding, not NOT RUN ----------------------------
# FR-004. The template repo has no map and is where these CORE files are authored; a gate that
# protects the consumer and not the author is backwards. R3 consults no owned set, so nothing stops
# it. C8 still holds: no map AND no R3 finding is still NOT RUN, and still never the word clean.
R=$(fresh_root c15d)
{ printf '#!/bin/sh\n'
  printf '# a bolded id: **%s**\n' "$OWNED_A"
  printf 'true\n'
} > "$R/test-thing.sh"
RC=0
OUT=$(sh "$GATE" --map "$TMP/there-is-no-map.md" --root "$R" 2>&1) || RC=$?
if [ "$RC" -eq 1 ] && contains "$OUT" "$OWNED_A" && ! contains "$OUT" "NOT RUN"; then
  ok 'with no map at all, R3 still reports — a finding, not NOT RUN'
else
  bad 'with no map at all, R3 still reports — a finding, not NOT RUN' "rc=$RC [$OUT]"
fi

# --- C15e: R3 does not read a shellcheck code as a scenario id ---------------------------------------
# The discriminator is the hyphen plus 3-4 digits, taken from the accounting gate so two patterns that
# claim to be the same one do not quietly disagree. A disable directive is decorated markdown often
# enough to matter.
R=$(fresh_root c15e)
{ printf '#!/bin/sh\n'
  printf '# see **SC2086** and | SC2154 | for why the quotes are there\n'
  printf 'true\n'
} > "$R/test-thing.sh"
run_gate "$R"
if [ "$RC" -eq 0 ]; then
  ok 'a shellcheck code is not a scenario id'
else
  bad 'a shellcheck code is not a scenario id' "rc=$RC [$OUT]"
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf 'fixture-map-ids: all cases pass\n'
  exit 0
fi
printf 'fixture-map-ids: %d case(s) failed\n' "$FAILED"
exit 1
