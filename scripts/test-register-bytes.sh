#!/bin/bash
# test-register-bytes.sh — pins scripts/register-bytes.sh (row 017).
#
# The helper decides what the context-cost canary tells a project to do about specs/INDEX.md. A
# wrong partition sends people at the wrong archiver, which is the defect row 017 exists to
# remove, so every move rule is checked on both sides of its threshold and every part's bytes
# must add up to wc -c.
#
# Run: bash scripts/test-register-bytes.sh
# Exit: 0 all cases pass · 1 one or more failed

set -u

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RB="$DIR/register-bytes.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/register-bytes.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

FAILED=0; PASSED=0
ok()  { printf '  ok:   %s\n' "$1"; PASSED=$((PASSED + 1)); }
bad() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }
has()    { if grep -Fqx -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "no line '$2' in: $(printf '%s' "$3" | tr '\n' '|')"; fi; }
hasnt()  { if grep -Fq -e "$2" <<< "$3"; then bad "$1" "unexpected '$2'"; else ok "$1"; fi; }
val()    { printf '%s\n' "$1" | sed -n "s/^$2=\([0-9]*\).*/\1/p"; }
eq()     { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected $3, got $2"; fi; }

# pad_to FILE LINE BYTES — append LINE until FILE exceeds BYTES.
pad_to() { while [ "$(wc -c < "$1" | tr -d ' ')" -le "$3" ]; do printf '%s\n' "$2" >> "$1"; done; }

sums_to_wc() { # sums_to_wc CASE FILE OUT
  _w=$(wc -c < "$2" | tr -d ' ')
  eq "$1: total = wc -c" "$(val "$3" total)" "$_w"
  eq "$1: rows + history + prose = total" "$(( $(val "$3" rows) + $(val "$3" history) + $(val "$3" prose) ))" "$_w"
}

# ---------------------------------------------------------------- partition
echo "partition"
F="$T/p.md"
printf '# Spec register\n\nPreamble.\n\n## Specs\n\n- [x] 001 — a — done\n- [ ] 002 — b — open\n  continued detail of 002\n- [/] 003 — c\n- [!] 004 — d\n\nA note between rows.\n\n## Register history (newest first)\n\n- 2026-09-01 — one\n- 2026-09-02 — two\n' > "$F"
OUT=$(bash "$RB" "$F"); RC=$?
eq "exit 0" "$RC" 0
sums_to_wc "partition" "$F" "$OUT"
# Rows: the four status lines plus 002's continuation line.
EXP_ROWS=$(grep -E '^(- \[[ x/!]\]|  continued)' "$F" | LC_ALL=C wc -c | tr -d ' ')
eq "rows = four status rows + the continuation line" "$(val "$OUT" rows)" "$EXP_ROWS"
EXP_HIST=$(sed -n '/^## Register history/,$p' "$F" | LC_ALL=C wc -c | tr -d ' ')
eq "history = the section, heading included" "$(val "$OUT" history)" "$EXP_HIST"
has "two history entries" "history=$EXP_HIST share=$(( EXP_HIST * 100 / $(val "$OUT" total) )) entries=2 over=0" "$OUT"
hasnt "a small compliant register has no move" "move=" "$OUT"

# A row inside history is history, never a row: the section wins.
F="$T/hrow.md"
printf '## Register history\n\n- [x] 009 — pasted into history by mistake\n' > "$F"
OUT=$(bash "$RB" "$F")
eq "a status row inside history counts as history" "$(val "$OUT" rows)" 0

# A table written inside the history section is prose, not history: the history archiver
# refuses such a section, so it must not be offered as the move.
F="$T/hprose.md"; printf '## Register history\n\n- 2026-09-01 — one\n' > "$F"
pad_to "$F" '| a | table | written | inside | history |' 4200
OUT=$(bash "$RB" "$F")
if grep -q '^move=prose' <<< "$OUT"; then ok "a table inside history is prose"; else bad "a table inside history is prose" "$OUT"; fi
hasnt "a table inside history is not a history move" "move=history" "$OUT"
sums_to_wc "hprose" "$F" "$OUT"

# CR is not part of a row's budget: a CRLF row of exactly 300 bytes is within it, as its LF twin is.
F="$T/r-crlf.md"; printf -- '- [x] 001 — %0286d\r\n' 0 > "$F"
OUT=$(bash "$RB" "$F")
hasnt "a 300-byte CRLF row is not over (CR is not counted)" "move=rows" "$OUT"

# A section after history ends it.
F="$T/after.md"
printf '## Register history\n\n- 2026-09-01 — one\n\n## Notes\n\nprose after history\n' > "$F"
OUT=$(bash "$RB" "$F")
eq "a later ## heading ends history" "$(val "$OUT" prose)" "$(printf '## Notes\n\nprose after history\n' | wc -c | tr -d ' ')"
sums_to_wc "after" "$F" "$OUT"

# ---------------------------------------------------------------- byte counting
echo "bytes, not characters"
F="$T/utf.md"
printf -- '- [ ] 001 — ✓ ✓ ✓\n' > "$F"
OUT=$(bash "$RB" "$F")
sums_to_wc "multi-byte" "$F" "$OUT"

F="$T/crlf.md"
printf -- '# R\r\n- [x] 001 — a\r\n  more\r\n## Register history\r\n- 2026-09-01 — x\r\n' > "$F"
OUT=$(bash "$RB" "$F")
sums_to_wc "CRLF" "$F" "$OUT"
eq "CRLF: the row and its continuation are rows" "$(val "$OUT" rows)" "$(printf -- '- [x] 001 — a\r\n  more\r\n' | wc -c | tr -d ' ')"
has "CRLF: the history entry is counted" "history=$(val "$OUT" history) share=$(( $(val "$OUT" history) * 100 / $(val "$OUT" total) )) entries=1 over=0" "$OUT"

F="$T/nonl.md"
printf -- '# R\n- [x] 001 — a' > "$F"
OUT=$(bash "$RB" "$F")
sums_to_wc "no trailing newline" "$F" "$OUT"

F="$T/empty.md"; : > "$F"
OUT=$(bash "$RB" "$F"); RC=$?
eq "empty file: exit 0" "$RC" 0
eq "empty file: total 0" "$(val "$OUT" total)" 0

# ---------------------------------------------------------------- move: rows
echo "move rules, both sides of each threshold"
# The prefix "- [x] 001 — " is 14 bytes (the em dash is 3), so %0Nd gives a row of 14+N bytes.
F="$T/r-under.md"; printf -- '- [x] 001 — %0283d\n' 0 > "$F"
OUT=$(bash "$RB" "$F")
eq "a 297-byte row is within budget" "$(printf '%s\n' "$OUT" | sed -n 's/^rows=.* over=//p')" 0
hasnt "no rows move under budget" "move=rows" "$OUT"

F="$T/r-at.md"; printf -- '- [x] 001 — %0286d\n' 0 > "$F"   # exactly 300: not over
OUT=$(bash "$RB" "$F")
hasnt "a 300-byte row is not over (budget is inclusive)" "move=rows" "$OUT"

F="$T/r-over.md"; printf -- '- [x] 001 — %0287d\n' 0 > "$F"  # 301
OUT=$(bash "$RB" "$F")
has  "a 301-byte row is over" "rows=$(wc -c < "$F" | tr -d ' ') share=100 over=1" "$OUT"
if grep -q '^move=rows scripts/archive-completed-rows.sh' <<< "$OUT"; then ok "rows over budget name the row archiver"; else bad "rows over budget name the row archiver" "$OUT"; fi

# A continuation line counts toward its row's budget, as the archivers count it.
F="$T/r-cont.md"; printf -- '- [ ] 001 — %0200d\n  %0100d\n' 0 0 > "$F"
OUT=$(bash "$RB" "$F")
if grep -q '^move=rows' <<< "$OUT"; then ok "a continuation line counts toward the row budget"; else bad "a continuation line counts toward the row budget" "$OUT"; fi

F="$T/r-maxb.md"; printf -- '- [x] 001 — %0100d\n' 0 > "$F"
OUT=$(bash "$RB" --max-bytes 50 "$F")
if grep -q '^move=rows .*50-byte budget' <<< "$OUT"; then ok "--max-bytes moves the budget"; else bad "--max-bytes moves the budget" "$OUT"; fi

# ---------------------------------------------------------------- move: history
F="$T/h5.md"; printf '## Register history\n\n' > "$F"
for d in 01 02 03 04 05; do printf -- '- 2026-09-%s — entry\n' "$d" >> "$F"; done
OUT=$(bash "$RB" "$F")
hasnt "5 history entries: no move (the cap is 5)" "move=history" "$OUT"
printf -- '- 2026-09-06 — entry\n' >> "$F"
OUT=$(bash "$RB" "$F")
if grep -q '^move=history scripts/archive-spec-history.sh --keep 5' <<< "$OUT"; then ok "6 entries name the history archiver"; else bad "6 entries name the history archiver" "$OUT"; fi

F="$T/hlong.md"; printf '## Register history\n\n- 2026-09-01 — %0300d\n' 0 > "$F"
OUT=$(bash "$RB" "$F")
if grep -q '^move=history' <<< "$OUT"; then ok "one over-budget entry names the history archiver"; else bad "one over-budget entry names the history archiver" "$OUT"; fi

# ---------------------------------------------------------------- move: prose
F="$T/pr-under.md"; printf '# R\n' > "$F"; pad_to "$F" 'prose line for the threshold' 4000
OUT=$(bash "$RB" "$F")
hasnt "prose at ~4 KB (<= 4096): no move" "move=prose" "$OUT"
F="$T/pr-over.md"; printf '# R\n' > "$F"; pad_to "$F" 'prose line for the threshold' 4096
OUT=$(bash "$RB" "$F")
if grep -q '^move=prose .*INDEX.notes.md' <<< "$OUT"; then ok "prose over 4096 names the notes sibling"; else bad "prose over 4096 names the notes sibling" "$OUT"; fi
hasnt "prose alone never names the row archiver" "archive-completed-rows" "$OUT"

# ---------------------------------------------------------------- the two live shapes
echo "the two shapes row 017 was filed for"
# msroute: many compliant ticked rows, little prose, short history -> compliant, no move.
F="$T/msroute.md"; printf '# Spec register\n\n## Specs\n\n' > "$F"
pad_to "$F" "- [x] 001 — a-done-row — spec-only — a compliant ticked row, archived verbatim elsewhere, well inside budget" 26000
printf '\n## Register history (newest first)\n\n- 2026-09-01 — one\n' >> "$F"
OUT=$(bash "$RB" "$F")
hasnt "msroute shape: compliant, no move at all" "move=" "$OUT"
sums_to_wc "msroute shape" "$F" "$OUT"

# agentcrm: prose is the largest part, one row over -> prose first, rows second.
F="$T/agentcrm.md"; printf '# Spec register\n\n## Specs\n\n' > "$F"
pad_to "$F" "- [x] 001 — a-done-row — spec-only — compliant" 10000
printf -- '- [x] 099 — %0290d\n' 0 >> "$F"
pad_to "$F" "| lane | owner | depends on | a table written inside the Specs section |" 30000
OUT=$(bash "$RB" "$F")
MOVES=$(printf '%s\n' "$OUT" | sed -n 's/^move=\([a-z]*\) .*/\1/p' | tr '\n' ' ')
eq "agentcrm shape: prose first, then rows" "$MOVES" "prose rows "

# ---------------------------------------------------------------- errors
echo "errors"
bash "$RB" "$T/does-not-exist.md" >/dev/null 2>&1; eq "missing file: exit 1" "$?" 1
OUT=$(bash "$RB" "$T/does-not-exist.md" 2>&1); hasnt "missing file: nothing on stdout that looks like a breakdown" "total=" "$OUT"
bash "$RB" --bogus "$T/p.md" >/dev/null 2>&1;      eq "unknown option: exit 2" "$?" 2
bash "$RB" --max-bytes >/dev/null 2>&1;             eq "--max-bytes without a value: exit 2" "$?" 2
bash "$RB" --max-bytes x "$T/p.md" >/dev/null 2>&1; eq "--max-bytes non-numeric: exit 2" "$?" 2
bash "$RB" --max-bytes 0 "$T/p.md" >/dev/null 2>&1; eq "--max-bytes 0: exit 2" "$?" 2
bash "$RB" "$T/p.md" "$T/p.md" >/dev/null 2>&1;     eq "two files: exit 2" "$?" 2
( cd "$T" && mkdir -p d/specs && cp p.md d/specs/INDEX.md && cd d && bash "$RB" >/dev/null 2>&1 ); eq "default FILE is specs/INDEX.md" "$?" 0

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
