#!/bin/bash
# Self-test for scripts/detect-verify-command.sh (spec 007ba).
#
# Travels with the detector into every project, for the same reason test-core-machinery-guard.sh
# and test-pipeline-hooks.sh do: a rule whose test stays behind is a rule nobody can re-check
# where it actually runs.
#
#   bash scripts/test-detect-verify-command.sh
#
# Synthetic trees only — nothing here builds or runs a test project. What is under test is the
# DECISION (what would we run, and when do we decline), not the runner.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
DETECT="$DIR/detect-verify-command.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/detect-verify-test.$$")
PASS=0
FAIL=0

cleanup() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }

# $1 name · $2 expected line 1 (empty string = expect silence) · $3 project dir
expect_command() {
  actual=$(bash "$DETECT" "$3" 2>/dev/null | sed -n '1p')
  if [ "$actual" = "$2" ]; then ok "$1"; else bad "$1" "${2:-<silence>}" "${actual:-<silence>}"; fi
}

expect_line() {
  actual=$(bash "$DETECT" "$4" 2>/dev/null | sed -n "$2p")
  if [ "$actual" = "$3" ]; then ok "$1"; else bad "$1" "${3:-<empty>}" "${actual:-<empty>}"; fi
}

mkproj() { mkdir -p "$TMP/$1"; printf '%s' "$TMP/$1"; }
mkcsproj() { mkdir -p "$(dirname "$1")"; printf '<Project Sdk="Microsoft.NET.Sdk" />\n' > "$1"; }
mkpkg() { mkdir -p "$(dirname "$1")"; printf '{ "name": "x", "scripts": { "test": "%s" } }\n' "$2" > "$1"; }

printf 'detect-verify-command self-test\n'

# --------------------------------------------------------------- .NET selection
P=$(mkproj unit-wins)
mkcsproj "$P/src/App/App.csproj"
mkcsproj "$P/tests/App.Tests.Unit/App.Tests.Unit.csproj"
mkcsproj "$P/tests/App.Tests.Integration/App.Tests.Integration.csproj"
mkcsproj "$P/tests/App.Tests.E2E/App.Tests.E2E.csproj"
expect_command "unit-named project wins over integration and e2e" \
  "dotnet test tests/App.Tests.Unit/App.Tests.Unit.csproj --nologo" "$P"
expect_line "…and says where it came from" 2 \
  "unit test project: tests/App.Tests.Unit/App.Tests.Unit.csproj" "$P"
expect_line "…and carries an evidence pattern" 3 \
  '(Passed!|Failed!|Total tests|Passed:[[:space:]]*[0-9])' "$P"

P=$(mkproj sole-test-project)
mkcsproj "$P/src/App/App.csproj"
mkcsproj "$P/tests/App.Tests/App.Tests.csproj"
expect_command "a single test project is unambiguous even without 'unit' in the name" \
  "dotnet test tests/App.Tests/App.Tests.csproj --nologo" "$P"

P=$(mkproj two-equal)
mkcsproj "$P/tests/App.Tests/App.Tests.csproj"
mkcsproj "$P/tests/Other.Tests/Other.Tests.csproj"
expect_command "two equally plausible suites derive nothing" "" "$P"

P=$(mkproj two-unit)
mkcsproj "$P/tests/A.Tests.Unit/A.Tests.Unit.csproj"
mkcsproj "$P/tests/B.Tests.Unit/B.Tests.Unit.csproj"
expect_command "two unit-named suites derive nothing either" "" "$P"

P=$(mkproj no-tests)
mkcsproj "$P/src/App/App.csproj"
expect_command "a project with no test project derives nothing" "" "$P"

P=$(mkproj sln-only)
mkcsproj "$P/src/App/App.csproj"
printf 'Microsoft Visual Studio Solution File\n' > "$P/App.sln"
expect_command "never the solution — it exits 0 on a solution with no test project (M1)" "" "$P"

# The path says "testing", the filenames do not. A rule reading the path would derive here.
P=$(mkproj path-not-filename)
mkcsproj "$P/testing/App/App.csproj"
expect_command "'test' in a directory name is not a test project" "" "$P"

# --------------------------------------------------------------- pruning
P=$(mkproj vendored)
mkcsproj "$P/tests/App.Tests.Unit/App.Tests.Unit.csproj"
mkcsproj "$P/node_modules/pkg/Bad.Tests.csproj"
mkcsproj "$P/src/App/obj/Debug/Ghost.Tests.csproj"
mkcsproj "$P/StrykerOutput/run/Mutant.Tests.csproj"
expect_command "vendored and generated trees are pruned, not counted" \
  "dotnet test tests/App.Tests.Unit/App.Tests.Unit.csproj --nologo" "$P"

# --------------------------------------------------------------- node
P=$(mkproj node-only)
mkpkg "$P/package.json" "vitest run"
expect_command "a package.json test script is a human's declaration" "npm --prefix . test" "$P"
expect_line "…and ships NO evidence pattern, because a human wrote it" 3 "" "$P"

P=$(mkproj node-nested)
mkpkg "$P/web/client/package.json" "jest"
expect_command "a nested package.json is found and prefixed" "npm --prefix web/client test" "$P"

P=$(mkproj node-placeholder)
mkpkg "$P/package.json" 'echo \"Error: no test specified\" && exit 1'
expect_command "npm's placeholder is not a test command" "" "$P"

P=$(mkproj node-no-script)
mkdir -p "$P"; printf '{ "name": "x", "scripts": { "build": "vite build" } }\n' > "$P/package.json"
expect_command "a package.json with no test script derives nothing" "" "$P"

P=$(mkproj node-two)
mkpkg "$P/a/package.json" "vitest run"
mkpkg "$P/b/package.json" "jest"
expect_command "two test scripts derive nothing" "" "$P"

P=$(mkproj node-playwright)
mkpkg "$P/package.json" "playwright test"
expect_command "a browser suite is not derived — it fails without a server and reads as known-bad" "" "$P"
N=$(bash "$DETECT" "$P" --candidates 2>/dev/null | grep -c 'browser suite')
if [ "$N" -eq 1 ]; then ok "…but it is named as a candidate, so the decline is actionable"
else bad "…but it is named as a candidate" "1 line" "$N lines"; fi

P=$(mkproj node-playwright-and-unit)
mkpkg "$P/e2e/package.json" "playwright test"
mkpkg "$P/app/package.json" "vitest run"
expect_command "a browser suite does not make a real unit suite ambiguous" "npm --prefix app test" "$P"

# --------------------------------------------------------------- precedence
P=$(mkproj both-stacks)
mkcsproj "$P/tests/App.Tests.Unit/App.Tests.Unit.csproj"
mkpkg "$P/client/package.json" "vitest run"
expect_command ".NET beats node — the sync rewrites what the backend suite covers" \
  "dotnet test tests/App.Tests.Unit/App.Tests.Unit.csproj --nologo" "$P"

# --------------------------------------------------------------- --candidates
P=$(mkproj candidates)
mkcsproj "$P/tests/A.Tests/A.Tests.csproj"
mkcsproj "$P/tests/B.Tests/B.Tests.csproj"
N=$(bash "$DETECT" "$P" --candidates 2>/dev/null | grep -c 'test project:')
if [ "$N" -eq 2 ]; then ok "--candidates names what it refused to choose between"
else bad "--candidates names what it refused to choose between" "2 lines" "$N lines"; fi

# --------------------------------------------------------------- robustness
P=$(mkproj malformed-json)
mkdir -p "$P"; printf '{ this is not json\n' > "$P/package.json"
expect_command "a malformed package.json is silence, not a crash" "" "$P"

expect_command "a nonexistent root is silence, not a crash" "" "$TMP/does-not-exist"

RC=$(bash "$DETECT" "$TMP/does-not-exist" >/dev/null 2>&1; echo $?)
if [ "$RC" -eq 0 ]; then ok "always exits 0 — a detector must never break a session start"
else bad "always exits 0" "0" "$RC"; fi

# Writes nothing. A detector that dirties a tree at session start is its own incident.
P=$(mkproj writes-nothing)
mkcsproj "$P/tests/App.Tests.Unit/App.Tests.Unit.csproj"
BEFORE=$(find "$P" | LC_ALL=C sort | cksum)
bash "$DETECT" "$P" >/dev/null 2>&1
AFTER=$(find "$P" | LC_ALL=C sort | cksum)
if [ "$BEFORE" = "$AFTER" ]; then ok "the detector writes nothing"
else bad "the detector writes nothing" "$BEFORE" "$AFTER"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
