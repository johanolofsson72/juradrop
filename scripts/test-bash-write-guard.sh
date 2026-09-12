#!/usr/bin/env bash
# Harness for the two Bash enforcement layers (row H7b).
#
# WHY THIS EXISTS
# ---------------
# The three pipeline guards were wired to Edit|Write|MultiEdit and to nothing else, so for 18 days the
# answer to "may I write this source file?" depended on which tool was asked. 56 register rows shipped
# through the shell while every Edit was denied. This harness is what stops that from being true again.
#
# BOTH LAYERS, AND THE SEAM BETWEEN THEM
# --------------------------------------
# The interesting fixture is not "the pre-layer blocks sed -i" — it is `bound`, which proves the pre-layer
# CANNOT see a python-heredoc write and that the post-layer catches exactly that. A declared coverage bound
# with no executable demonstration is prose, and prose is what failed in this row's own subject.
#
# Usage:
#   bash scripts/test-bash-write-guard.sh            # all fixtures
#   bash scripts/test-bash-write-guard.sh bound      # one fixture
#
# Exit: 0 all expectations met · 1 an expectation failed · 2 the harness broke.
# Three states on purpose (spec 007l): "the suite is red" and "the harness fell over" are different facts.
#
# Scenario map: SC-1437..SC-1442 (row H7b) and SC-1678..SC-1682, SC-1684 (row H7t) in specs/SCENARIOS.md.
#               SC-927..SC-933 (row S6) — the `ignored` fixture.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PRE="$SCRIPT_DIR/bash-write-guard-hook.sh"
POST="$SCRIPT_DIR/bash-write-detect-hook.sh"
for h in "$PRE" "$POST"; do
  [ -f "$h" ] || { echo "HARNESS ERROR: hook not found: $h" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "HARNESS ERROR: jq is required" >&2; exit 2; }

FILTER="${1:-}"
want() { [ -z "$FILTER" ] || [ "$FILTER" = "$1" ]; }

WORK=$(mktemp -d 2>/dev/null) || { echo "HARNESS ERROR: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

CHECKS=0
FAILURES=0
ok()  { CHECKS=$((CHECKS + 1)); echo "  ✓ $1"; }
bad() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); echo "  ✗ $1"; }

# A fixture project whose ACTIVE register row has no artifacts at all, so all three pipeline guards deny
# a source-file write. That is the precondition; everything below tests whether the shell can dodge it.
make_fixture() {
  local name="$1"
  local root="$WORK/$name"
  mkdir -p "$root/.git" "$root/src" "$root/scripts" "$root/specs" "$root/.claude"
  : > "$root/package.json"
  {
    echo "# Spec register"; echo; echo "## Specs"; echo
    echo '- [x] 007 — preview — full track — done'
    echo '- [/] 007z — active-spec — full track — IN PROGRESS, no artifacts at all'
  } > "$root/specs/INDEX.md"
  echo "class App {}" > "$root/src/App.cs"
  echo "notes" > "$root/notes.md"
  printf '%s' "$root"
}

# A fixture root that also carries the sync script, so scripts/core-machinery-guard-hook.sh can ask
# --is-core about it (row H7t). Without the sync present that guard exits early by design — "no sync, so
# no owner to defer to" — which would make every CORE assertion below pass for the wrong reason.
#
# The real script is copied rather than stubbed: the CORE lists ARE the thing under test, and a stub with
# a hand-written list here would be the fourth copy of exactly the policy this row refuses to duplicate.
make_core_fixture() {
  local name="$1" root
  root=$(make_fixture "$name")
  cp "$SCRIPT_DIR/template-autosync.sh" "$root/scripts/template-autosync.sh" 2>/dev/null || return 1
  mkdir -p "$root/.claude/rules"
  echo "# a core rule" > "$root/.claude/rules/spec-register.md"
  echo "#!/bin/bash" > "$root/scripts/thing.sh"
  printf '%s' "$root"
}

# Run the PreToolUse layer. Echoes "ALLOW" or "DENY <first line of reason>".
run_pre() {
  local root="$1" cmd="$2"
  local out
  out=$(jq -n --arg c "$cmd" --arg w "$root" '{tool_input:{command:$c}, cwd:$w}' \
        | CLAUDE_PROJECT_DIR="$root" bash "$PRE" 2>/dev/null)
  if [ -z "$out" ]; then printf 'ALLOW'; return 0; fi
  # The whole reason is flattened onto one line: the decision is on line 1 but the target path is on
  # line 3, and an assertion that can only see line 1 would have passed a guard that named the wrong file.
  printf '%s' "$out" | python3 -c '
import json,sys
try:
    h = json.load(sys.stdin).get("hookSpecificOutput", {})
    r = " ".join(h.get("permissionDecisionReason","").split())
    print(h.get("permissionDecision","?").upper() + " " + r)
except Exception:
    print("UNPARSEABLE")' 2>/dev/null || printf 'UNPARSEABLE'
}

# run_pre with ALLOW_CORE_MACHINERY_EDIT=1 in the environment. The override is the only sanctioned way
# past the CORE guard, and it is the half that is easy to lose: a delegation that ignored it would read as
# "stricter", and would break the one path spec 007al needed to restore work a sync had deleted.
run_pre_override() {
  local root="$1" cmd="$2" out
  out=$(jq -n --arg c "$cmd" --arg w "$root" '{tool_input:{command:$c}, cwd:$w}' \
        | CLAUDE_PROJECT_DIR="$root" ALLOW_CORE_MACHINERY_EDIT=1 bash "$PRE" 2>/dev/null)
  if [ -z "$out" ]; then printf 'ALLOW'; return 0; fi
  printf '%s' "$out" | python3 -c '
import json,sys
try:
    h = json.load(sys.stdin).get("hookSpecificOutput", {})
    if not h.get("permissionDecision"):
        print("ALLOW"); raise SystemExit
    r = " ".join(h.get("permissionDecisionReason","").split())
    print(h.get("permissionDecision","?").upper() + " " + r)
except Exception:
    print("UNPARSEABLE")' 2>/dev/null || printf 'UNPARSEABLE'
}

# Full reason text of the PreToolUse layer (for the secrets assertion).
run_pre_raw() {
  local root="$1" cmd="$2"
  jq -n --arg c "$cmd" --arg w "$root" '{tool_input:{command:$c}, cwd:$w}' \
    | CLAUDE_PROJECT_DIR="$root" bash "$PRE" 2>/dev/null
}

# Run the PostToolUse layer. Echoes "BLOCK <reason+systemMessage flattened>" or "SILENT".
#
# It reports through JSON rather than exit 2 on purpose (FR-016): exit 2 hands stderr to the model alone,
# and a detection only the model sees is one that can be summarised away. So the harness asserts on the
# decision AND on both audiences being addressed, not on an exit code.
# In-place edit that works on BSD sed (macOS) and GNU sed (Linux, Git Bash) alike.
#
# WHY: bare `sed -i 's/x/y/' f` is GNU-only. BSD sed reads the expression as the
# BACKUP SUFFIX and then tries to parse the filename as the script, so it fails and
# leaves the file untouched. That is what SC-922 was: lines 588/599 never made the
# tick, the detector correctly saw nothing changed and went SILENT, and the test
# read a portability bug as a broken gate for as long as it ran on a Mac. The gate
# itself was fine -- verified by making the same edit portably and watching it block.
#
# SC-921 was worse: it expects SILENT, so it PASSED, for exactly the wrong reason.
# Cross-platform is a base requirement here, not a nicety.
inplace() {  # inplace <sed-expression> <file>
  local expr="$1" file="$2" tmp
  tmp="${file}.inplace.$$"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}

run_post() {
  local root="$1" cmd="$2" out
  out=$(jq -n --arg c "$cmd" --arg w "$root" '{tool_input:{command:$c}, cwd:$w}' \
        | CLAUDE_PROJECT_DIR="$root" bash "$POST" 2>/dev/null)
  if [ -z "$out" ]; then printf 'SILENT'; return 0; fi
  printf '%s' "$out" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
    if d.get("decision") != "block":
        print("SILENT"); raise SystemExit
    body = " ".join((d.get("reason","") + " " + d.get("systemMessage","")).split())
    print(("BLOCK+MSG " if d.get("systemMessage") else "BLOCK-NOMSG ") + body)
except Exception:
    print("UNPARSEABLE")' 2>/dev/null || printf 'UNPARSEABLE'
}

expect_block()  { case "$2" in BLOCK+MSG*) ok "$1" ;;
                               BLOCK-NOMSG*) bad "$1 — blocked but emitted no systemMessage: the developer never sees it (FR-016)" ;;
                               *) bad "$1 — expected a block, got: $(printf '%s' "$2" | cut -c1-90)" ;; esac; }
expect_silent() { case "$2" in SILENT) ok "$1" ;; *) bad "$1 — expected silence, got: $(printf '%s' "$2" | cut -c1-90)" ;; esac; }

expect_deny() {
  local label="$1" actual="$2" needle="${3:-}"
  case "$actual" in
    DENY*)
      if [ -z "$needle" ]; then ok "$label — DENY"; return; fi
      case "$actual" in *"$needle"*) ok "$label — DENY (names $needle)" ;;
                        *) bad "$label — denied but did not name \"$needle\": $(printf '%s' "$actual" | cut -c1-90)" ;; esac ;;
    *) bad "$label — expected DENY, got: $(printf '%s' "$actual" | cut -c1-90)" ;;
  esac
}

expect_allow() {
  local label="$1" actual="$2"
  if [ "$actual" = "ALLOW" ]; then ok "$label — ALLOW"; else bad "$label — expected ALLOW, got: $(printf '%s' "$actual" | cut -c1-90)"; fi
}

# --------------------------------------------------------------- FORMS (SC-1437)
if want forms; then
  echo "FIXTURE forms — the six shell write forms the pre-layer claims, against a gated source file"
  ROOT=$(make_fixture forms)
  expect_deny "sed -i"       "$(run_pre "$ROOT" "sed -i '' 's/a/b/' src/App.cs")"        "App.cs"
  expect_deny "redirect >"   "$(run_pre "$ROOT" "echo 'class App {}' > src/App.cs")"     "App.cs"
  expect_deny "append >>"    "$(run_pre "$ROOT" "echo x >> src/App.cs")"                 "App.cs"
  expect_deny "heredoc"      "$(run_pre "$ROOT" "$(printf 'cat > src/App.cs <<%sEOF%s\nclass App {}\nEOF\n' "'" "'")")" "App.cs"
  expect_deny "tee"          "$(run_pre "$ROOT" "echo x | tee src/App.cs")"              "App.cs"
  expect_deny "cp"           "$(run_pre "$ROOT" "cp /tmp/other.cs src/App.cs")"          "App.cs"
  expect_deny "mv"           "$(run_pre "$ROOT" "mv /tmp/other.cs src/App.cs")"          "App.cs"
  # The reason must be the guard's own, passed through — not a second opinion written here.
  RAW=$(run_pre_raw "$ROOT" "sed -i '' 's/a/b/' src/App.cs")
  case "$RAW" in
    *"pipeline phases incomplete"*|*"cannot determine which spec is active"*|*"no spec register"*)
      ok "the delegated guard's own reason is passed through" ;;
    *) bad "the deny reason is not the guard's — the layer is deciding instead of delegating" ;;
  esac
fi

# --------------------------------------------------------------- QUIET (SC-1439)
if want quiet; then
  echo "FIXTURE quiet — a read-only command, an allowlisted path, a non-source extension: no output"
  ROOT=$(make_fixture quiet)
  expect_allow "read-only grep"        "$(run_pre "$ROOT" "grep -rn TODO src/")"
  expect_allow "read-only build"       "$(run_pre "$ROOT" "dotnet build 2>&1 | tail -5")"
  expect_allow "write under scripts/"  "$(run_pre "$ROOT" "echo x > scripts/thing.sh")"
  expect_allow "write under specs/"    "$(run_pre "$ROOT" "echo x > specs/INDEX.md")"
  expect_allow "non-source extension"  "$(run_pre "$ROOT" "echo x > notes.md")"
  expect_allow "redirect to /dev/null" "$(run_pre "$ROOT" "ls src/ > /dev/null")"
  expect_allow "fd duplication only"   "$(run_pre "$ROOT" "make all 2>&1")"
fi

# --------------------------------------------------------------- SECRETS (SC-1442)
if want secrets; then
  echo "FIXTURE secrets — neither layer may echo the command string"
  ROOT=$(make_fixture secrets)
  NEEDLE="hunter2-do-not-print-me"
  RAW=$(run_pre_raw "$ROOT" "sed -i '' 's/x/$NEEDLE/' src/App.cs")
  case "$RAW" in
    *"$NEEDLE"*) bad "pre-layer leaked the command string into its deny reason" ;;
    *)           ok  "pre-layer output holds no part of the command string" ;;
  esac
  : > "$ROOT/.claude/.bash-write-marker"
  sleep 1
  echo "changed" > "$ROOT/src/App.cs"
  RAW=$(run_post "$ROOT" "python3 -c \"open('src/App.cs','w').write('$NEEDLE')\"")
  case "$RAW" in
    *"$NEEDLE"*) bad "post-layer leaked the command string into its report" ;;
    *)           ok  "post-layer output holds no part of the command string" ;;
  esac
fi

# --------------------------------------------------------------- CAP (FR-006a)
if want cap; then
  echo "FIXTURE cap — more distinct write groups than the layer will check unverified"
  ROOT=$(make_fixture cap)
  CMD=""
  i=1
  while [ "$i" -le 9 ]; do
    mkdir -p "$ROOT/src/d$i"
    CMD="${CMD}echo x > src/d$i/F.cs; "
    i=$((i + 1))
  done
  expect_deny "nine groups" "$(run_pre "$ROOT" "$CMD")" "cap"
  # ...and eight is still checked properly rather than waved through.
  CMD=""
  i=1
  while [ "$i" -le 8 ]; do CMD="${CMD}echo x > src/d$i/F.cs; "; i=$((i + 1)); done
  expect_deny "eight groups (at the cap, still delegated)" "$(run_pre "$ROOT" "$CMD")" "F.cs"
fi

# --------------------------------------------------------------- BOUND (SC-1438 + FR-010)
# The fixture this whole design turns on. The pre-layer is a string parser and CANNOT see these writes;
# the post-layer must. If this fixture ever goes green on the pre-layer arm, the bound in the header is
# wrong. If it ever goes red on the post-layer arm, the coverage claim is wrong.
if want bound; then
  echo "FIXTURE bound — what the parser still cannot see, and what row S5 moved out of that set"
  ROOT=$(make_fixture bound)

  # Until row S5 this fixture asserted the OPPOSITE — that the pre-layer allows a python-heredoc
  # write, as the declared bound. It was a faithful description of a working bypass, and it was
  # used: a register tick went through this exact shape past all five guards. The bound was real;
  # what was wrong was the belief that the post-layer covered it, which it did not (see `postfive`).
  PY_CMD="python3 - <<'PY'
open('src/App.cs','w').write('mutated')
PY"
  expect_deny "pre-layer now sees a python-heredoc write" "$(run_pre "$ROOT" "$PY_CMD")" "src/App.cs"

  # The pre-layer stamped the marker on its way past — which is exactly what makes the next step possible.
  [ -f "$ROOT/.claude/.bash-write-marker" ] && ok "pre-layer stamped the before-marker even while deciding" \
    || bad "pre-layer decided without stamping a marker — the post-layer is now blind"

  sleep 1
  printf 'mutated\n' > "$ROOT/src/App.cs"        # what the python heredoc would have done
  OUT=$(run_post "$ROOT" "$PY_CMD")
  expect_block "post-layer catches it on the outcome too, and tells the developer as well as the model" "$OUT"
  case "$OUT" in *"src/App.cs"*) ok "post-layer names the changed file" ;;
                 *) bad "post-layer blocked without naming the file" ;; esac

  # eval — same story, different spelling.
  ROOT=$(make_fixture bound2)
  EVAL_CMD='CMD="sed -i \"\" s/a/b/ src/App.cs"; eval "$CMD"'
  expect_allow "pre-layer cannot see an eval-assembled write" "$(run_pre "$ROOT" "$EVAL_CMD")"
  sleep 1
  printf 'mutated\n' > "$ROOT/src/App.cs"
  OUT=$(run_post "$ROOT" "$EVAL_CMD")
  expect_block "post-layer caught the eval write" "$OUT"
fi

# --------------------------------------------------------------- ESCAPE (SC-1440)
if want escape; then
  echo "FIXTURE escape — the post-layer blocks once per finding, then lets the session move"
  ROOT=$(make_fixture escape)
  : > "$ROOT/.claude/.bash-write-marker"; sleep 1
  printf 'mutated\n' > "$ROOT/src/App.cs"
  OUT=$(run_post "$ROOT" "true")
  expect_block "first encounter blocks" "$OUT"

  : > "$ROOT/.claude/.bash-write-marker"; sleep 1
  printf 'mutated again\n' > "$ROOT/src/App.cs"
  OUT=$(run_post "$ROOT" "true")
  expect_silent "same finding again is silent — the session is not trapped" "$OUT"

  mkdir -p "$ROOT/src/other"
  : > "$ROOT/.claude/.bash-write-marker"; sleep 1
  printf 'new\n' > "$ROOT/src/other/New.cs"
  OUT=$(run_post "$ROOT" "true")
  expect_block "a DIFFERENT finding arms it again" "$OUT"
fi

# --------------------------------------------------------------- EXEMPT (SC-1441)
if want exempt; then
  echo "FIXTURE exempt — tree-moving git verbs are exempt; content-carrying ones are not"
  # The sync is on this list because row S5 put core-machinery into this layer's delegates and the very
  # sync that landed row S5 promptly reported its own four CORE files. Exempting the sanctioned writer of
  # CORE files is not a hole; reporting it every time is how a report stops being read.
  for verb in "git checkout -- ." "git stash pop" "git pull --rebase" "git reset --hard HEAD" \
              "bash scripts/template-autosync.sh --force"; do
    ROOT=$(make_fixture "exempt$(printf '%s' "$verb" | tr -cd 'a-z')")
    : > "$ROOT/.claude/.bash-write-marker"; sleep 1
    printf 'mutated\n' > "$ROOT/src/App.cs"
    OUT=$(run_post "$ROOT" "$verb")
    expect_silent "exempt: $verb" "$OUT"
  done
  for verb in "git apply /tmp/p.patch" "git cherry-pick abc123"; do
    ROOT=$(make_fixture "notexempt$(printf '%s' "$verb" | tr -cd 'a-z')")
    : > "$ROOT/.claude/.bash-write-marker"; sleep 1
    printf 'mutated\n' > "$ROOT/src/App.cs"
    OUT=$(run_post "$ROOT" "$verb")
    expect_block "NOT exempt: $verb" "$OUT"
  done
fi

# --------------------------------------------------------------- NOMARKER
if want nomarker; then
  echo "FIXTURE nomarker — with no before-time the post-layer says nothing rather than inventing a finding"
  ROOT=$(make_fixture nomarker)
  printf 'mutated\n' > "$ROOT/src/App.cs"
  OUT=$(run_post "$ROOT" "true")
  expect_silent "no marker → silent" "$OUT"
fi

# --------------------------------------------------------------- CORE (SC-1678..SC-1681, row H7t)
if want core; then
  echo "FIXTURE core — the CORE-ownership question is asked on the Bash route too, not only on Edit"
  if ! ROOT=$(make_core_fixture core); then
    bad "harness could not stage the sync script into the fixture"
  else
    # SC-1678 — the defect this fixture exists for. Before H7t: Edit denied, sed -i was silent.
    expect_deny "sed -i against a CORE script" \
      "$(run_pre "$ROOT" "sed -i '' 's/a/b/' scripts/template-autosync.sh")" "core-machinery-guard-hook.sh"
    expect_deny "redirect against a CORE script" \
      "$(run_pre "$ROOT" "echo x > scripts/spec_active.py")" "core-machinery-guard-hook.sh"
    expect_deny "redirect against a CORE rule" \
      "$(run_pre "$ROOT" "echo x > .claude/rules/spec-register.md")" "core-machinery-guard-hook.sh"

    # SC-1679 — without this the whole fixture is compatible with a guard that denies everything under
    # scripts/, which would break the three pipeline guards' deliberate scripts/** exemption.
    expect_allow "sed -i against a NON-core script under scripts/" \
      "$(run_pre "$ROOT" "sed -i '' 's/a/b/' scripts/thing.sh")"
    expect_allow "redirect to a new script nobody owns" \
      "$(run_pre "$ROOT" "echo x > scripts/brand-new-thing.sh")"

    # SC-1680 — the override. Named in the deny text, so it has to work on this route as well.
    expect_allow "ALLOW_CORE_MACHINERY_EDIT=1 on the same CORE write" \
      "$(run_pre_override "$ROOT" "sed -i '' 's/a/b/' scripts/template-autosync.sh")"

    # SC-1681 — the provenance line must name the right gate. A CORE file under scripts/ is not "a source
    # file", and the pipeline guards never see it, so the pipeline header would send the reader to run a
    # pipeline phase that has nothing to do with why they were stopped.
    RAW=$(run_pre_raw "$ROOT" "sed -i '' 's/a/b/' scripts/template-autosync.sh")
    case "$RAW" in
      *"a file the TEMPLATE owns"*) ok "the provenance line names template ownership, not the pipeline" ;;
      *) bad "the CORE deny wears the pipeline guard's header — it names the wrong gate" ;;
    esac
    case "$RAW" in
      *"a source file the pipeline guard denies"*)
        bad "the CORE deny still carries the pipeline header text" ;;
      *) ok "the pipeline header does not appear on a CORE deny" ;;
    esac
    # The delegate's own words, passed through rather than restated here.
    case "$RAW" in
      *"is not this project's file to edit"*) ok "the CORE guard's own reason is passed through verbatim" ;;
      *) bad "the CORE reason is not the guard's — the layer is deciding instead of delegating" ;;
    esac
    # Secrets (FR-006) holds on this arm too, not just on the pipeline arm.
    NEEDLE="hunter2-core-do-not-print-me"
    RAW2=$(run_pre_raw "$ROOT" "sed -i '' 's/x/$NEEDLE/' scripts/template-autosync.sh")
    case "$RAW2" in
      *"$NEEDLE"*) bad "the CORE arm leaked the command string into its deny reason" ;;
      *)           ok  "the CORE arm's output holds no part of the command string" ;;
    esac
  fi
fi

# --------------------------------------------------------------- OWNED (SC-1684, row H7t)
#
# The six files this family is made of were project-local for four days, during which four template syncs
# reverted the REST of their row and left them standing only because the template did not own them. That
# is not protection, it is an accident with a shelf life — and the same fact kept them out of every other
# project. They are CORE upstream now, and this check is what notices if a future sync drops them again:
# asked of THIS repo's own classifier, so it fails here the moment the list arrives without them.
if want owned; then
  echo "FIXTURE owned — the Bash-layer family is CORE, asked of this repo's own classifier"
  SYNC="$SCRIPT_DIR/template-autosync.sh"
  if [ ! -f "$SYNC" ]; then
    echo "  ----  no template-autosync.sh in this repo — nothing owns these files here, so nothing to check"
  else
    for f in bash_write_targets.py bash-write-guard-hook.sh bash-write-detect-hook.sh \
             test-bash-write-guard.sh validate-register-ids.sh test-register-ids.sh \
             core-machinery-guard-hook.sh; do
      if bash "$SYNC" --is-core "scripts/$f" >/dev/null 2>&1; then
        ok "scripts/$f is CORE — the sync carries it"
      else
        bad "scripts/$f is NOT CORE: the template does not own it, so hardening it here is already lost"
      fi
    done
  fi
fi

# ------------------------------------------------- FALSIFICATION (SC-1682, row H7t)
#
# Everything above is compatible with a guard that was already denying for some other reason. This block
# removes the one delegate under test and demands that the suite notices. A gate that is green both with
# and without its fix measures nothing — which is the whole subject of the row this fixture belongs to.
#
# The mutant runs from its OWN directory with every sibling guard copied beside it, so HOOK_DIR resolves
# and the ONLY difference between control and mutant is the name in the delegation list. Running the
# mutant from $WORK with no siblings would "pass" by finding no guards at all.
if want falsify; then
  echo "== falsification: removing the CORE delegate must turn this fixture red =="
  if ! ROOT=$(make_core_fixture falsify); then
    bad "harness could not stage the sync script into the fixture"
  else
    MUT="$WORK/mutant"
    mkdir -p "$MUT"
    for f in bash_write_targets.py core-machinery-guard-hook.sh spec-register-guard-hook.sh \
             pipeline-state-guard-hook.sh spec-interview-guard-hook.sh; do
      cp "$SCRIPT_DIR/$f" "$MUT/$f" 2>/dev/null || true
    done
    cp "$PRE" "$MUT/control.sh"
    sed 's/^BASENAME_GUARDS="core-machinery-guard-hook\.sh /BASENAME_GUARDS="/' "$PRE" > "$MUT/mutant.sh"
    if cmp -s "$MUT/control.sh" "$MUT/mutant.sh"; then
      bad "the mutation changed nothing — the delegation list is not written the way this block expects"
    else
      PAYLOAD=$(jq -n --arg c "sed -i '' 's/a/b/' scripts/template-autosync.sh" --arg w "$ROOT" \
                  '{tool_input:{command:$c}, cwd:$w}')
      CTRL=$(printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$ROOT" bash "$MUT/control.sh" 2>/dev/null)
      MUTO=$(printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$ROOT" bash "$MUT/mutant.sh" 2>/dev/null)
      if [ -n "$CTRL" ]; then ok "control (delegate present, copied tree) still denies"
      else bad "control did not deny from the copied tree — the falsification proves nothing"; fi
      if [ -z "$MUTO" ]; then ok "mutant (delegate removed) goes silent — the delegation is load-bearing"
      else bad "mutant still denies without the CORE delegate: this fixture would pass without the fix"; fi
    fi
  fi
fi

# --------------------------------------------------------------- OPAQUE (SC-913..SC-919, SC-925)
if want opaque; then
  echo "FIXTURE opaque — an interpreter with no script path, across five spellings and four controls"
  ROOT=$(make_fixture opaque)

  # SC-913 is the CONTROL, and it comes first on purpose. Four of the assertions below are "this
  # command is denied"; if the fixture's register were misbuilt so that NOTHING is denied, every one
  # of them would fail loudly — but if it were misbuilt so that EVERYTHING is denied, they would all
  # pass for no reason at all. The control is the arm that catches the second case.
  expect_deny "SC-913 control: sed -i on a gated source file" \
    "$(run_pre "$ROOT" "sed -i 's/a/b/' src/App.cs")" "src/App.cs"

  expect_deny "SC-914 the same write inside a python heredoc" "$(run_pre "$ROOT" "python3 - <<'PY'
open('src/App.cs','a').write('x')
PY")" "src/App.cs"

  # The semicolon is load-bearing: a naive segment split would cut the region here and never reach
  # the path. That is the shape `_split_unquoted` exists for.
  expect_deny "SC-915 python3 -c, with a semicolon inside the program" \
    "$(run_pre "$ROOT" "python3 -c \"import sys; open('src/App.cs','a').write('x')\"")" "src/App.cs"

  expect_deny "SC-916 perl -e, path nested one quoting level down" \
    "$(run_pre "$ROOT" "perl -e 'open(F,\">>\",\"src/App.cs\")'")" "src/App.cs"
  expect_deny "SC-916 node -e" \
    "$(run_pre "$ROOT" "node -e \"require('fs').appendFileSync('src/App.cs','x')\"")" "src/App.cs"
  expect_deny "SC-916 ruby -e" \
    "$(run_pre "$ROOT" "ruby -e 'File.write(\"src/App.cs\",\"x\")'")" "src/App.cs"

  # The other half of the trade, and the one that decides whether this guard survives contact with a
  # real session: an ordinary one-liner must cost nothing. A gate that fires on correct routine work
  # trains its reader to wave it through, and then it is not a gate.
  expect_allow "SC-917 an interpreter one-liner naming no path" "$(run_pre "$ROOT" "python3 -c \"print(1+1)\"")"
  expect_allow "SC-919 an interpreter one-liner naming an unguarded path" \
    "$(run_pre "$ROOT" "python3 -c \"open('notes.md','a').write('x')\"")"
  expect_allow "SC-925 no interpreter, no write form" "$(run_pre "$ROOT" "echo hello")"
  expect_allow "SC-925 a plain read of the same gated file" "$(run_pre "$ROOT" "cat src/App.cs")"

  # SC-918 — accepted cost, asserted rather than hoped for. A read-only one-liner naming a gated path
  # IS denied, because nothing here reads the program. The refusal has to carry the way out, or the
  # developer meets a wall with no door.
  OUT=$(run_pre "$ROOT" "python3 -c \"print(open('src/App.cs').read())\"")
  expect_deny "SC-918 a read-only one-liner naming a gated path is denied too" "$OUT" "src/App.cs"
  case "$OUT" in *"only READING"*) ok "SC-918 ...and the reason names the read escape" ;;
                 *) bad "SC-918 denied without telling the reader how to read the file" ;; esac
  case "$OUT" in *"Edit tool"*) ok "SC-918 ...and the write escape" ;;
                 *) bad "SC-918 denied without naming the Edit tool" ;; esac

  # A path built at runtime stays invisible, and the spec says so. Asserting the bound keeps the
  # claim honest when someone later reads the deny arms above and assumes full coverage.
  #
  # String concatenation is the honest demonstration: `'src/App' + '.cs'` leaves no token that is
  # both path-shaped and gated. `os.path.join('src','App.cs')` is NOT used here even though it is the
  # more idiomatic spelling — it happens to be denied, because the fragment `App.cs` carries a source
  # extension all by itself. That is an accident of this input, not coverage, and an assertion that
  # depends on it would be pinning luck.
  expect_allow "declared bound: a path assembled at runtime is still not seen" \
    "$(run_pre "$ROOT" "python3 -c \"open('src/App' + '.cs','a')\"")"
fi

# --------------------------------------------------------------- ORDER (SC-926)
if want order; then
  echo "FIXTURE order — the operand order must not decide the verdict"
  ROOT=$(make_core_fixture order) || { echo "  (skipped: template-autosync.sh not copyable)"; ROOT=""; }
  if [ -n "$ROOT" ]; then
    # Found while writing the fixtures above, not by looking for it. The grouping collapses files that
    # share a directory and an extension, which is an identity for the three guards that read only the
    # path — and NOT for core-machinery, which reads the basename. thing.sh and template-autosync.sh
    # are both scripts/*.sh with opposite verdicts, so whichever the grouping picked answered for both.
    expect_deny "control: the CORE file alone" \
      "$(run_pre "$ROOT" "sed -i 's/a/b/' scripts/template-autosync.sh")" "template-autosync.sh"
    expect_deny "CORE file first, non-CORE second" \
      "$(run_pre "$ROOT" "sed -i 's/a/b/' scripts/template-autosync.sh scripts/thing.sh")" "template-autosync.sh"
    expect_deny "non-CORE FIRST — this is the arm that used to ALLOW" \
      "$(run_pre "$ROOT" "sed -i 's/a/b/' scripts/thing.sh scripts/template-autosync.sh")" "template-autosync.sh"
    # The other direction, so the fix is a fix and not a blanket. A guard that denied everything under
    # scripts/ would satisfy all three arms above and be useless.
    expect_allow "a non-CORE script on its own is still allowed" \
      "$(run_pre "$ROOT" "sed -i 's/a/b/' scripts/thing.sh")"
  fi
fi

# --------------------------------------------------------------- POSTFIVE (SC-920)
if want postfive; then
  echo "FIXTURE postfive — the post-layer asks all five guards, not three"
  ROOT=$(make_core_fixture postfive) || { echo "  (skipped: template-autosync.sh not copyable)"; ROOT=""; }
  if [ -n "$ROOT" ]; then
    : > "$ROOT/.claude/.bash-write-marker"; rm -f "$ROOT/.claude/.bash-write-blocked"; sleep 1
    printf '# mutated\n' >> "$ROOT/scripts/template-autosync.sh"
    OUT=$(run_post "$ROOT" "true")
    expect_block "a changed CORE file is reported" "$OUT"
    case "$OUT" in *"core-machinery"*) ok "...and the report names which guard refused it" ;;
                   *) bad "reported without naming core-machinery — the reader cannot find the repair" ;; esac

    # Falsification. Cut the two guards row S5 added back out of the list and the same change must go
    # silent again — which is the state this fixture was written to end. Without this arm the block
    # above would pass on any project where some OTHER guard happens to object.
    MUT="$WORK/postfive-mut"; mkdir -p "$MUT"
    sed 's/^scan "\$ALLP" core-machinery-guard-hook\.sh core-owed-tick-guard-hook\.sh$/:/' "$POST" > "$MUT/mutant.sh"
    if cmp -s "$POST" "$MUT/mutant.sh"; then
      bad "the mutation changed nothing — the post-layer's delegate list is not written the way this block expects"
    else
      : > "$ROOT/.claude/.bash-write-marker"; rm -f "$ROOT/.claude/.bash-write-blocked"; sleep 1
      printf '# mutated again\n' >> "$ROOT/scripts/template-autosync.sh"
      MUTO=$(jq -n --arg c "true" --arg w "$ROOT" '{tool_input:{command:$c}, cwd:$w}' \
               | CLAUDE_PROJECT_DIR="$ROOT" bash "$MUT/mutant.sh" 2>/dev/null)
      if [ -z "$MUTO" ]; then ok "mutant (three delegates) goes silent — this is the defect S5 closed"
      else bad "mutant still reported: the fixture would pass without the fix"; fi
    fi
  fi
fi

# --------------------------------------------------------------- POSTBYTES (SC-921..SC-923)
if want postbytes; then
  echo "FIXTURE postbytes — the post-layer hands over the added lines, so its verdict is the narrow one"
  ROOT="$WORK/postbytes"
  mkdir -p "$ROOT/scripts" "$ROOT/.claude/rules" "$ROOT/specs" "$ROOT/src"
  git -C "$ROOT" init -q 2>/dev/null || git init -q "$ROOT"
  git -C "$ROOT" remote add origin "https://github.com/someone/not-the-template.git" 2>/dev/null
  : > "$ROOT/package.json"
  cp "$SCRIPT_DIR/template-autosync.sh" "$ROOT/scripts/template-autosync.sh" 2>/dev/null
  printf 'core rule\n' > "$ROOT/.claude/rules/feature-pipeline.md"
  printf '{}\n' > "$ROOT/.claude/settings.json"
  {
    echo "# Spec register"; echo; echo "## Specs"; echo
    echo '- [x] 001 — done — spec-only track — a finished row'
    echo '- [ ] 002 — next — spec-only track — the row after'
  } > "$ROOT/specs/INDEX.md"
  # A manifest that is deliberately WRONG about one CORE file, so --owed is non-empty and the tick
  # gate has something to refuse. Everything else matches, so the arm below fails for one reason.
  {
    printf 'sha=deadbeefcafe\n'
    printf 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  .claude/rules/feature-pipeline.md\n'
  } > "$ROOT/.claude/.template-sync"
  git -C "$ROOT" add -A >/dev/null 2>&1
  git -C "$ROOT" -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1

  if ! git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
    echo "  (skipped: no committable git fixture available)"
  else
    # SC-922 — a tick, made by any means, is reported.
    : > "$ROOT/.claude/.bash-write-marker"; rm -f "$ROOT/.claude/.bash-write-blocked"; sleep 1
    inplace 's/^- \[ \] 002/- [x] 002/' "$ROOT/specs/INDEX.md"
    OUT=$(run_post "$ROOT" "true")
    expect_block "SC-922 a register tick is reported while CORE work is owed" "$OUT"
    case "$OUT" in *"core-owed-tick"*) ok "SC-922 ...and names the tick gate" ;;
                   *) bad "SC-922 reported without naming core-owed-tick" ;; esac

    # SC-921 — the arm that makes the bytes worth passing. Marking a row in progress is what you do
    # ON THE WAY to landing what is owed; a layer that reported it would fire on correct routine work
    # every time, and a report that always fires is a report nobody reads.
    git -C "$ROOT" checkout -q -- specs/INDEX.md
    : > "$ROOT/.claude/.bash-write-marker"; rm -f "$ROOT/.claude/.bash-write-blocked"; sleep 1
    inplace 's/^- \[ \] 002/- [\/] 002/' "$ROOT/specs/INDEX.md"
    OUT=$(run_post "$ROOT" "true")
    expect_silent "SC-921 marking a row in progress stays silent — the added lines carry no tick" "$OUT"

    # SC-923 — no readable diff (untracked file): the guard is still asked, on the path alone, and
    # the report says which of the two verdicts the reader is looking at.
    git -C "$ROOT" checkout -q -- specs/INDEX.md
    : > "$ROOT/.claude/.bash-write-marker"; rm -f "$ROOT/.claude/.bash-write-blocked"; sleep 1
    # An UNTRACKED source file: a guard refuses it, and `git diff` has nothing to say about a file git
    # has never seen — which is exactly the fallback arm.
    printf 'class New {}\n' > "$ROOT/src/New.cs"
    OUT=$(run_post "$ROOT" "true")
    case "$OUT" in *"path alone"*) ok "SC-923 a finding with no readable diff says so, rather than implying the narrow verdict" ;;
                   *) bad "SC-923 no finding carried the path-only note: $(printf '%s' "$OUT" | cut -c1-90)" ;; esac
  fi
fi

# --------------------------------------------------------------- IGNORED OUTPUT (row S6)
#
# `npm run build` is in CLAUDE.md's verification floor, and the post-layer reported its own gitignored
# output as "source files the pipeline guard denies" — every build, because a fresh content hash makes
# every build a new finding set and the escape hatch never engages. A gate that fires on required
# routine work is one the reader learns to wave through.
#
# These fixtures need a REAL git repo: every other fixture here has a plain `.git` DIRECTORY, so
# `git check-ignore` errors there and the filter fails open, which is why they were untouched by S6.
make_git_fixture() {
  local name="$1"
  local root="$WORK/$name"
  mkdir -p "$root/src" "$root/specs" "$root/.claude"
  git -C "$root" init --quiet 2>/dev/null || return 1
  git -C "$root" config user.email t@t; git -C "$root" config user.name t
  : > "$root/package.json"
  {
    echo "# Spec register"; echo; echo "## Specs"; echo
    echo '- [/] 007z — active-spec — full track — IN PROGRESS, no artifacts at all'
  } > "$root/specs/INDEX.md"
  echo "class App {}" > "$root/src/App.cs"
  printf 'dist/\n.vite/\n' > "$root/.gitignore"
  # App.cs must be TRACKED: check-ignore never names a tracked file, and that is the property the
  # whole fix rests on.
  git -C "$root" add -A >/dev/null 2>&1
  git -C "$root" commit -qm init >/dev/null 2>&1 || return 1
  printf '%s' "$root"
}

if want ignored; then
  echo "FIXTURE ignored — build output is not a source edit, and a tracked file is not build output"
  if ! command -v git >/dev/null 2>&1; then
    echo "  ----  git is not installed — skipping (this fixture needs a real repo)"
  elif ! ROOT=$(make_git_fixture ignored); then
    # Not a skip. git exists, so a fixture that will not build is a broken harness, and reporting it
    # as "unavailable" is how an empty result gets read as a clean one.
    bad "SC-927..933 the git fixture could not be built — harness fault, not a pass"
  else
    stamp() { touch "$ROOT/.claude/.bash-write-marker"; rm -f "$ROOT/.claude/.bash-write-blocked"; sleep 1.1; }

    # CONTROL FIRST. An empty result and an uncalled probe look identical; if this one is silent every
    # silence below means nothing (.claude/rules/mutation-timeouts.md, trap 4).
    stamp; echo "class Changed {}" > "$ROOT/src/App.cs"
    expect_block "SC-927 control — a tracked source file is still reported" "$(run_post "$ROOT" 'sed -i s/a/b/ src/App.cs')"

    # The row itself.
    mkdir -p "$ROOT/dist/assets"
    stamp; echo "console.log(1)" > "$ROOT/dist/assets/index-deadbee1.js"
    expect_silent "SC-928 gitignored build output is silent" "$(run_post "$ROOT" 'npm run build')"

    # SC-929 — the measured trap. `--no-index` reports tracked files matching a pattern; plain
    # `--stdin` does not. Asserted on the question itself, because it is what the fix is made of.
    printf '%s\n' "$ROOT/src/App.cs" > "$WORK/ig-probe"
    if git -C "$ROOT" check-ignore --stdin < "$WORK/ig-probe" >/dev/null 2>&1; then
      bad "SC-929 check-ignore named a TRACKED file — the filter would blind the layer to committed source"
    else
      ok "SC-929 a tracked file is never named as ignored"
    fi

    # SC-930 — an ignored directory the prune list never enumerated. This is what "ask git" buys over
    # "add dist to the list".
    mkdir -p "$ROOT/.vite/deps"
    stamp; echo "x" > "$ROOT/.vite/deps/chunk.js"
    expect_silent "SC-930 an ignored dir absent from the prune list is silent too" "$(run_post "$ROOT" 'vite build')"

    # SC-931 — the filter keys on IGNORED, not on untracked.
    stamp; echo "class New {}" > "$ROOT/src/New.cs"
    expect_block "SC-931 a new, untracked, NOT-ignored source file is still reported" "$(run_post "$ROOT" 'cat > src/New.cs')"
    rm -f "$ROOT/src/New.cs"

    # SC-932 — one command doing both.
    stamp
    echo "console.log(2)" > "$ROOT/dist/assets/index-deadbee2.js"
    echo "class Mixed {}" > "$ROOT/src/App.cs"
    MIX=$(run_post "$ROOT" 'npm run build && sed -i s/a/b/ src/App.cs')
    case "$MIX" in
      *"App.cs"*) case "$MIX" in
            *"index-deadbee2.js"*) bad "SC-932 build output is still named alongside the source file" ;;
            *) ok "SC-932 the source file is reported and the build output is not" ;; esac ;;
      *) bad "SC-932 the source file was not reported at all" ;;
    esac

    # SC-933 — the bypass a quieter layer opens. A .gitignore line written in the same command must not
    # buy silence: if the ignore rules moved, they are not trusted for that command.
    stamp
    printf 'hidden/\n' >> "$ROOT/.gitignore"
    mkdir -p "$ROOT/hidden"
    echo "class Hidden {}" > "$ROOT/hidden/H.cs"
    expect_block "SC-933 a path hidden by a .gitignore line changed in the same command is still reported" \
                 "$(run_post "$ROOT" 'echo rule >> .gitignore && cat > hidden/H.cs')"
  fi
fi

# --------------------------------------------------------------- SUMMARY STRING (SC-924)
if want summary; then
  echo "FIXTURE summary — the developer-facing line names no foreign project"
  # This shipped for as long as the file existed: a CORE script opened its terminal summary with a
  # hard-coded project name belonging to somewhere else, in every project the template serves.
  # Grepping the script beats asserting on a rendered message, because the defect is the literal.
  if grep -q 'ConsultPilot' "$POST"; then
    bad "SC-924 the post-layer still carries a foreign project name in its summary"
  else
    ok "SC-924 no foreign project name in the post-layer"
  fi
  if grep -q 'SUMMARY="Pipeline guard:' "$POST"; then
    ok "SC-924 ...and the summary is project-neutral"
  else
    bad "SC-924 the summary line is not the expected neutral text"
  fi
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "PASS — $CHECKS/$CHECKS expectations met"
  exit 0
fi
echo "FAIL — $FAILURES of $CHECKS expectations missed"
exit 1
