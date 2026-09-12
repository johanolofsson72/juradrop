#!/bin/sh
# test-scenario-probe-ids.sh — harness for scripts/scenario-probe-ids.sh.
#
# WHY THIS EXISTS. The helper is the single place "which ids are free" is decided, and three
# harnesses read through it. A defect here is silent in all of them at once and shows up as the
# thing the helper was written to prevent — a fixture id that collides with a real scenario — which
# is precisely the failure nobody notices, because a colliding fixture still passes.
#
# The cases are the ones that were wrong, or latent, in the code this was extracted from:
#
#   - a RETIRED row (~~SC-NNNN~~) occupies its number. The original pattern anchored on `^| SC-`
#     and missed strike marks; it was harmless only because that map carried no retired row.
#   - a SUFFIXED id (a number plus a trailing letter, a real spelling in at least one map)
#     occupies its stem's number. Two handles differing by a letter must
#     not leave the digits between them looking free.
#   - a MISSING map yields an empty owned set rather than an error. The template ships no scenario
#     map, and a harness that refused to build fixtures there would refuse over an absent file it
#     only reads to avoid.
#   - EXHAUSTION returns short rather than looping, wrapping, or reaching below the window. The
#     caller must be able to see that it got fewer than it asked for.
#
# Run:  sh scripts/test-scenario-probe-ids.sh
# Exit: 0 all cases pass · 1 one or more failed
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/scenario-probe-ids.sh
. "$HERE/scenario-probe-ids.sh"

FAILED=0
ok()  { printf '  ok:   %s\n' "$1"; }
bad() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }

# IDS ARE COMPOSED, NEVER SPELLED — and here the reason is the mirror image of the one in the helper.
# A literal id in this file that the project's map DOES own would falsely trace that scenario; one it
# does NOT own becomes an ORPHAN reference and fails the id-accounting gate on the way past. There is
# no safe literal: both directions are findings, they are just findings in different gates. So the
# prefix is a variable and the digits are text, which matches neither gate's id pattern.
#
# The numbers are at the top of the four-digit space because these are also FIXTURE ids inside the
# sandbox maps below, and the top of the window is where no real map allocates. A harness that broke
# its own subject's rule while testing it would be the joke this row is about.
P="SC-"
TOP="${P}9999"; TOP1="${P}9998"; TOP2="${P}9997"; TOP3="${P}9996"; TOP4="${P}9995"

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t scenprobe)
trap 'rm -rf "$TMP"' EXIT INT TERM

printf '== scenario-probe-ids ==\n'

# --- descending order, off the top of the window -------------------------------------------
: > "$TMP/empty.md"
_got=$(scenario_probe_ids 3 "$TMP/empty.md" | tr '\n' ' ')
if [ "$_got" = "$TOP $TOP1 $TOP2 " ]; then
  ok 'an empty map yields the top of the window, descending'
else
  bad 'an empty map yields the top of the window, descending' "got [$_got]"
fi

# --- a missing map is not an error ----------------------------------------------------------
# Deliberately a path that cannot exist rather than one that happens not to: the assertion is about
# the branch, and a stale file in TMPDIR would make this pass for the wrong reason.
#
# STDERR IS PART OF THE ASSERTION, and that is not belt-and-braces. Written as `2>/dev/null` this
# case could not tell the readability guard from its absence: `cat` on a missing file fails, the
# pipeline still exits on awk, and the only observable difference is the complaint on stderr — which
# the test was throwing away. A falsification arm that removed the guard stayed GREEN. A defence no
# arm can fell is a defence nobody can show is doing anything, and it is the shape that gets deleted
# by the next reader as dead code.
_err="$TMP/missing.err"
_got=$(scenario_probe_ids 2 "$TMP/there-is-no-such-file.md" 2>"$_err" | tr '\n' ' ')
_rc=$?
if [ "$_rc" -eq 0 ] && [ "$_got" = "$TOP $TOP1 " ] && [ ! -s "$_err" ]; then
  ok 'a missing map is an empty owned set: right ids, rc 0, and silence on stderr'
else
  bad 'a missing map is an empty owned set: right ids, rc 0, and silence on stderr' \
      "rc=$_rc got [$_got] stderr [$(cat "$_err")]"
fi

# --- no map argument at all -------------------------------------------------------------------
_got=$(scenario_probe_ids 1 | tr '\n' ' ')
if [ "$_got" = "$TOP " ]; then
  ok 'no map argument yields the top of the window'
else
  bad 'no map argument yields the top of the window' "got [$_got]"
fi

# --- an owned row is skipped ------------------------------------------------------------------
{ printf '| %s | happy | the top of the window is taken | it must be skipped | ✓ |\n' "$TOP"
  printf '| %s | happy | and so is this one | also skipped | ✓ |\n' "$TOP2"
} > "$TMP/owned.md"
_got=$(scenario_probe_ids 3 "$TMP/owned.md" | tr '\n' ' ')
if [ "$_got" = "$TOP1 $TOP3 $TOP4 " ]; then
  ok 'an owned row is skipped'
else
  bad 'an owned row is skipped' "got [$_got]"
fi

# --- a RETIRED row still owns its id ------------------------------------------------------------
# The case the extracted copy got wrong. An id is a permanent handle; retiring a scenario does not
# return its number to the pool, and a probe that took it would collide with a row that still exists.
printf '| ~~%s~~ | happy | a retired row | its id stays reserved | ☐ |\n' "$TOP" > "$TMP/retired.md"
_got=$(scenario_probe_ids 1 "$TMP/retired.md" | tr '\n' ' ')
if [ "$_got" = "$TOP1 " ]; then
  ok 'a retired (~~) row still owns its id'
else
  bad 'a retired (~~) row still owns its id' "got [$_got]"
fi

# --- a SUFFIXED id occupies its stem's number ---------------------------------------------------
printf '| %sb | happy | a suffixed handle | its stem number is taken too | ✓ |\n' "$TOP" > "$TMP/suffix.md"
_got=$(scenario_probe_ids 1 "$TMP/suffix.md" | tr '\n' ' ')
if [ "$_got" = "$TOP1 " ]; then
  ok 'a suffixed id occupies its stem number'
else
  bad 'a suffixed id occupies its stem number' "got [$_got]"
fi

# --- prose is not a row --------------------------------------------------------------------------
# The mirror image of the defect that started this: here the id must NOT be treated as owned, because
# only a table row allocates one. A helper that read prose would walk away from free ids forever.
printf 'Some prose mentioning %s and a flowchart node %s, neither of them a row.\n' \
  "$TOP" "$TOP1" > "$TMP/prose.md"
_got=$(scenario_probe_ids 1 "$TMP/prose.md" | tr '\n' ' ')
if [ "$_got" = "$TOP " ]; then
  ok 'prose does not allocate an id'
else
  bad 'prose does not allocate an id' "got [$_got]"
fi

# --- several map files ---------------------------------------------------------------------------
# The split layout: rows live in the index AND in specs/scenarios/*.md. Reading only the first would
# hand out ids that a per-feature file already owns.
printf '| %s | happy | in the first file | taken | ✓ |\n' "$TOP"  > "$TMP/a.md"
printf '| %s | happy | in the second file | also taken | ✓ |\n' "$TOP1" > "$TMP/b.md"
_got=$(scenario_probe_ids 1 "$TMP/a.md" "$TMP/b.md" | tr '\n' ' ')
if [ "$_got" = "$TOP2 " ]; then
  ok 'every map file passed is consulted'
else
  bad 'every map file passed is consulted' "got [$_got]"
fi

# --- exhaustion returns SHORT, and never below the window ----------------------------------------
# A narrow window, so the exhaustion path is cheap to exercise — the property that made this a
# function rather than a loop. Asking for more than exists must yield what exists, not a wrap, not a
# reach into the three-digit space, and not a hang.
#
# The narrow window sits at the TOP of the space, not the bottom, and that is not arbitrary. Every
# fixture id in this file is also a literal id in a file under scripts/, so it must be one no real
# scenario map allocates — the very rule this helper exists to serve. The low four-digit numbers are
# exactly where a mature project's ids live; the top of the window is where nothing does. A harness
# that broke its own rule to test it would be the joke this row is about.
_saved_top=$SCENARIO_PROBE_TOP; _saved_bottom=$SCENARIO_PROBE_BOTTOM
SCENARIO_PROBE_TOP=9999; SCENARIO_PROBE_BOTTOM=9997
printf '| %s | happy | the middle of a three-wide window | taken | ✓ |\n' "$TOP1" > "$TMP/narrow.md"
_got=$(scenario_probe_ids 5 "$TMP/narrow.md" | tr '\n' ' ')
if [ "$_got" = "$TOP $TOP2 " ]; then
  ok 'exhaustion returns what exists and stays inside the window'
else
  bad 'exhaustion returns what exists and stays inside the window' "got [$_got]"
fi

_got=$(scenario_probe_ids 5 "$TMP/narrow.md" | grep -c .)
if [ "$_got" = "2" ]; then
  ok 'the caller can see it got fewer than it asked for'
else
  bad 'the caller can see it got fewer than it asked for' "count $_got, want 2"
fi
SCENARIO_PROBE_TOP=$_saved_top; SCENARIO_PROBE_BOTTOM=$_saved_bottom

# --- the checked wrapper -------------------------------------------------------------------------
# scenario_probe_checked is where the "the space is exhausted" refusal lives, once, for all callers.
# It RETURNS rather than exits because one caller is a script and one is a sourced library; a helper
# that exited would take the sourcing shell with it, and the failure would look like the consumer's.
: > "$TMP/checked.err"
_got=$(scenario_probe_checked 2 some-harness "$TMP/empty.md" 2>"$TMP/checked.err")
_rc=$?
_got=$(printf '%s\n' "$_got" | tr '\n' ' ')
if [ "$_rc" -eq 0 ] && [ "$_got" = "$TOP $TOP1 " ] && [ ! -s "$TMP/checked.err" ]; then
  ok 'the checked wrapper passes the ids through and says nothing when they exist'
else
  bad 'the checked wrapper passes the ids through and says nothing when they exist' \
      "rc=$_rc got [$_got] stderr [$(cat "$TMP/checked.err")]"
fi

_saved_top=$SCENARIO_PROBE_TOP; _saved_bottom=$SCENARIO_PROBE_BOTTOM
SCENARIO_PROBE_TOP=9999; SCENARIO_PROBE_BOTTOM=9999
# No `| tr` on this capture. A pipeline reports the LAST command's status, so piping the refusal
# through tr reads rc 0 for a function that returned 1 — the case would have passed a broken wrapper.
# The two production callers use a bare `$( ) || exit 1`, which is why they were never affected; the
# test almost was.
_got=$(scenario_probe_checked 3 some-harness "$TMP/empty.md" 2>"$TMP/checked.err")
_rc=$?
_got=$(printf '%s' "$_got" | tr '\n' ' ')
# The caller's NAME has to be in the refusal. A message that says only "the id space is exhausted"
# leaves the reader grepping for which of several harnesses said it, which is the hunt a refusal is
# supposed to remove.
if [ "$_rc" -eq 1 ] && [ -z "$_got" ] && grep -q 'some-harness' "$TMP/checked.err"; then
  ok 'the checked wrapper refuses by name and emits no partial id list'
else
  bad 'the checked wrapper refuses by name and emits no partial id list' \
      "rc=$_rc got [$_got] stderr [$(cat "$TMP/checked.err")]"
fi
SCENARIO_PROBE_TOP=$_saved_top; SCENARIO_PROBE_BOTTOM=$_saved_bottom

# --- the sed script ------------------------------------------------------------------------------
_script=$(scenario_probe_sed_script "$TOP" "$TOP1")
_got=$(printf '| @ID1@ | x | @ID2@ and @ID1@ again |\n' | sed "$_script")
if [ "$_got" = "| $TOP | x | $TOP1 and $TOP again |" ]; then
  ok 'the sed script substitutes every placeholder, repeats included'
else
  bad 'the sed script substitutes every placeholder, repeats included' "got [$_got]"
fi

# A placeholder with no id must survive untouched rather than becoming an empty cell. An id that
# silently vanished would leave a four-column row, which the row parser rejects for a reason the
# author would then go looking for in the parser.
_got=$(printf '@ID3@\n' | sed "$_script")
if [ "$_got" = "@ID3@" ]; then
  ok 'an unmapped placeholder is left alone, not blanked'
else
  bad 'an unmapped placeholder is left alone, not blanked' "got [$_got]"
fi

# --- the helper is sourceable and side-effect free ------------------------------------------------
# It defines functions and runs nothing. A helper that printed or exited on source would corrupt the
# output of every harness that sourced it, which is a failure that looks like the harness's fault.
_got=$(sh -c ". '$HERE/scenario-probe-ids.sh'" 2>&1)
if [ -z "$_got" ]; then
  ok 'sourcing the helper produces no output'
else
  bad 'sourcing the helper produces no output' "got [$_got]"
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf 'scenario-probe-ids: all cases pass\n'
  exit 0
fi
printf 'scenario-probe-ids: %d case(s) failed\n' "$FAILED"
exit 1
