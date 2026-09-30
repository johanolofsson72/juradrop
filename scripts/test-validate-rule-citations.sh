#!/bin/bash
# Tests scripts/validate-rule-citations.sh and the rule it was written for (spec 041).
#
# The defect: ten files cited .claude/rules/mutation-timeouts.md, most of them for its "trap 4", and
# the file never existed. Nothing checked that a cited rule is there, so a principle two rules and
# eight scripts reason with had no statement anyone could read.
#
# What would make this test lie, and the arm that stops it:
#   - a scan that finds nothing and says clean      → SC-J expects exit 3, not 0
#   - a validator that only reads one line          → SC-G splits the trap citation over two
#   - a fixture exemption wide enough to hide a real dangling citation → SC-B has no $ROOT form
#   - a real-repo arm that passes because it read nothing → SC-L asserts a nonzero count
#
# Run: bash scripts/test-validate-rule-citations.sh

set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
V="$REPO/scripts/validate-rule-citations.sh"
[ -f "$V" ] || { echo "FAIL: scripts/validate-rule-citations.sh not found"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required (the validator reads git ls-files)"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The dangling citations the arms plant, spelled so this file never holds one literally. SC-L runs
# the validator over the template itself, and this file is tracked: a literal rule path
# in a printf format is text the scan reads as a citation (H1, F036). Splitting the extension is
# narrower than any exemption the validator could grow for it.
NOWHERE='.claude/rules/nowhere'.md
GONE='.claude/docs/gone'.md
MISSING_MD='missing-rule'.md
BASE_MD='base'.md

# A git repo holding one rule with two traps, one doc, and whatever the arm adds. Files are tracked,
# because the validator reads the index, not the directory.
fixture() {
  _r="$TMP/$1"; rm -rf "$_r"; mkdir -p "$_r/.claude/rules" "$_r/.claude/docs" "$_r/scripts"
  printf '# Base rule\n\n## Trap 1 — one\n\nx\n\n## Trap 2 — two\n\ny\n' > "$_r/.claude/rules/base.md"
  printf '# A doc\n' > "$_r/.claude/docs/guide.md"
  printf '# see .claude/rules/base.md and .claude/docs/guide.md\n' > "$_r/scripts/ok.sh"
  git -C "$_r" init -q
  printf '%s\n' "$_r"
}
track() { git -C "$1" add -A >/dev/null 2>&1; }
run() { OUT=$(bash "$V" "$1" 2>&1); RC=$?; }

echo "validate-rule-citations"

R=$(fixture clean); track "$R"; run "$R"
same "SC-A clean fixture exits 0" "$RC" 0
has  "SC-A …and says how many citations it checked" "$OUT" "2 citation(s)"

R=$(fixture missing-rule)
printf '# per %s\n' "$NOWHERE" > "$R/scripts/bad.sh"; track "$R"; run "$R"
same "SC-B missing rule exits 1" "$RC" 1
has  "SC-B …names file:line and the path" "$OUT" "scripts/bad.sh:1: $NOWHERE does not exist"

R=$(fixture missing-doc)
printf 'See `%s`.\n' "$GONE" > "$R/.claude/rules/cites.md"; track "$R"; run "$R"
same "SC-C missing doc exits 1" "$RC" 1
has  "SC-C …names the doc" "$OUT" ".claude/rules/cites.md:1: $GONE does not exist"

R=$(fixture fixture-path)
cat > "$R/scripts/test-thing.sh" <<'EOF'
printf 'v1\n' > "$T/.claude/rules/demo-rule.md"
has "names it" "$OUT" "modified   .claude/rules/demo-rule.md"
EOF
track "$R"; run "$R"
same "SC-D a path the file builds under \$T/ is a fixture, exempt" "$RC" 0

R=$(fixture trap-ok)
printf '# an empty result is trap 2 (.claude/rules/base.md)\n' > "$R/scripts/t.sh"; track "$R"; run "$R"
same "SC-E a trap the rule defines resolves" "$RC" 0

R=$(fixture trap-missing)
printf '# see .claude/rules/base.md, trap 9\n' > "$R/scripts/t.sh"; track "$R"; run "$R"
same "SC-F an undefined trap exits 1" "$RC" 1
has  "SC-F …and says which" "$OUT" "scripts/t.sh:1: trap 9 is not defined in .claude/rules/base.md"

R=$(fixture trap-two-lines)
printf '# the known positive from trap 9 in\n#   .claude/rules/base.md: bites\n' > "$R/scripts/t.sh"; track "$R"; run "$R"
same "SC-G a trap on the line before the path is read" "$RC" 1
has  "SC-G …and reported at the path's line" "$OUT" "scripts/t.sh:2: trap 9 is not defined"
printf '# the known positive from trap 2 in\n#   .claude/rules/base.md: bites\n' > "$R/scripts/t.sh"; track "$R"; run "$R"
same "SC-G …and the defined one resolves" "$RC" 0

R=$(fixture bare-basename)
printf '#   2. never run as clean — trap 4 in %s.\n' "$MISSING_MD" > "$R/scripts/t.sh"; track "$R"; run "$R"
same "SC-H a bare trap citation of an absent file exits 1" "$RC" 1
has  "SC-H …names the basename" "$OUT" "missing-rule.md"
printf '#   2. an empty result — trap 1 in %s.\n' "$BASE_MD" > "$R/scripts/t.sh"; track "$R"; run "$R"
same "SC-H …and a bare citation of a real rule resolves" "$RC" 0

R=$(fixture specs-skipped)
mkdir -p "$R/specs"; printf 'cites %s, trap 4\n' "$NOWHERE" > "$R/specs/INDEX.pending.md"; track "$R"; run "$R"
same "SC-I specs/ is history, not scanned" "$RC" 0

R="$TMP/empty"; rm -rf "$R"; mkdir -p "$R"; git -C "$R" init -q; printf 'nothing\n' > "$R/a.txt"; track "$R"; run "$R"
same "SC-J no citations at all exits 3" "$RC" 3
has  "SC-J …and calls it unmeasurable, not clean" "$OUT" "unmeasurable"

R="$TMP/nogit"; rm -rf "$R"; mkdir -p "$R"; run "$R"
same "SC-K not a git work tree exits 2" "$RC" 2

# THE KNOWN POSITIVE. Red on HEAD before spec 041: ten citations of a file that did not exist.
run "$REPO"
same "SC-L the template's own citations all resolve" "$RC" 0
case "$OUT" in *" 0 citation(s)"*) bad "SC-L …read nothing" ;; *) ok "SC-L …and read something: ${OUT##*: }" ;; esac

RULE="$REPO/.claude/rules/mutation-timeouts.md"
if [ -f "$RULE" ]; then
  HEAD5=$(head -5 "$RULE")
  has "SC-M the rule is path-scoped" "$HEAD5" "paths:"
  for n in 1 2 3 4 5; do
    if grep -qE "^## Trap $n " "$RULE"; then ok "SC-M Trap $n is defined"; else bad "SC-M Trap $n is defined"; fi
  done
else
  bad "SC-M .claude/rules/mutation-timeouts.md exists"
fi

# Membership, not substring: a list that holds only `test-validate-rule-citations.sh` must not pass
# the validator's own arm.
# Query modes only, so drive_sync_readonly: a direct run here is what the sandbox gate forbids (H1).
. "$REPO/scripts/drive-sync.sh"
listed() {
  _l=$(DRIVE_SYNC_SCRIPT="$REPO/scripts/template-autosync.sh" drive_sync_readonly "$REPO" "$2" 2>/dev/null)
  case "
$_l
" in *"
$3
"*) ok "$1" ;; *) bad "$1 ($3 not in $2)" ;; esac
}
listed "SC-N the rule ships (CORE_RULES)" --list-core-rules  mutation-timeouts.md
listed "SC-N the validator ships"         --list-core-scripts validate-rule-citations.sh
listed "SC-N its test ships"              --list-core-scripts test-validate-rule-citations.sh

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
