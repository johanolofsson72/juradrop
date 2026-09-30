#!/usr/bin/env bash
#
# test-finding.sh — the findings ledger's own gate.
#
# WHY THIS EXISTS. finding.sh had no test, and on 2026-09-09 `--resolve 033`
# marked F027 resolved with the decision text meant for F033. `printf 'F%03d' 033`
# reads a leading zero as OCTAL: 033 -> 27, 034 -> 28, 044 -> 36, 047 -> 39,
# 071 -> 57. Five findings were closed with reasons belonging to five other
# findings, and the command reported success every time.
#
# The ledger writes ids as F027, F033, F090, so typing the id back with its
# leading zero is the obvious thing to do. That made the trap the DEFAULT path,
# not an edge case — and the only reason it was noticed is that ids above 070
# are not valid octal, so those printed "F000090 not found" and drew attention.
# Below 070 it was silently wrong.
#
# A ledger nobody can trust to close the right row is worse than no ledger: the
# whole point of the batch review is that a decision lands on the finding it was
# made about.

set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
FINDING="$SELF_DIR/finding.sh"
TMP="${TMPDIR:-/tmp}/finding-selftest.$$"
PASS=0; FAIL=0

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n         expected: %s\n         actual:   %s\n' "$1" "$2" "$3"; }

mkledger() {
  d="$TMP/$1"
  mkdir -p "$d/specs" "$d/scripts"
  ( cd "$d" && git init -q . >/dev/null 2>&1 )
  cp "$FINDING" "$d/scripts/finding.sh"
  {
    printf '# Findings\n\n'
    printf -- '- [ ] F027 — gap — 2026-01-01 · from spec 001 — twenty-seven\n'
    printf -- '- [ ] F028 — gap — 2026-01-01 · from spec 001 — twenty-eight\n'
    printf -- '- [ ] F033 — gap — 2026-01-01 · from spec 001 — thirty-three\n'
    printf -- '- [ ] F034 — gap — 2026-01-01 · from spec 001 — thirty-four\n'
    printf -- '- [ ] F090 — gap — 2026-01-01 · from spec 001 — ninety\n'
  } > "$d/specs/FINDINGS.md"
  printf '%s' "$d"
}

# $1 dir · $2 id — prints the status box for that id
#
# `grep -m1 … file | cut` rather than `grep … file | head -1 | cut`: head exits
# after the first line and leaves grep writing into a reader-less pipe, which is
# SIGPIPE and 141 under pipefail. Bounding the match at the producer gets the
# same one line with nothing downstream that can close early.
status_of() { grep -m1 -oE "^- \[.\] $2 " "$1/specs/FINDINGS.md" | cut -c4-4; }
# $1 dir · $2 id — prints the decision text, or empty
decision_of() { grep -m1 -E "^- \[.\] $2 " "$1/specs/FINDINGS.md" | sed -n 's/.*  →  //p'; }

printf 'finding.sh self-test (--resolve id parsing)\n'

# ---------------------------------------------------------- C1 — the octal trap
#
# The regression that motivated this file. Every one of these ids is valid octal
# with a different decimal value, so before the fix each resolved a DIFFERENT
# existing finding — silently, and reporting success.
printf '\n  -- C1  a leading zero is decimal, not octal\n'
D=$(mkledger octal)
( cd "$D" && bash scripts/finding.sh --resolve 033 "for thirty-three" >/dev/null 2>&1 )
[ "$(status_of "$D" F033)" = "x" ] && ok "033 resolves F033" || bad "033 resolves F033" "F033 resolved" "not resolved"
[ "$(status_of "$D" F027)" = " " ] && ok "…and leaves F027 (octal 033) alone" || bad "…and leaves F027 alone" "F027 open" "F027 resolved"
[ "$(decision_of "$D" F033)" = "for thirty-three" ] && ok "…and the decision lands on the right finding" \
  || bad "the decision lands on the right finding" "for thirty-three" "$(decision_of "$D" F033)"

printf '\n  -- C1  the same trap at the other measured ids\n'
D=$(mkledger octal2)
( cd "$D" && bash scripts/finding.sh --resolve 034 "for thirty-four" >/dev/null 2>&1 )
[ "$(status_of "$D" F034)" = "x" ] && ok "034 resolves F034" || bad "034 resolves F034" "F034 resolved" "not resolved"
[ "$(status_of "$D" F028)" = " " ] && ok "…and leaves F028 (octal 034) alone" || bad "…and leaves F028 alone" "F028 open" "F028 resolved"

# -------------------------------------------- C2 — the half that errored loudly
#
# 08 and 09 are not valid octal, so printf failed, the `|| echo` appended the raw
# argument, and the user saw "F000090 not found". Wrong in a different way, and
# the only reason the silent half above was ever noticed.
printf '\n  -- C2  an id above 070 with a leading zero resolves, not "F000090 not found"\n'
D=$(mkledger printferr)
OUT=$( cd "$D" && bash scripts/finding.sh --resolve 090 "for ninety" 2>&1 )
[ "$(status_of "$D" F090)" = "x" ] && ok "090 resolves F090" || bad "090 resolves F090" "F090 resolved" "not resolved"
case "$OUT" in *F000090*) bad "…and does not mangle the id" "no F000090" "$OUT" ;; *) ok "…and does not mangle the id" ;; esac

# ------------------------------------------------------- C3 — plain ids still work
printf '\n  -- C3  an id without a leading zero is unaffected\n'
D=$(mkledger plain)
( cd "$D" && bash scripts/finding.sh --resolve 27 "for twenty-seven" >/dev/null 2>&1 )
[ "$(status_of "$D" F027)" = "x" ] && ok "27 resolves F027" || bad "27 resolves F027" "F027 resolved" "not resolved"

# ------------------------------------------------- C4 — a non-number is refused
#
# Not decoration: stripping zeros with sed would turn "abc" into "abc" and then
# printf would emit F000 and "resolve" whatever F000 matched.
printf '\n  -- C4  a non-numeric argument is refused, not coerced\n'
D=$(mkledger notanumber)
OUT=$( cd "$D" && bash scripts/finding.sh --resolve abc "nope" 2>&1 ); RC=$?
[ "$RC" -ne 0 ] && ok "it exits non-zero" || bad "it exits non-zero" "non-zero" "$RC"
case "$OUT" in *"takes a number"*) ok "…and says why" ;; *) bad "…and says why" "takes a number" "$OUT" ;; esac
[ "$(grep -c '^- \[x\]' "$D/specs/FINDINGS.md")" = "0" ] && ok "…and resolves nothing" \
  || bad "…and resolves nothing" "0 resolved" "$(grep -c '^- \[x\]' "$D/specs/FINDINGS.md")"

# ------------------------------------------- C5 — an id that is genuinely absent
printf '\n  -- C5  an absent id is reported, not invented\n'
D=$(mkledger absent)
OUT=$( cd "$D" && bash scripts/finding.sh --resolve 999 "nope" 2>&1 ); RC=$?
[ "$RC" -ne 0 ] && ok "it exits non-zero" || bad "it exits non-zero" "non-zero" "$RC"
case "$OUT" in *"F999 not found"*) ok "…and names the id it looked for" ;; *) bad "…and names the id" "F999 not found" "$OUT" ;; esac

# ============================================ row proposals + the freeze (row 077)
mkfrozen() { # a ledger fixture plus the review/freeze engines and a frozen register
  d=$(mkledger "$1")
  cp "$SELF_DIR/finding_review.py" "$SELF_DIR/register-convergence.sh" "$SELF_DIR/register_freeze.py" "$d/scripts/"
  mkdir -p "$d/scripts/real"; : > "$d/scripts/real/present.sh"
  {
    printf '# Spec register\n\nFreeze: since 2026-09-29 · last row 010 · lifts below 3 open · x\n\n## Specs\n\n'
    printf -- '- [x] 001 — done — ticked\n'
    printf -- '- [ ] 009 — mutation-gate-reports-headline — the stryker mutation gate prints only the headline score and hides modules\n'
    printf -- '- [ ] 010 — something — unrelated plumbing\n'
    printf -- '- [ ] H1 — integration-hardening — checkpoint\n'
  } > "$d/specs/INDEX.md"
  printf '%s' "$d"
}
freeze() { ( cd "$1" && bash scripts/register-convergence.sh --freeze 2>&1 ); }

printf '\n  -- C6  a proposal without evidence is refused\n'
D=$(mkfrozen p-noneed)
OUT=$( cd "$D" && bash scripts/finding.sh --add "make a row" --propose-row 2>&1 ); RC=$?
[ "$RC" = 2 ] && ok "exit 2" || bad "exit 2" "2" "$RC"
case "$OUT" in *"needs --need"*) ok "…and says what is missing" ;; *) bad "…says what is missing" "needs --need" "$OUT" ;; esac
OUT=$( cd "$D" && bash scripts/finding.sh --add "make a row" --propose-row --need "   " 2>&1 ); RC=$?
[ "$RC" = 2 ] && ok "whitespace-only need is refused too" || bad "whitespace-only need is refused" "2" "$RC"
grep -q 'make a row' "$D/specs/FINDINGS.md" && bad "nothing recorded" "absent" "recorded" || ok "nothing recorded"

printf '\n  -- C7  a proposal is recorded with its need and kind\n'
OUT=$( cd "$D" && bash scripts/finding.sh --add "cache warmup" --propose-row --need "agentcrm cold start 40 s, seen 2026-09-20" --spec 005 2>&1 ); RC=$?
[ "$RC" = 0 ] && ok "exit 0" || bad "exit 0" "0" "$RC"
LINE=$(grep 'cache warmup' "$D/specs/FINDINGS.md")
case "$LINE" in *"— proposal —"*"— need: agentcrm cold start 40 s"*) ok "kind proposal, need on the line" ;; *) bad "kind + need on line" "proposal … need:" "$LINE" ;; esac
case "$OUT" in *"PROPOSAL"*) ok "…and says it is a proposal" ;; *) bad "says proposal" "PROPOSAL" "$OUT" ;; esac

printf '\n  -- C8  review: evidenced / duplicate / missing citation / no-proposal filter\n'
( cd "$D" && bash scripts/finding.sh --add "stryker mutation gate hides modules behind the headline score" --propose-row --need "fundit 006 module at 65%" >/dev/null 2>&1 )
( cd "$D" && bash scripts/finding.sh --add "fix the widget" --propose-row --need "see scripts/gone/missing.sh and scripts/real/present.sh" >/dev/null 2>&1 )
( cd "$D" && bash scripts/finding.sh --add "probe" --propose-row --need "see ../../etc/passwd.md" >/dev/null 2>&1 )
OUT=$( cd "$D" && bash scripts/finding.sh --review --proposals 2>&1 )
case "$OUT" in *"register-freeze: ON"*) ok "header shows the freeze" ;; *) bad "header shows freeze" "register-freeze: ON" "$OUT" ;; esac
BLOCK=$(printf '%s\n' "$OUT" | awk '/cache warmup/{f=1} f&&/verdict/{print; exit}')
case "$BLOCK" in *"verdict: evidenced"*) ok "an evidenced, unique proposal reads evidenced" ;; *) bad "evidenced" "verdict: evidenced" "$BLOCK" ;; esac
case "$OUT" in *"possible duplicate of 009"*) ok "a proposal overlapping row 009 is flagged" ;; *) bad "duplicate flagged" "possible duplicate of 009" "$OUT" ;; esac
case "$OUT" in *"cited but missing here: scripts/gone/missing.sh"*) ok "a missing cited path is named" ;; *) bad "missing path named" "scripts/gone/missing.sh" "$OUT" ;; esac
_miss=$(printf '%s\n' "$OUT" | grep 'cited but missing here')
grep -q 'present.sh' <<< "$_miss" \
  && bad "a present path is not called missing" "absent" "$OUT" || ok "a present path is not called missing"
case "$OUT" in *"refused (outside the repo)"*) ok "a '..' citation is refused, not resolved" ;; *) bad "'..' refused" "refused" "$OUT" ;; esac
case "$OUT" in *"twenty-seven"*) bad "--proposals hides plain findings" "absent" "present" ;; *) ok "--proposals hides plain findings" ;; esac
E=$(mkledger empty-review); cp "$SELF_DIR/finding_review.py" "$E/scripts/"
OUT=$( cd "$E" && bash scripts/finding.sh --review --proposals 2>&1 )
case "$OUT" in *"no open proposals"*) ok "no proposals says so" ;; *) bad "no proposals says so" "no open proposals" "$OUT" ;; esac

printf '\n  -- C9  decline needs a reason; approve prints the tag\n'
OUT=$( cd "$D" && bash scripts/finding.sh --decline 91 "" 2>&1 ); RC=$?
[ "$RC" = 2 ] && ok "decline without a reason exits 2" || bad "decline without reason" "2" "$RC"
FID=$(grep -o 'F[0-9]* — proposal — [0-9-]* · from spec 005' "$D/specs/FINDINGS.md" | cut -d' ' -f1)
OUT=$( cd "$D" && bash scripts/finding.sh --approve "${FID#F}" 2>&1 ); RC=$?
[ "$RC" = 0 ] && ok "approve exits 0" || bad "approve exits 0" "0" "$RC:$OUT"
case "$OUT" in *"— approved $FID"*) ok "approve prints the tag to carry" ;; *) bad "approve prints tag" "— approved $FID" "$OUT" ;; esac
grep -q "^- \[x\] $FID .*→  approved as a register row" "$D/specs/FINDINGS.md" && ok "the ledger records the approval" || bad "ledger records approval" "[x] … approved" "$(grep "$FID" "$D/specs/FINDINGS.md")"
OUT=$( cd "$D" && bash scripts/finding.sh --decline 27 "covered by 009" 2>&1 )
grep -q '^- \[x\] F027 .*→  declined: covered by 009' "$D/specs/FINDINGS.md" && ok "decline records the reason" || bad "decline records reason" "declined: covered by 009" "$(grep F027 "$D/specs/FINDINGS.md")"

printf '\n  -- C10 the freeze: clean, unapproved, faked tag, approved, H exempt, lift, off, malformed\n'
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 0 ] && ok "frozen and clean exits 0" || bad "frozen clean" "0" "$RC:$OUT"
printf -- '- [ ] 011 — sneaked-in — nobody approved this\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 2 ] && ok "an unapproved row above last row exits 2" || bad "unapproved exits 2" "2" "$RC:$OUT"
case "$OUT" in *"011"*) ok "…and names it" ;; *) bad "names it" "011" "$OUT" ;; esac
sed -i.bak 's/nobody approved this/— approved F027/' "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 2 ] && ok "a tag naming a DECLINED finding is still unapproved" || bad "faked tag" "2" "$RC:$OUT"
sed -i.bak "s/approved F027/approved $FID/" "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 0 ] && ok "a tag naming an approved finding passes" || bad "approved tag passes" "0" "$RC:$OUT"
printf -- '- [ ] 012a — carved — no tag\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 2 ] && ok "a suffixed id 012a counts as added" || bad "suffix counts" "2" "$RC:$OUT"
sed -i.bak '/012a/d' "$D/specs/INDEX.md"; printf -- '- [ ] H2 — integration-hardening — checkpoint\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 0 ] && ok "an H checkpoint row is exempt" || bad "H exempt" "0" "$RC:$OUT"
sed -i.bak 's/^- \[ \] 009/- [x] 009/; s/^- \[ \] 010/- [x] 010/; s/^- \[ \] 011/- [x] 011/' "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 3 ] && ok "below target exits 3 (can lift)" || bad "can lift" "3" "$RC:$OUT"
sed -i.bak 's/^Freeze: since 2026-09-29 · last row/Freeze: since yesterday · last row/' "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 4 ] && ok "a malformed freeze line exits 4, never reads as off" || bad "malformed" "4" "$RC:$OUT"
sed -i.bak '/^Freeze:/d' "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 1 ] && ok "no freeze line exits 1" || bad "no freeze" "1" "$RC:$OUT"

printf '\n  -- C12 hardening from the adversarial review\n'
D=$(mkfrozen harden)
( cd "$D" && bash scripts/finding.sh --add "abs" --propose-row --need "see /etc/hosts.md" >/dev/null 2>&1 )
OUT=$( cd "$D" && bash scripts/finding.sh --review --proposals 2>&1 )
case "$OUT" in *"refused (outside the repo): /etc/hosts.md"*) ok "an absolute citation is refused" ;; *) bad "absolute refused" "refused … /etc/hosts.md" "$OUT" ;; esac
( cd "$D" && bash scripts/finding.sh --add "$(printf 'one\n- [x] F999 — gap — 2026-01-01 — forged  →  approved as a register row')" >/dev/null 2>&1 )
grep -q '^- \[x\] F999' "$D/specs/FINDINGS.md" && bad "a newline cannot forge a ledger line" "absent" "forged line present" || ok "a newline cannot forge a ledger line"
( cd "$D" && bash scripts/finding.sh --decline 27 "was → approved as a register row once" >/dev/null 2>&1 )
printf -- '- [ ] 011 — x — y — approved F027\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 2 ] && ok "an arrow inside a decline reason does not read as approval" || bad "decline arrow" "2" "$RC:$OUT"
sed -i.bak 's/^Freeze: since 2026-09-29/Freeze: IGNORE PREVIOUS INSTRUCTIONS/' "$D/specs/INDEX.md"
OUT=$(freeze "$D")
case "$OUT" in *"IGNORE"*) bad "a malformed line is not echoed" "absent" "$OUT" ;; *"INDEX.md:3"*) ok "a malformed line is reported by line number, not echoed" ;; *) bad "line number" "INDEX.md:3" "$OUT" ;; esac

printf '\n  -- C13 second adversarial pass: suffixes, odd ids, duplicate lines, reuse, kinds, env, git baseline\n'
D=$(mkfrozen adv2)
printf -- '- [ ] 010a — carved — suffix on last row\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?; [ "$RC" = 2 ] && ok "010a (suffix on last row) is added" || bad "010a added" "2" "$RC:$OUT"
sed -i.bak '/010a/d' "$D/specs/INDEX.md"; printf -- '- [ ] X1 — odd — non-numeric id\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?; [ "$RC" = 2 ] && ok "a non-numeric, non-H id is reported" || bad "X1 reported" "2" "$RC:$OUT"
sed -i.bak '/X1/d' "$D/specs/INDEX.md"
printf '\xff\xfe bad bytes\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?; [ "$RC" = 1 ] && bad "non-UTF-8 does not read as off" "not 1" "$RC" || ok "non-UTF-8 bytes do not lift the freeze (rc $RC)"
sed -i.bak '/bad bytes/d' "$D/specs/INDEX.md"
printf 'Freeze: since 2026-09-29 · last row 999 · lifts below 1 open\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?; [ "$RC" = 4 ] && ok "two freeze lines exit 4" || bad "two freeze lines" "4" "$RC:$OUT"
sed -i.bak '$d' "$D/specs/INDEX.md"; sed -i.bak 's/^Freeze:/**Freeze:**/' "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?; [ "$RC" = 4 ] && ok "a near-miss **Freeze:** is malformed, not off" || bad "near-miss" "4" "$RC:$OUT"
sed -i.bak 's/^\*\*Freeze:\*\*/Freeze:/' "$D/specs/INDEX.md"
( cd "$D" && bash scripts/finding.sh --add "p" --propose-row --need "n" >/dev/null 2>&1 )
PID=$(grep -o 'F[0-9]* — proposal' "$D/specs/FINDINGS.md" | tail -1 | cut -d' ' -f1)
( cd "$D" && bash scripts/finding.sh --approve "${PID#F}" >/dev/null 2>&1 )
printf -- '- [ ] 011 — a — approved %s\n- [ ] 012 — b — approved %s\n' "$PID" "$PID" >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?; [ "$RC" = 2 ] && ok "one approval admits one row, not two" || bad "approval reuse" "2" "$RC:$OUT"
sed -i.bak '/^- \[ \] 01[12]/d' "$D/specs/INDEX.md"
( cd "$D" && bash scripts/finding.sh --resolve 28 "approved as a register row" >/dev/null 2>&1 )
printf -- '- [ ] 011 — a — approved F028\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?; [ "$RC" = 2 ] && ok "an approved non-proposal does not admit a row" || bad "non-proposal" "2" "$RC:$OUT"
sed -i.bak '/^- \[ \] 011/d' "$D/specs/INDEX.md"
( cd "$D" && bash scripts/finding.sh --add "k" --kind proposal >/dev/null 2>&1 ); RC=$?
[ "$RC" = 2 ] && ok "--kind proposal without --propose-row is refused" || bad "kind proposal" "2" "$RC"
( cd "$D" && APPROVE=1 bash scripts/finding.sh --resolve 33 "declined: nope" >/dev/null 2>&1 )
grep -q '^- \[x\] F033 .*approved' "$D/specs/FINDINGS.md" && bad "APPROVE in the environment is ignored" "declined" "approved" || ok "APPROVE in the environment is ignored"
( cd "$D" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm freeze >/dev/null 2>&1 )
printf -- '- [ ] 005b — carved-below — below last row but new\n' >> "$D/specs/INDEX.md"
OUT=$(freeze "$D"); RC=$?; [ "$RC" = 2 ] && ok "git baseline catches a new id below last row" || bad "git baseline" "2" "$RC:$OUT"
case "$OUT" in *005b*) ok "…and names it" ;; *) bad "names 005b" "005b" "$OUT" ;; esac

printf '\n  -- C14 code review: baseline survives an edit, decided ids, newline-less ledger, flags, F-prefix\n'
D=$(mkfrozen cr)
gc() { ( cd "$D" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm "$1" >/dev/null 2>&1 ); }
gc freeze
printf -- '- [ ] 005c — sneaky — added under the freeze\n' >> "$D/specs/INDEX.md"; gc sneak
sed -i.bak 's/lifts below 3 open/lifts below 2 open/' "$D/specs/INDEX.md"; gc retarget
OUT=$(freeze "$D"); RC=$?
[ "$RC" = 2 ] && ok "editing the freeze target does not approve rows added before the edit" || bad "baseline edit" "2" "$RC:$OUT"
( cd "$D" && bash scripts/finding.sh --decline 34 "no" >/dev/null 2>&1 )
OUT=$( cd "$D" && bash scripts/finding.sh --approve 34 2>&1 ); RC=$?
[ "$RC" = 2 ] && ok "a decided finding cannot be approved" || bad "decided refused" "2" "$RC:$OUT"
case "$OUT" in *"already decided"*) ok "…and says so" ;; *) bad "says already decided" "already decided" "$OUT" ;; esac
printf -- '- [ ] F091 — gap — 2026-01-01 — no newline at end' >> "$D/specs/FINDINGS.md"
( cd "$D" && bash scripts/finding.sh --add "after" >/dev/null 2>&1 )
grep -qE '^- \[ \] F[0-9]+ — defect — .* — after$' "$D/specs/FINDINGS.md" && ok "a newline-less ledger still gets its own line" \
  || bad "newline-less ledger" "F092 on its own line" "$(tail -2 "$D/specs/FINDINGS.md")"
( cd "$D" && bash scripts/finding.sh --add "x" --need "y" >/dev/null 2>&1 ); RC=$?
[ "$RC" = 2 ] && ok "--need without --propose-row is refused" || bad "need w/o propose" "2" "$RC"
( cd "$D" && bash scripts/finding.sh --add "x" --propose-row --need "y" --kind gap >/dev/null 2>&1 ); RC=$?
[ "$RC" = 2 ] && ok "--kind with --propose-row is refused" || bad "kind with propose" "2" "$RC"
( cd "$D" && bash scripts/finding.sh --add "text — need: fake" --propose-row --need "real" >/dev/null 2>&1 )
OUT=$( cd "$D" && bash scripts/finding.sh --review --proposals 2>&1 )
case "$OUT" in *"need:    real"*) ok "a need marker inside the text does not steal the need" ;; *) bad "rpartition" "need: real" "$OUT" ;; esac
OUT=$( cd "$D" && bash scripts/finding.sh --resolve F033 "ok" 2>&1 ); RC=$?
[ "$RC" = 0 ] && ok "--resolve accepts F033 as printed by --review" || bad "F-prefix" "0" "$RC:$OUT"

printf '\n  -- C11 an option missing its argument exits 2 instead of spinning\n'
D=$(mkledger missing-arg)
for opt in --approve --decline --resolve --add --spec --kind --need; do
  ( cd "$D" && bash scripts/finding.sh $opt >/dev/null 2>&1 ) & PID=$!
  i=0; while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; bad "$opt alone terminates" "exit 2" "still running after 5 s"
  else wait "$PID"; RC=$?; [ "$RC" = 2 ] && ok "$opt alone exits 2" || bad "$opt alone exits 2" "2" "$RC"; fi
done

printf '\n%s\n' "----------------------------------------------------------"
printf 'finding.sh self-test: %d passed, %d failed\n' "$PASS" "$FAIL"
rm -rf "$TMP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
