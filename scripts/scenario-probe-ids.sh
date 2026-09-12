#!/bin/sh
# scenario-probe-ids.sh — free scenario ids for fixtures and probes. SOURCE IT; it runs nothing.
#
# WHY THIS EXISTS. A harness that needs a scenario map needs ids to put in it, and the obvious move
# is to spell out a low id and get on with the test. That is a false binding waiting to happen: the
# scenario-id accounting gate scans `scripts/` for references, cannot tell a fixture from an
# assertion, and counts the fixture as proof that the real scenario is tested.
#
# It is not hypothetical and it is not a maskable risk. Measured in consultpilot on 2026-08-28
# (register row H7bd): nine real ids were referenced by fixture text in two harnesses here, and for
# one of them — the id in `test-scenario-map-rows.sh`'s "prose and flowchart mentions are not rows"
# fixture — that fixture line was its ONLY reference in the entire tests/ + scripts/ tree. The map
# row read ✓ and the gate reported it traced, on the strength of a sentence written to prove that
# sentences do not count.
#
# THE OTHER TWO WAYS, and why neither works here:
#
#   ID- prefix       test-archive-spec-history.sh uses `ID-NNN` in its fixtures and says so at the
#                    fixture (its note has been right for months). It does not transfer: the row
#                    extractor hardcodes `SC-` in its pattern, so an `ID-` fixture row extracts to
#                    nothing and the harness tests an empty map.
#   reserved band    A fixed band the map "never allocates" turns every fixture id into an ORPHAN
#                    reference instead of a false trace — unless every scanning gate is taught the
#                    band. One of those gates is CORE in every downstream project, so that lesson is
#                    one sync away from being deleted, and the reservation itself is only a comment
#                    until something refuses a map row inside it.
#
# So: DERIVE. Ask the map which ids it does not own and use those. An id that no row owns cannot
# trace a row, and an id that is not written literally cannot orphan either — the derivation reads
# the same map the gate does, so the two can never disagree.
#
# This is not a new idea; it is an old one that was written three times and shared zero times.
# consultpilot's test-scenario-id-accounting.sh has derived its probe ids since row H5s, for exactly
# this reason, and widened the window in H5z. This file is that code, made available to the harnesses
# that needed it and did not have it.
#
# USE:
#   . "$(dirname "$0")/scenario-probe-ids.sh"
#   IDS=$(scenario_probe_ids 4 "$MAP")            # newline-separated, descending
#   [ "$(printf '%s\n' "$IDS" | grep -c .)" -eq 4 ] || { ...exhausted...; exit 1; }
#   SUBST=$(scenario_probe_sed_script $IDS)       # @ID1@..@ID4@ -> the ids
#   cat <<'FIXTURE' | sed "$SUBST" > "$file"
#   | @ID1@ | happy | ... |
#   FIXTURE
#
# The heredoc stays SINGLE-QUOTED. Fixture bodies for a markdown table parser carry backslashes and
# backticks whose exact bytes are the thing under test; letting the shell expand them would change
# what the fixture contains, which is the one thing a fixture may not do.

# The window. Four digits only: the three-digit space is spent in the project this was extracted
# from, and falling back into it would make an "ids exhausted" refusal fire later than the real
# exhaustion it announces. Overridable, but there is no reason to.
SCENARIO_PROBE_TOP="${SCENARIO_PROBE_TOP:-9999}"
SCENARIO_PROBE_BOTTOM="${SCENARIO_PROBE_BOTTOM:-1000}"

# scenario_probe_ids <count> [map-file ...] — print <count> ids no map row owns, one per line,
# descending from SCENARIO_PROBE_TOP.
#
# Prints FEWER than <count> when the window runs out, and says nothing about it. The caller decides
# what an exhausted space means and what to print, because the caller is the one that knows what it
# was going to do with the ids. Silently proceeding with fewer is the failure this must not hide:
# a fixture short of an id still runs, still passes, and no longer tests what its name says.
#
# A map path that does not exist or cannot be read contributes nothing and is not an error. That is
# the normal state in the template itself, which ships no scenario map — and a harness that refused
# to build its fixtures there would be refusing over the absence of a file it only reads to avoid.
scenario_probe_ids() {
  _spi_want=$1
  shift

  # ONE pass over the maps, then pure arithmetic. The obvious loop — grep the map once per candidate
  # — is fine while the space is empty and quadratic exactly when it is not, which puts the cost on
  # the exhaustion path that most needs to stay cheap enough to test.
  #
  # A row is owned whether or not it is retired: `.claude/rules/scenarios.md` makes an id a permanent
  # handle that is never reused, so a struck row occupies its number forever. The pattern admits
  # the strike marks, which the copy this was extracted from did not — latent there only because that
  # map happens to carry no retired row today.
  #
  # The number is what is compared, so a suffixed id (a number plus a trailing letter, which real
  # maps do carry) occupies its stem's
  # number too. Two handles that differ by a letter must not let a probe take the digits between them.
  # No `2>/dev/null` on this group, deliberately. It was here, and it made the readability guard
  # below unfalsifiable: with the complaint swallowed, removing the guard changed nothing an assertion
  # could see, and an arm that deleted it stayed green. Two defences for one property, where only one
  # of them can ever be shown to work, is one defence and one decoration. The guard is the defence;
  # anything cat has to say now reaches stderr, where the self-test asserts on its absence.
  { for _spi_map in "$@"; do
      [ -n "$_spi_map" ] && [ -r "$_spi_map" ] && cat "$_spi_map"
    done
  } | awk -v want="$_spi_want" \
                      -v top="$SCENARIO_PROBE_TOP" \
                      -v bottom="$SCENARIO_PROBE_BOTTOM" '
    /^\| *~*SC-[0-9]/ {
      if (match($0, /SC-[0-9]+/)) owned[substr($0, RSTART + 3, RLENGTH - 3) + 0] = 1
    }
    END {
      c = 0
      for (n = top; n >= bottom && c < want; n--)
        if (!(n in owned)) { print "SC-" n; c++ }
    }
  '

  unset _spi_want _spi_map
}

# scenario_probe_checked <count> <caller-label> [map-file ...] — print <count> free ids, or print the
# exhaustion refusal on stderr and return 1.
#
# It RETURNS rather than exits, because one caller is a script and one is a sourced library, and a
# helper that exited would take the sourcing shell down with it. Each caller turns the 1 into its own
# `exit` or `return`; only the message is shared, and the message is the part that was about to exist
# in three places.
scenario_probe_checked() {
  _spc_want=$1
  _spc_who=$2
  shift 2
  _spc_ids=$(scenario_probe_ids "$_spc_want" "$@")
  if [ "$(printf '%s\n' "$_spc_ids" | grep -c .)" -ne "$_spc_want" ]; then
    # Refuse rather than run short. A fixture missing an id still parses, still passes, and quietly
    # stops asserting the case it is named after — the failure the derivation exists to avoid,
    # arriving through the back door.
    printf '%s: fewer than %d free scenario ids in the probe window (%s-%s).\n' \
      "$_spc_who" "$_spc_want" "$SCENARIO_PROBE_BOTTOM" "$SCENARIO_PROBE_TOP" >&2
    printf '  The id space is exhausted and this harness can no longer build a fixture the map does\n' >&2
    printf '  not own. Widen the id format — extractor pattern, gate regex and this window — first.\n' >&2
    unset _spc_want _spc_who _spc_ids
    return 1
  fi
  printf '%s\n' "$_spc_ids"
  unset _spc_want _spc_who _spc_ids
}

# scenario_probe_sed_script <id> [<id> ...] — emit a sed script replacing @ID1@, @ID2@, … with the
# ids given, in order. Intended for `cat <<'FIXTURE' | sed "$(scenario_probe_sed_script $IDS)"`.
#
# `@IDn@` and not `{{ID1}}` or `$ID1`: the token has to survive a single-quoted heredoc unexpanded,
# be impossible to confuse with markdown table syntax, and be greppable. `@` appears in neither
# harness's fixture bodies, so the substitution cannot collide with content.
scenario_probe_sed_script() {
  _sps_n=0
  for _sps_id in "$@"; do
    _sps_n=$((_sps_n + 1))
    printf 's/@ID%d@/%s/g\n' "$_sps_n" "$_sps_id"
  done
  unset _sps_n _sps_id
}
