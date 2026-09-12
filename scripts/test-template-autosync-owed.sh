#!/bin/bash
# Tests the [owed] block in scripts/template-autosync.sh (spec 007bg).
#
# Two bugs it guards, and they are different in kind:
#
#   F-01  core_divergence read the manifest's PROJECT-RELATIVE paths and handed them to sha_many,
#         which execs shasum on them — with no cwd anchoring. So the answer came from whatever
#         directory the caller stood in. The dangerous shape is not "an unrelated directory"
#         (which yields nothing and is merely silent); it is ANOTHER SYNCED PROJECT, whose CORE
#         files sit at the template's bytes and therefore match, so the sync answers "no
#         divergence" about a repository it never looked at.
#
#   F-02  [owed] rendered at two of the five reachable exits, and they were the wrong two: it fired
#         on the `[ok]` early exit and at the end of a full sync — i.e. once before the copy loop
#         and once AFTER it had already overwritten the file — while --check, --dry-run and the
#         mid-operation deferral, the three modes a developer runs before anything is destroyed,
#         said nothing.
#
# End-to-end rather than function extraction, because half of what is under test is WHERE the block
# renders and from WHICH directory the answer was computed. Note that the sibling harness
# (test-template-autosync-stranded.sh) cds into the project for every run, which is exactly why it
# never saw F-01 — AC-03 here exists to make that assumption explicit and false.
#
# Run: bash scripts/test-template-autosync-owed.sh

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The two files the probe diverges must be genuinely CORE — core_divergence filters on the same
# $CORE_SCRIPTS / $CORE_RULES the rest of the script uses, so a made-up `demo-rule.md` would be
# invisible to it and every assertion below would pass against a broken script.
CORE_RULE=".claude/rules/allium.md"
CORE_SCRIPT="scripts/emit-pipeline-reminder.sh"

# A template, and N projects synced from it. Every project ends committed and clean, so anything
# the tests see later is divergence (file != manifest) and not stranding (file != HEAD), which is
# 007bf's condition and a different block.
build() {
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"
  T="$R/template"

  mkdir -p "$T/scripts" "$T/.claude/rules"
  cp "$SCRIPT" "$T/scripts/"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'reminder v1\n' > "$T/$CORE_SCRIPT"
  printf 'allium v1\n'   > "$T/$CORE_RULE"
  git -C "$T" init -q -b main
  git -C "$T" config user.email t@t; git -C "$T" config user.name T
  git -C "$T" add -A; git -C "$T" commit -qm init

  shift
  for name in "$@"; do
    _p="$R/$name"
    mkdir -p "$_p/.claude/rules" "$_p/scripts"
    echo '{"name":"fake"}' > "$_p/package.json"
    cp "$SCRIPT" "$_p/scripts/"
    git -C "$_p" init -q -b main
    git -C "$_p" config user.email p@p; git -C "$_p" config user.name P
    git -C "$_p" add -A; git -C "$_p" commit -qm init
    sync "$_p" "$T" --quiet >/dev/null 2>&1      # establishes the manifest
    git -C "$_p" add -A >/dev/null 2>&1; git -C "$_p" commit -qm baseline >/dev/null 2>&1
  done
  P="$R/${2:-project}"
}

# Give a project local CORE work: edit both CORE files and COMMIT, so the tree is clean and the
# only thing wrong is that the bytes no longer match the manifest.
diverge() {
  printf 'local work\n' >> "$1/$CORE_RULE"
  printf 'local work\n' >> "$1/$CORE_SCRIPT"
  git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm "local CORE work" >/dev/null 2>&1
}

# Move the template so a run reaches the check block instead of the `[ok]` early exit.
bump() { printf 'v2\n' >> "$1/.claude/rules/allium.md"; git -C "$1" add -A; git -C "$1" commit -qm bump; }

# The project under test is named by $CLAUDE_PROJECT_DIR, so cwd is free to be anything — which is
# the whole point of AC-02 and AC-03.
sync_from() {  # sync_from <cwd> <project> <template> [args...]
  _c="$1"; _p="$2"; _t="$3"; shift 3
  ( cd "$_c" && CLAUDE_PROJECT_DIR="$_p" CLAUDE_TEMPLATE_DIR="$_t" bash "$_p/scripts/template-autosync.sh" "$@" 2>&1 )
}
sync() { _p="$1"; _t="$2"; shift 2; sync_from "$_p" "$_p" "$_t" "$@"; }

echo "== AC-01: divergence is reported from the project's own directory =="
build ac01 project
diverge "$P"
OUT=$(sync "$P" "$T")
has  "the early exit still fires"      "$OUT" "[ok] already at template"
has  "[owed] block present"            "$OUT" "[owed]"
has  "…names the CORE rule"            "$OUT" "$CORE_RULE"
has  "…names the CORE script"          "$OUT" "$CORE_SCRIPT"

echo "== AC-02: same answer from an unrelated directory (F-01) =="
OUT=$(sync_from "$TMP" "$P" "$T")
has  "[owed] survives a foreign cwd"   "$OUT" "[owed]"
has  "…still names the rule"           "$OUT" "$CORE_RULE"
has  "…still names the script"         "$OUT" "$CORE_SCRIPT"

echo "== AC-03: same answer from ANOTHER SYNCED PROJECT (F-01, the dangerous shape) =="
# The sibling holds the same CORE files at the template's bytes. Before 007bg this made the
# hashes match and the sync reported no divergence at all — confidently, about the wrong repo.
build ac03 project sibling
diverge "$TMP/ac03/project"
OUT=$(sync_from "$TMP/ac03/sibling" "$TMP/ac03/project" "$TMP/ac03/template")
has  "[owed] survives a sibling cwd"   "$OUT" "[owed]"
has  "…names the rule"                 "$OUT" "$CORE_RULE"
has  "…names the script"               "$OUT" "$CORE_SCRIPT"
# And the sibling itself, which is genuinely clean, must still be reported as clean.
OUT=$(sync_from "$TMP/ac03/project" "$TMP/ac03/sibling" "$TMP/ac03/template")
hasnt "a clean sibling stays silent"   "$OUT" "[owed]"

echo "== AC-04/05: --check and --dry-run warn before anything is destroyed (F-02) =="
build ac04 project
diverge "$P"
bump "$T"
OUT=$(sync "$P" "$T" --check)
has  "--check reaches the check block" "$OUT" "[check] template"
has  "--check reports [owed]"          "$OUT" "[owed]"
has  "…names the rule in the block"    "$OUT" "         $CORE_RULE"
OUT=$(sync "$P" "$T" --dry-run)
has  "--dry-run reports [owed]"        "$OUT" "[owed]"
# The indented form, not the bare path: --dry-run ALSO prints `update scripts/emit-pipeline-
# reminder.sh` in its file list, which is precisely the ambiguity this spec exists to remove (M3),
# so a bare substring match here would pass against the unfixed script.
has  "…names the script in the block"  "$OUT" "         $CORE_SCRIPT"

echo "== AC-06: the mid-operation deferral warns too, below [deferred] =="
mkdir -p "$P/.git/rebase-merge"
OUT=$(sync "$P" "$T")
has  "deferral fires"                  "$OUT" "[deferred]"
has  "…and reports [owed]"             "$OUT" "[owed]"
# Order matters: [deferred] says a future sync is coming, [owed] says what it will cost.
D_LINE=$(printf '%s\n' "$OUT" | grep -n '\[deferred\]' | head -1 | cut -d: -f1)
O_LINE=$(printf '%s\n' "$OUT" | grep -n '\[owed\]'     | head -1 | cut -d: -f1)
if [ -n "$D_LINE" ] && [ -n "$O_LINE" ] && [ "$D_LINE" -lt "$O_LINE" ]; then
  ok "[owed] renders below [deferred]"
else
  bad "[owed] renders below [deferred] (deferred@$D_LINE owed@$O_LINE)"
fi
rmdir "$P/.git/rebase-merge"

echo "== AC-07: the full sync still reports it (regression on the pre-existing site) =="
OUT=$(sync "$P" "$T")
has  "full sync reports [owed]"        "$OUT" "[owed]"
has  "…names the rule"                 "$OUT" "$CORE_RULE"

echo "== AC-08: silent on a clean project, at every exit =="
build ac08 project
OUT=$(sync "$P" "$T");            hasnt "early exit silent"  "$OUT" "owed"
bump "$T"
OUT=$(sync "$P" "$T" --check);    hasnt "--check silent"     "$OUT" "owed"
OUT=$(sync "$P" "$T" --dry-run);  hasnt "--dry-run silent"   "$OUT" "owed"
mkdir -p "$P/.git/rebase-merge"
OUT=$(sync "$P" "$T");            hasnt "deferral silent"    "$OUT" "owed"
rmdir "$P/.git/rebase-merge"
OUT=$(sync "$P" "$T");            hasnt "full sync silent"   "$OUT" "owed"

echo "== AC-09: --check is a query, not a gate =="
build ac09 project
diverge "$P"
bump "$T"
sync "$P" "$T" --check >/dev/null 2>&1; same "--check exits 0 with divergence" "$?" "0"
build ac09b project
bump "$T"
sync "$P" "$T" --check >/dev/null 2>&1; same "--check exits 0 without"         "$?" "0"

echo "== AC-10: a manifest path whose file is gone drops out silently (SC-07) =="
build ac10 project
rm -f "$P/$CORE_RULE"
OUT=$(sync_from "$TMP" "$P" "$T")
hasnt "no [owed] for a deleted file"   "$OUT" "[owed]"
hasnt "no shasum error leaks out"      "$OUT" "No such file"

echo "== AC-11: one hash process for all CORE paths (SC-05) =="
# A sha_of loop would satisfy every assertion above while reintroducing the per-file subprocess
# cost sha_many exists to avoid. Counted with a PATH shim rather than read out of the source.
# The early exit with a CLEAN tree is the right place to count: stranded_writes does no per-path
# hashing when git reports nothing dirty, so every exec seen here belongs to core_divergence.
build ac11 project
diverge "$P"
SHIM="$TMP/shim"; mkdir -p "$SHIM"
COUNT="$TMP/hashcount"; : > "$COUNT"
for tool in shasum sha256sum; do
  real=$(command -v "$tool" 2>/dev/null) || continue
  [ -n "$real" ] || continue
  printf '#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n' "$COUNT" "$real" > "$SHIM/$tool"
  chmod +x "$SHIM/$tool"
done
( cd "$TMP" && PATH="$SHIM:$PATH" CLAUDE_PROJECT_DIR="$P" CLAUDE_TEMPLATE_DIR="$T" \
    bash "$P/scripts/template-autosync.sh" >/dev/null 2>&1 )
N=$(grep -c . "$COUNT" 2>/dev/null || echo 0)
same "exactly one hash process" "$N" "1"

echo "== AC-12: the block's wording is unchanged (FR-03) =="
# Output, not source: a paraphrase is what this guards, and the four lines below are 007az's text.
build ac12 project
diverge "$P"
OUT=$(sync "$P" "$T")
has "headline"  "$OUT" "[owed] this sync found CORE file(s) differing from the bytes the template shipped:"
has "contract"  "$OUT" "CORE is overwritten unconditionally — a change that lives only here does not"
has "remedy"    "$OUT" "Land it in the template, push, then sync."

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
