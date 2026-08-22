#!/bin/bash
# Test harness for the two new pipeline enforcement hooks:
#   - scripts/pipeline-trigger-match.sh  (UserPromptSubmit anchor matcher)
#   - scripts/pipeline-state-guard-hook.sh  (PreToolUse phase guard)
#
# Run from the repo root:
#   bash scripts/test-pipeline-hooks.sh
#
# Exit 0 if all tests pass, 1 otherwise. Prints per-test PASS/FAIL plus
# section and grand totals.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PASS=0
FAIL=0
FAILED_NAMES=()

# Print a test result and update counters.
_record() {
  local name="$1" ok="$2"
  if [ "$ok" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf '  \033[32mPASS\033[0m  %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name")
    printf '  \033[31mFAIL\033[0m  %s\n' "$name"
  fi
}

# ─── pipeline-trigger-match.sh ────────────────────────────────────────────

trigger_test() {
  local name="$1" expect="$2" subcmd="$3" prompt="$4"
  local rc
  echo "$prompt" | jq -Rs '{prompt: .}' | bash scripts/pipeline-trigger-match.sh "$subcmd"
  rc=$?
  if [ "$rc" -eq "$expect" ]; then _record "$name" 0; else _record "$name (expected $expect, got $rc)" 1; fi
}

echo
echo "── pipeline-trigger-match.sh ──────────────────────────"
echo
echo "true positives (real invocations — expect exit 0):"
trigger_test "bare /speckit.analyze"            0 analyze "/speckit.analyze"
trigger_test "run verb + analyze"               0 analyze "run /speckit.analyze on spec 003"
trigger_test "swedish verb + analyze"           0 analyze "kör /speckit.analyze"
trigger_test "speckit.analyze no slash"         0 analyze "speckit.analyze"
trigger_test "speckit-analyze dash separator"   0 analyze "/speckit-analyze"
trigger_test "bare /clarify"                    0 clarify "/clarify"
trigger_test "/specify with args"               0 specify "/specify build a new feature"
trigger_test "speckit:tasks colon separator"    0 tasks "speckit:tasks"
trigger_test "now /speckit.implement"           0 implement "now /speckit.implement"
trigger_test "pipeline alias on /specify"       0 pipeline "/specify"
trigger_test "pipeline alias on speckit.plan"   0 pipeline "/speckit.plan"

echo
echo "false positives (quoted / pasted — expect exit 1):"
trigger_test "inline code with backticks"       1 analyze 'use the `/speckit.analyze` command later'
trigger_test "markdown blockquote"              1 analyze "> /speckit.analyze was skipped"
trigger_test "pipeline diagram with arrow"      1 specify "/specify → /clarify → /plan"
trigger_test "table cell box-drawing"           1 analyze "│ /speckit.analyze │ helt skippad │"
trigger_test "claude transcript marker"         1 analyze "⏺ /speckit.analyze done"
trigger_test "mid-sentence prose"               1 analyze "or use /speckit.analyze if you prefer"
trigger_test "multiple slash commands on line"  1 specify "/specify and /clarify together"
trigger_test "fenced code block"                1 analyze $'see below:\n```\n/speckit.analyze\n```\nnot really'
trigger_test "word-boundary safety"             1 analyze "/speckit.analyzeFoo"
trigger_test "pipeline alias suppressed"        1 pipeline "we had to use /specify → /clarify → /plan"

# ─── pipeline-state-guard-hook.sh ────────────────────────────────────────

run_guard() {
  local file="$1"
  printf '{"tool_input":{"file_path":"%s"}}' "$file" | bash scripts/pipeline-state-guard-hook.sh
}

# Test fixture: synthetic project with a register that says spec 003 is in-progress
TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/.git" "$TMP/.claude" "$TMP/specs/003-search" "$TMP/src"
echo '{"name":"fake"}' > "$TMP/package.json"
cat > "$TMP/specs/INDEX.md" <<'REG'
# Spec register

## Specs

- [x] 001 — auth — full track — bootstrap login
- [/] 003 — search — full track — fuzzy search bar

## Register history
- 2026-05-15 — initial
REG

guard_test() {
  local name="$1" expect="$2" file="$3"
  # expect: "allow" or "deny" or "deny:<phase>"
  local out rc
  out=$(run_guard "$file" 2>&1)
  rc=$?
  if [ "$expect" = "allow" ]; then
    if [ -z "$out" ]; then _record "$name" 0; else _record "$name (expected no output, got: ${out:0:100})" 1; fi
    return
  fi
  if [ "$expect" = "deny" ]; then
    if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
      _record "$name" 0
    else
      _record "$name (expected deny, got: ${out:0:100})" 1
    fi
    return
  fi
  # deny:<phase> — verify the specific phase appears in Missing phases
  local phase="${expect#deny:}"
  if printf '%s' "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\" and (.hookSpecificOutput.permissionDecisionReason | contains(\"$phase\"))" >/dev/null 2>&1; then
    _record "$name" 0
  else
    _record "$name (expected deny mentioning '$phase', got: ${out:0:150})" 1
  fi
}

echo
echo "── pipeline-state-guard-hook.sh ──────────────────────"
echo

echo "no spec artifacts yet (active spec 003-search, full track):"
guard_test "edit source — deny (all phases missing)"  "deny:specify" "$TMP/src/app.ts"
guard_test "edit spec.md — allow (specs/ allowlist)"  "allow"        "$TMP/specs/003-search/spec.md"
guard_test "edit .claude/x.json — allow"              "allow"        "$TMP/.claude/x.json"
guard_test "edit Dockerfile — allow"                  "allow"        "$TMP/Dockerfile"

echo
echo "with all artifacts present (full track):"
cat > "$TMP/specs/003-search/spec.md" <<'SPEC'
# Spec 003 — search

## Description
Fuzzy search bar.

## Clarifications

### Round 1
- Q: example
SPEC
echo "(allium placeholder)" > "$TMP/specs/003-search/spec.allium"
echo "# plan" > "$TMP/specs/003-search/plan.md"
echo "# tasks" > "$TMP/specs/003-search/tasks.md"
guard_test "edit source — allow (all phases done)"    "allow"   "$TMP/src/app.ts"

echo
echo "remove individual artifacts:"
rm "$TMP/specs/003-search/spec.allium"
guard_test "missing allium → deny (full track)"       "deny:allium_elicit" "$TMP/src/app.ts"
echo "(allium placeholder)" > "$TMP/specs/003-search/spec.allium"
rm "$TMP/specs/003-search/plan.md"
guard_test "missing plan → deny"                      "deny:plan"          "$TMP/src/app.ts"
echo "# plan" > "$TMP/specs/003-search/plan.md"
rm "$TMP/specs/003-search/tasks.md"
guard_test "missing tasks → deny"                     "deny:tasks"         "$TMP/src/app.ts"
echo "# tasks" > "$TMP/specs/003-search/tasks.md"

cat > "$TMP/specs/003-search/spec.md" <<'NOCLAR'
# Spec 003 — search
(no clarifications section)
NOCLAR
guard_test "missing clarify section → deny"           "deny:clarify"       "$TMP/src/app.ts"

echo
echo "track variations:"
cat > "$TMP/specs/003-search/spec.md" <<'SPEC2'
# Spec 003
## Clarifications
- Q: example
SPEC2

# light track: still needs allium
sed -i.bak 's|full track|light track|' "$TMP/specs/INDEX.md"
rm -f "$TMP/specs/003-search/spec.allium"
guard_test "light track without allium → deny"        "deny:allium_elicit" "$TMP/src/app.ts"

# spec-only track: allium not required
sed -i.bak 's|light track|spec-only track|' "$TMP/specs/INDEX.md"
guard_test "spec-only without allium → allow"         "allow"              "$TMP/src/app.ts"

# restore to full for next checks
sed -i.bak 's|spec-only track|full track|' "$TMP/specs/INDEX.md"
echo "(allium placeholder)" > "$TMP/specs/003-search/spec.allium"

echo
echo "environment edge cases:"
# Marker-less repo (template / scratch) — silent allow even with no register
TMP2=$(mktemp -d)
mkdir -p "$TMP2/.git" "$TMP2/src"
guard_test "marker-less repo → allow (silent)"        "allow"              "$TMP2/src/x.ts"
rm -rf "$TMP2"

# Non-source extension — bypass regardless of pipeline state
TMP3=$(mktemp -d)
mkdir -p "$TMP3/.git" "$TMP3/specs/003-search"
echo '{"name":"x"}' > "$TMP3/package.json"
cat > "$TMP3/specs/INDEX.md" <<'REG3'
## Specs
- [/] 003 — search — full track — goal
REG3
guard_test "edit .json file in marker repo → allow"   "allow"              "$TMP3/data/config.json"
rm -rf "$TMP3"

echo
echo "lane ownership (SPEC_OWNER + trailing @owner tags):"
# Two developers share one register. The lane a machine is in decides which row the guards
# resolve as "active". The register below is deliberately ordered so that the WRONG answer is
# visible: 005 is unowned and sits ABOVE david's 007, so a lane that merely filters (instead of
# preferring its own row) would point david at 005 — which on a dependency-ordered register is
# the row blocked behind johan's current spec.
TMP4=$(mktemp -d)
mkdir -p "$TMP4/.git" "$TMP4/specs/003-search" "$TMP4/src"
echo '{"name":"x"}' > "$TMP4/package.json"
cat > "$TMP4/specs/INDEX.md" <<'REG4'
# Spec register

## Specs

- [/] 003 — search — full track — needs 001 — fuzzy search bar — @johan
- [ ] 005 — shared — full track — unowned row, higher up
- [ ] 007 — mfa — full track — needs 001 — second lane's row — @david
REG4
# Two of the three rows carry a "needs" field (see scripts/next-rows.sh). It sits between the
# track and the goal, so a guard that reads the track as "the third em-dash field" keeps
# working and one that reads it as "everything after the slug" does not. The rows without the
# field are there on purpose: both shapes have to parse in the same register.
cat > "$TMP4/specs/003-search/spec.md" <<'SPEC4'
# Spec 003
## Clarifications
- Q: example
SPEC4
echo "(allium placeholder)" > "$TMP4/specs/003-search/spec.allium"
echo "# plan"  > "$TMP4/specs/003-search/plan.md"
echo "# tasks" > "$TMP4/specs/003-search/tasks.md"

lane_test() {
  local name="$1" lane="$2" expect="$3"
  local out
  out=$(printf '{"tool_input":{"file_path":"%s"}}' "$TMP4/src/app.ts" \
        | SPEC_OWNER="$lane" bash scripts/pipeline-state-guard-hook.sh 2>&1)
  if [ "$expect" = "allow" ]; then
    if [ -z "$out" ]; then _record "$name" 0; else _record "$name (expected allow, got: ${out:0:100})" 1; fi
    return
  fi
  if printf '%s' "$out" | jq -e ".hookSpecificOutput.permissionDecisionReason | contains(\"$expect\")" >/dev/null 2>&1; then
    _record "$name" 0
  else
    _record "$name (expected deny naming '$expect', got: ${out:0:150})" 1
  fi
}

lane_test "no lane → first row (003, complete) → allow"        ""       "allow"
lane_test "lane johan → own in-progress 003 → allow"           "johan"  "allow"
lane_test "lane david → own row 007, not unowned 005 → deny"   "david"  "007"
lane_test "unknown lane → first unowned row 005 → deny"        "patrik" "005"
rm -rf "$TMP4"

# ─── spec-interview-guard-hook.sh ────────────────────────────────────────

echo
echo "── spec-interview-guard-hook.sh ──────────────────────"
echo

# Fresh fixture: marker repo, register with in-progress spec 003, no interview yet.
IVT=$(mktemp -d)
mkdir -p "$IVT/.git" "$IVT/specs/003-search" "$IVT/src"
echo '{"name":"iv"}' > "$IVT/package.json"
cat > "$IVT/specs/INDEX.md" <<'IVREG'
# Spec register
## Specs
- [/] 003 — search — full track — fuzzy search
IVREG

# Write N answers of a given marker ("**A:**" human or "**A (auto):**" auto) to interview.md
write_interview() {
  local n_auto="$1" n_human="$2"
  { echo "# Spec interview — 003-search"; echo
    local i=1
    while [ "$i" -le "$n_auto" ]; do printf '## Q%s\n**Q:** q\n**A (auto):** recommended answer here\n\n' "$i"; i=$((i+1)); done
    while [ "$i" -le $((n_auto + n_human)) ]; do printf '## Q%s\n**Q:** q\n**A:** the human answer here\n\n' "$i"; i=$((i+1)); done
  } > "$IVT/specs/003-search/interview.md"
}

iv_guard() {
  # $1 = mode ("" for default auto, "manual"), $2 = file
  local mode="$1" file="$2"
  if [ -n "$mode" ]; then
    printf '{"tool_input":{"file_path":"%s"}}' "$file" | SPEC_INTERVIEW_MODE="$mode" bash scripts/spec-interview-guard-hook.sh
  else
    printf '{"tool_input":{"file_path":"%s"}}' "$file" | bash scripts/spec-interview-guard-hook.sh
  fi
}

iv_test() {
  local name="$1" expect="$2" mode="$3"
  local out
  out=$(iv_guard "$mode" "$IVT/src/app.ts" 2>&1)
  if [ "$expect" = "allow" ]; then
    if [ -z "$out" ]; then _record "$name" 0; else _record "$name (expected allow, got: ${out:0:80})" 1; fi
  else
    if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
      _record "$name" 0
    else
      _record "$name (expected deny, got: ${out:0:80})" 1
    fi
  fi
}

echo "no interview.md yet:"
iv_test "no interview → deny (auto default)"          "deny"  ""

echo
echo "AUTO mode (default — counts human + auto):"
write_interview 15 0
iv_test "15 auto answers → allow"                     "allow" ""
write_interview 14 0
iv_test "14 auto answers → deny (below floor)"        "deny"  ""
write_interview 8 7
iv_test "8 auto + 7 human = 15 → allow"               "allow" ""

echo
echo "MANUAL mode (SPEC_INTERVIEW_MODE=manual — counts only human):"
write_interview 15 0
iv_test "15 auto, manual mode → deny"                 "deny"  "manual"
write_interview 8 7
iv_test "8 auto + 7 human, manual mode → deny (7<15)" "deny"  "manual"
write_interview 0 15
iv_test "15 human, manual mode → allow"               "allow" "manual"

echo
echo "scope + environment (interview guard):"
_iv_scope() {
  local name="$1" expect="$2" file="$3"
  local out; out=$(iv_guard "" "$file" 2>&1)
  if [ "$expect" = "allow" ]; then
    if [ -z "$out" ]; then _record "$name" 0; else _record "$name (expected allow, got: ${out:0:80})" 1; fi
  else
    if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then _record "$name" 0; else _record "$name (expected deny)" 1; fi
  fi
}
write_interview 0 0   # empty interview so a source edit WOULD deny — proves allowlist bypasses it
_iv_scope "edit specs/ file → allow (allowlist)"      "allow" "$IVT/specs/003-search/spec.md"
_iv_scope "edit .claude/ file → allow (allowlist)"    "allow" "$IVT/.claude/x.json"
_iv_scope "edit README.md → allow (allowlist)"        "allow" "$IVT/README.md"
_iv_scope "edit data.json → allow (non-source ext)"   "allow" "$IVT/src/data.json"
_iv_scope "edit app.ts, empty interview → deny"       "deny"  "$IVT/src/app.ts"

# Marker-less repo → silent allow even with no interview
IVT2=$(mktemp -d); mkdir -p "$IVT2/.git" "$IVT2/src"
_iv_scope "marker-less repo → allow (silent)"         "allow" "$IVT2/src/x.ts"
rm -rf "$IVT2"

rm -rf "$IVT"

# ─── loop breakers, attempt limit, run log, quiet mode ────────────────────
#
# The four mechanisms added after the loop-engineering review. Together they are
# the "iteration limit + failure memory + attention mode" layer: a Stop hook that
# cannot re-block forever, an attempt counter that makes CLAUDE.md's 3-attempt cap
# real, a per-spec run log that survives /clear, and a SessionStart advisory that
# shuts up when nothing is wrong.

echo
echo "── loop breakers (stop_hook_active) ───────────────────"
echo

_stop_active() {
  local name="$1" script="$2" rc
  echo '{"stop_hook_active":true,"transcript_path":"/nonexistent"}' | bash "scripts/$script" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then _record "$name" 0; else _record "$name (expected 0, got $rc)" 1; fi
}
_stop_active "continuous-execution: re-entry → allow stop" continuous-execution-hook.sh
_stop_active "stop-validation: re-entry → allow stop"      stop-validation-hook.sh

echo
echo "── repeat-failure-guard-hook.sh ───────────────────────"
echo

RFT=$(mktemp -d); mkdir -p "$RFT/.git"
_rf() {  # $1 name, $2 expect(fire|quiet), $3 cmd, $4 output
  local out rc=0
  out=$(printf '{"tool_input":{"command":%s},"tool_response":{"stdout":%s}}' \
        "$(printf '%s' "$3" | jq -Rs .)" "$(printf '%s' "$4" | jq -Rs .)" \
        | CLAUDE_PROJECT_DIR="$RFT" bash scripts/repeat-failure-guard-hook.sh 2>/dev/null)
  case "$2" in
    fire)  [ -n "$out" ] || rc=1 ;;
    quiet) [ -z "$out" ] || rc=1 ;;
  esac
  _record "$1" "$rc"
}
FAILOUT="Build FAILED
  error CS1002: ; expected"
_rf "1st failure → quiet"                   quiet "dotnet test" "$FAILOUT"
_rf "2nd failure → quiet"                   quiet "dotnet test" "$FAILOUT"
_rf "3rd identical failure → fires"         fire  "dotnet test" "$FAILOUT"
_rf "non-verification cmd never counted"    quiet "git status"  "$FAILOUT"
printf '{"tool_input":{"command":"dotnet test"},"tool_response":{"stdout":"Passed!  - Failed: 0, Passed: 12"}}' \
  | CLAUDE_PROJECT_DIR="$RFT" bash scripts/repeat-failure-guard-hook.sh >/dev/null 2>&1
_rf "success resets the counter"            quiet "dotnet test" "$FAILOUT"
# ── H6s: three states, not two ────────────────────────────────────────────
#
# The five assertions above can only see whether the hook PRINTED. Both defects
# H6s fixes are invisible to that: they are about what happens to the COUNTER on
# a run the hook does not recognize. So these cases assert on the state file.
#
# Measured against the pre-H6s build (specs/H6s-.../research.md R-1, R-2):
#   - a 5-run spiral of unrecognized failures wrote ZERO state files;
#   - one unparseable payload erased a counter of 2 and silenced the 3rd failure.
# Both are red cases per H5b — they were observed failing before the fix existed.

_rf_reset() { rm -rf "$RFT/.claude/state/attempts" 2>/dev/null; }
_rf_send() {  # $1 raw payload json → echoes hook stdout
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$RFT" bash scripts/repeat-failure-guard-hook.sh 2>/dev/null
}
_rf_out() {   # $1 cmd, $2 stdout → payload json
  printf '{"tool_input":{"command":%s},"tool_response":{"stdout":%s}}' \
    "$(printf '%s' "$1" | jq -Rs .)" "$(printf '%s' "$2" | jq -Rs .)"
}
# Two counters now live side by side: the failure count ("<fp>") and the
# unclassified streak ("<fp>.unknown"). Reading them together would hide exactly
# the distinction H6s exists to make, so they are read separately.
_rf_count() {
  local f
  for f in "$RFT/.claude/state/attempts"/*; do
    case "$f" in *.unknown) continue ;; esac
    [ -f "$f" ] && cat "$f"
  done 2>/dev/null | tr -dc '0-9'
}
_rf_ucount() { cat "$RFT/.claude/state/attempts"/*.unknown 2>/dev/null | tr -dc '0-9'; }
_rf_expect() {  # $1 name, $2 expected failure counter ('' = no state file)
  local got; got=$(_rf_count)
  if [ "$got" = "$2" ]; then _record "$1" 0
  else _record "$1 (expected counter '$2', got '${got:-<none>}')" 1; fi
}
_rf_uexpect() {  # $1 name, $2 expected unclassified streak ('' = no state file)
  local got; got=$(_rf_ucount)
  if [ "$got" = "$2" ]; then _record "$1" 0
  else _record "$1 (expected streak '$2', got '${got:-<none>}')" 1; fi
}

# A real failure that matches NEITHER 'Exit code: [1-9]' NOR any FAIL_RE pattern.
NOVEL='Determining projects to restore...
/usr/share/dotnet/sdk/10.0.100/NuGet.targets(174,5): Unable to load the service index for source https://api.nuget.org/v3/index.json.
  Response status code does not indicate success: 503 (Service Unavailable).'

_rf_reset
_rf_send "$(_rf_out 'dotnet test' "$NOVEL")" >/dev/null
_rf_uexpect "unrecognized run #1 counts on the unclassified streak"  "1"
_rf_expect  "unrecognized run #1 does NOT touch the failure counter" ""
_rf_send "$(_rf_out 'dotnet test' "$NOVEL")" >/dev/null
_rf_uexpect "unrecognized run #2 counts"                             "2"
OUT3=$(_rf_send "$(_rf_out 'dotnet test' "$NOVEL")")
[ -n "$OUT3" ] && _record "unclassified spiral fires on the 3rd" 0 \
                || _record "unclassified spiral fires on the 3rd" 1
case "$OUT3" in
  *UNCLASSIFIED*) _record "unclassified nudge does not assert a failure" 0 ;;
  *)              _record "unclassified nudge does not assert a failure" 1 ;;
esac
# A classified outcome ends the streak — otherwise one stale unknown run would
# keep nudging forever on a command that has since started answering clearly.
_rf_send "$(_rf_out 'dotnet test' "$FAILOUT")" >/dev/null
_rf_uexpect "a recognized failure clears the unclassified streak"    ""
_rf_expect  "…and starts the failure counter at 1"                   "1"

# An unparseable payload must not erase what the hook already knew.
_rf_reset
_rf_send "$(_rf_out 'dotnet test' "$FAILOUT")" >/dev/null
_rf_send "$(_rf_out 'dotnet test' "$FAILOUT")" >/dev/null
_rf_expect "two recognized failures → counter 2"                     "2"
UNREADABLE='{"tool_input":{"command":"dotnet test"},"tool_response":"<truncated>"}'
UOUT=$(_rf_send "$UNREADABLE")
_rf_expect "unparseable payload leaves the counter untouched"        "2"
[ -z "$UOUT" ] && _record "unparseable payload stays silent" 0 \
               || _record "unparseable payload stays silent" 1
OUT3=$(_rf_send "$(_rf_out 'dotnet test' "$FAILOUT")")
[ -n "$OUT3" ] && _record "3rd real failure still fires after it" 0 \
                || _record "3rd real failure still fires after it" 1

# Failure wins when both signature sets match the same output.
_rf_reset
MIXED='Build succeeded.
    0 Error(s)
Failed!  - Failed:     3, Passed:    41, Skipped:     0'
_rf_send "$(_rf_out 'dotnet test' "$MIXED")" >/dev/null
_rf_expect "build-ok + tests-failed counts as failure"               "1"

# A tool that says nothing when it passes (tsc --noEmit, eslint, dotnet format).
_rf_reset
_rf_send "$(_rf_out 'npx tsc --noEmit' "$FAILOUT")" >/dev/null
_rf_send "$(_rf_out 'npx tsc --noEmit' "$FAILOUT")" >/dev/null
_rf_send "$(_rf_out 'npx tsc --noEmit' '')" >/dev/null
_rf_expect "silent success (readable, empty output) resets"          ""

# A non-.NET success signature must reset too — the tracked command set is eight
# stacks wide, so a .NET-only positive set would leave those counters stale.
_rf_reset
_rf_send "$(_rf_out 'npm test' "$FAILOUT")" >/dev/null
_rf_send "$(_rf_out 'npm test' 'Tests:       12 passed, 12 total')" >/dev/null
_rf_expect "jest success signature resets"                           ""

# An interrupted run proved nothing — it must not reset.
_rf_reset
_rf_send "$(_rf_out 'dotnet test' "$FAILOUT")" >/dev/null
_rf_send "$(_rf_out 'dotnet test' "$FAILOUT")" >/dev/null
_rf_send '{"tool_input":{"command":"dotnet test"},"tool_response":{"stdout":"","interrupted":true}}' >/dev/null
_rf_expect "interrupted run leaves the counter untouched"            "2"

# A false SUCCESS is the expensive direction: it resets a real spiral. pytest's
# summary line contains "41 passed in 1.20s", which the positive set matches —
# only failure-first ordering (FR-005/FR-011) stops it being read as a pass.
#
# Note the assertion shape: it seeds the counter with a recognized failure FIRST,
# so the three verdicts are distinguishable. Asserting "counter is 1" from an
# empty state cannot tell PASSED (reset) from UNKNOWN (untouched) — both leave no
# file — and would have passed vacuously while the bug was live.
_rf_mixed() {  # $1 name, $2 cmd, $3 output — expects FAILED (counter 1 → 2)
  _rf_reset
  _rf_send "$(_rf_out "$2" "$FAILOUT")" >/dev/null
  _rf_send "$(_rf_out "$2" "$3")" >/dev/null
  _rf_expect "$1" "2"
}
_rf_mixed "pytest mixed result counts as failure, not success" \
          'pytest -q' '3 failed, 41 passed in 1.20s'
_rf_mixed "cargo mixed result counts as failure, not success" \
          'cargo test' 'test result: FAILED. 2 passed; 1 failed; 0 ignored'

# A readable object that carries none of the four output fields tells us nothing.
_rf_reset
_rf_send "$(_rf_out 'dotnet test' "$FAILOUT")" >/dev/null
_rf_send '{"tool_input":{"command":"dotnet test"},"tool_response":{"isImage":false}}' >/dev/null
_rf_expect "object with no output fields → counter untouched"        "1"

# Every stack the command matcher tracks needs a success signature, or that
# stack's counter never resets (FR-010).
_rf_stack() {  # $1 label, $2 cmd, $3 success output
  _rf_reset
  _rf_send "$(_rf_out "$2" "$FAILOUT")" >/dev/null
  _rf_send "$(_rf_out "$2" "$3")" >/dev/null
  _rf_expect "$1 success signature resets" ""
}
_rf_stack "pytest"  "pytest"         "41 passed in 1.20s"
_rf_stack "cargo"   "cargo test"     "test result: ok. 41 passed; 0 failed; 0 ignored"
_rf_stack "go"      "go test ./..."  "ok  	github.com/x/y	0.512s"
_rf_stack "flutter" "flutter test"   "All tests passed!"
_rf_stack "ruff"    "ruff check ."   "All checks passed!"
_rf_stack "gradle"  "gradlew test"   "BUILD SUCCESSFUL in 3s"

# The TTL prune must reach the streak file too — otherwise yesterday's
# unclassified run keeps nudging today (FR-021).
_rf_reset
_rf_send "$(_rf_out 'dotnet test' "$NOVEL")" >/dev/null
_rf_uexpect "streak written before the prune check"                  "1"
find "$RFT/.claude/state/attempts" -name '*.unknown' -exec touch -t 200001010000 {} \; 2>/dev/null
ATTEMPT_TTL=1 _rf_send "$(_rf_out 'npm test' "$FAILOUT")" >/dev/null
_rf_uexpect "TTL prunes the unclassified streak file"                ""

# The hook never blocks, on any of the three paths.
RCS=""
for p in "$(_rf_out 'dotnet test' "$FAILOUT")" "$(_rf_out 'dotnet test' "$NOVEL")" "$UNREADABLE"; do
  printf '%s' "$p" | CLAUDE_PROJECT_DIR="$RFT" bash scripts/repeat-failure-guard-hook.sh >/dev/null 2>&1
  RCS="$RCS$?"
done
[ "$RCS" = "000" ] && _record "exits 0 on failed / unknown / unreadable" 0 \
                   || _record "exits 0 on failed / unknown / unreadable (got $RCS)" 1

rm -rf "$RFT"

echo
echo "── spec-run-log-hook.sh ───────────────────────────────"
echo

RLT=$(mktemp -d); mkdir -p "$RLT/.git" "$RLT/specs/002-search" "$RLT/src"
# --note resolves the active spec from the register, so the register must exist.
printf '# R\n\n## Specs\n\n- [/] 002 — search — full track — free-text search\n' > "$RLT/specs/INDEX.md"
_rl_write() { echo "{\"tool_input\":{\"file_path\":\"$1\"}}" | bash scripts/spec-run-log-hook.sh >/dev/null 2>&1; }
_rl_write "$RLT/specs/002-search/plan.md"
_rl_write "$RLT/specs/002-search/plan.md"     # dedupe against previous line
_rl_write "$RLT/src/app.ts"                   # not a pipeline artifact → ignored
LOG="$RLT/specs/002-search/run-log.md"
[ -f "$LOG" ] && [ "$(grep -cE '^- ' "$LOG")" -eq 1 ] \
  && _record "logs one line per phase, deduped" 0 || _record "logs one line per phase, deduped" 1
CLAUDE_PROJECT_DIR="$RLT" bash scripts/spec-run-log-hook.sh --note "mutation gate FAILED 41%" >/dev/null 2>&1
grep -q 'mutation gate FAILED' "$LOG" 2>/dev/null \
  && _record "--note writes to the active spec" 0 || _record "--note writes to the active spec" 1
rm -rf "$RLT"

# ── --note tells the caller WHICH outcome it got (H6s2) ──────────────────────
#
# The assertion above ("writes to the active spec") can only see a write that
# happened. Every way of NOT writing looked the same from outside: exit 0, no
# output. That is how the resolver-lookup defect it catches survived — in the one
# script whose entire job is failure memory across /clear, a lost line was
# indistinguishable from a logged one.
#
# So these assert on the exit code AND the stderr text, never on "nothing was
# written": the untouched build also writes nothing, so an absence-of-write
# assertion passes against the bug (the H6c/H6m vacuous-assertion trap).
#
# Exit grammar is the resolver's own (spec_active.py): 0 resolved · 3 an ANSWER,
# nothing to log · 4 cannot answer.
RLN=$(mktemp -d); mkdir -p "$RLN/.git" "$RLN/specs/002-search" "$RLN/bin"
printf '# R\n\n## Specs\n\n- [/] 002 — search — full track — free-text search\n' > "$RLN/specs/INDEX.md"
# A copy of the hook with NO resolver beside it — the state a project is in when
# an autosync is cut short (the .py pass runs after every .sh) or when python3 is
# absent. The hook must say so, not go quiet.
cp scripts/spec-run-log-hook.sh "$RLN/bin/spec-run-log-hook.sh"

# $1 name, $2 expected rc, $3 stderr must contain ("" = must be silent), $4.. = argv
_rl_note() {
  local name="$1" want_rc="$2" want_err="$3"; shift 3
  local err rc=0
  err=$(CLAUDE_PROJECT_DIR="$RLN" bash "$RLN/bin/spec-run-log-hook.sh" "$@" 2>&1 >/dev/null) || rc=$?
  if [ "$rc" != "$want_rc" ]; then
    _record "$name (expected exit $want_rc, got $rc)" 1; return
  fi
  if [ -z "$want_err" ]; then
    [ -z "$err" ] && _record "$name" 0 || _record "$name (expected silence, got: ${err:0:80})" 1
    return
  fi
  case "$err" in
    *"$want_err"*) _record "$name" 0 ;;
    *) _record "$name (stderr did not name '$want_err', got: ${err:0:100})" 1 ;;
  esac
}

_rl_note "--note without a reachable resolver exits 4, not 0"  4 "resolve-active-spec.sh" --note "unreachable resolver"
_rl_note "--note names the missing resolver on stderr"         4 "cannot resolve"         --note "unreachable resolver"
_rl_note "--spec pointing at no directory exits 4 and says so" 4 "$RLN/nope"              --note "bad spec dir" --spec "$RLN/nope"

# Every row ticked is an ANSWER, not a failure: exit 3, and still say it out loud
# so a note that was never recorded cannot pass for one that was.
printf '# R\n\n## Specs\n\n- [x] 002 — search — full track — free-text search\n' > "$RLN/specs/INDEX.md"
cp scripts/resolve-active-spec.sh scripts/spec_active.py "$RLN/bin/"
_rl_note "fully-ticked register → exit 3, not 4, and reports"  3 "no active spec"         --note "nothing active"

# ...and with the resolver reachable beside the hook, the happy path is silent
# and 0. This is the assertion that keeps the three outcomes distinguishable:
# without it, "always exit 4" would satisfy every test above.
printf '# R\n\n## Specs\n\n- [/] 002 — search — full track — free-text search\n' > "$RLN/specs/INDEX.md"
_rl_note "resolver beside the hook → writes, silent, exit 0"   0 ""                       --note "H6s2 happy path"
grep -q 'H6s2 happy path' "$RLN/specs/002-search/run-log.md" 2>/dev/null \
  && _record "--note resolves the hook's OWN sibling, not the project's" 0 \
  || _record "--note resolves the hook's OWN sibling, not the project's" 1

# append_line answers a failed write with `return 0` on all three of its write
# paths (header, append, cap rewrite). A read-only spec dir therefore used to
# produce the same observable as a successful log: exit 0, no output. Same shape
# as everything else in this block, on the one path the resolver never reaches.
mkdir -p "$RLN/specs/003-readonly"
chmod 555 "$RLN/specs/003-readonly"
_rl_note "a write that failed is reported, not swallowed" 4 "could not write" \
         --note "into a read-only dir" --spec "$RLN/specs/003-readonly"
chmod 755 "$RLN/specs/003-readonly"
rm -rf "$RLN"

echo
echo "── spec-register-orientation quiet/attention mode ─────"
echo

QOT=$(mktemp -d); mkdir -p "$QOT/.git" "$QOT/specs"; : > "$QOT/package.json"
_orient_lines() { (cd "$QOT" && bash "$ROOT/scripts/spec-register-orientation-hook.sh" | jq -r '.systemMessage // ""' | grep -c .); }
printf '# R\n\n## Specs\n\n- [x] 001 — a — light track — x\n- [ ] 002 — b — light track — y\n' > "$QOT/specs/INDEX.md"
[ "$(_orient_lines)" -eq 1 ] && _record "nothing actionable → one-line quiet mode" 0 \
                             || _record "nothing actionable → one-line quiet mode" 1
printf '# R\n\n## Specs\n\n- [x] 001 — a — light track — x\n- [ ] 002 — b — full track — y\n' > "$QOT/specs/INDEX.md"
[ "$(_orient_lines)" -gt 3 ] && _record "full-track next row → attention mode" 0 \
                             || _record "full-track next row → attention mode" 1

# The run-log tail is the whole point of the run log: five lines of failure memory
# handed to a session that has just been cleared. It is fetched through the same
# resolver, and used to be looked up under the INSPECTED project's scripts/ rather
# than beside this hook (H6s2) — so in any project whose scripts/ does not carry
# the resolver, the tail silently did not appear and --sync-feature-json silently
# did not run, leaving spec-kit's feature.json pointing at the previous spec:
# exactly the defect 007m existed to kill, reintroduced through the lookup path.
mkdir -p "$QOT/specs/004-tail"
printf '# R\n\n## Specs\n\n- [/] 004 — tail — full track — y\n' > "$QOT/specs/INDEX.md"
printf '# Run log\n\n- 2026-01-01T00:00Z · mutation gate FAILED at 41%%\n' > "$QOT/specs/004-tail/run-log.md"
(cd "$QOT" && bash "$ROOT/scripts/spec-register-orientation-hook.sh" | jq -r '.systemMessage // ""') \
  | grep -q 'mutation gate FAILED' \
  && _record "in-progress row → run-log tail is surfaced" 0 \
  || _record "in-progress row → run-log tail is surfaced" 1
rm -rf "$QOT"

echo
echo "── stack-marker-canary-hook.sh ────────────────────────"
echo

# $1 name, $2 expect(warn|silent), $3 marker value ("" = no marker file), $4.. = setup fn
_canary() {
  local name="$1" expect="$2" marker="$3" rc=0 out
  [ -n "$marker" ] && printf 'testing=%s\n' "$marker" > "$CT/.claude/.sync-stack" || rm -f "$CT/.claude/.sync-stack"
  out=$(CLAUDE_PROJECT_DIR="$CT" bash scripts/stack-marker-canary-hook.sh 2>/dev/null)
  case "$expect" in
    warn)   [ -n "$out" ] || rc=1 ;;
    silent) [ -z "$out" ] || rc=1 ;;
  esac
  _record "$name" "$rc"
}

# web project (vite + playwright, nested client dir like puck's web/)
CT=$(mktemp -d); mkdir -p "$CT/.git" "$CT/.claude" "$CT/web"
echo '{"devDependencies":{"vite":"5","@playwright/test":"1"}}' > "$CT/web/package.json"
_canary "web project marked mobile → warns"        warn   mobile
_canary "web project marked web → silent"          silent web
_canary "web project, no marker → warns"           warn   ""
_canary "hybrid marker on one-sided repo → silent" silent hybrid
rm -rf "$CT"

# Expo project
CT=$(mktemp -d); mkdir -p "$CT/.git" "$CT/.claude"
echo '{"dependencies":{"expo":"51","react-native":"0.74"}}' > "$CT/package.json"
_canary "expo project marked web → warns"          warn   web
_canary "expo project marked mobile → silent"      silent mobile
rm -rf "$CT"

# .NET backend + Expo client → hybrid
CT=$(mktemp -d); mkdir -p "$CT/.git" "$CT/.claude" "$CT/api" "$CT/mobile"
touch "$CT/api/Api.csproj"; echo '{"dependencies":{"expo":"51"}}' > "$CT/mobile/package.json"
_canary "dotnet + expo marked mobile → warns"      warn   mobile
_canary "dotnet + expo marked hybrid → silent"     silent hybrid
rm -rf "$CT"

# react-native-web is a WEB dependency — must not read as a native client
CT=$(mktemp -d); mkdir -p "$CT/.git" "$CT/.claude"
echo '{"dependencies":{"react-native-web":"0.19","vite":"5"}}' > "$CT/package.json"
_canary "react-native-web ≠ native (no false positive)" silent web
rm -rf "$CT"

# nothing recognizable (template/scratch repo) → never speaks
CT=$(mktemp -d); mkdir -p "$CT/.git" "$CT/.claude"
_canary "unrecognizable stack → silent"            silent ""
rm -rf "$CT"

echo
echo "── detect-stack.sh + prune-dangling-hooks.py ──────────"
echo

_detect() {  # $1 name, $2 expected, $3 setup dir
  local got; got=$(bash scripts/detect-stack.sh "$3" 2>/dev/null | sed -n '1p')
  [ "$got" = "$2" ] && _record "$1" 0 || _record "$1 (expected '$2', got '${got:-<empty>}')" 1
}
DT=$(mktemp -d); touch "$DT/App.csproj";                                   _detect "detect: csproj → web"        web    "$DT"
DT2=$(mktemp -d); echo '{"dependencies":{"expo":"51"}}' > "$DT2/package.json"; _detect "detect: expo → mobile"    mobile "$DT2"
DT3=$(mktemp -d); mkdir -p "$DT3/api" "$DT3/app"; touch "$DT3/api/A.csproj"
echo '{"dependencies":{"expo":"51"}}' > "$DT3/app/package.json";            _detect "detect: csproj+expo → hybrid" hybrid "$DT3"
DT4=$(mktemp -d);                                                          _detect "detect: empty dir → nothing" ""     "$DT4"
DT5=$(mktemp -d); printf 'name: x\ndependencies:\n  flutter:\n    sdk: flutter\n' > "$DT5/pubspec.yaml"
_detect "detect: flutter sdk → mobile" mobile "$DT5"
rm -rf "$DT" "$DT2" "$DT3" "$DT4" "$DT5"

# prune-dangling-hooks: a hook pointing at a missing script is a silent no-op
PD=$(mktemp -d); mkdir -p "$PD/.claude" "$PD/scripts"
cat > "$PD/scripts/present.sh" <<'SH'
#!/bin/bash
exit 0
SH
cat > "$PD/.claude/settings.json" <<'JSON'
{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/scripts/present.sh\""},
  {"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/scripts/absent.sh\""},
  {"type":"command","command":"echo inline-hook-no-script"}
]}]}}
JSON
(cd "$PD" && python3 "$ROOT/scripts/prune-dangling-hooks.py" >/dev/null 2>&1)
LEFT=$(grep -c 'scripts/' "$PD/.claude/settings.json")
INLINE=$(grep -c 'inline-hook-no-script' "$PD/.claude/settings.json")
[ "$LEFT" -eq 1 ] && _record "prune: removes the hook with the missing script" 0 \
                  || _record "prune: removes the hook with the missing script (script refs left: $LEFT)" 1
[ "$INLINE" -eq 1 ] && _record "prune: keeps inline hooks (no script reference)" 0 \
                    || _record "prune: keeps inline hooks (no script reference)" 1
python3 -m json.tool "$PD/.claude/settings.json" >/dev/null 2>&1 \
  && _record "prune: leaves valid JSON" 0 || _record "prune: leaves valid JSON" 1
rm -rf "$PD"

# ─── template-autosync-hook.sh (H6t) ──────────────────────────────────────
#
# The hook has to tell three outcomes apart: a sync that completed, a sync that
# was killed at its bound, and a sync that failed for some other reason. Before
# H6t all three exited 0 in silence, and the rate-limit marker was written
# *before* the sync ran — so a sync that always timed out bought itself six
# hours of suppression and template updates simply stopped arriving.
#
# The red cases below were observed failing against the untreated hook before
# the fix was written (H5b): the forced timeout was silent, and the marker was
# left holding the normal window.

echo
# Covers: SC-1298 SC-1299 SC-1300 SC-1301 SC-1302 SC-1303 SC-1304 SC-1305 SC-1306
#         SC-1307 SC-1308 SC-1309 SC-1310 SC-1311 SC-1312 SC-1313 SC-1314
echo "── template-autosync-hook.sh (H6t) ────────────────────"
echo

# A throwaway project: real .git, a .claude dir, a non-template origin, and a
# stub sync whose body the caller chooses. Echoes the sandbox path.
autosync_sandbox() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/scripts"
  git -C "$d" init -q .
  git -C "$d" remote add origin https://example.invalid/someone/other.git
  cp "$ROOT/scripts/template-autosync-hook.sh" "$d/scripts/"
  { echo '#!/bin/bash'
    echo 'echo run >> "$(dirname "$0")/../.sync-runs"'
    printf '%s\n' "$1"
  } > "$d/scripts/template-autosync.sh"
  chmod +x "$d/scripts/template-autosync.sh"
  printf '%s' "$d"
}

# How many times the stub sync actually started in this sandbox.
autosync_runs() {
  if [ -f "$1/.sync-runs" ]; then wc -l < "$1/.sync-runs" | tr -d ' '; else echo 0; fi
}

# The marker's kind — "absent", "empty" (legacy), or its recorded word.
autosync_marker() {
  if [ ! -f "$1/.claude/.template-sync-check" ]; then echo absent; return; fi
  local k
  k=$(head -1 "$1/.claude/.template-sync-check" 2>/dev/null | tr -d ' \t')
  if [ -n "$k" ]; then echo "$k"; else echo empty; fi
}

# Run the hook in a sandbox. Extra args are VAR=value env assignments.
autosync_hook() {
  local d="$1"; shift
  ( cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" bash "$d/scripts/template-autosync-hook.sh" )
}

_expect() {   # name, expected, actual
  if [ "$2" = "$3" ]; then _record "$1" 0; else _record "$1 (expected $2, got $3)" 1; fi
}
_expect_has() {   # name, needle, haystack
  case "$3" in *"$2"*) _record "$1" 0 ;; *) _record "$1 (missing '$2')" 1 ;; esac
}
_expect_lacks() {   # name, needle, haystack
  case "$3" in *"$2"*) _record "$1 (unexpectedly contains '$2')" 1 ;; *) _record "$1" 0 ;; esac
}

# Longer than any bound this harness or the pre-H6t hook imposes, so "killed at
# the bound" is what is actually being measured rather than "finished in time".
# Ignores TERM, so only an escalation to KILL — aimed at the sync itself and
# not at a wrapper around it — can stop it. Records its own pid so the test can
# ask whether it actually died rather than whether the hook stopped waiting.
STUBBORN_SYNC='trap "" TERM
echo $$ > "$(dirname "$0")/../.sync-pid"
echo "[synced] template deadbeef — 3 updated, 1 added"
sleep 30'

# "dead", "alive", or "unknown" — the state of the sync process the stub
# recorded. Reaps it when it outlived the hook, so one failing assertion does
# not leave a process behind for the rest of the suite.
autosync_syncstate() {
  local p
  p=$(cat "$1/.sync-pid" 2>/dev/null) || true
  if [ -z "$p" ]; then echo unknown; return; fi
  if kill -0 "$p" 2>/dev/null; then kill -9 "$p" 2>/dev/null; echo alive; else echo dead; fi
}

_expect_under() {   # name, ceiling seconds, actual seconds
  if [ "$3" -le "$2" ]; then _record "$1" 0
  else _record "$1 (took ${3}s against a ${2}s ceiling)" 1; fi
}

SLOW_SYNC='echo "[synced] template deadbeef — 3 updated, 1 added"
sleep 600'

# RED-1 — a sync killed at the bound says so, once, and still fails open.
AD=$(autosync_sandbox "$SLOW_SYNC")
AOUT=$(autosync_hook "$AD" TEMPLATE_AUTOSYNC_LIMIT=2); ARC=$?
_expect_has   "autosync: a killed sync reports the timeout (SC-1298)"        "timed out"  "$AOUT"
_expect       "autosync: a killed sync still exits 0 (fail open) (SC-1298)"  0            "$ARC"
# The killed sync had already printed its header — echoing the captured output
# would report a dead run as a completed one.
_expect_lacks "autosync: the timeout message carries no sync output (SC-1308)" "[synced]" "$AOUT"
# stdout is the SessionStart JSON channel. A stray line anywhere on it — a
# watchdog's chatter, a shell's job notice — corrupts the whole message, and
# nothing else in this file would notice.
_json_ok() { printf '%s' "$1" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' >/dev/null 2>&1; }
if _json_ok "$AOUT"; then _record "autosync: the timeout message is valid JSON (SC-1307)" 0
else _record "autosync: the timeout message is valid JSON (SC-1307)" 1; fi

# RED-2 — the killed run does not charge itself the normal six-hour window.
# Three outcomes must stay distinguishable here: absent / ok / timeout. An
# assertion that only checks "the sync ran again" passes for a hook that writes
# no marker at all, which is a different bug.
_expect "autosync: a killed sync marks the marker as a timeout (SC-1302)" timeout "$(autosync_marker "$AD")"
_expect "autosync: the killed sync did run once (SC-1302)"                1       "$(autosync_runs "$AD")"

# Inside the backoff window: silent, and the sync is not retried yet.
AOUT2=$(autosync_hook "$AD" TEMPLATE_AUTOSYNC_LIMIT=2)
_expect "autosync: inside the backoff window the sync is not retried (SC-1303)" 1 "$(autosync_runs "$AD")"
_expect "autosync: inside the backoff window the hook is silent (SC-1303)"      "" "$AOUT2"

# Past the backoff window: retried, rather than suppressed for six hours.
autosync_hook "$AD" TEMPLATE_AUTOSYNC_LIMIT=2 TEMPLATE_AUTOSYNC_TIMEOUT_BACKOFF=0 >/dev/null
_expect "autosync: past the backoff window the sync is retried (SC-1304)" 2 "$(autosync_runs "$AD")"
rm -rf "$AD"

# Control — a sync that completes and moved files still reports as before.
BD=$(autosync_sandbox 'echo "[synced] template deadbeef — 3 updated, 1 added"')
BOUT=$(autosync_hook "$BD" TEMPLATE_AUTOSYNC_LIMIT=2); BRC=$?
_expect_has "autosync: a completed sync still reports what moved (SC-1299)" "3 updated, 1 added" "$BOUT"
_expect     "autosync: a completed sync exits 0 (SC-1299)"                  0     "$BRC"
_expect     "autosync: a completed sync marks the marker ok (SC-1299)"      ok    "$(autosync_marker "$BD")"
if _json_ok "$BOUT"; then _record "autosync: the completed message is valid JSON (SC-1307)" 0
else _record "autosync: the completed message is valid JSON (SC-1307)" 1; fi
rm -rf "$BD"

# A hook killed from outside — the session ended, or settings.json's own 130 s
# hook timeout fired — must leave no marker at all, or the run it never
# finished would still buy the next session's silence. This is the property the
# whole retry story rests on.
JD=$(autosync_sandbox "$SLOW_SYNC")
( cd "$JD" && env TEMPLATE_AUTOSYNC_LIMIT=8 CLAUDE_PROJECT_DIR="$JD" \
  bash "$JD/scripts/template-autosync-hook.sh" ) >/dev/null 2>&1 &
JPID=$!
sleep 2
kill -TERM "$JPID" 2>/dev/null
wait "$JPID" 2>/dev/null
_expect "autosync: a hook killed from outside leaves no marker (SC-1306)" absent "$(autosync_marker "$JD")"
_expect "autosync: a hook killed from outside had started the sync (SC-1306)" 1 "$(autosync_runs "$JD")"
rm -rf "$JD"

# Control — a completed sync that moved nothing stays silent.
CD=$(autosync_sandbox 'echo "[synced] template deadbeef — 0 updated, 0 added"')
COUT=$(autosync_hook "$CD" TEMPLATE_AUTOSYNC_LIMIT=2)
_expect "autosync: a no-op sync stays silent (SC-1300)"          "" "$COUT"
_expect "autosync: a no-op sync marks the marker ok (SC-1300)"   ok "$(autosync_marker "$CD")"
rm -rf "$CD"

# Control — a non-timeout failure stays silent. H6t names the timeout and
# nothing else; making every failure loud is a different trade-off.
DD=$(autosync_sandbox 'echo "boom" >&2
exit 3')
DOUT=$(autosync_hook "$DD" TEMPLATE_AUTOSYNC_LIMIT=2); DRC=$?
_expect "autosync: another failure stays silent (SC-1301)"        "" "$DOUT"
_expect "autosync: another failure exits 0 (SC-1301)"             0  "$DRC"
_expect "autosync: another failure marks the marker ok (SC-1301)" ok "$(autosync_marker "$DD")"
rm -rf "$DD"

# 143 (128+TERM) is in the timeout class for the sake of `timeout`
# implementations this machine does not have, so nothing else in this file ever
# produces it. The accepted cost is stated in the spec (A2): a sync that exits
# 143 under its own power is read as a timeout.
MD=$(autosync_sandbox 'echo "[synced] partial"
exit 143')
MOUT=$(autosync_hook "$MD" TEMPLATE_AUTOSYNC_LIMIT=2)
_expect_has "autosync: rc 143 is read as a timeout (SC-1312)" "timed out" "$MOUT"
_expect     "autosync: rc 143 marks the marker as a timeout (SC-1312)" timeout "$(autosync_marker "$MD")"
rm -rf "$MD"

# The template ships to stock macOS, whose /bin/bash is 3.2. A syntax-only
# check is cheap and catches the bashism that would otherwise only fail on
# somebody else's laptop.
if [ -x /bin/bash ]; then
  if /bin/bash -n "$ROOT/scripts/template-autosync-hook.sh" 2>/dev/null; then
    _record "autosync: the hook parses under /bin/bash (3.2) (SC-1314)" 0
  else
    _record "autosync: the hook parses under /bin/bash (3.2) (SC-1314)" 1
  fi
fi

# Control — a marker left by the pre-H6t hook is an empty file and must read
# as "ok", i.e. today's behaviour. No migration.
ED=$(autosync_sandbox 'echo "[synced] template deadbeef — 3 updated, 1 added"')
: > "$ED/.claude/.template-sync-check"
EOUT=$(autosync_hook "$ED" TEMPLATE_AUTOSYNC_LIMIT=2)
_expect "autosync: a legacy empty marker suppresses like a normal one (SC-1305)" 0  "$(autosync_runs "$ED")"
_expect "autosync: a legacy empty marker keeps the hook silent (SC-1305)"        "" "$EOUT"
rm -rf "$ED"

# Control — opting out still short-circuits before anything else happens.
FD=$(autosync_sandbox "$SLOW_SYNC")
FOUT=$(autosync_hook "$FD" CLAUDE_TEMPLATE_AUTOSYNC=0)
_expect "autosync: opted out — the sync never runs (SC-1305)"   0      "$(autosync_runs "$FD")"
_expect "autosync: opted out — no marker is written (SC-1305)"  absent "$(autosync_marker "$FD")"
_expect "autosync: opted out — silent (SC-1305)"                ""     "$FOUT"
rm -rf "$FD"

# Control — the template repo is never its own sync target.
GD=$(autosync_sandbox "$SLOW_SYNC")
git -C "$GD" remote set-url origin https://github.com/johanolofsson72/Claude.git
GOUT=$(autosync_hook "$GD" TEMPLATE_AUTOSYNC_LIMIT=2)
_expect "autosync: the template repo syncs nothing (SC-1299)"        0      "$(autosync_runs "$GD")"
_expect "autosync: the template repo writes no marker (SC-1299)"     absent "$(autosync_marker "$GD")"
_expect "autosync: the template repo is silent (SC-1299)"            ""     "$GOUT"
rm -rf "$GD"

# The bound must exist even where coreutils does not. Stock macOS ships neither
# `timeout` nor `gtimeout`; without a bound of its own the hook runs the sync
# unmeasured, and the retry H6t introduces would then be unbounded too.
GUARD=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null)
if [ -n "$GUARD" ]; then
  HD=$(autosync_sandbox "$SLOW_SYNC")
  NOBIN=$(mktemp -d)
  for c in bash sh git dirname date stat sed tr sleep rm cat head wc mktemp kill; do
    p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$NOBIN/$c"
  done
  HOUT=$(cd "$HD" && "$GUARD" 20 env PATH="$NOBIN" TEMPLATE_AUTOSYNC_LIMIT=2 \
         CLAUDE_PROJECT_DIR="$HD" bash "$HD/scripts/template-autosync-hook.sh"); HRC=$?
  _expect       "autosync: bounded even with no timeout binary (SC-1309)"   0           "$HRC"
  _expect_has   "autosync: reports the timeout without coreutils (SC-1309)" "timed out" "$HOUT"
  _expect       "autosync: marks the marker as a timeout too (SC-1309)"     timeout     "$(autosync_marker "$HD")"
  rm -rf "$HD"

  # A watchdog that only signals its wrapper, or only sends TERM, advertises a
  # bound it does not have. Measured in seconds, because "it reported a
  # timeout" is true either way — it is the clock that discriminates.
  KD=$(autosync_sandbox "$STUBBORN_SYNC")
  KS=$(date +%s)
  KOUT=$(cd "$KD" && "$GUARD" 40 env PATH="$NOBIN" TEMPLATE_AUTOSYNC_LIMIT=2 \
         CLAUDE_PROJECT_DIR="$KD" bash "$KD/scripts/template-autosync-hook.sh")
  KE=$(( $(date +%s) - KS ))
  _expect_under "autosync: watchdog — a sync ignoring TERM is stopped at the bound (SC-1311)" 15 "$KE"
  _expect_has   "autosync: watchdog — a sync ignoring TERM reports a timeout (SC-1311)" "timed out" "$KOUT"
  _expect       "autosync: watchdog — a sync ignoring TERM is actually dead (SC-1311)" dead "$(autosync_syncstate "$KD")"
  rm -rf "$KD"
  rm -rf "$NOBIN"
else
  printf '  \033[33mSKIP\033[0m  autosync: no-coreutils case (no timeout binary to guard the test)\n'
fi

# The same claim on the path that normally runs. `timeout N` alone does not
# bound a sync that ignores TERM — it signals at N and then waits, so a 2 s
# bound against a 30 s TERM-ignoring sync returns 124 after the full 30 s. This
# is the assertion that pins `-k`, and it is timed rather than asserted on the
# message, which is identical either way.
LD=$(autosync_sandbox "$STUBBORN_SYNC")
LS=$(date +%s)
LOUT=$(autosync_hook "$LD" TEMPLATE_AUTOSYNC_LIMIT=2)
LE=$(( $(date +%s) - LS ))
_expect_under "autosync: a sync ignoring TERM is stopped at the bound (SC-1310)" 15 "$LE"
_expect_has   "autosync: a sync ignoring TERM reports a timeout (SC-1310)" "timed out" "$LOUT"
_expect       "autosync: a sync ignoring TERM is actually dead (SC-1310)" dead "$(autosync_syncstate "$LD")"
_expect       "autosync: a sync ignoring TERM marks the marker as a timeout (SC-1310)" timeout "$(autosync_marker "$LD")"
rm -rf "$LD"

# A watchdog that outlives the sync would leave a process behind on every
# session start, and anything it printed would corrupt the hook's JSON channel.
ID=$(autosync_sandbox 'echo "[synced] template deadbeef — 3 updated, 1 added"')
BEFORE=$(pgrep -f "$ID/scripts" 2>/dev/null | wc -l | tr -d ' ')
autosync_hook "$ID" TEMPLATE_AUTOSYNC_LIMIT=2 >/dev/null
sleep 3
AFTER=$(pgrep -f "$ID/scripts" 2>/dev/null | wc -l | tr -d ' ')
_expect "autosync: a completed sync leaves no watchdog behind (SC-1313)" "$BEFORE" "$AFTER"
rm -rf "$ID"

# ─── totals ───────────────────────────────────────────────────────────────

echo
echo "════════════════════════════════════════════════════════"
printf "Total: \033[32m%d passed\033[0m, " "$PASS"
if [ "$FAIL" -gt 0 ]; then
  printf "\033[31m%d failed\033[0m\n" "$FAIL"
  echo
  echo "Failed tests:"
  for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
  exit 1
else
  printf "0 failed\n"
  exit 0
fi
