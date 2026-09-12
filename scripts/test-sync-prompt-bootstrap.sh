#!/bin/bash
# Tests the Step -1 bootstrap block embedded in scripts/sync-prompt.md.
#
# That block is the reason /project-update alone is sufficient: it finds the
# template clone, clones one if there is none, and refreshes it against
# origin/main before any later step reads a file from it. Without the refresh
# the sync delivers months-old content while reporting success, because
# /project-update fetches its INSTRUCTIONS from GitHub but its FILES from the
# local clone.
#
# The block lives inside markdown, where nothing would otherwise notice it
# breaking. This test extracts it verbatim and runs it against real git repos.
#
# Run: bash scripts/test-sync-prompt-bootstrap.sh

set -u
cd "$(dirname "$0")/.." || exit 1
SRC="$PWD/scripts/sync-prompt.md"

# THIS HARNESS ONLY HAS A SUBJECT UPSTREAM.
#
# It extracts the Step -1 block out of scripts/sync-prompt.md and runs it. That file is
# authoritative in exactly one place: /project-update fetches it from
# raw.githubusercontent.com/johanolofsson72/Claude/main/scripts/sync-prompt.md (project-update
# SKILL.md, Step 4), so a project-local copy is a snapshot nobody reads. Two of the eight projects
# do not carry one at all and this harness failed there with "sync-prompt.md not found" — a red
# test for the absence of a file the project has no reason to have.
#
# Same predicate and same reasoning as test-sync-prompt-core-parity.sh and
# validate-no-sigpipe-assertions.sh: compare origin against the template slug, fall back to the
# sync stamp, and exempt nothing when neither answers.
_origin() {
  local top phys
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  phys="$(pwd -P)" || return 0
  [ "$top" = "$phys" ] || return 0
  git remote get-url origin 2>/dev/null || true
}
_O="$(_origin)"
case "$_O" in
  *johanolofsson72/Claude|*johanolofsson72/Claude.git|*johanolofsson72/Claude/|*johanolofsson72/Claude.git/) ;;
  "") [ -f .claude/.template-sync ] && {
        echo "SKIP: downstream (.claude/.template-sync is present) — the sync-prompt.md this would test"
        echo "      is not the one /project-update reads; the authoritative copy is fetched from GitHub."
        exit 0; } ;;
  *)  echo "SKIP: downstream (origin is $_O, not johanolofsson72/Claude) — the sync-prompt.md this would"
      echo "      test is not the one /project-update reads; the authoritative copy is fetched from GitHub."
      exit 0 ;;
esac

[ -f "$SRC" ] || { echo "FAIL: sync-prompt.md not found"; exit 1; }

# This tests a TEMPLATE artifact. A synced project also carries a scripts/
# sync-prompt.md, but that copy is never the one /project-update executes -- Step 4
# curls the file fresh from GitHub -- and autosync's copy loop globs *.sh and *.py,
# so the project's copy is a stale snapshot by design. Running the assertions
# against it reports failures about a file nobody uses. Run here only when this IS
# the template repo; anywhere else, say so and pass.
case "$(git remote get-url origin 2>/dev/null)" in
  *johanolofsson72/Claude*) ;;
  *)
    echo "SKIP — not the template repo. scripts/sync-prompt.md here is a stale local"
    echo "       copy; /project-update fetches the authoritative one from GitHub."
    exit 0 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ---- extract the first bash block after the Step -1 heading, verbatim
BLOCK="$TMP/step-1.sh"
awk '
  /^### Step -1:/      { seen=1 }
  seen && /^```bash$/  { inb=1; next }
  inb && /^```$/       { exit }
  inb                  { print }
' "$SRC" > "$BLOCK"
[ -s "$BLOCK" ] || { echo "FAIL: could not extract the Step -1 bash block"; exit 1; }
bash -n "$BLOCK" || { echo "FAIL: the Step -1 block is not valid bash"; exit 1; }
ok "Step -1 block extracts and parses as bash"

# ---- a bare repo whose PATH matches the origin test in the block
ORIGIN="$TMP/johanolofsson72/Claude.git"
mkdir -p "$(dirname "$ORIGIN")"; git init -q --bare -b main "$ORIGIN"

SEED="$TMP/seed"; git init -q -b main "$SEED"
mkdir -p "$SEED/.claude/skills/sync-template" "$SEED/.claude/rules"
echo v1 > "$SEED/CLAUDE.md"; echo v1 > "$SEED/.claude/skills/sync-template/SKILL.md"
git -C "$SEED" add -A && git -C "$SEED" commit -qm v1
git -C "$SEED" remote add origin "$ORIGIN" && git -C "$SEED" push -q origin main
echo v2 > "$SEED/CLAUDE.md"; git -C "$SEED" commit -qam v2 && git -C "$SEED" push -q origin main
V2=$(git -C "$SEED" rev-parse HEAD); V1=$(git -C "$SEED" rev-parse HEAD~1)

# The block clones from a hardcoded github URL; point it at the local bare repo
# so the test never touches the network. Everything else runs verbatim.
RUNNER="$TMP/run.sh"
sed "s#^TEMPLATE_URL=.*#TEMPLATE_URL=\"$ORIGIN\"#" "$BLOCK" > "$RUNNER"

run() {  # run <fake-home>  -> stdout of the block
  ( HOME="$1" CLAUDE_TEMPLATE_DIR="" bash "$RUNNER" 2>&1 )
}
clone_at() { git clone -q "$ORIGIN" "$1"; git -C "$1" checkout -q -B main "$2"; }

echo "== no clone anywhere: it makes one =="
H="$TMP/h-fresh"; mkdir -p "$H"
OUT=$(run "$H")
check "clone created at \$HOME/repos/Claude" "$([ -d "$H/repos/Claude/.git" ] && echo yes || echo no)" "yes"
case "$OUT" in *"Cloned the template"*) ok "says it cloned" ;; *) bad "no clone message: $OUT" ;; esac
check "clone is at origin/main" "$(git -C "$H/repos/Claude" rev-parse HEAD)" "$V2"

echo "== behind + clean: fast-forwards (the silent-staleness case) =="
H="$TMP/h-behind"; mkdir -p "$H/repos"; clone_at "$H/repos/Claude" "$V1"
OUT=$(run "$H")
check "fast-forwarded" "$(git -C "$H/repos/Claude" rev-parse HEAD)" "$V2"
check "content actually moved" "$(cat "$H/repos/Claude/CLAUDE.md")" "v2"
case "$OUT" in *"fast-forwarded"*) ok "says it fast-forwarded" ;; *) bad "silent ff: $OUT" ;; esac

echo "== behind + dirty: local work wins, staleness announced =="
H="$TMP/h-dirty"; mkdir -p "$H/repos"; clone_at "$H/repos/Claude" "$V1"
echo scratch > "$H/repos/Claude/CLAUDE.md"
OUT=$(run "$H")
check "not fast-forwarded" "$(git -C "$H/repos/Claude" rev-parse HEAD)" "$V1"
check "uncommitted work survives" "$(cat "$H/repos/Claude/CLAUDE.md")" "scratch"
case "$OUT" in *BEHIND*uncommitted*) ok "warns it is behind with local changes" ;; *) bad "no warning: $OUT" ;; esac

echo "== ahead: unpushed template work is left alone =="
H="$TMP/h-ahead"; mkdir -p "$H/repos"; clone_at "$H/repos/Claude" "$V2"
echo v3 > "$H/repos/Claude/CLAUDE.md"; git -C "$H/repos/Claude" commit -qam v3
A=$(git -C "$H/repos/Claude" rev-parse HEAD)
OUT=$(run "$H")
check "local commit preserved" "$(git -C "$H/repos/Claude" rev-parse HEAD)" "$A"
case "$OUT" in *AHEAD*) ok "reports ahead" ;; *) bad "did not report ahead: $OUT" ;; esac

echo "== diverged: touch nothing, warn =="
H="$TMP/h-div"; mkdir -p "$H/repos"; clone_at "$H/repos/Claude" "$V1"
echo other > "$H/repos/Claude/CLAUDE.md"; git -C "$H/repos/Claude" commit -qam local
D=$(git -C "$H/repos/Claude" rev-parse HEAD)
OUT=$(run "$H")
check "untouched" "$(git -C "$H/repos/Claude" rev-parse HEAD)" "$D"
case "$OUT" in *DIVERGED*) ok "warns about divergence" ;; *) bad "no divergence warning: $OUT" ;; esac

echo "== a foreign repo at the path is never fetched =="
H="$TMP/h-foreign"; mkdir -p "$H/repos/Claude/.claude/skills/sync-template"
C="$H/repos/Claude"; git init -q -b main "$C"
echo x > "$C/CLAUDE.md"; echo x > "$C/.claude/skills/sync-template/SKILL.md"
git -C "$C" add -A && git -C "$C" commit -qm x
git -C "$C" remote add origin "https://github.com/someone/else.git"
S=$(git -C "$C" rev-parse HEAD)
OUT=$(run "$H")
check "left alone" "$(git -C "$C" rev-parse HEAD)" "$S"
case "$OUT" in *"not a clone of the template repo"*) ok "says it is not ours" ;; *) bad "no notice: $OUT" ;; esac

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
