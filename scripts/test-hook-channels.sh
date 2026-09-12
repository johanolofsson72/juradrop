#!/bin/bash
# test-hook-channels.sh — the gate for spec 046.
#
#   bash scripts/test-hook-channels.sh
#
# Two defects, one root: every hook picked its own output channel, and there was
# nothing that could tell a right pick from a wrong one.
#
#   1. Advisories used `systemMessage` — "Warning shown to user in UI" — to talk
#      to the model. The developer got a red notification per line, per edit.
#   2. 42 hooks emitted a TOP-LEVEL `additionalContext`, which Claude Code
#      silently ignores. Four were wired as UserPromptSubmit hooks, so the first
#      enforcement layer of feature-pipeline.md had never said anything at all.
#
# The second one is what makes this file necessary rather than nice. A hook that
# shouts is obvious; a hook that has been silent since the day it was written
# looks exactly like a hook with nothing to report. Only a test tells them apart.

set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

echo "== 1. no hook emits a top-level additionalContext =="
# The CLI answers such a payload with "Did you mean
# hookSpecificOutput.additionalContext (with a hookEventName)?" and drops it.
HITS=$(grep -ln "'{additionalContext:\|\"additionalContext\":" scripts/*.sh 2>/dev/null \
       | while read -r f; do
           grep -q 'hookSpecificOutput' "$f" || printf '%s\n' "$f"
         done)
if [ -z "$HITS" ]; then ok "every additionalContext is nested"
else bad "top-level additionalContext (silently ignored) in:"; printf '       %s\n' $HITS; fi

echo "== 2. every hookSpecificOutput carries a hookEventName =="
# Proven live on 2026-09-12: hookEventName is the discriminator, not decoration.
# The same edit, against the same guard, was ALLOWED without the field and
# DENIED with it. So every PreToolUse guard in this template had been inert
# since it was written — including the settings.json rule that blocks reads of
# ~/.ssh, ~/.aws and .env. A hard block that silently permits looks exactly
# like a hard block that had nothing to stop.
#
# Emit sites only. `jq -r .hookSpecificOutput.x` is a hook READING another
# hook's verdict (bash-write-detect delegates to bash-write-guard that way),
# and a reader has no event name to carry.
MISSING=""
for f in scripts/*-hook.sh scripts/emit-*.sh scripts/feature-pipeline-detect.sh; do
  [ -f "$f" ] || continue
  grep 'hookSpecificOutput' "$f" | grep -qv 'jq -r' || continue
  grep -q 'hookEventName' "$f" || MISSING="$MISSING $f"
done
[ -z "$MISSING" ] && ok "all nested payloads name their event" \
  || { bad "hookSpecificOutput without hookEventName:"; printf '       %s\n' $MISSING; }

echo "== 3. no advisory hook uses the developer's channel =="
# systemMessage is legitimate, but only for news a person must act on: a hook
# changed files, a sync stopped halfway, a commit was made nobody typed. Every
# other use is a reminder in the wrong place. This is an allowlist, because the
# right answer is per-hook and a count cannot see the difference.
ALLOWED="scripts/bash-write-detect-hook.sh scripts/after-specify-hook.sh scripts/hook-notice.sh scripts/template-autosync-hook.sh"
OFFENDERS=""
for f in scripts/*-hook.sh; do
  [ -f "$f" ] || continue
  # Emit sites only — a comment explaining the history is not an emit.
  grep -qE '(systemMessage[\"'"'"']?[[:space:]]*:|\{systemMessage)' "$f" || continue
  case " $ALLOWED " in *" $f "*) continue ;; esac
  OFFENDERS="$OFFENDERS $f"
done
[ -z "$OFFENDERS" ] && ok "advisories are on the model's channel" \
  || { bad "systemMessage used for a reminder in:"; printf '       %s\n' $OFFENDERS; }

echo "== 4. a systemMessage is one line =="
# The UI renders one notification per line. A 26-line orientation banner became
# 26 red warnings, which is the visible half of this whole spec.
. "$ROOT/scripts/hook-notice.sh"
OUT=$(notice_user "first
second
third")
LINES=$(printf '%s' "$OUT" | python3 -c "
import sys,json
try: d=json.loads(sys.stdin.read())
except Exception: print(99); raise SystemExit
print(d.get('systemMessage','').count(chr(10))+1)")
[ "$LINES" = "1" ] && ok "notice_user collapses newlines (got 1 line)" \
                   || bad "notice_user emitted $LINES lines, expected 1"

echo "== 5. notice_model produces no user-visible field =="
OUT=$(notice_model PostToolUse "hello")
printf '%s' "$OUT" | grep -q systemMessage && bad "notice_model leaked a systemMessage" \
  || ok "notice_model is model-only"
printf '%s' "$OUT" | python3 -c "
import sys,json; d=json.load(sys.stdin)
h=d['hookSpecificOutput']
assert h['hookEventName']=='PostToolUse' and h['additionalContext']=='hello'
" 2>/dev/null && ok "notice_model shape is correct" || bad "notice_model shape is wrong"

echo "== 6. every emitter is valid JSON =="
BADJSON=""
for ev in PostToolUse SessionStart UserPromptSubmit; do
  for payload in 'plain' 'quote " and \ backslash' 'tab	and
newline'; do
    notice_model "$ev" "$payload" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null \
      || BADJSON="$BADJSON [$ev/$(printf '%s' "$payload" | head -c 12)]"
    notice_user "$payload" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null \
      || BADJSON="$BADJSON [user/$(printf '%s' "$payload" | head -c 12)]"
  done
done
[ -z "$BADJSON" ] && ok "escaping holds for quotes, backslashes, tabs, newlines" \
                  || bad "invalid JSON produced:$BADJSON"

echo "== 7. the same reminder does not repeat within a session =="
SID="test-$$-$(date +%s)"
A=$(notice_once PostToolUse "$SID" "k1" "text")
B=$(notice_once PostToolUse "$SID" "k1" "text")
C=$(notice_once PostToolUse "$SID" "k2" "text")
[ -n "$A" ] && [ -z "$B" ] && [ -n "$C" ] \
  && ok "first fires, repeat is silent, a different key still fires" \
  || bad "de-duplication wrong (first='${A:+set}' repeat='${B:+set}' other='${C:+set}')"

# No session id must NOT suppress: a hook run by hand, or by a test, has none,
# and losing a reminder is the worse of the two failures.
D=$(notice_once PostToolUse "" "k1" "text")
E=$(notice_once PostToolUse "" "k1" "text")
[ -n "$D" ] && [ -n "$E" ] && ok "no session id → never suppressed" \
                           || bad "missing session id suppressed a reminder"
rm -rf "${TMPDIR:-/tmp}/claude-hook-notices/$SID" 2>/dev/null

echo "== 8. the spec-coverage reminder does not fire on the register =="
# specs/INDEX.md contains the word "spec" in its path like every file under
# specs/, and the register's rows mention forms, search and upload. It matched,
# and ticking a row produced "Missing FUNCTIONAL COVERAGE: list EVERY
# implemented function" about a list of register rows.
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/specs/003-search"
cat > "$TMP/specs/INDEX.md" <<'EOF'
# Spec register
- [x] 001 — login-form — full track — the sign-in form and its upload button
- [ ] 002 — search — full track — search and filter over the catalogue
EOF
cp "$TMP/specs/INDEX.md" "$TMP/specs/INDEX.completed.md"
cat > "$TMP/specs/003-search/spec.md" <<'EOF'
# Search
The user types into a search input and clicks the submit button.
EOF
probe() {
  printf '{"session_id":"p%s","tool_input":{"file_path":"%s"}}' "$RANDOM" "$1" \
    | bash "$ROOT/scripts/spec-md-coverage-reminder-hook.sh" 2>/dev/null
}
[ -z "$(probe "$TMP/specs/INDEX.md")" ] && ok "silent on specs/INDEX.md" \
  || bad "still fires on the register"
[ -z "$(probe "$TMP/specs/INDEX.completed.md")" ] && ok "silent on the row archive" \
  || bad "still fires on specs/INDEX.completed.md"
[ -n "$(probe "$TMP/specs/003-search/spec.md")" ] && ok "still fires on a real spec.md" \
  || bad "no longer fires on a real spec — the anchor is too tight"

echo "== 9. the GC leaves everything it does not recognise =="
GCT=$(mktemp -d) || exit 1
mkdir -p "$GCT/.git" "$GCT/src/states" "$GCT/model/states/26-08-05-11-47-33" "$GCT/model/states/handwritten"
echo 'export const Panel = 1' > "$GCT/src/states/StatePanel.tsx"
: > "$GCT/model/states/26-08-05-11-47-33/Spec-0.st"
: > "$GCT/model/states/26-08-05-11-47-33/nodes_0"
echo 'MODULE Foo' > "$GCT/model/states/handwritten/Foo.tla"
CLAUDE_PROJECT_DIR="$GCT" bash "$ROOT/scripts/harness-state-gc.sh" >/dev/null 2>&1
[ -f "$GCT/src/states/StatePanel.tsx" ] && ok "source directory named states survives" \
  || bad "GC deleted a source directory"
[ -f "$GCT/model/states/handwritten/Foo.tla" ] && ok "hand-written .tla survives" \
  || bad "GC deleted a hand-written model"
[ ! -d "$GCT/model/states/26-08-05-11-47-33" ] && ok "TLC scratch is collected" \
  || bad "GC left TLC scratch behind"
rm -rf "$GCT"

echo
printf 'passed %s, failed %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
