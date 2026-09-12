#!/usr/bin/env bash
# test-core-machinery-guard.sh — the guard that refuses an edit the sync would revert.
#
# Spec 007ao. `scripts/core-machinery-guard-hook.sh` denies Edit/Write/MultiEdit
# against the CORE set — the files `template-autosync.sh` overwrites unconditionally.
# Getting the deny right is the easy half; the half that decides whether the guard
# survives contact with a developer is everything it must NOT do. So the arms below
# are weighted that way: two prove it bites, seven prove it stays quiet, and one
# proves the classifier underneath is cheap enough to sit in front of every edit.
#
# Everything here runs the real hook against real throwaway git repositories, feeding
# it the same PreToolUse JSON Claude Code does. Nothing greps the hook's source.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SELF_DIR/core-machinery-guard-hook.sh"
SYNC="$SELF_DIR/template-autosync.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

[ -f "$HOOK" ] || { echo "missing: $HOOK"; exit 1; }
[ -f "$SYNC" ] || { echo "missing: $SYNC"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t coreguard)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- the fixture
# A project as the guard expects to find one: a git root, a .claude/, and its own copy
# of the sync script — which is what makes the classifier reachable. `origin` is set to
# something that is emphatically not the template, because the template check is one of
# the arms and a repo with no origin at all would pass it for the wrong reason.
make_project() {
  _p="$WORK/$1"
  mkdir -p "$_p/scripts" "$_p/.claude/rules"
  git -C "$_p" init -q 2>/dev/null || { git init -q "$_p"; }
  git -C "$_p" remote add origin "https://github.com/someone/not-the-template.git" 2>/dev/null
  cp "$SYNC" "$_p/scripts/template-autosync.sh"
  : > "$_p/scripts/spec_active.py"                      # CORE
  : > "$_p/scripts/project-specific-thing.sh"           # not CORE
  : > "$_p/.claude/rules/feature-pipeline.md"           # CORE
  : > "$_p/.claude/rules/sqlite.md"                     # not CORE
  printf '%s' "$_p"
}

# Run the hook exactly as the harness does: JSON on stdin, decision on stdout.
run_hook() {          # $1 = file path, rest = VAR=VAL environment overrides
  _f="$1"; shift
  env "$@" bash "$HOOK" <<JSON 2>/dev/null
{"tool_name":"Edit","tool_input":{"file_path":"$_f"}}
JSON
}

decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null; }
reason()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }

PROJ=$(make_project proj)

printf '\n[deny] the two paths the sync owns\n'

# ---- A1: a CORE script is refused, and the refusal is usable -----------------
OUT=$(run_hook "$PROJ/scripts/spec_active.py")
if [ "$(decision "$OUT")" = "deny" ]; then
  ok "a CORE script is denied (scripts/spec_active.py)"
  R=$(reason "$OUT")
  # A deny that names no next step is an obstacle. Each of these is a separate
  # promise the spec makes about the message (FR-005), so each is asserted alone.
  case "$R" in *"scripts/spec_active.py"*) ok "  the reason names the path" ;;
    *) bad "  the reason does not name the path" ;; esac
  case "$R" in *"CORE machinery"*"overwrites it unconditionally"*|*"CORE machinery, which this sync overwrites unconditionally"*)
      ok "  the reason states the mechanism" ;;
    *) bad "  the reason does not state the mechanism"; info "$R" ;; esac
  case "$R" in *"ALLOW_CORE_MACHINERY_EDIT"*) ok "  the reason names the override" ;;
    *) bad "  the reason does not name the override" ;; esac
  case "$R" in *"--is-core"*) ok "  the reason says how to ask about any other path" ;;
    *) bad "  the reason does not mention --is-core" ;; esac
else
  bad "a CORE script was NOT denied"; info "$OUT"
fi

# ---- A2: a CORE rule is refused on the same terms ----------------------------
OUT=$(run_hook "$PROJ/.claude/rules/feature-pipeline.md")
[ "$(decision "$OUT")" = "deny" ] \
  && ok "a CORE rule is denied (.claude/rules/feature-pipeline.md)" \
  || bad "a CORE rule was NOT denied"

printf '\n[silent] everywhere it has no business speaking\n'

# ---- A3 / A4: the project's own files ----------------------------------------
OUT=$(run_hook "$PROJ/scripts/project-specific-thing.sh")
[ -z "$OUT" ] && ok "a non-CORE script is untouched" || { bad "a non-CORE script was judged"; info "$OUT"; }

OUT=$(run_hook "$PROJ/.claude/rules/sqlite.md")
[ -z "$OUT" ] && ok "a project-only rule is untouched" || { bad "a project rule was judged"; info "$OUT"; }

# ---- A5: the template repository itself --------------------------------------
# The whole deny message says "go and edit it in the template". Denying it there too
# would leave the instruction with nowhere to be followed.
TPL=$(make_project tpl)
git -C "$TPL" remote set-url origin "https://github.com/johanolofsson72/Claude.git"
OUT=$(run_hook "$TPL/scripts/spec_active.py")
[ -z "$OUT" ] && ok "the template repository is exempt — that is where the change belongs" \
              || { bad "the guard fired inside the template repo"; info "$OUT"; }

# ---- A6: a project with no sync ----------------------------------------------
# No sync script means no sync, which means nothing is coming to overwrite the file.
# A guard with no threat to point at has no claim to make.
NOSYNC=$(make_project nosync)
rm -f "$NOSYNC/scripts/template-autosync.sh"
OUT=$(run_hook "$NOSYNC/scripts/spec_active.py")
[ -z "$OUT" ] && ok "a project with no template-autosync.sh is exempt" \
             || { bad "the guard fired with no sync script present"; info "$OUT"; }

# ---- A7: outside a repository -------------------------------------------------
mkdir -p "$WORK/loose/scripts"
OUT=$(run_hook "$WORK/loose/scripts/spec_active.py")
[ -z "$OUT" ] && ok "a path outside any git repository is exempt" \
             || { bad "the guard fired outside a repository"; info "$OUT"; }

# ---- A8: a nested scripts/ directory that only shares a basename --------------
# .claude/skills/<skill>/scripts/detect-stack.sh is somebody else's file. The sync
# would never write it, so the guard must not claim it either.
mkdir -p "$PROJ/.claude/skills/x/scripts"
: > "$PROJ/.claude/skills/x/scripts/detect-stack.sh"
OUT=$(run_hook "$PROJ/.claude/skills/x/scripts/detect-stack.sh")
[ -z "$OUT" ] && ok "a nested scripts/ dir sharing a CORE basename is untouched" \
             || { bad "the guard claimed a file the sync does not own"; info "$OUT"; }

printf '\n[escape] the ways through, and the way it breaks\n'

# ---- A9: the override ---------------------------------------------------------
OUT=$(run_hook "$PROJ/scripts/spec_active.py" ALLOW_CORE_MACHINERY_EDIT=1)
if [ "$(decision "$OUT")" = "deny" ]; then
  bad "ALLOW_CORE_MACHINERY_EDIT=1 did not permit the edit"
else
  ok "ALLOW_CORE_MACHINERY_EDIT=1 permits the edit"
  # Permitting is not the same as saying nothing. A silent override is a bypass
  # nobody can see in the transcript afterwards.
  case "$OUT" in *ALLOW_CORE_MACHINERY_EDIT*) ok "  and still says what was overridden" ;;
    *) bad "  but says nothing about what was overridden"; info "$OUT" ;; esac
fi

# ---- A10: the classifier is broken -------------------------------------------
# Fail OPEN, and indistinguishably from "not CORE": if the machinery is not working,
# no sync is coming, and blocking every script edit in the meantime is how a guard
# gets deleted along with the protection it was carrying.
BROKEN=$(make_project broken)
printf '#!/bin/bash\nexit 77\n' > "$BROKEN/scripts/template-autosync.sh"
OUT=$(run_hook "$BROKEN/scripts/spec_active.py")
[ -z "$OUT" ] && ok "a classifier that errors fails open, silently" \
             || { bad "a broken classifier produced a decision"; info "$OUT"; }

# ---- A11: the classifier hangs ------------------------------------------------
# The bound is the difference between a guard and a hang in front of the editor.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  SLOW=$(make_project slow)
  printf '#!/bin/bash\nsleep 30\n' > "$SLOW/scripts/template-autosync.sh"
  T0=$(date +%s)
  OUT=$(run_hook "$SLOW/scripts/spec_active.py")
  T1=$(date +%s)
  if [ $((T1 - T0)) -lt 15 ]; then ok "a hanging classifier is bounded ($((T1 - T0))s)"
  else bad "a hanging classifier was not bounded ($((T1 - T0))s)"; fi
  [ -z "$OUT" ] && ok "  and the timeout fails open" || bad "  but produced a decision"
else
  info "no timeout(1) available — the bound arm is skipped, not passed"
fi

printf '\n[cost] the classifier sits in front of every edit\n'

# ---- A12: --is-core is in the millisecond class, with no template present -----
# Both halves matter. The wall clock is the budget; the missing template directory is
# the proof that it never resolves one, which is what keeps a 20 s bounded git fetch
# out of the path (research.md M7).
T0=$(date +%s)
i=0
while [ "$i" -lt 20 ]; do
  env -u CLAUDE_TEMPLATE_DIR HOME="$WORK/no-home" bash "$SYNC" --is-core scripts/spec_active.py >/dev/null 2>&1
  i=$((i + 1))
done
T1=$(date +%s)
if [ $((T1 - T0)) -le 4 ]; then ok "20 --is-core calls in $((T1 - T0))s with no template reachable"
else bad "20 --is-core calls took $((T1 - T0))s — something below it is resolving a template"; fi

env -u CLAUDE_TEMPLATE_DIR HOME="$WORK/no-home" bash "$SYNC" --is-core scripts/spec_active.py >/dev/null 2>&1
[ $? -eq 0 ] && ok "--is-core still answers CORE with no template directory anywhere" \
             || bad "--is-core needs a template to answer"

env -u CLAUDE_TEMPLATE_DIR HOME="$WORK/no-home" bash "$SYNC" --is-core scripts/project-specific-thing.sh >/dev/null 2>&1
[ $? -eq 1 ] && ok "--is-core exits 1 for a file the template does not own" \
             || bad "--is-core did not exit 1 for a non-CORE path"

bash "$SYNC" --is-core >/dev/null 2>&1
[ $? -eq 2 ] && ok "--is-core exits 2 with no path" || bad "--is-core did not exit 2 with no path"

bash "$SYNC" --is-core --quiet >/dev/null 2>&1
[ $? -eq 2 ] && ok "--is-core exits 2 rather than swallowing the next flag as a path" \
             || bad "--is-core swallowed a flag as its path argument"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
