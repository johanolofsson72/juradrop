#!/bin/bash
# register-bytes.sh — where the bytes in a spec register are, and which move shrinks it.
#
# WHY (row 017): two rules govern the size of specs/INDEX.md, and they do not compose. Every row
# stays inside 300 bytes, and the whole file stays under the 25 KB context-cost canary. A register
# can keep the first and break the second. The canary then named archive-completed-rows.sh, which
# correctly had nothing to do. Measured 2026-09-29:
#
#   msroute   29 897 B  done rows 75%, 0 rows over budget, all archived  -> no move exists
#   agentcrm  60 484 B  prose inside ## Specs 55% (explainers, tables)   -> move the prose out
#
# One symptom, two causes, and the old canary gave both the same advice, which neither could
# take. This script measures instead of assuming, so the advice follows the bytes. Both canary
# sites (spec-register-orientation-hook.sh, project-maintenance.sh) read it.
#
# PARTS
#   rows     every status row (- [ ] / [/] / [!] / [x]) plus its indented continuation lines,
#            the grammar spec_active.py and archive-completed-rows.sh use
#   history  the "## Register history" section up to the next "## ": its heading, entries, their
#            indented continuations and blank lines
#   prose    everything else: title, preamble, notes, tables, blank lines outside history, and
#            any table or paragraph written inside the history section
#
# MOVES (a part gets one only when a script or an edit in the template's vocabulary shrinks it)
#   rows     some row over --max-bytes         -> scripts/archive-completed-rows.sh
#   history  > 5 entries, or one over budget   -> scripts/archive-spec-history.sh --keep 5
#   prose    > 4096 bytes                      -> a sibling the pipeline does not read
#   The 4096 is absolute, not a share: the template's own preamble is ~1.2 KB and msroute's
#   legitimate title/header/freeze line 2.4 KB, against agentcrm's 33 KB. A share would fire on a
#   small register whose preamble is most of it.
#
# No move line means COMPLIANT: nothing in the template shrinks the file further. The only move
# left for msroute's shape is folding ticked rows out, which would change what next-register-id,
# the checkpoint cadence, register-convergence and maintenance-due count. That is a finding, not
# something a canary may recommend.
#
# LC_ALL=C is load-bearing: gawk in a UTF-8 locale returns characters from length(), macOS awk
# returns bytes, and a register is full of em dashes. Same reason as archive-spec-history.sh.
#
# Usage: bash scripts/register-bytes.sh [--max-bytes N] [FILE]      (FILE default specs/INDEX.md)
# Output, one key=value line each, moves largest part first (ties: rows, history, prose):
#   total=59632
#   rows=26658 share=44 over=1
#   history=793 share=1 entries=5 over=0
#   prose=33033 share=55
#   move=prose <advice>
#   move=rows <advice>
# Exit: 0 answered · 1 FILE does not exist · 2 usage error

set -u

MAX_BYTES=300
FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --max-bytes)
      [ $# -ge 2 ] || { echo "register-bytes: --max-bytes needs a number" >&2; exit 2; }
      MAX_BYTES="$2"; shift 2 ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    -*) echo "register-bytes: unknown option: $1" >&2; exit 2 ;;
    *)
      [ -z "$FILE" ] || { echo "register-bytes: one file only (got '$FILE' and '$1')" >&2; exit 2; }
      FILE="$1"; shift ;;
  esac
done
case "$MAX_BYTES" in ''|*[!0-9]*) echo "register-bytes: --max-bytes must be a positive integer" >&2; exit 2 ;; esac
[ "$MAX_BYTES" -gt 0 ] || { echo "register-bytes: --max-bytes must be a positive integer" >&2; exit 2; }
FILE="${FILE:-specs/INDEX.md}"
[ -f "$FILE" ] || { echo "register-bytes: no such file: $FILE" >&2; exit 1; }

# awk sees lines, not the bytes between them. Each line is charged its newline, so a file whose
# last line has none would come out one byte over wc -c. Say so up front and refund it in END.
NONL=0
[ -s "$FILE" ] && [ "$(tail -c 1 "$FILE" | od -An -c | tr -d ' ')" != '\n' ] && NONL=1

LC_ALL=C awk -v max="$MAX_BYTES" -v prose_move=4096 -v nonl="$NONL" '
  function close_row() { if (inrow && rowlen > max) rows_over++; inrow = 0 }
  function close_entry() { if (inent && entlen > max) hist_over++; inent = 0 }
  {
    line = $0; sub(/\r$/, "", line)
    b = length($0) + 1                      # + the newline wc -c counts
    total += b
  }
  /^## / {
    close_row(); close_entry()
    insec = ($0 ~ /^## Register history/)
  }
  # Inside history only the heading, entries, their continuations and blank lines are history.
  # A table or paragraph written there is prose: archive-spec-history.sh refuses such a section
  # (exit 3), so calling it history would offer a move that cannot run.
  insec && (line ~ /^## / || line ~ /^[ \t]*$/) { close_entry(); hist += b; last = "h"; next }
  insec && line ~ /^- / { close_entry(); inent = 1; entlen = length(line); hist_n++; hist += b; last = "h"; next }
  insec && inent && line ~ /^[ \t]+[^ \t]/ { entlen += length(line); hist += b; last = "h"; next }
  insec { close_entry(); prose += b; last = "p"; next }
  line ~ /^- \[[ x\/!]\]/ { close_row(); inrow = 1; rowlen = length(line); rows += b; last = "r"; next }
  inrow && line ~ /^[ \t]+[^ \t]/ { rowlen += length(line); rows += b; last = "r"; next }
  { close_row(); prose += b; last = "p" }
  END {
    close_row(); close_entry()
    if (nonl && NR) { total--; if (last == "h") hist--; else if (last == "r") rows--; else prose-- }
    if (total == 0) total = 1
    printf "total=%d\n", (NR ? total : 0)
    printf "rows=%d share=%d over=%d\n", rows, int(rows * 100 / total), rows_over
    printf "history=%d share=%d entries=%d over=%d\n", hist, int(hist * 100 / total), hist_n, hist_over
    printf "prose=%d share=%d\n", prose, int(prose * 100 / total)

    n = 0
    if (rows_over > 0) {
      n++; size[n] = rows; part[n] = "rows"
      adv[n] = "scripts/archive-completed-rows.sh — " rows_over " row(s) over the " max "-byte budget: archive each long form, then shorten the row"
    }
    if (hist_n > 5 || hist_over > 0) {
      n++; size[n] = hist; part[n] = "history"
      adv[n] = "scripts/archive-spec-history.sh --keep 5 — " hist_n " entries inline, " hist_over " over budget"
    }
    if (prose > prose_move) {
      n++; size[n] = prose; part[n] = "prose"
      adv[n] = "move the notes, tables and explainers out of the register into specs/INDEX.notes.md (a sibling the pipeline does not read, like INDEX.history.md) and leave a one-line pointer"
    }
    # Largest first; insertion order breaks ties, and insertion order is rows, history, prose.
    for (i = 1; i <= n; i++) {
      best = 0
      for (j = 1; j <= n; j++) if (!done[j] && (best == 0 || size[j] > size[best])) best = j
      done[best] = 1
      printf "move=%s %s\n", part[best], adv[best]
    }
  }
' "$FILE"
