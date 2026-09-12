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

echo "next-register-id: $P passed, $F failed"
[ "$F" -eq 0 ]
