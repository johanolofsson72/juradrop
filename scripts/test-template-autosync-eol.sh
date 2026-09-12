#!/bin/bash
# Tests the [eol] byte-divergence detector in scripts/template-autosync.sh (spec 007bi).
#
# The bug it guards: `resolve_local_template` copies the template clone's WORKING TREE, takes
# TEMPLATE_SHA from HEAD, and guards the gap with `git status --porcelain` — an oracle that answers
# for CONTENT after git's conversions, on a script that copies RAW BYTES. A file whose CRLF bytes
# were committed THROUGH git (add normalises CRLF->LF into the index and records the CRLF file's
# stat, so the entry reads up-to-date forever) is clean to status, clean to `git diff`, and yet its
# bytes on disk are not its blob's bytes.
#
# The damage lands in the PROJECT, one release later: the sync copies the CRLF bytes and records
# their hash in the manifest; the first git operation to touch the project's copy normalises it to
# LF; and from then on copy_file reads a hash nothing on disk can ever match again and reports
#
#     <path> — merge with /project-update, or record it with --accept-local
#
# on every future template release, forever, about a file nobody has touched. Measured across three
# releases (spec research.md M4) — which is why AC-03 below syncs twice rather than once. A test
# that only checks the bytes of the first sync passes on a script that still poisons the manifest.
#
# End-to-end against the real script, not function extraction: half of what is under test is WHERE
# the note renders (AC-10 — four modes, one call site) and WHAT the copy loop does with the result,
# neither of which survives being lifted out of the script.
#
# Run: bash scripts/test-template-autosync-eol.sh

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="${EOL_TEST_SCRIPT:-$PWD/scripts/template-autosync.sh}"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found at $SCRIPT"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
        else shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; fi; }
blob_sha() { git -C "$1" cat-file -p "HEAD:$2" 2>/dev/null | { if command -v sha256sum >/dev/null 2>&1
        then sha256sum; else shasum -a 256; fi; } | cut -d' ' -f1; }

# The executable probe must be a name in $CORE_SCRIPTS: a non-CORE script that the project does not
# already have is never ADDED by copy_file ("New file: only add CORE machinery, plus template-owned
# SKILLS"), so a made-up name would never reach the project and AC-11 would pass against anything.
EXEC_PROBE="scripts/tlc-cleanup.sh"
DEMO=".claude/skills/demo/SKILL.md"        # CRLF-authored, nested (AC-12)
CTRL=".claude/skills/control/SKILL.md"     # LF-authored control
BIN=".claude/skills/demo/logo.bin"
EMPTY=".claude/skills/demo/empty.md"

# ---------------------------------------------------------------------------- fixtures
# A template clone and a project. $1 names the sandbox; the rest of the arguments are flags that
# turn individual hazards on, so each scenario builds only what it asserts about.
build() {
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"
  T="$R/template"; P="$R/project"
  shift
  FLAGS=" $* "

  mkdir -p "$T/scripts" "$T/.claude/rules" "$T/.claude/skills/demo" "$T/.claude/skills/control"
  cp "$SCRIPT" "$T/scripts/template-autosync.sh"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'placeholder\n' > "$T/.claude/rules/allium.md"

  case "$FLAGS" in
    *" clean "*) printf '# demo skill\nversion one\n' > "$T/$DEMO" ;;   # LF everywhere
    *)           printf '# demo skill\r\nversion one\r\n' > "$T/$DEMO" ;;
  esac
  printf '# control skill\nversion one\n' > "$T/$CTRL"
  printf '\037\213\010\000binary\000\001\002' > "$T/$BIN"
  : > "$T/$EMPTY"
  case "$FLAGS" in
    *" exec "*) printf '#!/bin/sh\r\necho probe v1\r\n' > "$T/$EXEC_PROBE"; chmod +x "$T/$EXEC_PROBE" ;;
  esac

  git -C "$T" init -q -b main
  git -C "$T" config user.email t@t; git -C "$T" config user.name T
  git -C "$T" config core.autocrlf input
  git -C "$T" add -A; git -C "$T" commit -qm "template v1"

  # Hazards that must exist AFTER the commit.
  case "$FLAGS" in
    *" dirty "*)  printf '# control skill\nedited but not staged\n' > "$T/$CTRL" ;;
  esac
  case "$FLAGS" in
    *" both "*)   printf '# demo skill\r\nedited AND crlf\r\n' > "$T/$DEMO" ;;
  esac
  case "$FLAGS" in
    *" staged "*) printf '# demo skill\r\nstaged not committed\r\n' > "$T/$DEMO"
                  git -C "$T" add "$DEMO" ;;
  esac

  mkdir -p "$P/.claude" "$P/scripts"
  echo '{"name":"fake"}' > "$P/package.json"
  cp "$SCRIPT" "$P/scripts/template-autosync.sh"
  git -C "$P" init -q -b main
  git -C "$P" config user.email p@p; git -C "$P" config user.name P
  git -C "$P" config core.autocrlf input
  git -C "$P" add -A; git -C "$P" commit -qm "project init"
}

sync() { CLAUDE_TEMPLATE_DIR="$T" CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT" "$@" 2>&1; }

# Just the [eol] block. The negative assertions below are about what the NOTE names, and a whole-run
# capture also contains the `[changed] add ...` listing — which names every file the sync wrote,
# including the binary and the control. Asserting `hasnt` against the full output tests nothing and
# fails for the wrong reason; this is the difference between "the oracle did not flag it" and "the
# string never appeared anywhere".
eol_note() { printf '%s\n' "$1" | sed -n '/^\[eol\]/,/add --renormalize/p'; }

# Ship a new version of both skills from the template.
release() {
  printf '# demo skill\n%s\n' "$1" > "$T/$DEMO"
  printf '# control skill\n%s\n' "$1" > "$T/$CTRL"
  git -C "$T" add -A; git -C "$T" commit -qm "template $1"
}

echo "=== A. the divergent clone: bytes, hash, and the release after ==="
build a
OUT=$(sync --quiet)

has "AC-15a note fires with the count"        "$OUT" "[eol] 1 file(s) in the template clone differ"
has "AC-15b note names the path"              "$OUT" "$DEMO"
has "AC-15c note names the fix command"       "$OUT" "add --renormalize ."
has "AC-15d note explains what it is doing"   "$OUT" "Syncing the committed bytes instead"

same "AC-01 project got the COMMITTED bytes" "$(sha "$P/$DEMO")" "$(blob_sha "$T" "$DEMO")"
MANIFEST=$(awk -v p="$DEMO" 'NF == 2 && $2 == p { print $1 }' "$P/.claude/.template-sync")
same "AC-02 manifest records the committed hash" "$MANIFEST" "$(blob_sha "$T" "$DEMO")"

NOTE=$(eol_note "$OUT")
hasnt "AC-05 binary is never named"  "$NOTE" "$BIN"
hasnt "AC-06 empty file never named" "$NOTE" "$EMPTY"
same  "AC-04a control bytes untouched" "$(sha "$P/$CTRL")" "$(blob_sha "$T" "$CTRL")"
hasnt "AC-04b control never named"     "$NOTE" "$CTRL"

# The whole point. Normalise the project's copy the way any checkout/stash/clean would, then ship a
# new template version and demand that it lands.
rm "$P/$DEMO"; git -C "$P" checkout -- "$DEMO" 2>/dev/null
release "version two"
OUT2=$(sync --quiet)
DEMO_NOW=$(tr -d '\r\n' < "$P/$DEMO")
has   "AC-03a the release actually landed"      "$DEMO_NOW" "version two"
hasnt "AC-03b not reported as a local edit"     "$OUT2" "merge with /project-update"

echo
echo "=== B. the clean clone pays one process and says nothing ==="
build b clean
SHIM="$TMP/shim"; mkdir -p "$SHIM"
REALGIT=$(command -v git)
cat > "$SHIM/git" <<SHIMEOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/gitcalls.log"
exec "$REALGIT" "\$@"
SHIMEOF
chmod +x "$SHIM/git"

: > "$TMP/gitcalls.log"
OUT=$(PATH="$SHIM:$PATH" sync --quiet)
hasnt "AC-09 clean clone emits no note" "$OUT" "[eol]"
same  "AC-16a exactly one ls-files --eol"  "$(grep -c 'ls-files --eol' "$TMP/gitcalls.log")" "1"
same  "AC-16b no checkout-index at all"    "$(grep -c 'checkout-index'  "$TMP/gitcalls.log")" "0"

echo
echo "=== C. many divergent paths still cost one materialisation ==="
build c exec
: > "$TMP/gitcalls.log"
OUT=$(PATH="$SHIM:$PATH" sync --quiet)
has  "AC-13a two paths diverge"           "$OUT" "[eol] 2 file(s)"
same "AC-13b still ONE checkout-index"    "$(grep -c 'checkout-index' "$TMP/gitcalls.log")" "1"
same "AC-12 nested path materialised"     "$(sha "$P/$DEMO")" "$(blob_sha "$T" "$DEMO")"
if [ -x "$P/$EXEC_PROBE" ]; then ok "AC-11 exec bit survived the staging area"
else bad "AC-11 exec bit LOST — this would strip +x off every hook in every project"; fi
same "AC-11b exec probe got committed bytes" "$(sha "$P/$EXEC_PROBE")" "$(blob_sha "$T" "$EXEC_PROBE")"

echo
echo "=== D. content-dirty wins, and still marks the SHA ==="
# `clean` too: with the demo file LF-authored, the ONLY hazard in this sandbox is the content-dirty
# control, so "no note at all" is a meaningful assertion rather than an accident of which file the
# note happened to name.
build d dirty clean
OUT=$(sync --quiet)
CTRL_NOW=$(cat "$P/$CTRL")
has   "AC-07a worktree bytes copied, not the index" "$CTRL_NOW" "edited but not staged"
has   "AC-07b SHA marked dirty" "$(sed -n 's/^sha=//p' "$P/.claude/.template-sync")" "-dirty-"
hasnt "AC-07c content-dirty path never reaches the oracle" "$OUT" "[eol]"

build e both
OUT=$(sync --quiet)
DEMO_NOW=$(tr -d '\r' < "$P/$DEMO")
has   "AC-08a both-at-once keeps worktree bytes" "$DEMO_NOW" "edited AND crlf"
hasnt "AC-08b and is not staged from the index"  "$OUT" "[eol] 1 file(s)"

build f staged
OUT=$(sync --quiet)
DEMO_NOW=$(tr -d '\r' < "$P/$DEMO")
has   "AC-17a staged-not-committed keeps worktree bytes" "$DEMO_NOW" "staged not committed"
hasnt "AC-17b never materialised from the index"         "$OUT" "[eol] 1 file(s)"

echo
echo "=== E. every mode a developer can reach before anything is written ==="
build g
for MODE in --check --dry-run; do
  OUT=$(sync $MODE)
  has "AC-10 $MODE carries the note" "$OUT" "[eol] 1 file(s)"
done
OUT=$(sync --quiet); has "AC-10 full sync carries the note" "$OUT" "[eol] 1 file(s)"
OUT=$(sync --quiet)   # second run: stamp matches, [ok] early exit
has "AC-10 [ok] early exit carries the note" "$OUT" "[eol] 1 file(s)"

echo
echo "=== F. a failed materialisation falls back, it does not drop the file ==="
build h
# Sabotage: make mktemp -d land somewhere checkout-index cannot write into.
OUT=$(CLAUDE_TEMPLATE_DIR="$T" CLAUDE_PROJECT_DIR="$P" TMPDIR=/nonexistent-eol-probe \
      bash "$SCRIPT" --quiet 2>&1)
if [ -f "$P/$DEMO" ]; then ok "AC-14a file still copied (from the worktree)"
else bad "AC-14a file was DROPPED from the copy loop"; fi
hasnt "AC-14b not announced as a retracted orphan" "$OUT" "orphaned"

echo
echo "=== G. the note survives the SessionStart hook's two gates ==="
# FR-6 is "reported to the developer", and the script satisfying it is only half the journey: the
# hook drops anything without [synced], and drops it again on "0 updated, 0 added". The second gate
# is the steady state of exactly the clone this note exists for — the divergent bytes were copied on
# an earlier run, so a later sync legitimately writes nothing. Without the escape the warning
# reaches --check and --dry-run and never reaches a session start, which is where nobody is looking
# for it and everybody is.
HOOK="${EOL_TEST_HOOK:-$PWD/scripts/template-autosync-hook.sh}"
if [ -f "$HOOK" ]; then
  build i
  sync --quiet >/dev/null 2>&1          # first run copies; second is the 0/0 steady state
  OUT=$(CLAUDE_PROJECT_DIR="$P" CLAUDE_TEMPLATE_DIR="$T" CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS=1 \
        bash "$HOOK" 2>&1)
  has "AC-18a hook forwards the note at all"     "$OUT" "[eol]"
  has "AC-18b hook names the divergent path"     "$OUT" "$DEMO"
  has "AC-18c hook keeps the fix command"        "$OUT" "add --renormalize"
else
  bad "AC-18 template-autosync-hook.sh not found"
fi

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
