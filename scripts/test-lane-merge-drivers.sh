#!/bin/bash
# test-lane-merge-drivers.sh — prove the union driver actually resolves the merge
# it was installed for, and that the backstop still catches what union hides.
#
# The claim being tested is specific: two lanes appending DIFFERENT rows to
# specs/INDEX.md merge clean and keep both rows; two lanes editing the SAME row
# merge without a conflict marker and produce a duplicate that a gate must catch.
# The second half is the trade this driver makes, so it is tested, not assumed.
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PASS=0; FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

setup() { # setup <dir> <install: yes|no>
  local d="$1" install="$2"
  rm -rf "$d"; mkdir -p "$d/specs" "$d/scripts"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  cp "$SCRIPT_DIR/install-lane-merge-drivers.sh" "$d/scripts/"
  printf '# Spec register\n\n## Specs\n\n- [ ] 001 — a — spec-only — goal\n- [ ] 002 — b — spec-only — goal\n' > "$d/specs/INDEX.md"
  git -C "$d" add -A; git -C "$d" commit -qm base
  if [ "$install" = yes ]; then
    ( cd "$d" && bash scripts/install-lane-merge-drivers.sh >/dev/null 2>&1 )
    git -C "$d" add -A; git -C "$d" commit -qm attrs
  fi
}

two_lanes() { # two_lanes <dir> <lineA> <lineB>  -- both branch from main, each appends
  local d="$1"
  git -C "$d" checkout -q -b laneA main
  printf '%s\n' "$2" >> "$d/specs/INDEX.md"; git -C "$d" commit -qam A
  git -C "$d" checkout -q -b laneB main
  printf '%s\n' "$3" >> "$d/specs/INDEX.md"; git -C "$d" commit -qam B
}

# 1. Without the driver, this is the conflict the developers were living with.
setup "$TMP/without" no
two_lanes "$TMP/without" '- [ ] 003 — johan-row — spec-only — goal' '- [ ] 004 — david-row — spec-only — goal'
if git -C "$TMP/without" merge laneA -m m >/dev/null 2>&1; then
  bad "control: append/append should conflict WITHOUT the driver"
else ok "control: append/append conflicts without the driver"; fi

# 2. With it, the same merge is clean and keeps both rows.
setup "$TMP/with" yes
two_lanes "$TMP/with" '- [ ] 003 — johan-row — spec-only — goal' '- [ ] 004 — david-row — spec-only — goal'
if git -C "$TMP/with" merge laneA -m m >/dev/null 2>&1; then
  if grep -q 'johan-row' "$TMP/with/specs/INDEX.md" && grep -q 'david-row' "$TMP/with/specs/INDEX.md"; then
    ok "append/append merges clean and keeps both rows"
  else bad "merge was clean but a row was lost"; fi
else bad "append/append still conflicts WITH the driver"; fi

# 3. No conflict markers leaked into the file.
grep -q '<<<<<<<\|>>>>>>>' "$TMP/with/specs/INDEX.md" \
  && bad "conflict markers left in the merged file" \
  || ok "no conflict markers in the merged file"

# 4. The documented trade: both lanes editing the SAME row is kept twice, not
#    flagged. This is the risk the rule bounds with validate-register-ids.sh --
#    asserted here so nobody discovers it in a merge instead of in a test.
setup "$TMP/samerow" yes
git -C "$TMP/samerow" checkout -q -b laneA main
sed -i.bak 's/- \[ \] 002 — b — spec-only — goal/- [x] 002 — b — spec-only — goal/' "$TMP/samerow/specs/INDEX.md"
rm -f "$TMP/samerow/specs/INDEX.md.bak"; git -C "$TMP/samerow" commit -qam A
git -C "$TMP/samerow" checkout -q -b laneB main
sed -i.bak 's/- \[ \] 002 — b — spec-only — goal/- [!] 002 — b — spec-only — goal/' "$TMP/samerow/specs/INDEX.md"
rm -f "$TMP/samerow/specs/INDEX.md.bak"; git -C "$TMP/samerow" commit -qam B
git -C "$TMP/samerow" merge laneA -m m >/dev/null 2>&1
n=$(grep -c '002 — b' "$TMP/samerow/specs/INDEX.md")
if [ "$n" = 2 ]; then
  ok "same-row edit yields a DUPLICATE (the documented trade; validate-register-ids.sh is the gate)"
else
  bad "same-row edit produced $n copies of the row — the documented trade has changed, re-read the rule"
fi

# 5. Idempotent: installing twice must not stack the block.
setup "$TMP/idem" yes
( cd "$TMP/idem" && bash scripts/install-lane-merge-drivers.sh >/dev/null 2>&1 )
n=$(grep -c '>>> claude lane merge drivers' "$TMP/idem/.gitattributes")
[ "$n" = 1 ] && ok "install is idempotent" || bad "install stacked the block ($n copies)"

# 6. --remove takes it back out.
( cd "$TMP/idem" && bash scripts/install-lane-merge-drivers.sh --remove >/dev/null 2>&1 )
grep -q 'claude lane merge drivers' "$TMP/idem/.gitattributes" \
  && bad "--remove left the block behind" || ok "--remove removes the block"

# 7. The success message must not execute its own backticks. An unquoted heredoc
#    printed "union: command not found" into the middle of it on the first real
#    run against agentcrm.
# The fixture must be a fresh repo: on an already-installed one the script prints
# "already installed" and never reaches the message under test, which would pass
# this assertion without exercising anything.
setup "$TMP/heredoc" no
out=$( cd "$TMP/heredoc" && bash "$SCRIPT_DIR/install-lane-merge-drivers.sh" 2>&1 )
grep -q 'is a built-in git merge strategy' <<< "$out" \
  || bad "success message did not print — the assertion below would be vacuous"
grep -q 'command not found' <<< "$out" \
  && bad "success message runs its own backticks (unquoted heredoc)" \
  || ok "success message does not execute its backticks"

# 8. SCENARIOS.md must NOT be union-merged: interleaving two Mermaid graphs
#    produces a diagram that renders as nothing, and nothing would report it.
grep -qE '^specs/SCENARIOS\.md\s+merge=union' "$SCRIPT_DIR/install-lane-merge-drivers.sh" \
  && bad "SCENARIOS.md is union-merged — Mermaid blocks would interleave" \
  || ok "SCENARIOS.md is excluded from union merge"

echo "lane-merge-drivers: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
