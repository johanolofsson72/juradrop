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
# Test scripts are excluded because they carry the pattern as DATA — this very
# file greps for it. Until 2026-09-12 that exclusion was accidental: this file
# happened to also mention hookSpecificOutput, which the filter below read as
# "nested, therefore fine". A test that passes itself by coincidence is a test
# that stops passing when someone edits an unrelated line.
HITS=$(grep -ln "'{additionalContext:\|\"additionalContext\":" scripts/*.sh 2>/dev/null \
       | grep -v '/test-' \
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
  EMITS=$(grep 'hookSpecificOutput' "$f" 2>/dev/null | grep -cv 'jq -r')
  [ "${EMITS:-0}" -eq 0 ] && continue
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
case "$OUT" in
  *systemMessage*) bad "notice_model leaked a systemMessage" ;;
  *)               ok  "notice_model is model-only" ;;
esac
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

echo "== 10. the sync repairs an inline payload the CLI would discard =="
# sync-core-hooks.py preserves inline hooks verbatim by design, which is right
# for what a hook SAYS and wrong for whether it is heard. The template fixed its
# own settings.json and nothing moved: 41 projects kept an inert .ssh/.aws/.env
# read-block — a security rule that was present in the file and did nothing.
RT=$(mktemp -d) || exit 1
mkdir -p "$RT/.claude" "$RT/scripts"
cat > "$RT/.claude/settings.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "matcher": "Read",
  "hooks": [ { "type": "command",
    "command": "echo '{\"hookSpecificOutput\": {\"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"no\"}}'" } ] } ],
  "PostToolUse": [ { "hooks": [ { "type": "command",
    "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"fine\"}}'" } ] } ] } }
JSON
BEFORE=$(cat "$RT/.claude/settings.json")
( cd "$RT" && python3 "$ROOT/scripts/sync-core-hooks.py" "$ROOT/.claude/settings.json" ) >/dev/null 2>&1
python3 - "$RT/.claude/settings.json" <<'PY2'
import json,sys
d=json.load(open(sys.argv[1]))
pre=d["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
post=[h["command"] for g in d["hooks"]["PostToolUse"] for h in g["hooks"] if "fine" in h["command"]]
assert '"hookEventName": "PreToolUse"' in pre, "deny not repaired"
assert post and post[0].count("hookEventName")==1, "correct hook was rewritten"
PY2
[ $? -eq 0 ] && ok "inert deny repaired, correct hook left alone" || bad "repair pass wrong"
# idempotent: a second run must change nothing
A=$(cat "$RT/.claude/settings.json")
( cd "$RT" && python3 "$ROOT/scripts/sync-core-hooks.py" "$ROOT/.claude/settings.json" ) >/dev/null 2>&1
[ "$A" = "$(cat "$RT/.claude/settings.json")" ] && ok "repair is idempotent" || bad "repair is not idempotent"
rm -rf "$RT"

# ── Spec 029 ────────────────────────────────────────────────────────────────
# §2 asks whether a FILE mentions hookEventName; a guard with three deny sites and
# one bare one passes it. And every guard test read `.permissionDecision` alone,
# which is the probe that fooled rocky's H13: the pre-046 guards, all inert, pass
# the pre-029 tests 399/399. These checks look at each emit site, and at how the
# tests read what the guards say.
. "$ROOT/scripts/hook-verdict.sh"

# Emit sites of a permissionDecision: the key, in any quoting a shell or python
# hook writes it (bare jq key, "json", \"escaped\", 'single'), that do not carry
# `hookEventName: "PreToolUse"` on the same line or the 3 non-comment lines above
# it. The heredoc layout pipeline-state-guard uses puts the field two lines up.
# Comments are dropped before the window is read, so `# hookEventName` above a bare
# emit cannot vouch for it, and the value must be PreToolUse, not merely present.
# Reads (`.permissionDecision`, `get("permissionDecision")`) are not emits.
# DENY_COUNT=1 prints the number of emit sites instead.
deny_scan() {
  python3 - "$@" <<'PYSCAN'
import os, re, sys
Q = r"""[\\"']*"""
KEY = re.compile(r"(?<![.\w])" + Q + r"permissionDecision" + Q + r"\s*:")
EVENT = re.compile(r"hookEventName" + Q + r"\s*:\s*" + Q + r"PreToolUse\b")
COMMENT = re.compile(r"^\s*#")
bare, sites = [], 0
for path in sys.argv[1:]:
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    window = []
    for n, line in enumerate(lines, 1):
        if COMMENT.match(line):
            continue
        window = (window + [line])[-4:]
        if KEY.search(line):
            sites += 1
            if not any(EVENT.search(w) for w in window):
                bare.append(f"{path}:{n}")
            window = []  # the next emit is another object; this one cannot vouch for it
if os.environ.get("DENY_COUNT"):
    print(sites)
elif bare:
    print("\n".join(bare))
PYSCAN
}
bare_deny_sites() { deny_scan "$@"; }

echo "== 11. every deny emit site names its event =="
# probe-live-deny.sh is excluded by name: its control arm is bare ON PURPOSE, to
# show the CLI drops it. §15 pins that script's behaviour instead.
EMITTERS=()
for f in scripts/*.sh scripts/*.py .claude/hooks/*; do
  [ -f "$f" ] || continue
  case "$f" in scripts/test-*|scripts/hook-verdict.sh|scripts/probe-live-deny.sh) ;; *) EMITTERS+=("$f") ;; esac
done
SITES=$(bare_deny_sites "${EMITTERS[@]}" 2>/dev/null)
inline_bare() {
  python3 - "$ROOT/.claude/settings.json" "$ROOT/.claude/settings.local.json" <<'PY3'
import json, re, sys
EVENT = re.compile(r'hookEventName\\?"?\s*:\s*\\?"?PreToolUse')
KEY = re.compile(r'permissionDecision\\?"?\s*:')
seen = 0
for path in sys.argv[1:]:
    try:
        d = json.load(open(path))
    except (OSError, ValueError):
        continue
    for ev, groups in d.get("hooks", {}).items():
        for g in groups:
            for h in g.get("hooks", []):
                c = h.get("command", "")
                seen += len(KEY.findall(c))
                if len(KEY.findall(c)) > len(EVENT.findall(c)):
                    print(f"{path.rsplit('/', 1)[-1]} {ev} matcher={g.get('matcher', '')}")
# The template ships one inline deny (the sensitive-file rule). Seeing none means
# the pattern stopped matching, which must not read as clean.
if seen == 0:
    print("inline:none-seen")
PY3
}
INLINE=$(inline_bare)
# A check that found no sites at all proves nothing: the pattern would have
# stopped matching, not the guards stopped emitting.
N=$(DENY_COUNT=1 deny_scan "${EMITTERS[@]}")
if [ "${N:-0}" -lt 7 ]; then bad "only ${N:-0} deny emit sites found — the site pattern no longer matches the guards"
elif [ -z "$SITES$INLINE" ]; then ok "all $N deny emit sites and every inline hook name their event"
else bad "deny emitted without hookEventName (the CLI drops it):"; printf '       %s\n' $SITES ${INLINE:+"$INLINE"}; fi

echo "== 12. the site check bites (sabotage) =="
SB=$(mktemp -d) || exit 1
printf '%s\n' "jq -n '{hookSpecificOutput: {permissionDecision: \"deny\"}}'" > "$SB/bare.sh"
printf '%s\n' 'cat <<EOF' '{"hookSpecificOutput": {' '  "hookEventName": "PreToolUse",' '  "permissionDecision": "deny",' '}}' 'EOF' > "$SB/heredoc.sh"
printf '%s\n' "# permissionDecision: deny  (a comment)" "x=\$(jq -r '.hookSpecificOutput.permissionDecision')" > "$SB/reader.sh"
printf '%s\n' '"hookEventName": "PreToolUse",' 'a' 'b' 'c' '"permissionDecision": "deny",' > "$SB/far.sh"
[ -n "$(bare_deny_sites "$SB/bare.sh")" ]    && ok "a bare jq deny is flagged"          || bad "bare jq deny not flagged"
[ -z "$(bare_deny_sites "$SB/heredoc.sh")" ] && ok "the heredoc layout passes"          || bad "heredoc layout flagged"
[ -z "$(bare_deny_sites "$SB/reader.sh")" ]  && ok "readers and comments are not emits" || bad "a reader or comment was flagged"
[ -n "$(bare_deny_sites "$SB/far.sh")" ]     && ok "a field 4 lines up is another object" || bad "the window is too wide"
cat > "$SB/goodthenbare.sh" <<'EOF'
jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny"}}'
jq -n '{hookSpecificOutput: {permissionDecision: "deny"}}'
EOF
[ "$(bare_deny_sites "$SB/goodthenbare.sh")" = "$SB/goodthenbare.sh:2" ] \
  && ok "a good emit cannot vouch for the bare one after it" || bad "a good emit vouched for the next"
cat > "$SB/escaped.sh" <<'EOF'
printf '{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\"}}'
EOF
cat > "$SB/commented.sh" <<'EOF'
# hookEventName: "PreToolUse"
jq -n '{hookSpecificOutput: {permissionDecision: "deny"}}'
EOF
cat > "$SB/wrongevent.sh" <<'EOF'
jq -n '{hookSpecificOutput: {hookEventName: "PostToolUse", permissionDecision: "deny"}}'
EOF
cat > "$SB/emit.py" <<'EOF'
print(json.dumps({"hookSpecificOutput": {"permissionDecision": "deny"}}))
EOF
[ -n "$(bare_deny_sites "$SB/escaped.sh")" ]    && ok "an escaped-quote JSON deny is flagged"  || bad "escaped-quote deny not flagged"
[ -n "$(bare_deny_sites "$SB/commented.sh")" ]  && ok "a comment cannot vouch for a bare deny" || bad "a comment vouched for a bare deny"
[ -n "$(bare_deny_sites "$SB/wrongevent.sh")" ] && ok "the wrong event name is flagged"        || bad "PostToolUse accepted as the event"
[ -n "$(bare_deny_sites "$SB/emit.py")" ]       && ok "a python-emitted bare deny is flagged"  || bad "python emit not flagged"
rm -rf "$SB"

echo "== 13. hook_verdict reads what the CLI reads =="
[ "$(hook_verdict '{"hookSpecificOutput":{"permissionDecision":"deny"}}')" = dropped ] \
  && ok "the pre-046 shape is dropped" || bad "the bare shape reads as a verdict"
[ "$(hook_verdict '{"hookSpecificOutput":{"hookEventName":"PostToolUse","permissionDecision":"deny"}}')" = dropped ] \
  && ok "the wrong event is dropped" || bad "a PostToolUse deny reads as a PreToolUse verdict"
[ "$(hook_verdict '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}')" = deny ] \
  && ok "the well-formed deny is a deny" || bad "the well-formed deny is not read"
[ "$(hook_verdict '')" = none ] && [ "$(hook_verdict 'not json')" = invalid ] \
  && ok "empty is none, garbage is invalid" || bad "empty/garbage misread"
# A real guard, then the same guard with the field stripped: deny, then dropped.
GV=$(mktemp -d) || exit 1
mkdir -p "$GV/.git" "$GV/src"; echo '{}' > "$GV/package.json"
sed -e 's/hookEventName: "PreToolUse", //' "$ROOT/scripts/spec-register-guard-hook.sh" > "$GV/bare-guard.sh"
P="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$GV/src/a.ts\"}}"
# The CLI reads stdout JSON only on exit 0; a deny that exits 1 is not a deny.
O1=$(printf '%s' "$P" | bash "$ROOT/scripts/spec-register-guard-hook.sh" 2>/dev/null); RC1=$?
V1=$(hook_verdict "$O1")
V2=$(hook_verdict "$(printf '%s' "$P" | bash "$GV/bare-guard.sh" 2>/dev/null)")
[ "$V1" = deny ] && [ "$RC1" -eq 0 ] && [ "$V2" = dropped ] && ok "live guard: deny on exit 0; stripped copy: dropped" \
  || bad "guard verdicts wrong (real=$V1 rc=$RC1 stripped=$V2)"
# A second guard, so the arm is not one guard's accident. pipeline-state-guard
# resolves the active row through spec_active.py next to it, so the copy gets one.
mkdir -p "$GV/specs" "$GV/g"
printf '# Spec register\n\n## Specs\n\n- [ ] 001 — foo — full track — x\n' > "$GV/specs/INDEX.md"
cp "$ROOT/scripts/spec_active.py" "$GV/g/"
sed -e 's/hookEventName: "PreToolUse", //' -e '/"hookEventName": "PreToolUse",/d' \
  "$ROOT/scripts/pipeline-state-guard-hook.sh" > "$GV/g/pipeline-state-guard-hook.sh"
V3=$(hook_verdict "$(printf '%s' "$P" | CLAUDE_PROJECT_DIR="$GV" bash "$ROOT/scripts/pipeline-state-guard-hook.sh" 2>/dev/null)")
V4=$(hook_verdict "$(printf '%s' "$P" | CLAUDE_PROJECT_DIR="$GV" bash "$GV/g/pipeline-state-guard-hook.sh" 2>/dev/null)")
[ "$V3" = deny ] && [ "$V4" = dropped ] && ok "second guard (pipeline-state): deny; stripped copy: dropped" \
  || bad "pipeline-state-guard verdicts wrong (real=$V3 stripped=$V4)"
rm -rf "$GV"

echo "== 14. guard tests decode through the CLI's rule =="
# A test that reads .permissionDecision alone reopens the hole this spec closed.
# Per read, not per file: one hook_verdict call must not vouch for a lenient read
# elsewhere in the same file. A jq path read is never allowed (use hook_verdict);
# a python get("permissionDecision") needs the DROPPED guard (a real
# h.get("hookEventName") call, not a mention) within 6 lines above.
lenient_reads() {
  python3 - scripts/test-*.sh <<'PY14'
import re, sys
JQ = re.compile(r"\.permissionDecision(?!Reason)\b")
PY = re.compile(r"""get\(\s*["']permissionDecision["']""")
for path in sys.argv[1:]:
    if path.endswith("test-hook-channels.sh"):
        continue
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    for n, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        guarded = any('get("hookEventName")' in l for l in lines[max(0, n - 7):n - 1])
        if JQ.search(line) or (PY.search(line) and not guarded):
            print(f"{path}:{n}")
PY14
}
LENIENT=$(lenient_reads)
[ -z "$LENIENT" ] && ok "every verdict read in the guard tests goes through the CLI's rule" \
  || { bad "reads permissionDecision without the discriminator:"; printf '       %s\n' $LENIENT; }

echo "== 15. probe-live-deny reads the CLI's behaviour correctly (fake claude) =="
# The live probe spends model calls, so its verdict logic is pinned here against a
# stand-in CLI: one that behaves like the real one, one that ignores every deny,
# one that refuses every edit, one that never calls the hook, one that fails, and
# one that returns what `timeout` returns when it cuts an arm off.
FK=$(mktemp -d) || exit 1
cat > "$FK/claude" <<'FAKE'
#!/bin/bash
[ "${1:-}" = --version ] && { echo "0.0.0 (fake)"; exit 0; }
S=""; while [ $# -gt 0 ]; do [ "$1" = --settings ] && S="$2"; shift; done
hook() { bash -c "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$S")"; }
edit() { sed -i.bak 's/= 1;/= 2;/' probe.ts; }
case "$FAKE_CLI" in
  obey)   hook | grep -q hookEventName || edit ;;
  ignore) hook >/dev/null; edit ;;
  refuse) hook >/dev/null ;;
  silent) : ;;
  fail)   hook >/dev/null; exit 1 ;;
  timeout-rc) exit 124 ;;   # what `timeout` returns when it cuts an arm off
esac
FAKE
chmod +x "$FK/claude"
probe_exit() { PATH="$FK:$PATH" FAKE_CLI="$1" PROBE_MODES="${2:-bypassPermissions}" \
                 bash "$ROOT/scripts/probe-live-deny.sh" >/dev/null 2>&1; echo $?; }
[ "$(probe_exit obey)" = 0 ]   && ok "a CLI that applies the deny: exit 0"         || bad "obeying CLI not reported as holding"
[ "$(probe_exit ignore)" = 1 ] && ok "a CLI that ignores the deny: exit 1"         || bad "ignoring CLI not reported as broken"
[ "$(probe_exit refuse)" = 3 ] && ok "a CLI that refuses every edit: inconclusive" || bad "refusing CLI read as a pass"
[ "$(probe_exit timeout-rc)" = 3 ] && ok "an arm cut off by timeout: inconclusive" || bad "a timed-out arm read as a pass"
[ "$(probe_exit obey 'acceptEdits bypassPermissions')" = 0 ]   && ok "both modes probed, both hold: exit 0" || bad "two-mode run misread"
[ "$(probe_exit ignore 'acceptEdits bypassPermissions')" = 1 ] && ok "both modes broken: exit 1"            || bad "two-mode broken run misread"
[ "$(probe_exit silent)" = 3 ] && ok "a hook that never fired: inconclusive"       || bad "an arm with no hook call read as held"
[ "$(probe_exit fail)" = 3 ]   && ok "a CLI that exits non-zero: inconclusive"     || bad "a failed CLI read as held"
[ "$(probe_exit obey ' ')" = 3 ] && ok "no mode probed: inconclusive, never a pass" || bad "zero modes read as a pass"
[ "$(probe_exit obey 'default')" = 2 ] && ok "an unsupported mode is refused"       || bad "unsupported mode accepted"
[ "$(PATH="$FK:$PATH" FAKE_CLI=obey PROBE_TIMEOUT='1 x' bash "$ROOT/scripts/probe-live-deny.sh" >/dev/null 2>&1; echo $?)" = 2 ] \
  && ok "a non-numeric timeout is refused" || bad "PROBE_TIMEOUT not validated"
[ "$(PATH="/usr/bin:/bin" bash "$ROOT/scripts/probe-live-deny.sh" >/dev/null 2>&1; echo $?)" = 2 ] \
  && ok "no claude on PATH: exit 2" || bad "missing CLI not reported"
rm -rf "$FK"

echo
printf 'passed %s, failed %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
