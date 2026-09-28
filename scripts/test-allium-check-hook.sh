#!/bin/bash
# test-allium-check-hook.sh — prove allium-check-hook.sh blocks on errors and ONLY on errors.
#
# Real-CLI arms need `allium` on PATH (skipped with a notice otherwise). Fake-CLI arms stub the
# binary through ALLIUM_BIN, so the missing / garbage / timeout paths are tested on any machine.
# The sabotage arm is the point: a hook that decides on the CLI's exit code must FAIL the
# warnings-only case, or this suite cannot tell the difference.
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$SCRIPT_DIR/allium-check-hook.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"   # hook-notice state lands here, not in the real session dir

run() { # run <hook> <file> [env...]  → prints hook stdout
  local hook="$1" file="$2"; shift 2
  printf '{"session_id":"t-%s","tool_input":{"file_path":"%s"}}' "$RANDOM" "$file" \
    | env "$@" bash "$hook"
}
blocks() { printf '%s' "$1" | jq -e '.decision == "block"' >/dev/null 2>&1; }

CLEAN="$TMP/clean.allium"
printf -- '-- allium: 3\n\nentity W {\n    ok: Boolean\n}\n\nrule R {\n    when: Go(w)\n    ensures: w.ok = true\n}\n' > "$CLEAN"
WARN="$TMP/warn.allium"
printf -- '-- allium: 3\n\nentity Lonely {\n    x: String\n}\n' > "$WARN"
PARSE="$TMP/parse.allium"
printf -- '-- allium: 3\n\nexternal entity User { id: String; role: String }\n' > "$PARSE"
MANY="$TMP/many.allium"
{ printf -- '-- allium: 3\n\n'; for i in $(seq 1 25); do printf 'garbage_%s ;;\n' "$i"; done; } > "$MANY"
SPACED="$TMP/with space/s.allium"; mkdir -p "$TMP/with space"; cp "$PARSE" "$SPACED"

echo "== real CLI"
if command -v allium >/dev/null 2>&1; then
  allium check "$WARN" >/dev/null 2>&1; wrc=$?
  [ "$wrc" -ne 0 ] && ok "precondition: CLI exits $wrc on a warnings-only file" \
                   || bad "precondition: warnings-only fixture produced exit 0 — the sabotage arm proves nothing"

  out=$(run "$HOOK" "$CLEAN");  [ -z "$out" ] && ok "clean file passes silently" || bad "clean file: $out"
  out=$(run "$HOOK" "$WARN");   [ -z "$out" ] && ok "warnings-only file passes" || bad "warnings-only blocked: $out"
  out=$(run "$HOOK" "$PARSE");  blocks "$out" && ok "parse error blocks" || bad "parse error passed: $out"
  grep -q '^  3:' <<< "$(printf '%s' "$out" | jq -r .reason)" && ok "reason names line 3" || bad "reason lacks line: $out"
  out=$(run "$HOOK" "$SPACED"); blocks "$out" && ok "path with a space is validated" || bad "spaced path: $out"
  out=$(run "$HOOK" "$MANY")
  n=$(printf '%s' "$out" | jq -r .reason | grep -c '^  [0-9]')
  { [ "$n" -eq 20 ] && grep -q 'and [0-9]* more' <<< "$(printf '%s' "$out" | jq -r .reason)"; } \
    && ok "reason capped at 20 lines + 'and N more'" || bad "cap: $n lines"

  # Sabotage: decide on the exit code instead of severity. Must block the warnings-only file.
  SAB="$TMP/sabotaged-hook.sh"
  sed 's/^\[ -z "\$REASON" \] \&\& exit 0$/[ "$RC" -eq 0 ] \&\& exit 0; REASON=${REASON:-exit $RC}/' "$HOOK" > "$SAB"
  cp "$SCRIPT_DIR/hook-notice.sh" "$TMP/hook-notice.sh"
  if cmp -s "$HOOK" "$SAB"; then
    bad "sabotage: sed did not change the hook — the arm is vacuous"
  else
    out=$(run "$SAB" "$WARN")
    blocks "$out" && ok "sabotage: an exit-code hook DOES block warnings-only (the suite can tell)" \
                  || bad "sabotage: exit-code hook passed warnings-only — suite is blind"
  fi
else
  echo "  SKIP  allium CLI not installed — real-CLI arms not run"
fi

echo "== fake CLI"
FAKE="$TMP/fake"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho "segfault"\nexit 139\n' > "$FAKE/garbage";  chmod +x "$FAKE/garbage"
printf '#!/bin/sh\nexit 0\n' > "$FAKE/empty";                        chmod +x "$FAKE/empty"
printf '#!/bin/sh\necho "{\\"diagnostics\\": 7}"\n' > "$FAKE/shape"; chmod +x "$FAKE/shape"
printf '#!/bin/sh\nsleep 5\n' > "$FAKE/slow";                        chmod +x "$FAKE/slow"

out=$(run "$HOOK" "$CLEAN" ALLIUM_BIN="$FAKE/garbage"); blocks "$out" && ok "non-JSON output blocks" || bad "garbage: $out"
out=$(run "$HOOK" "$CLEAN" ALLIUM_BIN="$FAKE/empty");   blocks "$out" && ok "empty output blocks"    || bad "empty: $out"
out=$(run "$HOOK" "$CLEAN" ALLIUM_BIN="$FAKE/shape");   blocks "$out" && ok "wrong shape blocks"     || bad "shape: $out"
out=$(run "$HOOK" "$CLEAN" ALLIUM_BIN="$FAKE/slow" ALLIUM_CHECK_TIMEOUT=1)
{ blocks "$out" && grep -q 'timed out' <<< "$out"; } && ok "timeout blocks" || bad "timeout: $out"

out=$(run "$HOOK" "$CLEAN" ALLIUM_BIN="$FAKE/does-not-exist")
{ ! blocks "$out" && grep -q 'NOT being validated' <<< "$out"; } \
  && ok "missing CLI passes with a notice" || bad "missing CLI: $out"

BADPY="$TMP/badpy"; mkdir -p "$BADPY"
printf '#!/bin/sh\ncat >/dev/null\nexit 3\n' > "$BADPY/python3"; chmod +x "$BADPY/python3"
out=$(run "$HOOK" "$CLEAN" PATH="$BADPY:$PATH" ALLIUM_BIN="$FAKE/empty")
{ blocks "$out" && grep -q 'reader exit 3' <<< "$out"; } \
  && ok "a crashing report reader blocks (never fails open)" || bad "reader crash: $out"

echo "== ignored paths"
out=$(run "$HOOK" "$TMP/readme.md" ALLIUM_BIN="$FAKE/garbage"); [ -z "$out" ] && ok "non-.allium ignored" || bad "md: $out"
out=$(run "$HOOK" "$TMP/gone.allium" ALLIUM_BIN="$FAKE/garbage"); [ -z "$out" ] && ok "missing file ignored" || bad "gone: $out"

echo
echo "allium-check-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
