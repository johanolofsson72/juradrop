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
