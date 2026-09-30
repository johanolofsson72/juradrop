#!/bin/bash
# Surgical arms for the mutants H1 found alive in scripts/template-autosync.sh (spec 078).
#
# H1 ran a sampled operator-mutation pass over the most-changed CORE script and every suite that
# drives it killed 2 of 12. Spec 078 re-drew the sample (the six named sites plus six new ones) and
# measured 4 of 12. Two of the eight survivors are equivalent and have no arm (see spec.md). Each
# arm below exists for exactly one of the other six, and `--sabotage` proves it: it applies that
# mutant to a copy of the script, runs the arm against the copy, and expects red.
#
#   M01  template-mode --unlisted: the `[ -f "$_f" ] || continue` glob guard
#   M08  local_record: `[ -f "$LOCAL_RECORD" ] || return 1`
#   M09  --accept-local CORE refusal: the `[ "$_first" -eq 1 ]` prefix line
#   M10  --accept-local CORE refusal: `exit 1`
#   M11  --accept-local, template does not ship the path: `exit 1`
#   M12  the final core-hooks re-merge: `&& python3 -m json.tool` validity check
#
# Run:  bash scripts/test-template-autosync-arms.sh              # the arms against the real script
#       bash scripts/test-template-autosync-arms.sh --sabotage   # every arm against its mutant
# ARMS_TEST_SCRIPT selects the script under test (the sabotage mode sets it per mutant).

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="${ARMS_TEST_SCRIPT:-$PWD/scripts/template-autosync.sh}"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found at $SCRIPT"; exit 1; }
. "$PWD/scripts/drive-sync.sh"                 # the only way to the sync (spec 011)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------- sabotage mode
# One record per arm, fields separated by @@ because the texts contain `|`: id, the exact text to
# mutate (it must occur exactly once in the script, or the anchor is stale and the mode fails
# rather than skipping), the replacement, and the arm function that has to go red. An arm that stays green against its mutant is theatre.
MUTANTS='M01@@        [ -f "$_f" ] || continue@@        :@@arm_unlisted_glob
M08@@  [ -f "$LOCAL_RECORD" ] || return 1@@  [ -f "$LOCAL_RECORD" ] || return 0@@arm_no_record_is_not_stale
M09@@        if [ "$_first" -eq 1 ]; then warn "[accept-local] refused: $_l"; _first=0@@        if [ "$_first" -ne 1 ]; then warn "[accept-local] refused: $_l"; _first=0@@arm_accept_core
M10@@      done; }
      exit 1@@      done; }
      exit 0@@arm_accept_core
M11@@      warn "               differ from — this sync never looks at that path."
      exit 1@@      warn "               differ from — this sync never looks at that path."
      exit 0@@arm_accept_unshipped
M12@@     && python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    cmp -s@@     || python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    cmp -s@@arm_settings_stay_valid'

if [ "${1:-}" = "--sabotage" ]; then
  RED=0; STILL_GREEN=""; STALE_ANCHOR=""
  # A record starts at an `Mnn@@` line; its anchor and replacement may span two lines, so the list
  # is parsed in Python rather than with `read`.
  MUTANTS="$MUTANTS" python3 - "$SCRIPT" "$TMP" <<'PYEOF' > "$TMP/plan" || { echo "FAIL: sabotage plan could not be built"; exit 1; }
import os, re, sys
src, tmp = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
raw = os.environ["MUTANTS"]
records = re.split(r'\n(?=M\d\d@@)', raw)
for rec in records:
    mid, old, new, arm = rec.split("@@")
    n = text.count(old)
    if n != 1:
        print(f"{mid} STALE {arm} {n}")
        continue
    out = f"{tmp}/{mid}.sh"
    open(out, "w", encoding="utf-8").write(text.replace(old, new, 1))
    print(f"{mid} OK {arm} {out}")
PYEOF
  while read -r mid state arm path; do
    if [ "$state" = STALE ]; then
      STALE_ANCHOR="$STALE_ANCHOR $mid(matches:$path)"; continue
    fi
    if ARMS_TEST_SCRIPT="$path" ARMS_ONLY="$arm" bash "$0" >"$TMP/$mid.out" 2>&1; then
      STILL_GREEN="$STILL_GREEN $mid($arm)"
    else
      RED=$((RED+1)); printf '  ok   %s kills %s\n' "$arm" "$mid"
      grep '^  FAIL' "$TMP/$mid.out" | sed 's/^/         /'
    fi
  done < "$TMP/plan"
  [ -z "$STALE_ANCHOR" ] || echo "  FAIL stale mutant anchor(s) — the script moved under them:$STALE_ANCHOR"
  [ -z "$STILL_GREEN" ]  || echo "  FAIL arm(s) still green against their mutant:$STILL_GREEN"
  echo
  echo "sabotage: $RED killed"
  [ -z "$STALE_ANCHOR$STILL_GREEN" ]
  exit $?
fi

# ---------------------------------------------------------------------------- fixtures
# A template clone and a project, both git repositories. The template ships one CORE script
# (the sync itself), one ordinary rule and a project-owned doc; the project starts empty.
build() {
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"
  T="$R/template"; P="$R/project"
  mkdir -p "$T/scripts" "$T/.claude/rules" "$T/.claude/docs"
  cp "$SCRIPT" "$T/scripts/template-autosync.sh"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'rule v1\n' > "$T/.claude/rules/demo-rule.md"
  git -C "$T" init -q -b main
  git -C "$T" config user.email t@t; git -C "$T" config user.name T

  mkdir -p "$P/.claude/rules" "$P/scripts"
  echo '{"name":"fake"}' > "$P/package.json"
  cp "$SCRIPT" "$P/scripts/template-autosync.sh"
  git -C "$P" init -q -b main
  git -C "$P" config user.email p@p; git -C "$P" config user.name P
}
commit_both() {
  git -C "$T" add -A; git -C "$T" commit -qm template
  git -C "$P" add -A; git -C "$P" commit -qm project
}

sync() { CLAUDE_TEMPLATE_DIR="$T" DRIVE_SYNC_SCRIPT="$SCRIPT" drive_sync "$P" "$TMP" "$@"; }

want() { [ -z "${ARMS_ONLY:-}" ] || [ "$ARMS_ONLY" = "$1" ]; }

# ---------------------------------------------------------------------------- M01
# In the template, `--unlisted` walks scripts/*.sh and scripts/*.py. A glob that matches nothing
# stays literal, and without the -f guard the literal pattern is reported as a script that ships
# to no project. The template has .py files today, which is why no suite ever saw it.
arm_unlisted_glob() {
  echo "== M01 — template --unlisted: an empty glob is not a script"
  R="$TMP/m01"; rm -rf "$R"; mkdir -p "$R/scripts" "$R/.claude"
  git -C "$R" init -q -b main
  git -C "$R" remote add origin https://github.com/johanolofsson72/Claude.git
  : > "$R/scripts/not-in-core.sh"
  OUT=$(DRIVE_SYNC_SCRIPT="$SCRIPT" drive_sync "$R" "$TMP" --unlisted 2>&1)
  has   "M01 template mode is engaged (a real unlisted .sh is named)" "$OUT" "scripts/not-in-core.sh	absent from CORE_SCRIPTS"
  hasnt "M01 no literal scripts/*.py when there is no .py"            "$OUT" 'scripts/*.py'
}

# ---------------------------------------------------------------------------- M08
# local_record answers "is there an accepted difference for this path". With no .sync-local at
# all the answer is no. If it said yes, every file already identical to the template would be
# reported as a stale record the developer should drop from a file that does not exist.
arm_no_record_is_not_stale() {
  echo "== M08 — no .sync-local means no stale records"
  build m08
  cp "$T/.claude/rules/demo-rule.md" "$P/.claude/rules/demo-rule.md"   # identical before any sync
  commit_both
  OUT=$(sync --check 2>&1)
  has   "M08 the check ran"                              "$OUT" "[check] would update:"
  hasnt "M08 an identical file is not a stale record"    "$OUT" "stale:"

  # The control: a real record for an identical file IS stale, so the arm is not blind to the bucket.
  SHA=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$P/.claude/rules/demo-rule.md"
        else shasum -a 256 "$P/.claude/rules/demo-rule.md"; fi | cut -d' ' -f1)
  printf '%s  %s  .claude/rules/demo-rule.md\n' "$SHA" "$SHA" > "$P/.claude/.sync-local"
  OUT=$(sync --check 2>&1)
  has   "M08 control: a record for an identical file is stale" "$OUT" "stale:1"
}

# ---------------------------------------------------------------------------- M09 / M10
# A CORE file cannot be accepted as a local difference: the sync would overwrite it anyway. The
# refusal has to fail (exit 1) and has to read as a refusal from its first line.
arm_accept_core() {
  echo "== M09/M10 — --accept-local refuses a CORE file"
  build m09
  commit_both
  sync --quiet >/dev/null 2>&1
  printf '# local edit\n' >> "$P/scripts/template-autosync.sh"
  ERR=$(sync --accept-local scripts/template-autosync.sh 2>&1 >/dev/null); RC=$?
  same "M10 refusing a CORE file exits 1"                   "$RC" "1"
  same "M09 the first line carries the refusal prefix"      "$(printf '%s\n' "$ERR" | head -1 | cut -c1-23)" "[accept-local] refused:"
  hasnt "M09 no later line repeats the prefix"              "$(printf '%s\n' "$ERR" | sed 1d)" "[accept-local] refused:"
  [ -f "$P/.claude/.sync-local" ] && bad "M10 a refused path wrote no record" || ok "M10 a refused path wrote no record"
}

# ---------------------------------------------------------------------------- M11
# A path the template does not ship has nothing to differ from; accepting it must fail too.
arm_accept_unshipped() {
  echo "== M11 — --accept-local refuses a path the template does not ship"
  build m11
  printf 'mine\n' > "$P/.claude/rules/project-only.md"
  commit_both
  sync --quiet >/dev/null 2>&1
  ERR=$(sync --accept-local .claude/rules/project-only.md 2>&1 >/dev/null); RC=$?
  same "M11 an unshipped path exits 1"      "$RC" "1"
  has  "M11 and says why"                   "$ERR" "the template does not ship '.claude/rules/project-only.md'"

  # The control: a shipped, non-CORE, differing path is accepted, so exit 1 is not the only answer.
  printf 'rule, locally\n' > "$P/.claude/rules/demo-rule.md"
  sync --accept-local .claude/rules/demo-rule.md >/dev/null 2>&1; RC=$?
  same "M11 control: a shipped differing rule is accepted" "$RC" "0"
}

# ---------------------------------------------------------------------------- M12
# The last core-hooks re-merge keeps the helper's output only if settings.json still parses. A
# helper that exits 0 after writing broken JSON must be rolled back, or every hook in the project
# stops loading at the next session start.
arm_settings_stay_valid() {
  echo "== M12 — a merge that breaks settings.json is rolled back"
  build m12
  printf '{"hooks":{}}\n' > "$T/.claude/settings.json"
  cat > "$T/scripts/sync-core-hooks.py" <<'EOF'
import sys
open(".claude/settings.json", "w").write("{ broken")
sys.exit(0)
EOF
  printf '{"hooks":{}}\n' > "$P/.claude/settings.json"
  commit_both
  sync --quiet >/dev/null 2>&1
  if python3 -m json.tool "$P/.claude/settings.json" >/dev/null 2>&1; then
    ok "M12 settings.json still parses after a helper wrote broken JSON"
  else
    bad "M12 settings.json still parses after a helper wrote broken JSON (got: $(head -c 40 "$P/.claude/settings.json"))"
  fi
}

want arm_unlisted_glob          && arm_unlisted_glob
want arm_no_record_is_not_stale && arm_no_record_is_not_stale
want arm_accept_core            && arm_accept_core
want arm_accept_unshipped       && arm_accept_unshipped
want arm_settings_stay_valid    && arm_settings_stay_valid

echo
echo "test-template-autosync-arms.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
