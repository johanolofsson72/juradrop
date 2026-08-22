#!/bin/bash
# Tests refresh_local_template() in scripts/template-autosync.sh.
#
# The bug it guards: a local template clone was preferred over the tarball and
# never fetched, so a developer who followed sync-prompt.md Step -1 and cloned
# the template pinned their autosync to that commit forever, silently.
#
# Four states, and only one of them should move anything:
#   equal     -> no change, no output
#   behind    -> fast-forwarded to origin/main
#   ahead     -> untouched (the template author mid-work)
#   diverged  -> untouched, warned
# Plus: dirty-and-behind stays untouched, and a non-template repo parked at the
# path is never fetched.
#
# Run: bash scripts/test-template-clone-refresh.sh

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found"; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

# Extract just the function under test. The script does real work at load time,
# so sourcing it whole is not an option.
HARNESS=$(mktemp)
{
  echo 'QUIET=0'
  echo 'say()  { printf "%s\n" "$*"; }'
  echo 'warn() { printf "%s\n" "$*"; }'
  sed -n '/^refresh_local_template() {$/,/^}$/p' "$SCRIPT"
} > "$HARNESS"
grep -q 'refresh_local_template' "$HARNESS" || { echo "FAIL: could not extract function"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP" "$HARNESS"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A bare "origin" that looks like the template repo to the URL check.
ORIGIN="$TMP/johanolofsson72/Claude.git"
mkdir -p "$(dirname "$ORIGIN")"
git init -q --bare -b main "$ORIGIN"

SEED="$TMP/seed"
git init -q -b main "$SEED"
mkdir -p "$SEED/scripts" "$SEED/.claude/rules"
echo v1 > "$SEED/scripts/sync-prompt.md"
echo v1 > "$SEED/.claude/rules/frontend.md"
git -C "$SEED" add -A && git -C "$SEED" commit -qm v1
git -C "$SEED" remote add origin "$ORIGIN" && git -C "$SEED" push -q origin main

# Advance origin by one commit so clones can be "behind".
echo v2 > "$SEED/.claude/rules/frontend.md"
git -C "$SEED" commit -qam v2 && git -C "$SEED" push -q origin main
V2=$(git -C "$SEED" rev-parse HEAD)
V1=$(git -C "$SEED" rev-parse HEAD~1)

clone_at() {  # clone_at <dir> <sha>
  git clone -q "$ORIGIN" "$1" 2>/dev/null
  git -C "$1" checkout -q -B main "$2"
}
run() { ( . "$HARNESS"; refresh_local_template "$1" ) 2>&1; }

echo "== behind: the bug =="
C="$TMP/behind"; clone_at "$C" "$V1"
OUT=$(run "$C")
check "fast-forwards to origin/main" "$(git -C "$C" rev-parse HEAD)" "$V2"
case "$OUT" in *"fast-forwarded"*) ok "says it fast-forwarded" ;; *) bad "silent fast-forward: '$OUT'" ;; esac
check "file content actually moved" "$(cat "$C/.claude/rules/frontend.md")" "v2"

echo "== equal: nothing to do =="
C="$TMP/equal"; clone_at "$C" "$V2"
OUT=$(run "$C")
check "stays at origin/main" "$(git -C "$C" rev-parse HEAD)" "$V2"
check "says nothing" "$OUT" ""

echo "== ahead: the template author mid-work =="
C="$TMP/ahead"; clone_at "$C" "$V2"
echo v3 > "$C/.claude/rules/frontend.md"; git -C "$C" commit -qam v3
AHEAD=$(git -C "$C" rev-parse HEAD)
OUT=$(run "$C")
check "local commit is preserved" "$(git -C "$C" rev-parse HEAD)" "$AHEAD"
check "does not warn" "$OUT" ""

echo "== diverged: touch nothing, warn =="
C="$TMP/diverged"; clone_at "$C" "$V1"
echo other > "$C/.claude/rules/frontend.md"; git -C "$C" commit -qam local-work
DIV=$(git -C "$C" rev-parse HEAD)
OUT=$(run "$C")
check "clone is untouched" "$(git -C "$C" rev-parse HEAD)" "$DIV"
case "$OUT" in *diverged*) ok "warns about divergence" ;; *) bad "no divergence warning: '$OUT'" ;; esac

echo "== dirty and behind: uncommitted work wins, but say so =="
C="$TMP/dirty"; clone_at "$C" "$V1"
echo scratch > "$C/.claude/rules/frontend.md"
OUT=$(run "$C")
check "stays behind (no ff over dirty tree)" "$(git -C "$C" rev-parse HEAD)" "$V1"
check "uncommitted change survives" "$(cat "$C/.claude/rules/frontend.md")" "scratch"
case "$OUT" in *"uncommitted"*) ok "warns that the source is stale" ;; *) bad "silent stale sync: '$OUT'" ;; esac

echo "== a different repo parked at the path is never fetched =="
C="$TMP/notours"; git init -q -b main "$C"
mkdir -p "$C/scripts" "$C/.claude/rules"; echo x > "$C/scripts/sync-prompt.md"
git -C "$C" add -A && git -C "$C" commit -qm x
git -C "$C" remote add origin "https://github.com/someone/else.git"
SHA=$(git -C "$C" rev-parse HEAD)
OUT=$(run "$C")
check "left alone" "$(git -C "$C" rev-parse HEAD)" "$SHA"
check "says nothing" "$OUT" ""

echo "== not a git clone at all: fails open =="
C="$TMP/plain"; mkdir -p "$C/scripts" "$C/.claude/rules"; echo x > "$C/scripts/sync-prompt.md"
OUT=$(run "$C"); RC=$?
check "returns 0" "$RC" "0"
check "says nothing" "$OUT" ""

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
