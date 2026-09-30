#!/bin/bash
# test-next-register-id.sh — the id allocator never hands out a taken id.
#
# Three colliding ids were picked by hand on 2026-09-03 (rocky 578-580 and H12,
# the template's 021, film-i-vast's 032). validate-register-ids.sh caught every
# one; each still cost a commit, a renumber and a second push.
set -uo pipefail
export LC_ALL=C
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$SD/next-register-id.sh"
P=0; F=0
ok(){ echo "  PASS  $1"; P=$((P+1)); }
bad(){ echo "  FAIL  $1"; F=$((F+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

mk(){ mkdir -p "$1/specs"; { echo "# Spec register"; echo; echo "## Specs"; echo; cat; } > "$1/specs/INDEX.md"; }

# Append, not fill-the-gap: the register rule says append, and a low free id on a
# mature register reads as a renumber nobody decided.
mk "$T/a" <<'M'
- [x] 404 — old — spec-only — a row
- [ ] 587 — newest — spec-only — a row
M
got=$(bash "$SUT" --dir "$T/a")
[ "$got" = "588" ] && ok "appends past the highest id (588)" || bad "append: got $got, want 588"

# An archived id is taken. rocky keeps INDEX-done.md beside the other archives,
# and an id this cannot see is an id it hands out twice.
printf '# done\n\n## 604 — archived — spec-only — a row\n' > "$T/a/specs/INDEX-done.md"
got=$(bash "$SUT" --dir "$T/a")
[ "$got" = "605" ] && ok "an id in any INDEX*.md sibling is taken (605)" || bad "archive: got $got, want 605"

# Ticked rows count — an id is a permanent handle and is never reused.
mk "$T/b" <<'M'
- [x] 001 — done — spec-only — a row
- [x] 002 — done — spec-only — a row
M
got=$(bash "$SUT" --dir "$T/b")
[ "$got" = "003" ] && ok "a ticked row's id is taken (003)" || bad "ticked: got $got, want 003"

# Several at once, all distinct and all free.
got=$(bash "$SUT" --dir "$T/b" --count 3 | tr '\n' ' ')
[ "$got" = "003 004 005 " ] && ok "--count returns distinct consecutive ids" || bad "--count: got '$got'"

# Letter series append too.
mk "$T/c" <<'M'
- [x] S1 — a — spec-only — a row
- [ ] S20 — b — spec-only — a row
- [x] H1 — cp — checkpoint — a row
M
got=$(bash "$SUT" --dir "$T/c" --alpha S)
[ "$got" = "S21" ] && ok "--alpha appends in its own series (S21)" || bad "--alpha: got $got, want S21"
got=$(bash "$SUT" --dir "$T/c" --checkpoint)
[ "$got" = "H2" ] && ok "--checkpoint appends in the H series (H2)" || bad "--checkpoint: got $got, want H2"

# The width of the register's own ids is preserved.
mk "$T/d" <<'M'
- [x] 0001 — wide — spec-only — a row
M
got=$(bash "$SUT" --dir "$T/d")
[ "$got" = "0002" ] && ok "keeps the register's id width (0002)" || bad "width: got $got, want 0002"

# No register is a usage error, never a guessed id.
mkdir -p "$T/e"
bash "$SUT" --dir "$T/e" >/dev/null 2>&1
[ "$?" = 2 ] && ok "no register exits 2 rather than guessing" || bad "no register did not exit 2"

# THE POINT: whatever it returns is not already in the register.
for d in "$T/a" "$T/b" "$T/c"; do
  n=$(bash "$SUT" --dir "$d" 2>/dev/null)
  if grep -qE "^- \[[ xX/!]\] +\*{0,2}${n} — " "$d/specs/INDEX.md"; then
    bad "handed out a taken id ($n)"; else P=$((P+1)); fi
done
ok "every returned id is free in its register"

# --suffix: the carved id, parent plus the next free letter (row 066, fundit F095).
# --alpha 005 returned 0051, so carved ids were the one shape still picked by eye.
mk "$T/s" <<'M'
- [x] 005 — parent — spec-only — a row
- [ ] 006 — other — spec-only — a row
- [ ] 007 — root — spec-only — a row
- [x] 007c — child — spec-only — a row
- [ ] 007ch — grandchild — spec-only — a row
- [x] H7 — cp — checkpoint — a row
- [ ] H7u — carved — spec-only — a row
- [ ] 009 — upper — spec-only — a row
- [ ] 009A — upper child — spec-only — a row
M
got=$(bash "$SUT" --dir "$T/s" --suffix 005 2>/dev/null)
[ "$got" = "005a" ] && ok "--suffix gives the parent its first letter (005a)" || bad "--suffix 005: got '$got', want 005a"
got=$(bash "$SUT" --dir "$T/s" --suffix 006 2>/dev/null)
[ "$got" = "006a" ] && ok "--suffix on an open parent (006a)" || bad "--suffix 006: got '$got', want 006a"
got=$(bash "$SUT" --dir "$T/s" --suffix 007 2>/dev/null)
[ "$got" = "007d" ] && ok "--suffix ignores a grandchild (007ch is 007c's) → 007d" || bad "--suffix 007: got '$got', want 007d"
got=$(bash "$SUT" --dir "$T/s" --suffix 007c 2>/dev/null)
[ "$got" = "007ci" ] && ok "--suffix on a carved parent (007ci)" || bad "--suffix 007c: got '$got', want 007ci"
got=$(bash "$SUT" --dir "$T/s" --suffix H7 2>/dev/null)
[ "$got" = "H7v" ] && ok "--suffix on a letter-led parent (H7v)" || bad "--suffix H7: got '$got', want H7v"
got=$(bash "$SUT" --dir "$T/s" --suffix 009 2>/dev/null)
[ "$got" = "009b" ] && ok "an uppercase 009A counts as taken (009b)" || bad "--suffix 009: got '$got', want 009b"

# Append past the highest letter; a ticked or archived child is still taken.
mk "$T/t" <<'M'
- [x] 005 — parent — spec-only — a row
- [x] 005a — done child — spec-only — a row
- [ ] 005c — open child — spec-only — a row
M
got=$(bash "$SUT" --dir "$T/t" --suffix 005 2>/dev/null)
[ "$got" = "005d" ] && ok "--suffix appends past the highest letter (005d)" || bad "--suffix append: got '$got', want 005d"
printf '# done\n\n## 005f — archived child — spec-only — a row\n' > "$T/t/specs/INDEX.completed.md"
got=$(bash "$SUT" --dir "$T/t" --suffix 005 2>/dev/null)
[ "$got" = "005g" ] && ok "an archived child is taken (005g)" || bad "--suffix archive: got '$got', want 005g"
got=$(bash "$SUT" --dir "$T/t" --suffix 005 --count 3 2>/dev/null | tr '\n' ' ')
[ "$got" = "005g 005h 005i " ] && ok "--suffix --count returns consecutive letters" || bad "--suffix --count: got '$got'"

# A parent that lives only in an archive is still a real parent.
printf '## 004 — archived parent — spec-only — a row\n' >> "$T/t/specs/INDEX.completed.md"
got=$(bash "$SUT" --dir "$T/t" --suffix 004 2>/dev/null)
[ "$got" = "004a" ] && ok "a parent known only to an archive is accepted (004a)" || bad "archived parent: got '$got', want 004a"

# Refusals: exit 2, a named reason, nothing on stdout.
out=$(bash "$SUT" --dir "$T/t" --suffix 999 2>"$T/err"); rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q "999" "$T/err" && ok "an unknown parent exits 2 and names it" \
  || bad "unknown parent: rc=$rc out='$out' err='$(cat "$T/err")'"
bash "$SUT" --dir "$T/t" --suffix 2>"$T/err" >/dev/null; rc=$?
[ "$rc" = 2 ] && grep -q -- "--suffix needs a parent" "$T/err" && ok "a missing parent says so" || bad "missing parent: rc=$rc"
for p in 'x y' '005-' '' '0/5'; do
  out=$(bash "$SUT" --dir "$T/t" --suffix "$p" 2>/dev/null); rc=$?
  [ "$rc" = 2 ] && [ -z "$out" ] && P=$((P+1)) || bad "malformed parent '$p': rc=$rc out='$out'"
done
ok "a malformed parent exits 2"
out=$(bash "$SUT" --dir "$T/t" --suffix 005 --alpha S 2>/dev/null); rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] && ok "--suffix with --alpha is a usage error" || bad "--suffix+--alpha: rc=$rc out='$out'"
out=$(bash "$SUT" --dir "$T/t" --checkpoint --suffix 005 2>/dev/null); rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] && ok "--checkpoint with --suffix is a usage error" || bad "--checkpoint+--suffix: rc=$rc out='$out'"

# Out of letters: exit 2, never wrap into another parent's namespace, never a partial list.
mk "$T/u" <<'M'
- [x] 005 — parent — spec-only — a row
- [ ] 005z — last — spec-only — a row
- [ ] 006 — parent — spec-only — a row
- [ ] 006x — near the end — spec-only — a row
M
out=$(bash "$SUT" --dir "$T/u" --suffix 005 2>"$T/err"); rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q "a-z" "$T/err" && ok "past z exits 2, says the letters ran out" \
  || bad "exhausted: rc=$rc out='$out' err='$(cat "$T/err")'"
out=$(bash "$SUT" --dir "$T/u" --suffix 006 --count 3 2>"$T/err"); rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q "a-z" "$T/err" && ok "--count past z is all-or-nothing" || bad "partial: rc=$rc out='$out'"

# THE POINT, again: a carved id is free and parses under the resolver's numeric grammar.
for par in 005 006 007 007c; do
  n=$(bash "$SUT" --dir "$T/s" --suffix "$par" 2>/dev/null)
  if [ -n "$n" ] && ! grep -qiE "^- \[[ xX/!]\] +\*{0,2}${n} — " "$T/s/specs/INDEX.md" \
     && grep -qE '^[0-9]+[a-z]+$' <<< "$n"; then P=$((P+1)); else bad "carved id '$n' is taken or off-grammar"; fi
done
ok "every carved id is free and on-grammar"

echo "next-register-id: $P passed, $F failed"
[ "$F" -eq 0 ]
