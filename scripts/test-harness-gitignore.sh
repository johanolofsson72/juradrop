#!/bin/bash
# Tests scripts/harness-gitignore.sh and the sync's use of it (spec 040).
#
# The defect: the harness writes files it knows are machine-local, and nothing carried that knowledge
# into a project's .gitignore except prose applied by hand. hetznerradar committed 109 attempt
# counters. The fix owns one delimited block in .gitignore and reports what is already tracked.
#
# What would make this test lie, and the arm that stops it:
#   - a rewrite that eats project lines          → every arm compares the bytes OUTSIDE the block
#   - a "current" block rewritten anyway          → SC-040-04 checks the mtime, not just the output
#   - a malformed block silently "repaired"       → SC-040-07/08 assert the file is byte-identical
#   - the sync writing the file and not committing it → SC-040-12 asserts a clean tree afterwards
#   - a markers test that stopped reading the list    → SC-040-16 drops a pattern and expects red
#
# Run: bash scripts/test-harness-gitignore.sh

set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
HG="$REPO/scripts/harness-gitignore.sh"
SCRIPT="$REPO/scripts/template-autosync.sh"
[ -f "$HG" ] || { echo "FAIL: scripts/harness-gitignore.sh not found"; exit 1; }
. "$REPO/scripts/drive-sync.sh"                 # the only way to the sync (spec 011)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BEGIN_MARK='# >>> claude-code harness (managed by scripts/harness-gitignore.sh) >>>'
END_MARK='# <<< claude-code harness <<<'

fresh() { rm -rf "$TMP/$1"; mkdir -p "$TMP/$1"; printf '%s\n' "$TMP/$1"; }
# Everything outside the managed block, with the block replaced by one placeholder line.
outside() { awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
  { l = $0; sub(/\r$/, "", l) }
  l == b { print "<BLOCK>"; skip = 1; next }
  l == e { skip = 0; next }
  !skip' "$1"; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }   # GNU first; BSD stat rejects -c
sum()   { cksum < "$1"; }

echo "== FR-01: --list =="
L=$(bash "$HG" --list)
has   "lists .claude/state/"               "$L" ".claude/state/"
has   "lists settings.local.json"          "$L" ".claude/settings.local.json"
has   "lists __pycache__/"                 "$L" "__pycache__/"
hasnt "prints patterns only, no reasons"   "$L" "%"

echo "== SC-040-01: no .gitignore → created with the block =="
D=$(fresh sc01)
OUT=$(bash "$HG" --apply "$D"); RC=$?
same "exit 0"                    "$RC" 0
same "prints added"              "$OUT" "added"
has  "file carries the start"    "$(cat "$D/.gitignore")" "$BEGIN_MARK"
has  "file carries the end"      "$(cat "$D/.gitignore")" "$END_MARK"
has  "file carries a pattern"    "$(cat "$D/.gitignore")" ".claude/state/"

echo "== SC-040-02: project .gitignore without the block → appended, originals kept =="
D=$(fresh sc02)
printf 'bin/\nobj/\n# my own comment\n!keep.me\n' > "$D/.gitignore"
cp "$D/.gitignore" "$TMP/sc02.orig"
OUT=$(bash "$HG" --apply "$D")
same "prints updated"            "$OUT" "updated"
same "original bytes are a prefix of the new file" \
     "$(head -c "$(wc -c < "$TMP/sc02.orig")" "$D/.gitignore" | cksum)" "$(sum "$TMP/sc02.orig")"
same "block is the last thing in the file" "$(tail -n 1 "$D/.gitignore")" "$END_MARK"

echo "== SC-040-03: no final newline → one inserted, original bytes kept =="
D=$(fresh sc03)
printf 'bin/\nobj/' > "$D/.gitignore"
bash "$HG" --apply "$D" >/dev/null
same "obj/ is still its own line"  "$(sed -n 2p "$D/.gitignore")" "obj/"
same "block starts after a blank"  "$(sed -n 4p "$D/.gitignore")" "$BEGIN_MARK"

echo "== SC-040-04: second --apply → silent, file untouched =="
D=$(fresh sc04)
printf 'bin/\n' > "$D/.gitignore"
bash "$HG" --apply "$D" >/dev/null
B1=$(sum "$D/.gitignore"); touch -t 200001010000 "$D/.gitignore"; M1=$(mtime "$D/.gitignore")
OUT=$(bash "$HG" --apply "$D"); RC=$?
same "exit 0"                    "$RC" 0
same "prints nothing"            "$OUT" ""
same "bytes unchanged"           "$(sum "$D/.gitignore")" "$B1"
same "mtime unchanged"           "$(mtime "$D/.gitignore")" "$M1"

echo "== SC-040-05: stale block → rewritten, bytes outside identical =="
D=$(fresh sc05)
{ printf 'before/\n\n'; printf '%s\n' "$BEGIN_MARK" '.claude/state/' 'my-hand-edit/' "$END_MARK"; printf 'after/\n!after.keep\n'; } > "$D/.gitignore"
outside "$D/.gitignore" > "$TMP/sc05.out"
OUT=$(bash "$HG" --apply "$D")
same  "prints updated"            "$OUT" "updated"
same  "bytes outside identical"   "$(outside "$D/.gitignore" | cksum)" "$(sum "$TMP/sc05.out")"
hasnt "hand edit inside is gone"  "$(cat "$D/.gitignore")" "my-hand-edit/"
has   "current list is in"        "$(cat "$D/.gitignore")" ".claude/settings.local.json"
same  "the after-lines stay after" "$(tail -n 1 "$D/.gitignore")" "!after.keep"

echo "== SC-040-06: CRLF file → CRLF block, second apply silent =="
D=$(fresh sc06)
printf 'bin/\r\nobj/\r\n' > "$D/.gitignore"
bash "$HG" --apply "$D" >/dev/null
N_LF=$(grep -c '' "$D/.gitignore"); N_CRLF=$(grep -c "$(printf '\r')\$" "$D/.gitignore")
same "every line ends CRLF"      "$N_CRLF" "$N_LF"
same "second apply is silent"    "$(bash "$HG" --apply "$D")" ""

echo "== SC-040-07: start marker without end → exit 3, unchanged =="
D=$(fresh sc07)
printf 'bin/\n%s\n.claude/state/\nmine/\n' "$BEGIN_MARK" > "$D/.gitignore"; B1=$(sum "$D/.gitignore")
ERR=$(bash "$HG" --apply "$D" 2>&1 >/dev/null); RC=$?
same "exit 3"                    "$RC" 3
has  "names the problem"         "$ERR" "start marker (line 2) with no end marker"
same "file unchanged"            "$(sum "$D/.gitignore")" "$B1"

echo "== SC-040-08: two blocks → exit 3, unchanged =="
D=$(fresh sc08)
printf '%s\n' "$BEGIN_MARK" a "$END_MARK" "$BEGIN_MARK" b "$END_MARK" > "$D/.gitignore"; B1=$(sum "$D/.gitignore")
bash "$HG" --apply "$D" >/dev/null 2>&1; RC=$?
same "exit 3"                    "$RC" 3
same "file unchanged"            "$(sum "$D/.gitignore")" "$B1"
D=$(fresh sc08b)
printf '%s\n' "$END_MARK" a "$BEGIN_MARK" > "$D/.gitignore"
ERR=$(bash "$HG" --apply "$D" 2>&1 >/dev/null); RC=$?
same "reversed markers exit 3"   "$RC" 3
has  "…and say so"               "$ERR" "comes before the start marker"

echo "== SC-040-09: --check writes nothing =="
D=$(fresh sc09)
printf 'bin/\n' > "$D/.gitignore"; B1=$(sum "$D/.gitignore")
same "prints updated"            "$(bash "$HG" --check "$D")" "updated"
same "file unchanged"            "$(sum "$D/.gitignore")" "$B1"
D=$(fresh sc09b)
same "no file: prints added"     "$(bash "$HG" --check "$D")" "added"
[ -e "$D/.gitignore" ] && bad "--check created a .gitignore" || ok "--check created nothing"

echo "== SC-040-10/11: --tracked =="
D=$(fresh sc10)
git -C "$D" init -q
mkdir -p "$D/.claude/state/attempts" "$D/scripts/__pycache__" "$D/src"
touch "$D/.claude/state/attempts/a" "$D/.claude/state/attempts/b" "$D/.claude/state/attempts/c" \
      "$D/scripts/__pycache__/x.pyc" "$D/.claude/.bash-write-marker" "$D/src/app.cs" "$D/.claude/.template-sync"
git -C "$D" add -- .claude scripts src
T=$(bash "$HG" --tracked "$D")
has   "collapses to .claude/state"         "$T" ".claude/state"
hasnt "no attempt file listed"             "$T" "attempts/"
has   "unanchored dir collapses"           "$T" "scripts/__pycache__"
has   "a tracked file pattern is listed"   "$T" ".claude/.bash-write-marker"
hasnt "source is not listed"               "$T" "src/app.cs"
hasnt "the sync manifest is not listed"    "$T" ".claude/.template-sync
"
same  "exactly three entries"              "$(printf '%s\n' "$T" | grep -c .)" 3
mkdir -p "$D/.claude/.local-llm-cache"
for i in 1 2 3 4; do touch "$D/.claude/.local-llm-cache/r$i.txt"; done
git -C "$D" add -f -- .claude/.local-llm-cache
T=$(bash "$HG" --tracked "$D")
has   "a glob-matched directory collapses"  "$T" ".claude/.local-llm-cache
"
hasnt "no cached response listed"          "$T" "r1.txt"
D=$(fresh sc11)
git -C "$D" init -q; mkdir -p "$D/src"; touch "$D/src/app.cs"; git -C "$D" add -- src
same "clean project: nothing"              "$(bash "$HG" --tracked "$D")" ""
D=$(fresh sc11b)
same "not a repo: nothing, exit 0"         "$(bash "$HG" --tracked "$D"; echo "rc=$?")" "rc=0"

echo "== SC-040-15: an earlier negation is overridden, a later one is left alone =="
D=$(fresh sc15)
git -C "$D" init -q
printf '!.claude/state/\n' > "$D/.gitignore"
bash "$HG" --apply "$D" >/dev/null
git -C "$D" check-ignore -q .claude/state/x && ok "earlier negation overridden by the block" \
  || bad "earlier negation still wins"
printf '!.claude/settings.local.json\n' >> "$D/.gitignore"
bash "$HG" --apply "$D" >/dev/null
git -C "$D" check-ignore -q .claude/settings.local.json && bad "a later negation was overridden" \
  || ok "a negation after the block is the project's call"
same "…and survives a re-apply" "$(tail -n 1 "$D/.gitignore")" "!.claude/settings.local.json"

echo "== usage =="
bash "$HG" --apply >/dev/null 2>&1; same "missing root is exit 2" "$?" 2
bash "$HG" --bogus >/dev/null 2>&1; same "unknown flag is exit 2" "$?" 2

# ---------------------------------------------------------------------------------- the sync
# A template carrying the real sync and the real helper, and a project synced from it.
build() {
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"
  T="$R/template"; P="$R/project"
  mkdir -p "$T/scripts" "$T/.claude/rules"
  cp "$SCRIPT" "$HG" "$T/scripts/"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'rule v1\n' > "$T/.claude/rules/demo-rule.md"
  git -C "$T" init -q -b main
  git -C "$T" config user.email t@t; git -C "$T" config user.name T
  git -C "$T" add -- scripts .claude; git -C "$T" commit -qm init

  mkdir -p "$P/.claude/rules" "$P/scripts"
  echo '{"name":"fake"}' > "$P/package.json"
  printf 'node_modules/\n' > "$P/.gitignore"
  cp "$SCRIPT" "$P/scripts/"
  git -C "$P" init -q -b main
  git -C "$P" config user.email p@p; git -C "$P" config user.name P
  git -C "$P" add -- package.json .gitignore scripts; git -C "$P" commit -qm init
}
sync() { _p="$1"; _t="$2"; shift 2
  CLAUDE_TEMPLATE_DIR="$_t" DRIVE_SYNC_SCRIPT="$_p/scripts/template-autosync.sh" drive_sync "$_p" "$TMP" "$@" 2>&1; }
bump() { printf 'v2\n' >> "$1/.claude/rules/demo-rule.md"; git -C "$1" add -- .claude; git -C "$1" commit -qm bump; }

echo "== SC-040-14: --check / --dry-run write nothing, and --dry-run names .gitignore =="
build sc14
B1=$(sum "$P/.gitignore")
OUT=$(sync "$P" "$T" --dry-run)
has  "--dry-run lists .gitignore"          "$OUT" "update .gitignore"
same "--dry-run left .gitignore alone"     "$(sum "$P/.gitignore")" "$B1"
sync "$P" "$T" --check >/dev/null
same "--check left .gitignore alone"       "$(sum "$P/.gitignore")" "$B1"

echo "== SC-040-12: the sync writes the block and commits it =="
build sc12
sync "$P" "$T" --quiet >/dev/null
has  "the block is in .gitignore"          "$(cat "$P/.gitignore")" "$BEGIN_MARK"
has  "the project's own line survived"     "$(cat "$P/.gitignore")" "node_modules/"
same "the sync commit carries .gitignore"  "$(git -C "$P" diff-tree --no-commit-id --name-only -r HEAD | grep -cx '.gitignore')" 1
same ".gitignore is clean afterwards"      "$(git -C "$P" status --porcelain -- .gitignore)" ""
bump "$T"
sync "$P" "$T" --quiet >/dev/null
same "a second sync leaves it untouched"   "$(git -C "$P" status --porcelain -- .gitignore)" ""
same "…and does not re-commit it"          "$(git -C "$P" diff-tree --no-commit-id --name-only -r HEAD | grep -cx '.gitignore')" 0

echo "== SC-040-12b: a project with no .gitignore gets one, listed as add and committed =="
build sc12b
git -C "$P" rm -q -- .gitignore; git -C "$P" commit -qm "no ignore file"
OUT=$(sync "$P" "$T" --dry-run)
has  "--dry-run lists it as add"           "$OUT" "add    .gitignore"
[ -e "$P/.gitignore" ] && bad "--dry-run created .gitignore" || ok "--dry-run created nothing"
sync "$P" "$T" --quiet >/dev/null
has  "the sync created it with the block"  "$(cat "$P/.gitignore" 2>/dev/null)" "$BEGIN_MARK"
same "the sync commit carries it"          "$(git -C "$P" diff-tree --no-commit-id --name-only -r HEAD | grep -cx '.gitignore')" 1
same "…and it is clean afterwards"         "$(git -C "$P" status --porcelain -- .gitignore)" ""

echo "== SC-040-13: tracked machine-local files are reported, at the full sync and at [ok] =="
build sc13
mkdir -p "$P/.claude/state/attempts"
for i in 1 2 3; do printf 'x\n' > "$P/.claude/state/attempts/$i"; done
printf '{}\n' > "$P/.claude/settings.local.json"
# -f: a developer's global excludes often ignore settings.local.json already, and the defect is the
# repository that tracks it anyway.
git -C "$P" add -f -- .claude; git -C "$P" commit -qm "oops"
OUT=$(sync "$P" "$T")
has  "full sync reports [tracked]"         "$OUT" "[tracked]"
has  "…names .claude/state"                "$OUT" ".claude/state"
has  "…names settings.local.json"          "$OUT" ".claude/settings.local.json"
has  "…gives the git rm line"              "$OUT" "git rm -r --cached --"
[ -f "$P/.claude/state/attempts/1" ] && ok "nothing was deleted from disk" || bad "the sync deleted a file"
same "nothing was untracked"               "$(git -C "$P" ls-files .claude/state | grep -c .)" 3
OUT=$(sync "$P" "$T")
has  "the [ok] exit still fires"           "$OUT" "[ok] already at template"
has  "…and reports [tracked] too"          "$OUT" "[tracked]"
OUT=$(sync "$P" "$T" --check)
has  "--check reports [tracked] too"       "$OUT" "[tracked]"
git -C "$P" rm -r -q --cached -- .claude/state .claude/settings.local.json
git -C "$P" commit -qm untrack
OUT=$(sync "$P" "$T")
hasnt "silent once untracked"              "$OUT" "[tracked]"

echo "== SC-040-13b: more than ten paths → capped list, and the printed command works =="
build sc13b
for i in 1 2 3 4 5 6 7 8 9 10 11; do mkdir -p "$P/m$i/__pycache__"; printf 'x\n' > "$P/m$i/__pycache__/a.pyc"; done
git -C "$P" add -f -- m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11; git -C "$P" commit -qm "eleven caches"
OUT=$(sync "$P" "$T")
has  "counts all eleven"                   "$OUT" "[tracked] 11 path(s)"
has  "caps the list"                       "$OUT" "… and 1 more"
CMD=$(printf '%s\n' "$OUT" | sed -n 's/^ *\(bash scripts\/harness-gitignore.sh --tracked .*\)$/\1/p')
has  "prints the pathspec pipeline"        "$CMD" "--pathspec-from-file=-"
( cd "$P" && eval "$CMD" >/dev/null 2>&1 )
same "running it untracks all eleven"      "$(git -C "$P" ls-files -- '*.pyc' | grep -c .)" 0
same "…and leaves them on disk"            "$(ls "$P"/m*/__pycache__/a.pyc | grep -c .)" 11

echo "== SC-040-13c: a spaced path gets the pipeline, which works =="
build sc13c
mkdir -p "$P/my dir/__pycache__"; printf 'x\n' > "$P/my dir/__pycache__/a.pyc"
git -C "$P" add -f -- "my dir"; git -C "$P" commit -qm "spaced cache"
OUT=$(sync "$P" "$T")
hasnt "no literal line that would split"   "$OUT" "git rm -r --cached -- my dir"
CMD=$(printf '%s\n' "$OUT" | sed -n 's/^ *\(bash scripts\/harness-gitignore.sh --tracked .*\)$/\1/p')
( cd "$P" && eval "$CMD" >/dev/null 2>&1 )
same "running it untracks the spaced path" "$(git -C "$P" ls-files -- '*.pyc' | grep -c .)" 0

echo "== the sync surfaces a malformed block =="
build malformed
printf '%s\n' "$BEGIN_MARK" >> "$P/.gitignore"; git -C "$P" add -- .gitignore; git -C "$P" commit -qm broken
B1=$(sum "$P/.gitignore")
OUT=$(sync "$P" "$T")
has  "[gitignore] names the problem"       "$OUT" "[gitignore]"
same ".gitignore left as it was"           "$(sum "$P/.gitignore")" "$B1"

echo "== FR-13: the template carries its own current block =="
if [ -f "$REPO/scripts/sync-prompt.md" ] && [ -d "$REPO/.claude/rules" ] && [ ! -f "$REPO/.claude/.template-sync" ]; then
  same "--check . in the template says nothing" "$(bash "$HG" --check "$REPO" 2>&1)" ""
else
  echo "  skip not the template repository (a project's block is the sync's job, SC-040-12)"
fi

echo "== SC-040-16: the markers test reads this list =="
MT="$REPO/scripts/test-runtime-markers-ignored.sh"
D=$(fresh sc16)
git -C "$D" init -q
mkdir -p "$D/scripts"
# A helper whose list has lost .claude/state/, and a .gitignore that still covers everything, so
# the only thing that can go red is assertion D reading the list.
bash "$HG" --list | grep -vx '.claude/state/' > "$TMP/sc16.list"
printf '#!/bin/bash\n[ "$1" = --list ] && cat %s\n' "$TMP/sc16.list" > "$D/scripts/harness-gitignore.sh"
bash "$HG" --apply "$D" >/dev/null
OUT=$( cd "$D" && bash "$MT" 2>&1 )
has  "D fails naming the dropped path"     "$OUT" "[D] not seeded to new projects: .claude/state/"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
