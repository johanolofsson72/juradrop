#!/usr/bin/env bash
#
# test-speckit-sync.sh — the spec-kit pin's own gate (spec 073).
#
# WHY THIS EXISTS. spec-kit was installed unpinned from `main` in three places, the wizard
# re-initialised on every run, and the policy script's "the stop is back" warning went to a stderr
# nobody read. speckit-sync.sh replaces all of that with one pin and one decision. This proves the
# decision: install only when the CLI differs, re-init only when the project differs, never touch
# a project without .specify/, keep the constitution, and pass the policy's exit 2 through.
#
# No network and no real spec-kit: `specify` and `uv` are stubs on PATH that record their calls.

set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="${TMPDIR:-/tmp}/speckit-sync-selftest.$$"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n         expected: %s\n         actual:   %s\n' "$1" "$2" "$3"; }
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/scripts"
cp "$SELF_DIR/speckit-sync.sh" "$SELF_DIR/speckit-extension-policy.sh" "$TMP/scripts/"
printf 'v9.9.9\n' > "$TMP/scripts/speckit-version"
CALLS="$TMP/calls"; : > "$CALLS"
CLI_STATE="$TMP/cli-version"; printf '1.0.2.dev0\n' > "$CLI_STATE"

# The stub writes what 1.0.x's init writes that matters here: init-options.json with the CLI's
# version, and the implement skill carrying the verbatim stop the policy has to find. STUB_REWORD
# makes it write reworded text instead, which is the shape of an upstream wording change.
cat > "$TMP/bin/specify" <<'STUB'
#!/usr/bin/env bash
ver=$(cat "$CLI_STATE")
case "$1" in
  --version) echo "specify $ver" ;;
  init)
    echo "init $*" >> "$CALLS"
    mkdir -p .specify/memory .claude/skills/speckit-implement
    printf '{"speckit_version": "%s", "script": "sh"}\n' "$ver" > .specify/init-options.json
    [ -n "${STUB_CLOBBER:-}" ] && echo "SPECKIT DEFAULT" > .specify/memory/constitution.md
    if [ -n "${STUB_REWORD:-}" ]; then
      echo "Ask the user whether to continue." > .claude/skills/speckit-implement/SKILL.md
    else
      printf '%s\n' '     - **STOP** and ask: "Some checklists have unchecked items. Do you want to proceed with implementation anyway? (yes/no)"' \
        '     - Wait for user response before continuing' \
        '     - If user says "no" or "wait" or "stop", halt execution' \
        '     - If user says "yes" or "proceed" or "continue", proceed to step 3' > .claude/skills/speckit-implement/SKILL.md
    fi ;;
esac
STUB
cat > "$TMP/bin/uv" <<'STUB'
#!/usr/bin/env bash
echo "uv $*" >> "$CALLS"
case "$*" in *spec-kit.git@v9.9.9*) echo "9.9.9" > "$CLI_STATE" ;; esac
STUB
chmod +x "$TMP/bin/specify" "$TMP/bin/uv"
export PATH="$TMP/bin:$PATH" CALLS CLI_STATE

mkproj() {
  d="$TMP/p-$1"; mkdir -p "$d"; ( cd "$d" && git init -q . )
  printf '%s\n' "$d"
}
run() { bash "$TMP/scripts/speckit-sync.sh" "$@" >"$TMP/out" 2>&1; echo $?; }

echo "speckit-sync.sh"

# 1. --check on an out-of-date CLI installs nothing and exits 3.
P=$(mkproj check)
rc=$(run --check --cli-only)
[ "$rc" = 3 ] && ! grep -q '^uv' "$CALLS" && ok "--check reports an out-of-date CLI and installs nothing" \
  || bad "--check" "rc 3, no uv call" "rc $rc; $(cat "$CALLS")"

# 2. The CLI is installed from the pinned tag, not from main.
rc=$(run --cli-only)
grep -q 'spec-kit.git@v9.9.9' "$CALLS" && [ "$rc" = 0 ] && ok "CLI installed from the pinned tag" \
  || bad "pinned install" "uv ... spec-kit.git@v9.9.9, rc 0" "rc $rc; $(cat "$CALLS")"

# 3. A second run is a no-op: no uv call.
: > "$CALLS"; rc=$(run --cli-only)
[ ! -s "$CALLS" ] && [ "$rc" = 0 ] && ok "CLI at the pin → no reinstall" || bad "cli no-op" "no calls" "$(cat "$CALLS")"

# 4. A project without .specify/ is left alone — and the CLI is not even looked at, so a repo that
#    does not run spec-kit neither fails on a machine without uv nor pays for an install.
P=$(mkproj plain); : > "$CALLS"; echo "0.0.1" > "$CLI_STATE"; rc=$(run --repo "$P")
[ ! -d "$P/.specify" ] && [ "$rc" = 0 ] && [ ! -s "$CALLS" ] && ok "no .specify/ → untouched, CLI not installed" \
  || bad "plain project" "no calls at all" "rc $rc; $(cat "$CALLS")"
echo "9.9.9" > "$CLI_STATE"

# 5. --init-new creates it, and the policy neutralises the stop.
rc=$(run --repo "$P" --init-new)
grep -q 'speckit-nostop' "$P/.claude/skills/speckit-implement/SKILL.md" 2>/dev/null && [ "$rc" = 0 ] \
  && ok "--init-new initialises and applies the policy" || bad "init-new" "patched skill, rc 0" "rc $rc; $(cat "$TMP/out")"

# 6. At the pin → no re-init (init is not idempotent).
: > "$CALLS"; rc=$(run --repo "$P")
! grep -q '^init' "$CALLS" && [ "$rc" = 0 ] && ok "project at the pin → no re-init" || bad "project no-op" "no init" "$(cat "$CALLS")"

# 7. An old project re-inits, and its constitution survives an init that overwrites it.
P=$(mkproj old); mkdir -p "$P/.specify/memory"
printf '{"speckit_version": "1.0.2.dev0", "script": "sh"}\n' > "$P/.specify/init-options.json"
echo "OUR CONSTITUTION" > "$P/.specify/memory/constitution.md"
rc=$(STUB_CLOBBER=1 run --repo "$P")
[ "$(cat "$P/.specify/memory/constitution.md")" = "OUR CONSTITUTION" ] && [ "$rc" = 0 ] \
  && ok "re-init keeps the constitution" || bad "constitution" "OUR CONSTITUTION" "$(cat "$P/.specify/memory/constitution.md"); rc $rc"

# 8. A reworded upstream stop is exit 2 and a visible FAIL line — never silent.
P=$(mkproj reword); mkdir -p "$P/.specify"
printf '{"speckit_version": "1.0.0", "script": "sh"}\n' > "$P/.specify/init-options.json"
rc=$(STUB_REWORD=1 run --repo "$P")
[ "$rc" = 2 ] && grep -q 'FAIL' "$TMP/out" && ok "moved anchor → exit 2 with a FAIL line" \
  || bad "moved anchor" "rc 2 + FAIL" "rc $rc; $(cat "$TMP/out")"

# 9. No pin → hard failure, not a silent unpinned install.
mv "$TMP/scripts/speckit-version" "$TMP/scripts/speckit-version.off"
rc=$(run --cli-only)
[ "$rc" = 1 ] && ok "missing pin → exit 1" || bad "missing pin" "rc 1" "rc $rc"
mv "$TMP/scripts/speckit-version.off" "$TMP/scripts/speckit-version"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
