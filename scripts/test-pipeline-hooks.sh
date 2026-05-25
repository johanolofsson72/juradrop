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
