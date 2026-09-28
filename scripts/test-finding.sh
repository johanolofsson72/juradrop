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

printf '\n%s\n' "----------------------------------------------------------"
printf 'finding.sh self-test: %d passed, %d failed\n' "$PASS" "$FAIL"
rm -rf "$TMP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
