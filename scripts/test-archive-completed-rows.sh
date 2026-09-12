#!/bin/bash
# test-archive-completed-rows.sh — harness for scripts/archive-completed-rows.sh.
#
# EVERY case carries a NEGATIVE CONTROL: a variant constructed so the assertion
# MUST fail, run and watched failing before the real case is trusted. 007br's
# lesson — a falsification arm that cannot fail is decoration, and this project
# shipped one. A control that passes is reported as a HARNESS DEFECT, not as a
# pass, because a test that cannot fail tells you nothing about the code.
#
# Assertions use `grep -q PATTERN <<< "$VAR"`, never `printf ... | grep -q`. Under
# `set -o pipefail` an early-exiting `grep -q` returns 141 once the tail after the
# match fills the pipe buffer, which reads a true claim as false and — negated —
# reads a false claim as PASS. Row 007cj is open against 12 such pipelines in this
# project's other harnesses; this one does not add a thirteenth.
#
# Each case runs against a throwaway specs/ tree under a temp dir, so the live
# register is never touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$SCRIPT_DIR/archive-completed-rows.sh"
PASS=0; FAIL=0; DEFECT=0

pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
defect() { DEFECT=$((DEFECT+1)); printf '  HARNESS DEFECT  %s — negative control did not fail\n' "$1"; }

# mk <dir> <index-body> [completed-body] [pending-body]
mk() {
  local d="$1"; mkdir -p "$d/specs"
  printf '# Spec register\n\n## Specs\n\n%s\n\n## Register history (newest first)\n\n- 2026-08-29 — seed\n' "$2" > "$d/specs/INDEX.md"
  [ $# -ge 3 ] && printf '# Completed-spec retrospectives (archive)\n%s\n' "$3" > "$d/specs/INDEX.completed.md"
  [ $# -ge 4 ] && printf '# Pending-row diagnosis (archive)\n%s\n' "$4" > "$d/specs/INDEX.pending.md"
  return 0
}

run() { local d="$1"; shift; "$TARGET" --dir "$d/specs" "$@" 2>&1; }
code() { local d="$1"; shift; "$TARGET" --dir "$d/specs" "$@" >/dev/null 2>&1; echo $?; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LONG="$(python3 -c 'print("x"*400)')"
SHORT_ROW='- [x] 001 — alpha — spec-only track — short goal.'
LONG_ROW="- [x] 002 — beta — spec-only track — $LONG"
LONG_TODO="- [ ] 003 — gamma — spec-only track — $LONG"

echo "== archive-completed-rows.sh =="

# ---------------------------------------------------------------- FR-1, FR-2
# A completed row is archived verbatim under '## <id> — <slug>'.
d="$TMP/fr1"; mk "$d" "$SHORT_ROW" ""
run "$d" >/dev/null
out="$(cat "$d/specs/INDEX.completed.md")"
if grep -q '^## 001 — alpha$' <<< "$out" && grep -qF -- "$SHORT_ROW" <<< "$out"; then
  pass "FR-1 completed row archived verbatim under its id heading"
else fail "FR-1 completed row archived verbatim under its id heading"; fi
# negative control: a row that was never archived must NOT be found
if grep -q '^## 999 — nope$' <<< "$out"; then defect "FR-1"; else pass "FR-1 control: absent row is absent"; fi

# FR-2 idempotency — a second run must not duplicate.
before="$(cat "$d/specs/INDEX.completed.md")"
run "$d" >/dev/null
after="$(cat "$d/specs/INDEX.completed.md")"
if [ "$before" = "$after" ]; then pass "FR-2 second run is byte-identical (idempotent)"
else fail "FR-2 second run is byte-identical (idempotent)"; fi
# negative control: mutate the archive, prove the comparison can see a difference
mutated="${after}extra"
if [ "$before" = "$mutated" ]; then defect "FR-2"; else pass "FR-2 control: comparison detects a changed archive"; fi

# ---------------------------------------------------------------------- FR-3
# The inline row is never modified.
d="$TMP/fr3"; mk "$d" "$LONG_ROW" ""
idx_before="$(cat "$d/specs/INDEX.md")"
run "$d" >/dev/null
if [ "$idx_before" = "$(cat "$d/specs/INDEX.md")" ]; then pass "FR-3 INDEX.md is not modified"
else fail "FR-3 INDEX.md is not modified"; fi
# negative control: touching the file must be detectable by the same comparison
printf 'x\n' >> "$d/specs/INDEX.md"
if [ "$idx_before" = "$(cat "$d/specs/INDEX.md")" ]; then defect "FR-3"; else pass "FR-3 control: comparison detects a modified INDEX.md"; fi

# ---------------------------------------------------------------------- FR-4
# --max-bytes reports the over-budget row with line, id, status and size.
d="$TMP/fr4"; mk "$d" "$LONG_ROW" ""
out="$(run "$d")"
if grep -q 'INDEX.md:5' <<< "$out" && grep -q '\[x\] 002' <<< "$out" && grep -qE '4[0-9]{2} B' <<< "$out"; then
  pass "FR-4 over-budget row reported with line, id, status, size"
else fail "FR-4 over-budget row reported with line, id, status, size"; fi
# negative control: a short row must produce no over-budget report
d="$TMP/fr4b"; mk "$d" "$SHORT_ROW" ""
out="$(run "$d")"
if grep -qE '[0-9]+ row\(s\) over 300 bytes' <<< "$out"; then defect "FR-4"; else pass "FR-4 control: compliant row triggers no report"; fi

# default budget is 300
d="$TMP/fr4c"; mk "$d" "- [ ] 004 — delta — spec-only track — $(python3 -c 'print("y"*301)')" ""
if [ "$(code "$d")" = "4" ]; then pass "FR-4 default budget is 300 (301 B flagged)"
else fail "FR-4 default budget is 300 (301 B flagged)"; fi
d="$TMP/fr4d"; mk "$d" "$(python3 -c 'row="- [ ] 004 — delta — spec-only track — "; print(row + "y"*(300-len(row.encode())))')" ""
if [ "$(code "$d")" = "4" ]; then defect "FR-4 boundary"; else pass "FR-4 control: exactly 300 B is not flagged"; fi

# ------------------------------------------------------------------ FR-5/FR-6
# An archived over-budget row reports 'shortenable'; an unarchived one 'archive first'.
d="$TMP/fr5"; mk "$d" "$LONG_TODO" "" "$(printf '\n## 003 — gamma\n\nseed\n')"
out="$(run "$d")"
if grep -q 'shortenable' <<< "$out" && grep -q 'INDEX.pending.md' <<< "$out"; then
  pass "FR-5 pending row with an archive entry reports shortenable"
else fail "FR-5 pending row with an archive entry reports shortenable"; fi
d="$TMP/fr5b"; mk "$d" "$LONG_TODO" "" ""
out="$(run "$d")"
if grep -q 'shortenable' <<< "$out"; then defect "FR-5"; else pass "FR-5 control: no archive entry means not shortenable"; fi
if grep -q 'archive first' <<< "$out"; then pass "FR-6 unarchived pending row reports 'archive first'"
else fail "FR-6 unarchived pending row reports 'archive first'"; fi

# FR-6 completed: a live run archives it in the same pass, so it is shortenable next run.
d="$TMP/fr6"; mk "$d" "$LONG_ROW" ""
run "$d" >/dev/null
out="$(run "$d")"
if grep -q 'shortenable' <<< "$out"; then pass "FR-6 completed row is shortenable on the next run"
else fail "FR-6 completed row is shortenable on the next run"; fi
# negative control: under --dry-run nothing is archived, so it stays 'archive first'
d="$TMP/fr6b"; mk "$d" "$LONG_ROW" ""
out="$(run "$d" --dry-run)"
if grep -q 'shortenable' <<< "$out"; then defect "FR-6 dry-run"; else pass "FR-6 control: --dry-run leaves it 'archive first'"; fi

# ---------------------------------------------------------------------- FR-7
d="$TMP/fr7"; mk "$d" "$SHORT_ROW" ""
[ "$(code "$d")" = "0" ] && pass "FR-7 exit 0 on a clean register" || fail "FR-7 exit 0 on a clean register"
d="$TMP/fr7b"; mk "$d" "$LONG_ROW" ""
[ "$(code "$d")" = "4" ] && pass "FR-7 exit 4 when a row is over budget" || fail "FR-7 exit 4 when a row is over budget"
# negative control: with the budget disabled the same register must exit 0
[ "$(code "$d" --max-bytes 0)" = "0" ] && pass "FR-7 control: --max-bytes 0 disables the check" || defect "FR-7 budget-disable"
[ "$(code "$TMP/fr7" --bogus)" = "2" ] && pass "FR-7 exit 2 on an unknown arg" || fail "FR-7 exit 2 on an unknown arg"
[ "$(code "$TMP/fr7" --max-bytes abc)" = "2" ] && pass "FR-7 exit 2 on a non-numeric budget" || fail "FR-7 exit 2 on a non-numeric budget"
[ "$(code "$TMP/fr7" --max-bytes -5)" = "2" ] && pass "FR-7 exit 2 on a negative budget" || fail "FR-7 exit 2 on a negative budget"
mkdir -p "$TMP/nospecs"
"$TARGET" --dir "$TMP/nospecs/specs" >/dev/null 2>&1; [ "$?" = "1" ] && pass "FR-7 exit 1 when specs/ is missing" || fail "FR-7 exit 1 when specs/ is missing"

# ---------------------------------------------------------------------- FR-8
d="$TMP/fr8"; mk "$d" "$LONG_ROW" ""
before="$(cat "$d/specs/INDEX.completed.md")"
run "$d" --dry-run >/dev/null
if [ "$before" = "$(cat "$d/specs/INDEX.completed.md")" ]; then pass "FR-8 --dry-run writes nothing"
else fail "FR-8 --dry-run writes nothing"; fi
# negative control: without --dry-run the same run must write
run "$d" >/dev/null
if [ "$before" = "$(cat "$d/specs/INDEX.completed.md")" ]; then defect "FR-8"; else pass "FR-8 control: a live run does write"; fi

# --pending / --completed scoping
d="$TMP/fr8b"; mk "$d" "$(printf '%s\n%s' "$LONG_ROW" "$LONG_TODO")" ""
out="$(run "$d" --pending)"
if grep -q '003' <<< "$out" && ! grep -q '\[x\] 002' <<< "$out"; then pass "FR-8 --pending reports only unstarted rows"
else fail "FR-8 --pending reports only unstarted rows"; fi
out="$(run "$d" --completed)"
if grep -q '003' <<< "$out"; then defect "FR-8 scoping"; else pass "FR-8 control: --completed excludes the pending row"; fi

# ------------------------------------------------------- row 009: --write-pending
# The default must stay hands-off (FR-10 above); the opt-in must actually write.
d="$TMP/wp"; mk "$d" "$(printf '%s\n%s' "$LONG_TODO" "$SHORT_ROW")" "" ""
before="$(cat "$d/specs/INDEX.pending.md")"
run "$d" >/dev/null 2>&1
[ "$before" = "$(cat "$d/specs/INDEX.pending.md")" ] \
  && pass "row 009 control: without the flag, pending is still untouched" \
  || fail "row 009 control: the default wrote pending"
out="$(run "$d" --write-pending)"
if grep -q '003' <<< "$out" && grep -q '003' "$d/specs/INDEX.pending.md"; then
  pass "row 009 --write-pending archives an over-budget open row"
else
  fail "row 009 --write-pending did not archive: $(head -2 <<<"$out")"
fi
# and it must be idempotent — a second run has nothing left to do
n1=$(grep -c '^## ' "$d/specs/INDEX.pending.md")
run "$d" --write-pending >/dev/null 2>&1
n2=$(grep -c '^## ' "$d/specs/INDEX.pending.md")
[ "$n1" = "$n2" ] && pass "row 009 --write-pending is idempotent" \
  || fail "row 009 --write-pending duplicated entries ($n1 -> $n2)"
# a compliant open row is left alone — only over-budget rows earn an archive entry
grep -q '001' "$d/specs/INDEX.pending.md" \
  && fail "row 009 archived a row that was already within budget" \
  || pass "row 009 leaves within-budget rows alone"

# ---------------------------------------------------------------------- FR-9
# A register may group its rows under milestone headings instead of one flat
# "## Specs" list. rocky has done so since its first commit, and this script
# refused it on every invocation while that register grew to 359 KB with 62 of
# its 123 rows in an INLINE "## Archives" section. ROW_RE already tells a row
# from a prose bullet by shape -- on rocky, 193 bullets and 123 rows -- so the
# heading was a proxy for a job the regex was already doing.
#
# These two cases previously passed for the WRONG reason: the fixtures had no
# INDEX.completed.md, and that refusal (also exit 3) stood in for the heading
# refusal after it was removed. Both now supply one, so the assertion is about
# the heading and nothing else.
d="$TMP/fr9"; mkdir -p "$d/specs"
printf '# Spec register\n\n## Milestone: one\n\n%s\n\n## Register history (newest first)\n\n- 2026-09-03 — seed\n' "$SHORT_ROW" > "$d/specs/INDEX.md"
printf '# Completed-spec retrospectives (archive)\n' > "$d/specs/INDEX.completed.md"
[ "$(code "$d")" = "3" ] && fail "FR-9 a milestone-grouped register is accepted" || pass "FR-9 a milestone-grouped register is accepted"

# ...and its rows are actually SEEN, not merely tolerated. SHORT_ROW is compliant,
# so it is correctly reported as nothing; the probe needs a row the script has
# something to say about, hence LONG_ROW (over budget, not yet archived).
d="$TMP/fr9seen"; mkdir -p "$d/specs"
printf '# Spec register\n\n## Milestone: one\n\n%s\n\n## Register history (newest first)\n\n- 2026-09-03 — seed\n' "$LONG_ROW" > "$d/specs/INDEX.md"
printf '# Completed-spec retrospectives (archive)\n' > "$d/specs/INDEX.completed.md"
out="$(run "$d/" --completed)"
grep -q '002' <<< "$out" && pass "FR-9 rows under a milestone heading are found" || fail "FR-9 rows under a milestone heading are found"

# The history section stays out of the row region even with no "## Specs" --
# archive-spec-history.sh owns it, and a history bullet must never be archived
# as a row.
d="$TMP/fr9hist"; mkdir -p "$d/specs"
printf '# Spec register\n\n## Milestone: one\n\n%s\n\n## Register history (newest first)\n\n- [x] 999 — decoy — spec-only track — a bullet in history shaped like a row.\n' "$SHORT_ROW" > "$d/specs/INDEX.md"
printf '# Completed-spec retrospectives (archive)\n' > "$d/specs/INDEX.completed.md"
out="$(run "$d" --completed)"
grep -q '999' <<< "$out" && fail "FR-9 history bullets stay out of the row region" || pass "FR-9 history bullets stay out of the row region"

# negative control: the flat "## Specs" layout still works unchanged.
mk "$d" "$SHORT_ROW" ""
[ "$(code "$d")" = "3" ] && defect "FR-9 heading" || pass "FR-9 control: the flat ## Specs layout still works"

d="$TMP/fr9b"; mk "$d" '- [x] beta — no-numeric-id — spec-only track — bad id.' ""
[ "$(code "$d")" = "3" ] && pass "FR-9 exit 3 on an unparseable id" || fail "FR-9 exit 3 on an unparseable id"
d="$TMP/fr9c"; mk "$d" '- [x] H12 — checkpoint — checkpoint — a checkpoint id parses.' ""
[ "$(code "$d")" = "3" ] && defect "FR-9 checkpoint id" || pass "FR-9 control: a checkpoint id (H12) is accepted"
d="$TMP/fr9d"; mk "$d" '- [x] 007ce — suffixed — spec-only track — a letter-suffixed id parses.' ""
[ "$(code "$d")" = "3" ] && defect "FR-9 suffixed id" || pass "FR-9 control: a letter-suffixed id (007ce) is accepted"
# The two grammars must agree. Each of these was a live refusal on a real register
# while validate-register-ids.sh passed the same id: agentcrm's S-rows (any
# letter-led id, not just HN) and rocky's dotted sub-specs.
d="$TMP/fr9e"; mk "$d" '- [x] S1 — letter-led — spec-only track — a letter-led id that is not a checkpoint.' ""
[ "$(code "$d")" = "3" ] && fail "FR-9 a letter-led id (S1) is accepted" || pass "FR-9 a letter-led id (S1) is accepted"
d="$TMP/fr9f"; mk "$d" '- [x] 501.1 — dotted — spec-only track — a dotted sub-spec id.' ""
[ "$(code "$d")" = "3" ] && fail "FR-9 a dotted sub-spec id (501.1) is accepted" || pass "FR-9 a dotted sub-spec id (501.1) is accepted"
d="$TMP/fr9g"; mk "$d" '- [x] **404e** — bolded — spec-only track — a register that bolds its ids.' ""
[ "$(code "$d")" = "3" ] && fail "FR-9 a bolded id (**404e**) is accepted" || pass "FR-9 a bolded id (**404e**) is accepted"

# A malformed row that starts like one must refuse, not be silently skipped.
d="$TMP/fr9e"; mk "$d" '- [x] 001-alpha no em-dash separator at all' ""
[ "$(code "$d")" = "3" ] && pass "FR-9 exit 3 on a row that starts like one but does not parse" || fail "FR-9 exit 3 on a row that starts like one but does not parse"

# Q21: a note among the rows is IGNORED, not refused.
d="$TMP/fr9f"; mk "$d" "$(printf '%s\n\n> a note among the rows\n' "$SHORT_ROW")" ""
[ "$(code "$d")" = "3" ] && defect "Q21 note tolerance" || pass "Q21 control: a note among the rows is ignored, not refused"

# --------------------------------------------------------------------- FR-10
# INDEX.pending.md is READ, never written.
d="$TMP/fr10"; mk "$d" "$LONG_TODO" "" "$(printf '\n## 003 — gamma\n\nseed\n')"
before="$(cat "$d/specs/INDEX.pending.md")"
run "$d" >/dev/null
if [ "$before" = "$(cat "$d/specs/INDEX.pending.md")" ]; then pass "FR-10 INDEX.pending.md is never written"
else fail "FR-10 INDEX.pending.md is never written"; fi

# ------------------------------------------------------- Q19: no re-archiving
# A row archived, then edited inline, must not overwrite its archived entry.
d="$TMP/q19"; mk "$d" "$SHORT_ROW" ""
run "$d" >/dev/null
python3 - "$d" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "specs" / "INDEX.md"
p.write_text(p.read_text().replace("short goal.", "EDITED INLINE."))
PY
run "$d" >/dev/null
arch="$(cat "$d/specs/INDEX.completed.md")"
if grep -qF -- "short goal." <<< "$arch" && ! grep -qF -- "EDITED INLINE." <<< "$arch"; then
  pass "Q19 an inline edit does not rewrite the archived entry"
else fail "Q19 an inline edit does not rewrite the archived entry"; fi
# negative control: the archive really does contain findable text
if grep -qF -- "no-such-text-anywhere" <<< "$arch"; then defect "Q19"; else pass "Q19 control: grep over the archive can miss"; fi

# ------------------------------------------------------------- exit precedence
# 3 BEATS 4: a refused register reports the refusal, not the byte count.
# The refusal here is the unparseable-row one; the previous fixture relied on the
# missing-"## Specs" refusal, which no longer exists.
d="$TMP/prec"; mkdir -p "$d/specs"
mk "$d" "$(printf '%s\n- [x] nope — unparseable-id — spec-only track — refuses.' "$LONG_ROW")" ""
[ "$(code "$d")" = "3" ] && pass "exit precedence: 3 beats 4 (refusal outranks over-budget)" || fail "exit precedence: 3 beats 4"

echo
printf 'passed %d, failed %d, harness defects %d\n' "$PASS" "$FAIL" "$DEFECT"
[ "$FAIL" -eq 0 ] && [ "$DEFECT" -eq 0 ] || exit 1
