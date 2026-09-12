#!/bin/sh
# scenario-map-rows.sh — extract every scenario row from a scenario map, one line each.
#
# WHY: splitting specs/SCENARIOS.md into per-feature files has to be provably lossless across
# hundreds of rows, so it is checked mechanically: snapshot before, extract after, diff. This script
# is both halves of that, and scripts/test-scenario-map-split.sh is the gate around it.
#
# OUTPUT: one line per row, sorted by id, TAB-separated:
#     id<TAB>kind<TAB>scenario<TAB>expected_outcome<TAB>status<TAB>struck
# where `struck` is 1 for a retired row (written ~~SC-NNN~~ in the map) and 0 otherwise.
# The id is emitted WITHOUT the strikethrough markers so ids sort and compare naturally;
# the strike survives as its own field, because losing it would free a reserved id.
#
# THE DELIMITER IS A TAB BECAUSE A CELL CAN CONTAIN A PIPE. It was "|" until 2026-08-28, which
# reads fine until a scenario quotes one — see trap 3 — and then the emitted line has seven
# fields where every caller splits on six. `IFS=... read -r id kind scen expected status struck`
# does not fail on that; it shifts status into expected and puts "✓|0" in struck, so the row
# quietly stops counting as validated. A tab cannot collide the same way, and not by convention:
# squeeze() below collapses every whitespace run in a cell to a single space, so no emitted cell
# contains a tab. That is an invariant of this script, not an escaping rule callers must know.
#
# ------------------------------------------------------------------------------------------------
# FOUR TRAPS THIS SCRIPT EXISTS TO AVOID. The first two were found while scoping 007bl; the third
# by a gate refusing a real map on 2026-08-28; the fourth by that same gate refusing a DIFFERENT
# real map on 2026-08-29, one repository over.
#
#   1. The obvious pattern '^\| SC-' misses every retired row, because those are written
#      `| ~~SC-nnn~~ |`. Extracting with it yields 185 and looks correct. All three rows it
#      drops are precisely the ones whose ids must never be reused (.claude/rules/scenarios.md
#      makes an id a permanent handle), so the ONE check that must not miss them misses them.
#      Hence the (~~)? in the row pattern below, and the struck field.
#
#   2. `grep -c 'SC-'` counts every prose mention, every flowchart label and every id quoted in a
#      comment, so it disagrees with the ledger and nobody can say which number is right. The
#      pattern here is anchored to a TABLE ROW — a leading pipe, and the id in the FIRST
#      cell IS an id — so prose mentions, flowchart references and comments cannot inflate the
#      count. That is the whole reason extraction is anchored to the table rather than the text.
#
#   3. FS = "|" splits a markdown-escaped pipe. GFM writes a literal pipe inside a cell as \|
#      and renders it as text, not as a column break — so a row whose scenario text quotes one
#      arrives at awk with six cells and is rejected as malformed. agentcrm's SC-436 does exactly
#      that (a formula-injection payload beginning `=cmd\|`), and one such row took the whole
#      traceability gate down for a 482-row map: the guard reports the row and exits 2, so nothing
#      downstream got a single scenario out of a file that was never malformed. Adversarial rows
#      are where the payloads live, so this will keep happening. See the rejoin loop below.
#
#   4. A LINE THAT STARTS `| SC-` IS NOT NECESSARILY A LEDGER ROW. Feature files carry commentary
#      tables that cite ids — a promotion note (`| SC | now | why |`) recording which scenarios an
#      operator validated, or a two-column evidence summary. Judging those on arity refuses the
#      whole map over a table that was never a ledger, which is how rocky's gate spent 2026-08-29
#      at `exit 3` again the day after it was fixed. Worse, when the arity happens to match, their
#      rows are read as real ones and MANUFACTURE DUPLICATE IDS, because the same id is also a row
#      in the real ledger further down the file. So the HEADER decides: a table without a ledger
#      header is not a ledger, and its rows are ignored in silence.
#
#      The header check is also the only thing that can catch a REORDER. One file was written
#      "| SC | Scenario | Type | Coverage | Status |" — five columns, so arity accepted it, and
#      every row was silently mis-sliced: its `kind` held the scenario prose and its `scenario`
#      held the word "adversarial". Status landed in column 5 by luck, so nothing went red. Column
#      ORDER is the contract; column NAMES are not, so a file that renames its columns passes and
#      a file that reorders them fails. Accepting a rename while rejecting a reorder is the point.
# ------------------------------------------------------------------------------------------------
#
# The map's rows are uniform: exactly five columns, none wrapped across lines. If that ever stops
# being true this script reports it rather than silently emitting a short row — see the
# column-count guard. An escaped pipe is NOT a shape change and no longer trips that guard.
#
# USAGE:
#   scripts/scenario-map-rows.sh specs/SCENARIOS.md
#   scripts/scenario-map-rows.sh specs/SCENARIOS.md specs/scenarios/*.md
#   scripts/scenario-map-rows.sh --summary specs/SCENARIOS.md      # counts, not rows
#   scripts/scenario-map-rows.sh --partial specs/SCENARIOS.md      # skip a bad row, keep going
#
# EXIT: 0 extracted cleanly · 1 no readable input · 2 a malformed row (or a reordered ledger
#       header) was found · 4 --partial only: rows were emitted AND rows were skipped.

set -eu

SUMMARY=0
PARTIAL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --summary) SUMMARY=1; shift ;;
    # --partial: report a malformed row and SKIP it, instead of refusing the whole input.
    #
    # This flag exists because of what the default did. A traceability gate that calls this script
    # was exiting 3 — "scenario-map-rows.sh refused the map" — for over a year, checking neither
    # uncovered nor dangling ids, because 80 of 226 files contained one malformed row each and this
    # script refuses everything when it meets one. All-or-nothing is right for the losslessness
    # harness, where a single unreadable row invalidates the diff. It is exactly wrong for a gate,
    # where it converts one hand-edited table into total silence. So the strictness stays the
    # DEFAULT and the gate opts out.
    --partial) PARTIAL=1; shift ;;
    --) shift; break ;;
    -*) echo "scenario-map-rows: unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done

if [ "$#" -eq 0 ]; then
  echo "usage: $0 [--summary] [--partial] <map-file> [more-files...]" >&2
  exit 1
fi

for f in "$@"; do
  [ -f "$f" ] || { echo "scenario-map-rows: no such file: $f" >&2; exit 1; }
done

# The tab is needed before the first sort, not after it. Defined here so every use below — the
# sort key, the dedup pass, cut, and the summary awk — reads the same byte.
TAB=$(printf '\t')

# awk does the parsing so the cell splitting is one implementation, not one per call site.
# A row is: leading '|', optional decoration, SC-<digits>, INSIDE A LEDGER TABLE. Everything else
# in the file is ignored, including flowchart node labels and prose that quotes an id.
EXTRACT='
  BEGIN { FS = "|"; bad = 0; skipped = 0; in_ledger = 0; prev = "" }

  # ---------------------------------------------------------------- which table are we inside?
  #
  # The separator line (|---|---|) is what identifies the line before it as a header, so the
  # context is set here and the header itself is the previous line. classify() decides whether
  # that header is a ledger header, a reordered one, or not a header at all.
  /^[[:space:]]*\|[[:space:]:|-]+\|[[:space:]]*$/ {
    if (prev ~ /^[[:space:]]*\|/) {
      k = classify(prev)
      in_ledger = (k == "ledger")
      if (k == "reordered") {
        printf "scenario-map-rows: %s:%d ledger header is not in canonical order (ID|Type|Scenario|Expected outcome|Status): %s\n", FILENAME, FNR - 1, prev > "/dev/stderr"
        bad = 1
      }
    }
    prev = $0
    next
  }

  # An HTML comment inside a table does NOT end it. .claude/rules/scenarios.md
  # shows comments inside a map in its own worked example, and this project uses
  # them to record why a row carries the status it does -- so they belong in the
  # middle of a ledger, not only between tables.
  #
  # Treating one as "left the table" silently dropped every row after it. Measured
  # on consultpilot 2026-09-03: a five-line note between SC-176 and SC-937 cost 12
  # rows, and the gate then reported all 12 as ids the map "does not have" -- 18 of
  # its 18 dangling findings were this, not one real one. A fixture proved a
  # ONE-line comment does it too: three rows became one.
  #
  # NOTE FOR THE NEXT EDITOR: this awk program is inside a single-quoted shell
  # string, so an apostrophe here ends the program. The first draft of this very
  # comment wrote "the map-apostrophe-s own example" and turned the whole
  # extractor into "own: command not found" -- zero rows, on every map.
  #
  # Comment state is tracked across lines because a comment can open on one line
  # and close on a later one. Anything inside is skipped without touching
  # in_ledger, so the table survives it.
  /^[[:space:]]*<!--/ { if ($0 !~ /-->/) in_comment = 1; prev = $0; next }
  in_comment { if ($0 ~ /-->/) in_comment = 0; prev = $0; next }

  # Leaving the table (any line that is not a table row) resets the context.
  !/^[[:space:]]*\|/ { in_ledger = 0; prev = $0; next }

  # `**SC-nnnn**` is how some files write their ids — 77 rows across three files that the old
  # pattern never matched, so they were not refused, they were INVISIBLE: a "✓" among them was never
  # checked, and a test naming one was reported as dangling because the map appeared not to have it.
  /^[[:space:]]*\|[[:space:]]*(\*\*)?(~~)?SC-[0-9]+/ {
    if (!in_ledger) { ignored[FILENAME]++; prev = $0; next }

    # Rejoin the cells FS cut apart at an escaped pipe (trap 3). A field ending in an ODD
    # number of backslashes was cut mid-cell: the last one escapes the delimiter. An even
    # number is literal backslashes standing in front of a real column break, so the count
    # is what distinguishes them — a bare /\\$/ test would join the second case wrongly.
    # The pipe goes back spelled as the map spells it, \|, because every other cell is
    # emitted verbatim and a diff of two extractions is meant to be a diff of the maps.
    # (No apostrophes in this block: EXTRACT is a single-quoted shell string, and one
    # stray quote ends it mid-program. Cost of learning that: nine red cases below.)
    # Output stays splittable because the delimiter is a tab, not because of that backslash.
    n = 0
    cur = $1
    for (i = 2; i <= NF; i++) {
      if (odd_backslashes(cur)) cur = cur "|" $i
      else { cell[++n] = cur; cur = $i }
    }
    cell[++n] = cur

    # n-2 is the cell count: FS on a full-width markdown row yields an empty first and
    # last field. The map is uniformly five columns; anything else is a shape change this
    # script must not paper over.
    if (n - 2 != 5) {
      printf "scenario-map-rows: %s:%d has %d columns, expected 5: %s\n", FILENAME, FNR, n - 2, $0 > "/dev/stderr"
      if (PARTIAL) { skipped++ } else { bad = 1 }
      prev = $0
      next
    }

    id = trim(cell[2])
    sub(/^\*\*/, "", id); sub(/\*\*$/, "", id)

    # RENUMBERED ROW: "~~SC-nnnn~~ SC-mmmm" — the old id struck, the new one live, both in one cell.
    # scripts/scenario-scid-renumber.py writes this form and hundreds of rows carry it, but nothing
    # here ever parsed it, so the whole cell became the id. Two consequences, both silent: a test
    # naming the LIVE id was reported dangling because the map appeared not to have it, and the row
    # status was attributed to an id that does not exist, inflating the uncovered count.
    #
    # The retired id still has to be REAL — .claude/rules/scenarios.md makes an id a permanent
    # handle, so a test still naming SC-1522 is stale rather than wrong about the map. It is
    # therefore emitted as its own struck row, exempt from coverage but present for the dangling
    # direction — subject to the dedup pass below, which is where the subtlety lives.
    alias = ""
    if (id ~ /^~~SC-[0-9]+~~[[:space:]]+SC-[0-9]+/) {
      alias = id
      sub(/^~~/, "", alias)
      sub(/~~.*$/, "", alias)
      sub(/^~~SC-[0-9]+~~[[:space:]]+/, "", id)
      # Status is the em dash, not an ASCII hyphen: test-scenario-map-index.py holds that a row
      # status is the em dash exactly when the row is struck, and an alias row IS struck.
      printf "%s\t%s\t%s\t%s\t%s\t%d\n", alias, "retired", "renumbered to " id, "—", "—", 1
    }

    kind     = trim(cell[3])
    scenario = trim(cell[4])
    expected = trim(cell[5])
    status   = trim(cell[6])

    struck = 0
    if (id ~ /^~~.*~~$/) {
      struck = 1
      sub(/^~~/, "", id)
      sub(/~~$/, "", id)
    }

    # Collapse internal whitespace runs so a reflowed cell (same words, different padding)
    # is not reported as a changed row. The move copies rows verbatim, but a future editor
    # reformatting a table should not read as scenario loss. This is ALSO what guarantees no
    # emitted cell contains a tab, which is what makes the output contract safe.
    scenario = squeeze(scenario)
    expected = squeeze(expected)
    status   = squeeze(status)
    kind     = squeeze(kind)

    emitted[FILENAME]++
    printf "%s\t%s\t%s\t%s\t%s\t%d\n", id, kind, scenario, expected, status, struck
    prev = $0
    next
  }

  # Any other table row: still inside the table, just not a ledger row.
  { prev = $0 }

  END {
    # A FILE THAT YIELDS NOTHING AT ALL, while containing lines that look like ledger rows, is
    # reported. Requiring a header is right, but "wrong header, therefore silence" is the failure
    # mode that cost this project a year: an invisible row is worse than a refused one, because a
    # refusal is loud. This does not fail the run — a file may legitimately cite ids in commentary
    # and carry no ledger — it says out loud that the whole file went unread.
    for (f in ignored) {
      if (!(f in emitted)) {
        printf "scenario-map-rows: %s has %d id-leading table row(s) but no recognised ledger header — the whole file was read as commentary\n", f, ignored[f] > "/dev/stderr"
      }
    }
    if (bad) exit 2
    # Exit 4 is "I emitted rows AND skipped some" — the state --partial exists to make sayable.
    # Reporting it as 0 would be the defect this flag was added to remove: "clean over what I could
    # read" reported as "clean".
    if (skipped) {
      printf "scenario-map-rows: skipped %d malformed row(s) under --partial\n", skipped > "/dev/stderr"
      exit 4
    }
  }

  # The trailing run of backslashes, isolated by deleting everything up to the last character
  # that is not one. A string that is ALL backslashes matches nothing and is left whole, which
  # is the case a greedy /.*\\/ strip would get wrong.
  function odd_backslashes(s,   t) {
    t = s
    sub(/^.*[^\\]/, "", t)
    return (length(t) % 2) == 1
  }

  function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
  function squeeze(s) { gsub(/[[:space:]]+/, " ", s); return s }

  # Role order is the contract; the names are free. Returns "ledger", "reordered" or "no".
  #
  # PERMISSIVE ON NAMES IT DOES NOT KNOW, and that is the whole design. A first draft enumerated the
  # acceptable label for every column and called anything else a reorder, which condemned four real
  # harness fixtures whose headers read "| id | type | flow | expected | st |" — five columns, right
  # order, vocabulary this script had never been told about. A gate whose first honest run says the
  # fixtures are the bug has misidentified the bug.
  #
  # So: a column whose name maps to a KNOWN role must sit in that role slot; a column whose name
  # maps to nothing occupies whatever slot it is in without objection. That still catches the case
  # the check exists for — a header written "| SC | Scenario | Type | Coverage | Status |" puts the
  # recognised name "scenario" in the type slot, and every row behind it was being sliced into the
  # wrong fields with nothing going red.
  #
  # The first cell is the exception: it MUST name the id column. It is the one column whose meaning
  # the row pattern already assumes, so a table whose first column is something else is not a
  # ledger at all rather than a broken one.
  # NOTE: this whole awk program lives in a single-quoted shell string, so no comment in it may
  # contain an apostrophe. One did, briefly, and it closed the string 100 lines early.
  function role(nm) {
    if (nm == "id" || nm == "sc" || nm == "sc-id" || nm == "sc id" || nm == "scenario id") return "id"
    if (nm == "type" || nm == "kind") return "type"
    if (nm == "scenario" || nm == "user flow") return "scenario"
    if (nm == "expected outcome" || nm == "expected" || nm == "expected result") return "expected"
    if (nm == "status" || nm == "state") return "status"
    return ""
  }

  function classify(hdr,   n, a, i, c, r, canon, known) {
    n = split(hdr, a, "|")
    if (n - 2 != 5) return "no"
    canon[1] = "id"; canon[2] = "type"; canon[3] = "scenario"
    canon[4] = "expected"; canon[5] = "status"
    for (i = 1; i <= 5; i++) { c[i] = tolower(trim(a[i + 1])); gsub(/[[:space:]]+/, " ", c[i]) }
    if (role(c[1]) != "id") return "no"
    known = 0
    for (i = 2; i <= 5; i++) {
      r = role(c[i])
      if (r == "") continue
      if (r != canon[i]) return "reordered"
      known++
    }
    # At least ONE column beyond the id must be a name this script recognises. Pure permissiveness
    # was too permissive in the one direction that matters: a five-column COMMENTARY table whose
    # first cell is an id and whose other four labels are all unknown (| SC | now | why | evidence |
    # note |) would be read as a ledger, and its rows would manufacture duplicate ids against the
    # real ledger further down the same file — the exact defect the header rule was added to stop,
    # re-entering through the door held open for renames. One recognised column is enough to tell a
    # renamed ledger from a table that is not one, and a file that renames ALL FIVE of its columns
    # is not a rename any more.
    if (known == 0) return "no"
    return "ledger"
  }
'

# awk runs on its own line, NOT as `$(awk ... | sort)`. In a pipeline `$?` is the LAST
# command's status, so piping straight into sort reports sort's exit and silently discards
# awk's `exit 2` — the malformed-row guard above would print its warning and then return 0,
# which is the guard failing in the one direction nobody checks. Sort afterwards instead.
# `RC=0; RAW=$(...) || RC=$?` and NOT a bare assignment: under `set -e` a command substitution that
# exits non-zero kills the script AT THE ASSIGNMENT, so --partial's exit 4 would take the rows down
# with it — the extractor would report "rows emitted, rows skipped" and emit nothing. That is the
# same family as the pipeline trap documented above, and it was caught by a harness rather than by
# reading, which is the argument for the harness existing.
RC=0
RAW=$(awk -v PARTIAL="$PARTIAL" "$EXTRACT" "$@") || RC=$?
# 4 is --partial's "rows emitted, rows skipped". It is carried to the caller at the END of this
# script, not here: exiting now would discard the rows we did manage to read, which is the
# all-or-nothing behaviour --partial exists to replace.
[ "$RC" -ne 0 ] && [ "$RC" -ne 4 ] && exit "$RC"

# Drop a renumber ALIAS row whose id is already defined as a real row somewhere in the map.
#
# Read scenario-scid-renumber.py's docstring before touching this. `~~SC-nnnn~~ SC-mmmm` does NOT
# mean "SC-nnnn retired here". It means the OPPOSITE: SC-nnnn was defined in two files, the
# lowest-numbered file KEEPS it, and this file's definition was reassigned to SC-mmmm. So the struck
# id still belongs to the keeper.
#
# Emitting the struck id as a row here would therefore RE-CREATE the exact duplicates the renumber
# tool was written to remove. Measured on one real map: 103 unique alias ids, and all 103 already
# defined elsewhere — not a coincidence but the tool's whole contract.
#
# It is dropped CONDITIONALLY rather than deleted outright, for the one case the contract does not
# cover: an id struck by hand, with no keeper anywhere. There the alias is the only thing keeping a
# permanent handle real, so every test still naming it would otherwise read as dangling.
DEDUP_TMP=$(mktemp 2>/dev/null || mktemp -t scenario-rows)
printf '%s\n' "$RAW" | sed '/^$/d' > "$DEDUP_TMP"
ROWS=$(awk -F'\t' '
  NR == FNR { if (!($2 == "retired" && $3 ~ /^renumbered to /)) real[$1] = 1; next }
  { if ($2 == "retired" && $3 ~ /^renumbered to / && ($1 in real)) next; print }
' "$DEDUP_TMP" "$DEDUP_TMP" | sort -t"$TAB" -k1,1)
rm -f "$DEDUP_TMP"

if [ "$SUMMARY" -eq 0 ]; then
  printf '%s\n' "$ROWS"
  exit "$RC"
fi

# --summary: the numbers the split harness asserts against, so the snapshot is verified rather
# than trusted.
TOTAL=$(printf '%s\n' "$ROWS" | grep -c . || true)
UNIQUE=$(printf '%s\n' "$ROWS" | cut -d"$TAB" -f1 | sort -u | grep -c . || true)
DUPES=$((TOTAL - UNIQUE))

printf 'rows:      %s\n' "$TOTAL"
printf 'unique:    %s\n' "$UNIQUE"
printf 'duplicate: %s\n' "$DUPES"
printf 'struck:    %s\n' "$(printf '%s\n' "$ROWS" | awk -F'\t' '$6 == 1' | grep -c . || true)"
printf -- '--- status histogram ---\n'
printf '%s\n' "$ROWS" | awk -F'\t' '{ h[$5]++ } END { for (k in h) printf "%-6s %d\n", k, h[k] }' | sort -k2 -rn

[ "$DUPES" -eq 0 ] || {
  echo "scenario-map-rows: $DUPES duplicate id(s) — ids are permanent handles and must be unique" >&2
  exit 2
}
exit "$RC"
