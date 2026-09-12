#!/bin/bash
# test-sync-prompt-core-parity.sh — /project-update must mirror the SAME set of
# scripts the autosync calls CORE, and must not keep its own copy of the list.
#
# WHY. sync-prompt.md carried a hardcoded list of 27 script names. CORE_SCRIPTS
# in template-autosync.sh is 96. Measured 2026-09-03, 70 CORE scripts were never
# copied by /project-update at all: every PreToolUse guard, every test harness,
# the row archiver, the convergence check. It went unreported for months because
# an INCOMPLETE list looks exactly like a finished one — there is no error state
# for "you forgot to add it here too".
#
# So the second list is gone and this is what keeps it gone. A list is not a
# thing to keep in sync; it is a thing to have once.
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SP="$SCRIPT_DIR/sync-prompt.md"
TA="$SCRIPT_DIR/template-autosync.sh"

# WHICH sync-prompt.md this harness is allowed to judge.
#
# This file is CORE, so it ships to every project. The file it tests is NOT: `/project-update`
# fetches sync-prompt.md fresh from
# raw.githubusercontent.com/johanolofsson72/Claude/main/scripts/sync-prompt.md (project-update
# SKILL.md Step 4), so a project-local copy is never read by anything. Measured 2026-09-03: five
# projects carried one, 58 KB to 102 KB, all different, none holding the --list-core-scripts
# rewrite, every one still carrying the hardcoded 27-script list this harness exists to keep out.
#
# Judging that copy is judging a file nobody owns and nobody reads, and it turned this harness red
# in five projects for a defect that cannot be fixed there — the H7t lesson that
# validate-no-sigpipe-assertions.sh already learned. Downstream, the checks that read sync-prompt.md
# are SKIPPED and say so; the checks about CORE_SCRIPTS itself still run, because those are about
# the project's own manifest.
#
# The predicate is the same one that gate uses, for the same reason: compare origin against the
# template slug, fall back to the sync stamp, and exempt nothing when neither answers.
template_origin() {
  local top phys
  top="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null)" || return 0
  phys="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd -P)" || return 0
  [ "$top" = "$phys" ] || return 0
  git -C "$SCRIPT_DIR/.." remote get-url origin 2>/dev/null || true
}
ORIGIN="$(template_origin)"
case "$ORIGIN" in
  *johanolofsson72/Claude|*johanolofsson72/Claude.git|*johanolofsson72/Claude/|*johanolofsson72/Claude.git/)
    MODE=template; MODE_WHY="origin is johanolofsson72/Claude" ;;
  "")
    if [ -f "$SCRIPT_DIR/../.claude/.template-sync" ]; then
      MODE=downstream; MODE_WHY=".claude/.template-sync is present — the sync writes it into every target"
    else
      MODE=template; MODE_WHY="neither an origin remote nor a sync stamp answers — undecidable, so nothing is skipped"
    fi ;;
  *) MODE=downstream; MODE_WHY="origin is $ORIGIN, which is not johanolofsson72/Claude" ;;
esac
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

# 1. The query modes exist and answer without a clone, a network or a stamp.
N_S=$(bash "$TA" --list-core-scripts 2>/dev/null | wc -l | tr -d ' ')
N_R=$(bash "$TA" --list-core-rules   2>/dev/null | wc -l | tr -d ' ')
[ "${N_S:-0}" -gt 50 ] && ok "--list-core-scripts answers ($N_S scripts)" \
  || bad "--list-core-scripts returned $N_S — the query mode is the whole mechanism"
[ "${N_R:-0}" -gt 5 ] && ok "--list-core-rules answers ($N_R rules)" \
  || bad "--list-core-rules returned $N_R"

# 2. Every name it returns is a real file, so a typo in CORE_SCRIPTS is a red test
#    rather than a script that silently never ships.
GHOST=""
while IFS= read -r s; do
  [ -n "$s" ] || continue
  [ -f "$SCRIPT_DIR/$s" ] || GHOST="$GHOST $s"
done < <(bash "$TA" --list-core-scripts 2>/dev/null)
[ -z "$GHOST" ] && ok "every CORE_SCRIPTS entry exists on disk" \
  || bad "CORE_SCRIPTS names files that do not exist:$GHOST"

# 3. sync-prompt.md must ASK, not carry its own list.
if [ "$MODE" = downstream ]; then
  echo "  SKIP  the four sync-prompt.md checks — this project's copy is not the one /project-update reads"
  echo "        ($MODE_WHY; the authoritative copy is fetched from GitHub at sync time)"
else
grep -q -- '--list-core-scripts' "$SP" \
  && ok "sync-prompt.md derives the list from the template" \
  || bad "sync-prompt.md does not call --list-core-scripts — the second list is back"

# The specific shape of the old defect: a `for s in` loop over literal .sh names.
if grep -qE 'for s in .*[a-z-]+\.sh [a-z-]+\.sh' "$SP"; then
  bad "sync-prompt.md still iterates a hardcoded script list"
else
  ok "no hardcoded script list remains in sync-prompt.md"
fi

# 4. The copy must carry the mode. `cp` over an EXISTING file keeps the
#    DESTINATION's mode, so without this a script that was once non-executable
#    stays non-executable through every future sync — which is exactly what had
#    happened to template-autosync.sh in all six projects.
grep -q 'chmod +x "scripts/\$s"' "$SP" \
  && ok "the copy loop sets the executable bit from the source" \
  || bad "the copy loop does not carry the mode — cp keeps the destination's"

# 5. And the template's own modes have to be right, or there is nothing to carry.
NOEXEC=""
while IFS= read -r s; do
  case "$s" in *.sh) ;; *) continue ;; esac
  [ -f "$SCRIPT_DIR/$s" ] || continue
  [ -x "$SCRIPT_DIR/$s" ] || NOEXEC="$NOEXEC $s"
done < <(bash "$TA" --list-core-scripts 2>/dev/null)
[ -z "$NOEXEC" ] && ok "every CORE .sh in the template is executable" \
  || bad "CORE .sh without the executable bit:$NOEXEC"

# 6. Refuses rather than falling back. A silent fallback to a stale list is the
#    defect wearing a different hat.
grep -q 'Refusing to fall back to a hardcoded list' "$SP" \
  && ok "an unreadable template is a failure, not a quiet fallback" \
  || bad "sync-prompt.md has no explicit refusal when the list cannot be read"
fi

echo "mode: $MODE — $MODE_WHY"
echo "sync-prompt-core-parity: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
