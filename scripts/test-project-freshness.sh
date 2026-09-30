#!/bin/bash
# Self-test for scripts/project-freshness.sh — the deps walk and its filters (spec 007bj).
#
# Travels with the script into every project, for the same reason test-detect-verify-command.sh
# and test-core-machinery-guard.sh do: a filter whose test stays behind is a filter nobody can
# re-check where it actually runs.
#
#   bash scripts/test-project-freshness.sh
#
# What is under test is the DECISION — which manifests does the walk hand to npm audit, and does
# it say so out loud — not npm's verdict about any of them. So no fixture gets a lockfile: the
# script prints `package: <rel>` before it checks for one, which is exactly the line that records
# the decision. npm is therefore never invoked, nothing touches the network, and the suite runs in
# under a second. Every run passes --deps --no-install so trufflehog is never invoked or installed.
#
# H1/F-03 is the failure this exists to prevent recurring: a dead agent worktree's package.json
# audited as if it were the live app, reported under the same basename, with the "high severity"
# belonging to a checkout twelve days dead.
#
# bash 3.2-safe (macOS system bash): no associative arrays, no mapfile, no ${var,,}.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
FRESH="$DIR/project-freshness.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/project-freshness-test.$$")
PASS=0
FAIL=0

cleanup() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }

# Run the real script in a fixture and capture everything it says. osv-scanner and dotnet
# point at paths that do not exist unless a case overrides them, so the suite does not depend
# on what this machine has installed and never reaches the network.
NO_BIN="$TMP/no-such-bin"
OSV_UNDER_TEST="$NO_BIN/osv-scanner"
DOTNET_UNDER_TEST="$NO_BIN/dotnet"
run() {
  ( cd "$1" && FRESHNESS_OSV_SCANNER="$OSV_UNDER_TEST" FRESHNESS_DOTNET="$DOTNET_UNDER_TEST" \
      bash "$FRESH" --deps --no-install 2>&1 )
}

# A stub binary: prints $2 and exits $3. Each call is logged, so a case can assert the
# arguments the script actually passed. Assertions match path suffixes, not $P: the script
# roots at `git rev-parse --show-toplevel`, which resolves /var to /private/var on macOS.
mkstub() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho "$0 $*" >> "%s.calls"\nprintf "%%s\\n" "%s"\nexit %s\n' "$1" "$2" "$3" > "$1"
  chmod +x "$1"
}

# $1 name · $2 expected count · $3 output
expect_pkg_count() {
  actual=$(printf '%s\n' "$3" | grep -c '^  package: ')
  actual=$(printf '%s' "$actual" | tr -d ' ')
  if [ "$actual" = "$2" ]; then ok "$1"; else bad "$1" "$2 audited manifest(s)" "$actual"; fi
}

# $1 name · $2 substring that must appear · $3 output
expect_contains() {
  if grep -Fq -- "$2" <<< "$3"; then ok "$1"; else bad "$1" "output contains '$2'" "not found"; fi
}

# $1 name · $2 substring that must NOT appear · $3 output
expect_absent() {
  if grep -Fq -- "$2" <<< "$3"; then bad "$1" "output does NOT contain '$2'" "found"; else ok "$1"; fi
}

mkpkg() { mkdir -p "$(dirname "$1")"; printf '{ "name": "%s", "version": "1.0.0" }\n' "$2" > "$1"; }
mkrepo() {
  mkdir -p "$TMP/$1"
  ( cd "$TMP/$1" && git init -q . >/dev/null 2>&1 )
  printf '%s' "$TMP/$1"
}

printf 'project-freshness self-test (deps walk + filters, key-shape scan)\n'

# ---------------------------------------------- C1 — the dead agent worktree (H1 F-03 itself)
#
# There are two filters and they are deliberately not equally loud:
#
#   - The `find` path exclusions (node_modules, dist, build, bin, obj, .claude/worktrees) are
#     STRUCTURAL and silent. They always were — nobody wants four hundred skip lines for
#     node_modules — and a transient agent worktree is scratch space by definition, so the
#     right report is simply the live app with no commentary.
#   - The `git check-ignore` oracle is PROJECT-SPECIFIC and loud. What a given repo chooses to
#     ignore can surprise the reader, so every manifest it declines is named with its reason.
#
# So this case asserts the OUTCOME (one manifest, the right one) and NOT a skip line — the
# worktree never reaches the loop to be reported on. C2 is where the loud path is exercised.
# If you came here to "fix" the missing skip line, read the division above first.
printf '\n  -- C1  a dead agent worktree is not this project (silent, structural filter)\n'
P=$(mkrepo worktree)
mkpkg "$P/src/App/ClientApp/package.json" live
mkpkg "$P/.claude/worktrees/agent-dead/src/App/ClientApp/package.json" dead
printf '.claude/worktrees/\n' > "$P/.gitignore"
OUT=$(run "$P")
expect_pkg_count "exactly one manifest is audited" 1 "$OUT"
expect_contains  "…and it is the live app, labelled by relative path" \
  "package: src/App/ClientApp/package.json" "$OUT"
expect_absent    "…the worktree copy never reaches the audit" \
  "package: .claude/worktrees" "$OUT"
expect_absent    "…and its CVEs are not attributed to the live app's label" \
  "agent-dead" "$OUT"

# ------------------------------------------- C2/C3 — the Stryker sandbox (3 fleet repos), loudly
# The same failure shape as the worktree, produced by this project's OWN mutation gate: a full
# copy of the app tree under a path no exclusion list named. This is the case the ignore oracle
# exists for, so it is also where "skips are reported, never silent" is proven.
printf '\n  -- C2/C3  a Stryker sandbox is not this project either (loud, ignore oracle)\n'
P=$(mkrepo stryker)
mkpkg "$P/client/package.json" live
mkpkg "$P/client/.stryker-tmp/sandbox-a1b2/package.json" sandbox
printf '.stryker-tmp/\n' > "$P/.gitignore"
OUT=$(run "$P")
expect_pkg_count "exactly one manifest is audited" 1 "$OUT"
expect_contains  "…and it is the live client" "package: client/package.json" "$OUT"
expect_absent    "…the sandbox never reaches the audit" "package: client/.stryker-tmp" "$OUT"
expect_contains  "the skip names the path it declined" \
  "client/.stryker-tmp/sandbox-a1b2/package.json" "$OUT"
expect_contains  "…and gives the reason, so it is not a silent filter" "gitignored" "$OUT"
expect_contains  "…and offers the by-hand escape route" "npm audit" "$OUT"
expect_contains  "the summary accounts for what it skipped" "+1 gitignored, skipped" "$OUT"

# ------------------------------------------------------------- C4 — no git, the filter goes inert
# The path exclusions must keep working with no git at all, and the ignore filter must not
# suppress anything it cannot have an opinion about. The banner assertion proves the fixture is
# really rootless rather than silently resolving to some parent repository.
printf '\n  -- C4  without git the filter is inert, not restrictive\n'
P="$TMP/nogit"
mkdir -p "$P"
mkpkg "$P/src/App/ClientApp/package.json" live
mkpkg "$P/.claude/worktrees/agent-dead/other/package.json" dead
printf '.claude/worktrees/\n' > "$P/.gitignore"
OUT=$(run "$P")
expect_contains  "the fixture really is the root (no parent repo leaked in)" \
  "project-freshness — $P" "$OUT"
expect_pkg_count "the path exclusion still holds without git" 1 "$OUT"
expect_contains  "…and the live app is audited" "package: src/App/ClientApp/package.json" "$OUT"
expect_absent    "…nothing is attributed to a gitignore nobody could read" "gitignored" "$OUT"

# ---------------------------------------------------- C5 — untracked is not ignored (new project)
# A project with nothing committed must still be audited. check-ignore is non-zero for
# untracked-but-not-ignored, which is the whole reason this filter is safe to add.
printf '\n  -- C5  a brand-new project with nothing committed is still audited\n'
P=$(mkrepo fresh)
mkpkg "$P/package.json" brand-new
OUT=$(run "$P")
expect_pkg_count "the untracked manifest is audited" 1 "$OUT"
expect_absent    "…and not mistaken for ignored" "gitignored" "$OUT"

# ------------------------------------------- C6 — two manifests, one basename (the other half of F-03)
# No exclusion list can fix this one: both are legitimately the project's. The label has to carry
# the path, or the summary says "web/" twice and means two different things.
printf '\n  -- C6  same basename, different packages, distinguishable anyway\n'
P=$(mkrepo monorepo)
mkpkg "$P/apps/web/package.json" app-web
mkpkg "$P/packages/web/package.json" lib-web
OUT=$(run "$P")
expect_pkg_count "both are audited" 2 "$OUT"
expect_contains  "the app is named by its path" "package: apps/web/package.json" "$OUT"
expect_contains  "the library is named by its path" "package: packages/web/package.json" "$OUT"

# ------------------------------ C7 — "found none" and "declined all" are different sentences
# The regression guarded here is a comforting one: a summary that says "not a Node project" when
# the walk actually found manifests and skipped every one of them reads as full coverage.
printf '\n  -- C7  all-ignored does not report as "not a Node project"\n'
P=$(mkrepo allignored)
mkpkg "$P/.claude/worktrees/agent-x/client/package.json" dead1
mkpkg "$P/vendored/thing/package.json" dead2
printf '.claude/worktrees/\nvendored/\n' > "$P/.gitignore"
OUT=$(run "$P")
expect_pkg_count "nothing is audited" 0 "$OUT"
expect_contains  "the summary says none were auditable" "no auditable package.json" "$OUT"
expect_absent    "…and does not claim this is not a Node project" "not a Node project" "$OUT"
expect_absent    "…and does not report deps as clean" "npm:     clean" "$OUT"

# ------------------------------------------------------------- C8 — a manifest at the repo root
printf '\n  -- C8  a manifest at the root labels as ./\n'
P=$(mkrepo rootpkg)
mkpkg "$P/package.json" root-app
OUT=$(run "$P")
expect_pkg_count "it is audited" 1 "$OUT"
expect_contains  "…and labelled without an absolute prefix" "package: package.json" "$OUT"

# ------------------------------------------------------ C9 — node_modules still excluded by path
# Regression guard on the pre-existing exclusions: the new filter must not have replaced them.
printf '\n  -- C9  the pre-existing path exclusions survive\n'
P=$(mkrepo nodemods)
mkpkg "$P/package.json" app
mkpkg "$P/node_modules/left-pad/package.json" dep
mkpkg "$P/dist/package.json" built
mkpkg "$P/obj/package.json" built2
OUT=$(run "$P")
expect_pkg_count "only the project's own manifest is audited" 1 "$OUT"
expect_absent    "node_modules is not walked" "left-pad" "$OUT"

# --------------------------------------------------- C10 — an npm workspaces member is covered
#
# A member has no lockfile of its own by design: the root holds one lockfile and one
# node_modules for the whole tree, and `npm audit` at the root covers every member. The
# pass used to report each member as "No lockfile — run 'npm install' in <dir>", which is
# both a false unscanned-package report AND harmful advice — that command creates a nested
# lockfile and breaks the hoisting the workspace depends on. Measured on fundit: eight
# members, eight SKIPs, and a red verdict on a tree that had been fully audited.
printf '\n  -- C10 an npm workspaces member is covered by its root, not reported unscanned\n'
P=$(mkrepo workspaces)
mkpkg "$P/src/web/package.json" web-root
# Make the root a workspaces root WITH a lockfile; members deliberately get neither.
printf '{ "name": "web-root", "version": "1.0.0", "workspaces": ["packages/*"] }\n' > "$P/src/web/package.json"
printf '{ "name": "web-root", "lockfileVersion": 3, "packages": {} }\n' > "$P/src/web/package-lock.json"
mkpkg "$P/src/web/packages/ui/package.json" ui
mkpkg "$P/src/web/packages/api/package.json" api
# A stub npm, because the walk stops at the first package when npm is missing and never reaches
# the members — so without one this case measured whether the machine had Node, not the member
# logic. It passed on every Mac and failed in the Linux container (spec 073, test-on-linux.sh).
NPM_STUB_DIR="$TMP/npm-stub"; mkstub "$NPM_STUB_DIR/npm" '{"vulnerabilities":{},"metadata":{"vulnerabilities":{"total":0}}}' 0
OUT=$(PATH="$NPM_STUB_DIR:$PATH" run "$P")
expect_contains "the member is reported as covered by its root" "npm workspaces member" "$OUT"
expect_absent   "…and is NOT told to run npm install in itself" \
                "run 'npm install' in $P/src/web/packages/ui" "$OUT"

# The sabotage arm: a lockfile-less package that is NOT under a workspaces root must still
# be reported. Without this, "covered" could be returned for everything and read as a pass.
printf '\n  -- C10 a lone lockfile-less package is still reported\n'
P=$(mkrepo lonepkg)
mkpkg "$P/client/package.json" lonely
OUT=$(run "$P")
expect_contains "it is still skipped for want of a lockfile" "No lockfile" "$OUT"
expect_absent   "…and is not claimed to be a workspaces member" "npm workspaces member" "$OUT"

# ---------------------------------------------- C11 — osv-scanner absent: loud skip, not clean
printf '\n  -- C11 osv-scanner missing is a loud one-line skip, and the summary repeats it\n'
P=$(mkrepo noosv)
mkpkg "$P/package.json" app
OUT=$(run "$P"); RC=$?
expect_contains "the skip line names what went unscanned" \
  "[skip] osv-scanner not installed — NuGet/pub/Maven/Gradle/Cargo/Go/pip lockfiles unscanned; install:" "$OUT"
expect_contains "the summary does not call it clean" "OSV:     SKIPPED" "$OUT"
if [ "$RC" -eq 0 ]; then ok "…and it fails open (exit 0)"; else bad "…and it fails open (exit 0)" "0" "$RC"; fi

# ------------------------------------------ C12 — osv-scanner verdicts map onto its exit codes
printf '\n  -- C12 osv-scanner exit codes: 0 clean, 1 finding, 128 nothing to scan, other = error\n'
P=$(mkrepo osv)
mkpkg "$P/package.json" app
OSV_UNDER_TEST="$TMP/stubs/osv0/osv-scanner"; mkstub "$OSV_UNDER_TEST" "No issues found" 0
OUT=$(run "$P"); RC=$?
expect_contains "exit 0 reads as clean" "OSV:     clean" "$OUT"
expect_contains "…and it was called as a recursive source scan" "scan source -r " \
  "$(cat "$OSV_UNDER_TEST.calls" 2>/dev/null)"
if [ "$RC" -eq 0 ]; then ok "…and the pass stays green"; else bad "…and the pass stays green" "0" "$RC"; fi
OSV_UNDER_TEST="$TMP/stubs/osv1/osv-scanner"; mkstub "$OSV_UNDER_TEST" "GHSA-xxxx NuGet Newtonsoft.Json" 1
OUT=$(run "$P"); RC=$?
expect_contains "exit 1 is a finding" "[FINDING] osv-scanner reported vulnerabilities" "$OUT"
if [ "$RC" -eq 1 ]; then ok "…and the pass exits 1"; else bad "…and the pass exits 1" "1" "$RC"; fi
OSV_UNDER_TEST="$TMP/stubs/osv128/osv-scanner"; mkstub "$OSV_UNDER_TEST" "No package sources found" 128
OUT=$(run "$P")
expect_contains "exit 128 is 'nothing to scan', not clean" "OSV:     no lockfiles found" "$OUT"
OSV_UNDER_TEST="$TMP/stubs/osv127/osv-scanner"; mkstub "$OSV_UNDER_TEST" "boom" 127
OUT=$(run "$P"); RC=$?
expect_contains "any other exit is an error that verified nothing" "ERROR (exit 127)" "$OUT"
if [ "$RC" -eq 0 ]; then ok "…and a tool error is not a vulnerability finding"; else bad "…and a tool error is not a vulnerability finding" "0" "$RC"; fi
OSV_UNDER_TEST="$NO_BIN/osv-scanner"

# ----------------------------------------------- C13 — dotnet: solution first, text verdicts
printf '\n  -- C13 dotnet list package --vulnerable over the solution, not each project\n'
P=$(mkrepo dotnet)
mkdir -p "$P/src/App" "$P/tests/App.Tests"
: > "$P/App.sln"; : > "$P/src/App/App.csproj"; : > "$P/tests/App.Tests/App.Tests.csproj"
DOTNET_UNDER_TEST="$TMP/stubs/dn-clean/dotnet"
mkstub "$DOTNET_UNDER_TEST" "The given project App has no vulnerable packages given the current sources." 0
OUT=$(run "$P"); RC=$?
CALLS=$(cat "$DOTNET_UNDER_TEST.calls" 2>/dev/null)
expect_contains "the solution is the target" "/App.sln package --vulnerable --include-transitive" "$CALLS"
expect_absent   "…and its projects are not listed a second time" "App.csproj" "$CALLS"
expect_contains "no vulnerable packages reads as clean" ".NET:    clean" "$OUT"
if [ "$RC" -eq 0 ]; then ok "…and the pass stays green"; else bad "…and the pass stays green" "0" "$RC"; fi

DOTNET_UNDER_TEST="$TMP/stubs/dn-vuln/dotnet"
mkstub "$DOTNET_UNDER_TEST" "Project App has the following vulnerable packages" 0
OUT=$(run "$P"); RC=$?
expect_contains "the text verdict is a finding even though dotnet exits 0" \
  "[FINDING] vulnerable NuGet packages in App.sln" "$OUT"
if [ "$RC" -eq 1 ]; then ok "…and the pass exits 1"; else bad "…and the pass exits 1" "1" "$RC"; fi

DOTNET_UNDER_TEST="$TMP/stubs/dn-norestore/dotnet"
mkstub "$DOTNET_UNDER_TEST" "No assets file was found for App.csproj. Please run restore." 1
OUT=$(run "$P")
expect_contains "an unrestored solution is unscanned, not clean" ".NET:    unscanned — restore first" "$OUT"

printf '\n  -- C13 loose projects are targets only when there is no solution\n'
P=$(mkrepo loosecsproj)
mkdir -p "$P/src/Api"; : > "$P/src/Api/Api.csproj"
mkdir -p "$P/src/Api/bin/Debug"; : > "$P/src/Api/bin/Debug/Copy.csproj"
DOTNET_UNDER_TEST="$TMP/stubs/dn-loose/dotnet"
mkstub "$DOTNET_UNDER_TEST" "has no vulnerable packages" 0
OUT=$(run "$P")
CALLS=$(cat "$DOTNET_UNDER_TEST.calls" 2>/dev/null)
expect_contains "the loose project is listed" "/loosecsproj/src/Api/Api.csproj package" "$CALLS"
expect_absent   "…and bin/ output is not" "Copy.csproj" "$CALLS"

# ------------------------------------------ C14 — dotnet missing / no .NET project, said plainly
printf '\n  -- C14 a .NET project without dotnet is a named skip; no .NET project is silent-ish\n'
P=$(mkrepo nodotnet)
: > "$P/App.sln"
DOTNET_UNDER_TEST="$NO_BIN/dotnet"
OUT=$(run "$P")
expect_contains "missing dotnet is reported as unscanned" ".NET:    SKIPPED — dotnet not installed" "$OUT"
P=$(mkrepo notdotnet)
mkpkg "$P/package.json" app
OUT=$(run "$P")
expect_contains "a Node-only project says it is not .NET" ".NET:    no .NET project" "$OUT"

# ------------------------------- C15–C20 — dependency coverage: no manifest is silently unchecked
# Spec 070 (ekofak H1): a Maven backend was never audited and the report read as complete. The
# coverage pass lists every non-npm, non-.NET manifest as covered by osv-scanner or as a named
# [SKIP] … no auditor, and an unchecked one keeps RESULT from saying clean.
printf '\n  -- C15 a Maven backend without osv-scanner is named, counted and NOT SCANNED\n'
P=$(mkrepo maven)
mkdir -p "$P/backend" "$P/backend/target/classes/META-INF/maven"
printf '<project/>\n' > "$P/backend/pom.xml"
printf '<project/>\n' > "$P/backend/target/classes/META-INF/maven/pom.xml"
OSV_UNDER_TEST="$NO_BIN/osv-scanner"
OUT=$(run "$P"); RC=$?
expect_contains "SC-070-01 the backend manifest is a named skip" \
  "[SKIP] backend/pom.xml — no auditor: osv-scanner not installed" "$OUT"
expect_contains "…the summary counts it" "Other:   1 of 1 UNCHECKED — backend/pom.xml" "$OUT"
expect_contains "…RESULT says not scanned" "NOT SCANNED: deps(backend/pom.xml)" "$OUT"
expect_absent   "…never clean" "RESULT: clean" "$OUT"
expect_absent   "SC-070-06 Maven's target/ copy is not listed" "target/classes" "$OUT"
if [ "$RC" -eq 0 ]; then ok "…and unchecked is not a finding (exit 0)"; else bad "…and unchecked is not a finding (exit 0)" "0" "$RC"; fi
expect_contains "SC-070-07 the osv skip line names the JVM ecosystems" "Maven/Gradle" "$OUT"

printf '\n  -- C16 osv-scanner with a verdict covers pom.xml itself\n'
OSV_UNDER_TEST="$TMP/stubs/c16/osv-scanner"; mkstub "$OSV_UNDER_TEST" "No issues found" 0
OUT=$(run "$P")
expect_contains "SC-070-02 pom.xml is covered" "[OK] backend/pom.xml — osv-scanner (backend/pom.xml)" "$OUT"
expect_contains "…the summary says all covered" "Other:   all 1 covered by osv-scanner" "$OUT"
expect_contains "…and RESULT is clean" "RESULT: clean" "$OUT"
mkpkg "$P/package.json" app
: > "$P/build.gradle"
OSV_UNDER_TEST="$TMP/stubs/c16b/osv-scanner"; mkstub "$OSV_UNDER_TEST" "GHSA-xxxx" 1
OUT=$(run "$P")
expect_contains "…findings elsewhere do not hide the unchecked manifest" \
  "Also NOT SCANNED: deps(./build.gradle)" "$OUT"
OSV_UNDER_TEST="$TMP/stubs/c16/osv-scanner"

printf '\n  -- C17 build.gradle needs a lockfile osv-scanner reads\n'
P=$(mkrepo gradle)
mkdir -p "$P/app"; : > "$P/app/build.gradle.kts"; : > "$P/settings.gradle.kts"
OUT=$(run "$P")
expect_contains "SC-070-03 a lockless Gradle build is unchecked even with osv present" \
  "[SKIP] app/build.gradle.kts — no auditor: no lockfile osv-scanner reads" "$OUT"
expect_contains "…with the lock command" "--write-locks" "$OUT"
expect_contains "…and RESULT says not scanned" "NOT SCANNED" "$OUT"
mkdir -p "$P/gradle"; : > "$P/gradle/verification-metadata.xml"
OUT=$(run "$P")
expect_contains "…the root verification metadata covers it" \
  "[OK] app/build.gradle.kts — osv-scanner (gradle/verification-metadata.xml)" "$OUT"

printf '\n  -- C18 a workspace member is covered by the root lockfile\n'
P=$(mkrepo cargo)
mkdir -p "$P/crates/core"; : > "$P/Cargo.toml"; : > "$P/crates/core/Cargo.toml"; : > "$P/Cargo.lock"
OUT=$(run "$P")
expect_contains "SC-070-04 the member finds the ancestor lock" \
  "[OK] crates/core/Cargo.toml — osv-scanner (Cargo.lock)" "$OUT"
expect_contains "…the root is labelled ./" "[OK] ./Cargo.toml — osv-scanner (Cargo.lock)" "$OUT"
expect_contains "…both counted" "Other:   all 2 covered by osv-scanner" "$OUT"

printf '\n  -- C19 osv-scanner without a verdict covers nothing\n'
P=$(mkrepo osverr)
: > "$P/go.mod"; mkdir -p "$P/ignored"; : > "$P/ignored/requirements.txt"; printf 'ignored/\n' > "$P/.gitignore"
OSV_UNDER_TEST="$TMP/stubs/c19/osv-scanner"; mkstub "$OSV_UNDER_TEST" "boom" 127
OUT=$(run "$P")
expect_contains "SC-070-05 an errored scanner vouches for nothing" \
  "[SKIP] ./go.mod — no auditor: osv-scanner gave no verdict (exit 127)" "$OUT"
expect_absent   "…a gitignored manifest is not listed" "ignored/requirements.txt" "$OUT"

printf '\n  -- C20 no such manifests: one quiet line, nothing unscanned\n'
P=$(mkrepo nomanifests)
mkpkg "$P/package.json" app
OSV_UNDER_TEST="$NO_BIN/osv-scanner"
OUT=$(run "$P")
expect_contains "SC-070-07 none found" "Other:   none found" "$OUT"
expect_absent   "…and no deps() not-scanned entry" "deps(" "$OUT"
expect_contains "SC-070-08 the npm verdict is labelled npm" "npm:     " "$OUT"
expect_absent   "…not Deps" "Deps:    " "$OUT"
expect_contains "…and the headers count six passes" "[6/6] dependency coverage" "$OUT"

printf '\n  -- C21 sabotage: the tests bite\n'
SAB="$TMP/sabotage"; mkdir -p "$SAB"
# Arm 1: osv present counts as covered, lockfile or not.
awk '/# sabotage:lockfile-rule:start/{print; print "    lock=\"$m\""; skip=1; next} /# sabotage:lockfile-rule:end/{skip=0} !skip' \
  "$FRESH" > "$SAB/arm1.sh"
# Arm 2: an unchecked manifest no longer joins NOT_SCANNED.
awk '/# sabotage:not-scanned-join:start/{print; skip=1; next} /# sabotage:not-scanned-join:end/{skip=0} !skip' \
  "$FRESH" > "$SAB/arm2.sh"
sabrun() { ( cd "$2" && FRESHNESS_OSV_SCANNER="$OSV_UNDER_TEST" FRESHNESS_DOTNET="$DOTNET_UNDER_TEST" \
    bash "$1" --deps --no-install 2>&1 ); }
if cmp -s "$FRESH" "$SAB/arm1.sh" || cmp -s "$FRESH" "$SAB/arm2.sh"; then
  bad "sabotage markers exist" "both arms change the script" "a marker is missing"
else
  P=$(mkrepo sab1); : > "$P/build.gradle"
  OSV_UNDER_TEST="$TMP/stubs/c21/osv-scanner"; mkstub "$OSV_UNDER_TEST" "No issues found" 0
  SABOUT=$(sabrun "$SAB/arm1.sh" "$P")
  if grep -Fq "[SKIP] ./build.gradle — no auditor: no lockfile" <<< "$SABOUT"; then
    bad "arm 1 (lockfile rule dropped) turns C17 red" "the SKIP line disappears" "still there"
  else ok "arm 1 (lockfile rule dropped) turns C17 red"; fi
  P=$(mkrepo sab2); : > "$P/pom.xml"
  OSV_UNDER_TEST="$NO_BIN/osv-scanner"
  SABOUT=$(sabrun "$SAB/arm2.sh" "$P")
  if grep -Fq "NOT SCANNED: deps(./pom.xml)" <<< "$SABOUT"; then
    bad "arm 2 (NOT_SCANNED join dropped) turns C15 red" "RESULT loses NOT SCANNED" "still there"
  else ok "arm 2 (NOT_SCANNED join dropped) turns C15 red"; fi
fi
OSV_UNDER_TEST="$NO_BIN/osv-scanner"

# =============================================================================================
# Key-shape scan (spec 023). trufflehog --only-verified cannot see a key that no provider will
# answer for; this arm finds it by shape. Every fixture is built here at runtime: no key-shaped
# bytes are committed to the template, so the template's own scan stays clean.
#
# SENTINEL is the "key bytes". It must never appear in any output (FR-06): a report gets pasted
# into chats and PR comments, and must not become the leak. Every key-scan output is collected in
# ALL_KEY_OUT and checked once at the end.
# =============================================================================================
TH_UNDER_TEST="$NO_BIN/trufflehog"
ALL_KEY_OUT=""
runk() {
  ( cd "$1" && FRESHNESS_TRUFFLEHOG="$TH_UNDER_TEST" FRESHNESS_OSV_SCANNER="$OSV_UNDER_TEST" \
      FRESHNESS_DOTNET="$DOTNET_UNDER_TEST" bash "$FRESH" ${2:---secrets} --no-install 2>&1; echo "EXIT=$?" )
}
keyscan() { OUT=$(runk "$@"); ALL_KEY_OUT="$ALL_KEY_OUT
$OUT"; }
commit_all() {
  ( cd "$1" && git add -A && git -c user.name=t -c user.email=t@example.invalid \
      -c commit.gpgsign=false commit -qm "${2:-fixture}" >/dev/null 2>&1 )
}
SENT='SENTINEL+KEY/BYT'   # 16 characters, and it exercises + and /
LINE64="$SENT$SENT$SENT$SENT"
BODY="$LINE64
$LINE64
$LINE64"
M5='-----'
# $1 type prefix ("RSA ", "", "ENCRYPTED ", "OPENSSH ") · $2 body
pem() { printf '%sBEGIN %sPRIVATE KEY%s\n%s\n%sEND %sPRIVATE KEY%s\n' "$M5" "$1" "$M5" "$2" "$M5" "$1" "$M5"; }
dpkey() {  # $1 = plain | encrypted
  printf '<?xml version="1.0" encoding="utf-8"?>\n<key id="d51365dc-16f0-4e2a-918c-df1fef2bdb34" version="1">\n  <descriptor><descriptor>\n'
  if [ "$1" = plain ]; then
    printf '    <masterKey p4:requiresEncryption="true" xmlns:p4="http://schemas.asp.net/2015/03/dataProtection">\n      <value>%s</value>\n    </masterKey>\n' "$LINE64"
  else
    printf '    <masterKey><encryptedSecret decryptorType="X"><EncryptedData>%s</EncryptedData></encryptedSecret></masterKey>\n' "$LINE64"
  fi
  printf '  </descriptor></descriptor>\n</key>\n'
}
GUIDXML='key-d51365dc-16f0-4e2a-918c-df1fef2bdb34.xml'
expect_exit() { if grep -q "^EXIT=$2\$" <<< "$3"; then ok "$1"; else bad "$1" "EXIT=$2" "$(grep '^EXIT=' <<< "$3")"; fi; }

printf '\n  -- K1  a plaintext Data Protection key untracked at HEAD is still a FINDING (the filed case)\n'
P=$(mkrepo k1); mkdir -p "$P/src/Web/keys"; dpkey plain > "$P/src/Web/keys/$GUIDXML"
printf 'x\n' > "$P/README"; commit_all "$P" add-key
( cd "$P" && git rm -q --cached "src/Web/keys/$GUIDXML" && printf 'src/Web/keys/\n' > .gitignore ); commit_all "$P" untrack
keyscan "$P"
expect_contains "the key ring is found in history" "[FINDING] src/Web/keys/$GUIDXML — ASP.NET Data Protection key (plaintext master key) — history only" "$OUT"
expect_contains "…with the commit that added it" "added " "$OUT"
expect_contains "…the remedy is rotation, not untracking" "Untracking does not un-leak a key" "$OUT"
expect_contains "…and the DP-specific step" "delete the key ring" "$OUT"
expect_contains "the SUMMARY has a Keys line" "Keys:    1 KEY FILE(S) FOUND" "$OUT"
expect_exit     "a key FINDING exits 1" 1 "$OUT"
expect_contains "trufflehog is missing in this run…" "Secrets: skipped (trufflehog unavailable)" "$OUT"
expect_contains "…and the key scan ran anyway" "[2/6] key-shape scan" "$OUT"

printf '\n  -- K2  an encrypted-at-rest key ring is a NOTE, not a finding\n'
P=$(mkrepo k2); mkdir -p "$P/keys"; dpkey encrypted > "$P/keys/$GUIDXML"; commit_all "$P"
keyscan "$P"
expect_contains "encrypted ring is a NOTE at HEAD" "[NOTE] keys/$GUIDXML — ASP.NET Data Protection key (encrypted at rest) — at HEAD" "$OUT"
expect_contains "…counted in the summary" "Keys:    clean, 1 note(s)" "$OUT"
expect_exit     "…and does not fail the pass" 0 "$OUT"

printf '\n  -- K3  PEM bodies pasted into config and code (JSON / C# escapes)\n'
P=$(mkrepo k3); mkdir -p "$P/src"
ESC=$(pem "RSA " "$BODY" | awk '{ printf "%s\\n", $0 }')
printf '{ "Signing": { "Pem": "%s" } }\n' "$ESC" > "$P/src/appsettings.json"
printf 'var k = "%s";\n' "$(pem "" "$BODY" | awk '{ printf "%s\\n", $0 }')" > "$P/src/Keys.cs"
commit_all "$P"
keyscan "$P"
expect_contains "RSA key in JSON with \\n escapes" "[FINDING] src/appsettings.json — PEM private key (RSA) — at HEAD" "$OUT"
expect_contains "PKCS#8 key in a C# string" "[FINDING] src/Keys.cs — PEM private key (PKCS#8) — at HEAD" "$OUT"
expect_exit     "…exit 1" 1 "$OUT"

printf '\n  -- K4  passphrase-encrypted PEM (PKCS#8 ENCRYPTED and RFC 1421 Proc-Type) is a NOTE\n'
P=$(mkrepo k4)
pem "ENCRYPTED " "$BODY" > "$P/a.pem"
printf '%sBEGIN RSA PRIVATE KEY%s\nProc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,0011\n\n%s\n%sEND RSA PRIVATE KEY%s\n' "$M5" "$M5" "$BODY" "$M5" "$M5" > "$P/b.key"
commit_all "$P"
keyscan "$P"
expect_contains "PKCS#8 ENCRYPTED is a NOTE" "[NOTE] a.pem — PEM private key (passphrase-encrypted)" "$OUT"
expect_contains "Proc-Type ENCRYPTED is a NOTE" "[NOTE] b.key — PEM private key (passphrase-encrypted)" "$OUT"
expect_exit     "…exit 0" 0 "$OUT"

printf '\n  -- K5  OpenSSH: cipher none is a FINDING, anything else a NOTE\n'
P=$(mkrepo k5); mkdir -p "$P/deploy"
OSSH_NONE="b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAM$SENT"
OSSH_AES="b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAA$SENT"
pem "OPENSSH " "$OSSH_NONE
$BODY" > "$P/deploy/id_ed25519"
pem "OPENSSH " "$OSSH_AES
$BODY" > "$P/deploy/id_rsa"
commit_all "$P"
keyscan "$P"
expect_contains "unencrypted OpenSSH key" "[FINDING] deploy/id_ed25519 — OpenSSH private key (no passphrase)" "$OUT"
expect_contains "encrypted OpenSSH key" "[NOTE] deploy/id_rsa — OpenSSH private key (passphrase-encrypted)" "$OUT"
# The prefix constant is only as good as its agreement with ssh-keygen. Check it against the real
# tool when there is one (macOS, Linux and Git for Windows all ship it); skip, loudly, when not.
if command -v ssh-keygen >/dev/null 2>&1; then
  P=$(mkrepo k5real)
  ssh-keygen -q -t ed25519 -N '' -C t -f "$P/id_ed25519" >/dev/null 2>&1
  ssh-keygen -q -t ed25519 -N 'pw' -C t -f "$P/other_ed25519" >/dev/null 2>&1
  mv "$P/other_ed25519" "$P/id_ecdsa"; rm -f "$P"/*.pub; commit_all "$P"
  OUT=$(runk "$P")   # real key bytes: kept out of ALL_KEY_OUT, checked for leakage right here
  expect_contains "a real ssh-keygen key without passphrase is a FINDING" "[FINDING] id_ed25519 — OpenSSH private key (no passphrase)" "$OUT"
  expect_contains "a real one with a passphrase is a NOTE" "[NOTE] id_ecdsa — OpenSSH private key (passphrase-encrypted)" "$OUT"
  REALLINE=$(sed -n 2p "$P/id_ed25519")
  expect_absent "…and not one line of the real key reaches the output" "$REALLINE" "$OUT"
else
  printf '  skip real ssh-keygen check (ssh-keygen not installed)\n'
fi

printf '\n  -- K6  PKCS#12 is a FINDING by name, any case, without reading it\n'
P=$(mkrepo k6); mkdir -p "$P/Certificate"
printf 'binary\000stuff' > "$P/Certificate/site.PFX"; printf 'x' > "$P/sign.p12"; commit_all "$P"
keyscan "$P"
expect_contains ".PFX (upper case)" "[FINDING] Certificate/site.PFX — PKCS#12 bundle" "$OUT"
expect_contains ".p12" "[FINDING] sign.p12 — PKCS#12 bundle" "$OUT"

printf '\n  -- K7  negatives: public cert, marker-only fixture, empty template, prose\n'
P=$(mkrepo k7); mkdir -p "$P/Administration" "$P/tests" "$P/docs"
printf '%sBEGIN CERTIFICATE%s\n%s\n%sEND CERTIFICATE%s\n' "$M5" "$M5" "$BODY" "$M5" "$M5" > "$P/Administration/cert.pem"
printf '[InlineData("%sBEGIN RSA PRIVATE KEY%s", "private key block")]\nvar s = "a b c d e f g h i j k l m n o p q r s t u v w x y z a b c d e f g h i j k l m n o p q r s t u v w x y z a b c d e f g h i j k l m n o p";\n' "$M5" "$M5" > "$P/tests/ScannerTests.cs"
printf '[InlineData("%sBEGIN RSA PRIVATE KEY%s and then a long run of ordinary words that are not base64 at all but go on and on for well over one hundred and twenty characters")]\n' "$M5" "$M5" > "$P/tests/Prose.cs"
printf '{ "type": "service_account", "private_key_id": "", "private_key": "", "client_email": "" }\n' > "$P/Credentials.json"
printf 'The ring holds <masterKey> and, when protected, <encryptedSecret>.\n' > "$P/docs/dp.md"
commit_all "$P"
keyscan "$P"
expect_contains "nothing key-shaped: OK" "[OK] No key material in git history" "$OUT"
expect_absent   "the public certificate is not flagged" "cert.pem" "$OUT"
expect_absent   "the marker-only fixture is not flagged" "ScannerTests.cs" "$OUT"
expect_absent   "marker + prose is not a key body" "Prose.cs" "$OUT"
expect_absent   "prose naming the DP elements is not a key ring" "dp.md" "$OUT"
expect_exit     "…exit 0" 0 "$OUT"

printf '\n  -- K8  the 60-character body boundary (Ed25519 PKCS#8 is 64), counted in 40+ tokens\n'
P=$(mkrepo k8)
T60="${LINE64%????}"   # 60 base64 characters
T59="${T60%?}"
T39="${T60%?????????????????????}"
pem "EC " "$T59" > "$P/under.pem"
pem "EC " "$T60" > "$P/at.pem"
pem "EC " "$T39 $T39 $T39" > "$P/short-tokens.pem"
commit_all "$P"
keyscan "$P"
expect_absent   "59 body characters is not a key" "under.pem" "$OUT"
expect_contains "60 is" "[FINDING] at.pem — PEM private key (EC)" "$OUT"
expect_absent   "tokens under 40 characters never add up to a key" "short-tokens.pem" "$OUT"

printf '\n  -- K9  one key at three paths, spaces included, is three lines\n'
P=$(mkrepo k9); mkdir -p "$P/App/My Project/~BROMIUM" "$P/App/~BROMIUM"
printf 'pfx' > "$P/App/Temp Key.pfx"; cp "$P/App/Temp Key.pfx" "$P/App/My Project/~BROMIUM/Temp Key.pfx"
cp "$P/App/Temp Key.pfx" "$P/App/~BROMIUM/Temp Key.pfx"; commit_all "$P"
keyscan "$P"
expect_contains "path 1" "[FINDING] App/Temp Key.pfx" "$OUT"
expect_contains "path 2 (spaces)" "[FINDING] App/My Project/~BROMIUM/Temp Key.pfx" "$OUT"
expect_contains "path 3" "[FINDING] App/~BROMIUM/Temp Key.pfx" "$OUT"
expect_contains "…counted as three" "Keys:    3 KEY FILE(S) FOUND" "$OUT"

printf '\n  -- K10 a key changed many times is one line; worst verdict wins\n'
P=$(mkrepo k10)
pem "ENCRYPTED " "$BODY" > "$P/svc.key"; commit_all "$P" v1
pem "" "$BODY" > "$P/svc.key"; commit_all "$P" v2
pem "ENCRYPTED " "$BODY" > "$P/svc.key"; commit_all "$P" v3
keyscan "$P"
C=$(grep -c 'svc.key' <<< "$OUT" | tr -d ' ')
if [ "$C" = 1 ]; then ok "one line for the path"; else bad "one line for the path" 1 "$C"; fi
# The plaintext version is in history; HEAD holds the encrypted one. Location is per blob.
expect_contains "…and it is the FINDING, located in history, not at HEAD" "[FINDING] svc.key — PEM private key (PKCS#8) — history only (the path is tracked; this content is not at HEAD; added " "$OUT"

printf '\n  -- K11 untracked-not-ignored is a candidate; ignored is not\n'
P=$(mkrepo k11); printf 'x\n' > "$P/README"; printf 'secrets/\n' > "$P/.gitignore"; commit_all "$P"
mkdir -p "$P/secrets"; pem "RSA " "$BODY" > "$P/about-to-commit.pem"; pem "RSA " "$BODY" > "$P/secrets/ignored.pem"
keyscan "$P"
expect_contains "untracked key" "[FINDING] about-to-commit.pem — PEM private key (RSA) — untracked (not ignored)" "$OUT"
expect_absent   "ignored key stays out" "ignored.pem" "$OUT"

printf '\n  -- K12 .secret-shapes-allow: a reason allows, no reason is ignored and named\n'
P=$(mkrepo k12); mkdir -p "$P/tests/fixtures"
pem "RSA " "$BODY" > "$P/tests/fixtures/throwaway.pem"; pem "RSA " "$BODY" > "$P/real.pem"
printf '# fixtures\n\ntests/fixtures/*.pem   # generated for the parser tests, never deployed\nreal.pem\n' > "$P/.secret-shapes-allow"
commit_all "$P"
keyscan "$P"
expect_contains "allowed hit is printed with its reason" "[ALLOWED] tests/fixtures/throwaway.pem — PEM private key (RSA) — at HEAD — generated for the parser tests, never deployed" "$OUT"
expect_contains "a line with no reason is named by number" "[WARN] .secret-shapes-allow:4 has no '# reason'" "$OUT"
expect_contains "…and does not allow" "[FINDING] real.pem" "$OUT"
expect_contains "the summary counts the allowed one" "Keys:    1 KEY FILE(S) FOUND — rotate now, 1 allowed" "$OUT"
( cd "$P" && git rm -q real.pem ); commit_all "$P" drop
( cd "$P" && printf 'tests/fixtures/*.pem  # fixtures\nreal.pem  # rotated 2026-09-29, purge pending\n' > .secret-shapes-allow ); commit_all "$P" allow
keyscan "$P"
expect_contains "a rotated history-only key can be allowed" "[ALLOWED] real.pem — PEM private key (RSA) — history only" "$OUT"
expect_contains "…and the pass is clean with the allowances counted" "Keys:    clean, 2 allowed" "$OUT"
expect_exit     "…exit 0" 0 "$OUT"

printf '\n  -- K13 outside git: the working tree is scanned\n'
P="$TMP/k13"; mkdir -p "$P/cfg" "$P/node_modules/x"
pem "" "$BODY" > "$P/cfg/signing.txt"; pem "" "$BODY" > "$P/node_modules/x/k.pem"
keyscan "$P"
expect_contains "a key in a plain directory" "[FINDING] cfg/signing.txt — PEM private key (PKCS#8) — working tree" "$OUT"
expect_absent   "node_modules is structural noise" "node_modules" "$OUT"

printf '\n  -- K14 padding a key past 1 MiB does not hide it (no size gate; the classifier streams)\n'
P=$(mkrepo k14)
{ LC_ALL=C awk 'BEGIN { for (i = 0; i < 17000; i++) print "# padding padding padding padding padding padding padding padding" }'; pem "" "$BODY"; LC_ALL=C awk 'BEGIN { for (i = 0; i < 17000; i++) print "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" }'; } > "$P/huge.key"
commit_all "$P"
keyscan "$P"
expect_contains "a padded key is still a FINDING" "[FINDING] huge.key — PEM private key (PKCS#8)" "$OUT"

printf '\n  -- K15 a binary key-named file is a NOTE\n'
P=$(mkrepo k15); printf '\060\202\004\275\002\001\000\060\015' > "$P/der.key"; commit_all "$P"
keyscan "$P"
expect_contains "DER is named for a human" "[NOTE] der.key — binary key-named file, not PEM" "$OUT"

printf '\n  -- K16 trufflehog wording and scope flags\n'
P=$(mkrepo k16); printf 'x\n' > "$P/README"; commit_all "$P"
TH_UNDER_TEST="$TMP/stubs/th/trufflehog"; mkstub "$TH_UNDER_TEST" "" 0
keyscan "$P"
expect_contains "a clean trufflehog says verified credentials, not secrets" "Secrets: no verified credentials" "$OUT"
expect_contains "…and points at the key pass" "provider-checkable tokens only; key files: next pass" "$OUT"
expect_contains "the stub was the binary that ran" "git file://" "$(cat "$TH_UNDER_TEST.calls" 2>/dev/null)"
expect_contains "both clean: the RESULT names both" "no verified credentials, no committed key material" "$OUT"
TH_UNDER_TEST="$NO_BIN/trufflehog"
keyscan "$P" --deps
expect_contains "--deps does not run the key scan" "Keys:    not run (--deps)" "$OUT"
expect_absent   "…nor print its section" "[2/6] key-shape" "$OUT"

printf '\n  -- K18 escapes and prefixes: +, \/, CRLF, commented-out body lines\n'
P=$(mkrepo k18); mkdir -p "$P/cfg"
J=$(pem "" "$BODY" | awk '{ printf "%s\\n", $0 }' | sed 's|+|\\u002B|g; s|/|\\/|g')
printf '{ "Key": "%s" }\n' "$J" > "$P/cfg/dotnet.json"
pem "RSA " "$BODY" | sed 's/$/\r/' > "$P/cfg/crlf.txt"
pem "EC " "$BODY" | sed 's/^/# /' > "$P/cfg/commented.sh"
commit_all "$P"
keyscan "$P"
expect_contains "System.Text.Json \\u002B and PHP \\/ are decoded" "[FINDING] cfg/dotnet.json — PEM private key (PKCS#8)" "$OUT"
expect_contains "CRLF" "[FINDING] cfg/crlf.txt — PEM private key (RSA)" "$OUT"
expect_contains "a body behind '# ' prefixes is still a body" "[FINDING] cfg/commented.sh — PEM private key (EC)" "$OUT"

printf '\n  -- K19 base64-wrapped PEM (a Kubernetes Secret); a wrapped certificate is not a key\n'
P=$(mkrepo k19); mkdir -p "$P/k8s"
printf 'data:\n  tls.key: %s\n' "$(pem "" "$BODY" | base64 | tr -d '\n')" > "$P/k8s/secret.yaml"
printf 'data:\n  ca.crt: %s\n' "$(printf '%sBEGIN CERTIFICATE%s\n%s\n%sEND CERTIFICATE%s\n' "$M5" "$M5" "$BODY" "$M5" "$M5" | base64 | tr -d '\n')" > "$P/k8s/ca.yaml"
commit_all "$P"
keyscan "$P"
expect_contains "base64 of a private-key PEM" "[FINDING] k8s/secret.yaml — base64-encoded PEM private key" "$OUT"
expect_absent   "base64 of a certificate" "ca.yaml" "$OUT"

printf '\n  -- K20 PGP and PuTTY key formats\n'
P=$(mkrepo k20)
printf '%sBEGIN PGP PRIVATE KEY BLOCK%s\nVersion: x\n\n%s\n=abcd\n%sEND PGP PRIVATE KEY BLOCK%s\n' "$M5" "$M5" "$BODY" "$M5" "$M5" > "$P/signing.asc"
printf 'PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none\nComment: x\nPublic-Lines: 2\n%s\nPrivate-Lines: 1\n%s\n' "$LINE64" "$LINE64" > "$P/deploy.ppk"
printf 'PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: aes256-cbc\nComment: x\nPublic-Lines: 2\n%s\nPrivate-Lines: 1\n%s\n' "$LINE64" "$LINE64" > "$P/locked.ppk"
commit_all "$P"
keyscan "$P"
expect_contains "PGP secret key" "[FINDING] signing.asc — PGP private key block" "$OUT"
expect_contains "PuTTY without passphrase" "[FINDING] deploy.ppk — PuTTY private key (no passphrase)" "$OUT"
expect_contains "PuTTY with one" "[NOTE] locked.ppk — PuTTY private key (passphrase-encrypted)" "$OUT"

printf '\n  -- K21 a header that merely says ENCRYPTED does not downgrade a plaintext key\n'
P=$(mkrepo k21)
printf '%sBEGIN RSA PRIVATE KEY%s\nComment: ENCRYPTED\n\n%s\n%sEND RSA PRIVATE KEY%s\n' "$M5" "$M5" "$BODY" "$M5" "$M5" > "$P/liar.pem"
commit_all "$P"
keyscan "$P"
expect_contains "Comment: ENCRYPTED is not Proc-Type" "[FINDING] liar.pem — PEM private key (RSA)" "$OUT"

printf '\n  -- K22 a key scrubbed from a tracked file is history, and so is a renamed key'"'"'s old name\n'
P=$(mkrepo k22); mkdir -p "$P/src"
printf '{ "Key": "%s" }\n' "$(pem "" "$BODY" | awk '{ printf "%s\\n", $0 }')" > "$P/src/appsettings.json"; commit_all "$P" paste
printf '{ "Key": "" }\n' > "$P/src/appsettings.json"; commit_all "$P" scrub
pem "" "$BODY" > "$P/secret.txt"; commit_all "$P" add
( cd "$P" && git mv secret.txt notes.txt ); commit_all "$P" rename
keyscan "$P"
expect_contains "scrubbed paste: history, path still tracked" "[FINDING] src/appsettings.json — PEM private key (PKCS#8) — history only (the path is tracked; this content is not at HEAD; added " "$OUT"
expect_contains "renamed key: found at its new name, at HEAD" "[FINDING] notes.txt — PEM private key (PKCS#8) — at HEAD" "$OUT"
expect_contains "…and at its old one, as history" "[FINDING] secret.txt — PEM private key (PKCS#8) — history only (untracked at HEAD" "$OUT"

printf '\n  -- K23 staged but not committed\n'
P=$(mkrepo k23); printf 'x\n' > "$P/README"; commit_all "$P"
pem "" "$BODY" > "$P/new.key"; ( cd "$P" && git add new.key )
keyscan "$P"
expect_contains "a staged key" "[FINDING] new.key — PEM private key (PKCS#8) — staged, not committed" "$OUT"

printf '\n  -- K24 odd names: non-ASCII, tab, a leading dash, "=", a control character, a directory named .pfx\n'
P=$(mkrepo k24); mkdir -p "$P/nyckelr"$'\303\245'"d" "$P/bundle.pfx"
pem "" "$BODY" > "$P/nyckelr"$'\303\245'"d/"$'\303\266'"ppen.pem"
pem "" "$BODY" > "$P/tab"$'\t'"name.pem"
printf 'not a key\n' > "$P/bundle.pfx/readme.txt"
commit_all "$P"
pem "" "$BODY" > "$P/-q.pem"; pem "" "$BODY" > "$P/-x.txt"; pem "" "$BODY" > "$P/a=b.txt"; pem "" "$BODY" > "$P/esc"$'\033'"[2K.pem"
keyscan "$P"
expect_contains "non-ASCII tracked path, at HEAD" "[FINDING] nyckelr"$'\303\245'"d/"$'\303\266'"ppen.pem — PEM private key (PKCS#8) — at HEAD" "$OUT"
expect_contains "a tab in a path does not shift the verdict (shown as ?)" "[FINDING] tab?name.pem — PEM private key (PKCS#8) — at HEAD" "$OUT"
expect_contains "an untracked '-q.pem' is a file, not a grep option" "[FINDING] -q.pem" "$OUT"
expect_contains "an untracked content-only '-x.txt' is a file, not a grep option" "[FINDING] -x.txt" "$OUT"
expect_contains "an untracked 'a=b.txt' is a file, not an awk assignment" "[FINDING] a=b.txt" "$OUT"
expect_contains "an escape sequence in a name prints as ?" "[FINDING] esc?[2K.pem" "$OUT"
expect_absent   "…and never reaches the terminal raw" $'\033' "$OUT"
expect_absent   "a directory named bundle.pfx is not a key" "bundle.pfx" "$OUT"

printf '\n  -- K25 .gitattributes cannot switch the pickaxe off\n'
P=$(mkrepo k25); mkdir -p "$P/cfg"
printf '*.conf -diff\n' > "$P/.gitattributes"
pem "RSA " "$BODY" > "$P/cfg/app.conf"; commit_all "$P" add
printf 'scrubbed\n' > "$P/cfg/app.conf"; commit_all "$P" scrub
keyscan "$P"
expect_contains "a key in a -diff file's history" "[FINDING] cfg/app.conf — PEM private key (RSA) — history only" "$OUT"

printf '\n  -- K26 not scanned is not clean: a broken ref, a shallow clone\n'
P=$(mkrepo k26); printf 'x\n' > "$P/README"; commit_all "$P"
printf '0123456789012345678901234567890123456789\n' > "$P/.git/refs/heads/broken"
keyscan "$P"
expect_contains "the scan says it is incomplete" "[WARN] key-shape scan incomplete" "$OUT"
expect_contains "…the SUMMARY says so" "Keys:    INCOMPLETE" "$OUT"
expect_contains "…and RESULT does not say clean" "RESULT: no findings, but NOT SCANNED: trufflehog key-shape" "$OUT"
expect_absent   "…anywhere" "RESULT: clean" "$OUT"
P2="$TMP/k26shallow"
( cd "$TMP" && git clone -q --depth 1 "file://$(cd "$P" && git rev-parse --show-toplevel 2>/dev/null)" k26shallow >/dev/null 2>&1 ) \
  || git clone -q --depth 1 "file://$P" "$P2" >/dev/null 2>&1
rm -f "$P/.git/refs/heads/broken"
if [ -d "$P2/.git" ]; then
  keyscan "$P2"
  expect_contains "a shallow clone is named, not called clean" "shallow clone" "$OUT"
else
  printf '  skip shallow clone check (clone failed)\n'
fi

printf '\n  -- K27 a large text certificate bundle is not a "binary" NOTE; empty allow reason is refused\n'
P=$(mkrepo k27)
LC_ALL=C awk -v m="$M5" 'BEGIN { for (c = 0; c < 400; c++) { print m "BEGIN CERTIFICATE" m; for (i = 0; i < 10; i++) print "MIIDdzCCAl+gAwIBAgIEAgAAuTANBgkqhkiG9w0BAQUFADBaMQswCQYDVQQGEwJJ"; print m "END CERTIFICATE" m } }' > "$P/cacert.pem"
pem "" "$BODY" > "$P/k.pem"
printf 'k.pem  #   \n' > "$P/.secret-shapes-allow"
commit_all "$P"
keyscan "$P"
expect_absent   "a 250 KB text bundle is not called binary" "cacert.pem" "$OUT"
expect_contains "'#' followed by only spaces is no reason" "[WARN] .secret-shapes-allow:1 has no '# reason'" "$OUT"
expect_contains "…so the key is still a FINDING" "[FINDING] k.pem" "$OUT"

if command -v openssl >/dev/null 2>&1 && openssl genpkey -algorithm ed25519 -out /dev/null >/dev/null 2>&1; then
  printf '\n  -- K28 a real Ed25519 PKCS#8 key from openssl (64-character body)\n'
  P=$(mkrepo k28)
  openssl genpkey -algorithm ed25519 -out "$P/jwt-signing.pem" >/dev/null 2>&1; commit_all "$P"
  OUT=$(runk "$P")
  expect_contains "Ed25519 is found" "[FINDING] jwt-signing.pem — PEM private key (PKCS#8)" "$OUT"
  expect_absent   "…and its body line never printed" "$(sed -n 2p "$P/jwt-signing.pem")" "$OUT"
fi

# Spec 038. `--fail` exits 183 on results and trufflehog exits 1 when it cannot scan (a repo with
# no commits). Only 183 is a finding; any other non-zero exit is "could not scan", never clean.
# $1 path · $2 exit code · $3 line on stderr
mkthstub() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho "$0 $*" >> "%s.calls"\nprintf "%%s\\n" "%s" >&2\nexit %s\n' "$1" "$3" "$2" > "$1"
  chmod +x "$1"
}
printf '\n  -- K29 a trufflehog error is not a verified secret (spec 038)\n'
P=$(mkrepo k29); printf 'x\n' > "$P/README"; commit_all "$P"
NG="$TMP/k29-nogit"; mkdir -p "$NG"; printf 'x\n' > "$NG/README"
TH_UNDER_TEST="$TMP/stubs/th29/ok/trufflehog"; mkthstub "$TH_UNDER_TEST" 0 "finished scanning"
keyscan "$P"
expect_contains "SC-038-01 exit 0 is clean" "Secrets: no verified credentials" "$OUT"
expect_absent   "…and no finding" "[FINDING] trufflehog" "$OUT"
expect_contains "SC-038-06 the git call passes --fail-on-scan-errors" "--fail-on-scan-errors" "$(cat "$TH_UNDER_TEST.calls" 2>/dev/null)"
TH_UNDER_TEST="$TMP/stubs/th29/hit/trufflehog"; mkthstub "$TH_UNDER_TEST" 183 "verified_secrets: 1"
keyscan "$P"
expect_contains "SC-038-02 exit 183 is a finding" "[FINDING] trufflehog found verified secret(s)" "$OUT"
expect_contains "…in the SUMMARY" "Secrets: VERIFIED SECRET(S) FOUND" "$OUT"
expect_contains "…and exits 1" "EXIT=1" "$OUT"
TH_UNDER_TEST="$TMP/stubs/th29/err/trufflehog"; mkthstub "$TH_UNDER_TEST" 1 "error running scan: failed to read index file"
keyscan "$P"
expect_contains "SC-038-03 exit 1 could not scan" "[WARN] trufflehog could not scan (exit 1)" "$OUT"
expect_contains "…quotes trufflehog's reason" "failed to read index file" "$OUT"
expect_contains "…SUMMARY says scan failed" "Secrets: scan failed (exit 1)" "$OUT"
expect_contains "…RESULT says not scanned" "RESULT: no findings, but NOT SCANNED: trufflehog" "$OUT"
expect_absent   "…never a finding" "[FINDING] trufflehog" "$OUT"
expect_absent   "…never rotate" "otate" "$OUT"
expect_contains "…and exits 0" "EXIT=0" "$OUT"
keyscan "$NG"
expect_contains "SC-038-04 filesystem exit 1 could not scan" "[WARN] trufflehog could not scan (exit 1)" "$OUT"
expect_absent   "…never a finding" "[FINDING] trufflehog" "$OUT"
expect_contains "…the filesystem call ran" "filesystem" "$(cat "$TH_UNDER_TEST.calls" 2>/dev/null)"
TH_UNDER_TEST="$TMP/stubs/th29/hitfs/trufflehog"; mkthstub "$TH_UNDER_TEST" 183 "verified_secrets: 1"
keyscan "$NG"
expect_contains "SC-038-05 filesystem exit 183 is a finding" "[FINDING] trufflehog found verified secret(s)" "$OUT"
expect_contains "SC-038-06 the filesystem call passes --fail-on-scan-errors" "--fail-on-scan-errors" "$(cat "$TH_UNDER_TEST.calls" 2>/dev/null)"
if command -v trufflehog >/dev/null 2>&1; then
  P=$(mkrepo k29empty)
  TH_UNDER_TEST=$(command -v trufflehog)
  keyscan "$P"
  expect_contains "SC-038-07 real trufflehog, no commits: could not scan" "[WARN] trufflehog could not scan" "$OUT"
  expect_contains "…with the no-commits hint" "no commits yet" "$OUT"
  expect_absent   "…and no breach" "[FINDING] trufflehog" "$OUT"
fi
TH_UNDER_TEST="$NO_BIN/trufflehog"

printf '\n  -- K17 FR-06: no byte of any fixture key reaches any output\n'
expect_absent "the sentinel never appears" "$SENT" "$ALL_KEY_OUT"
expect_absent "…nor a 64-character body line" "$LINE64" "$ALL_KEY_OUT"

# ------------------------------------------------------------------------------- verdict
printf '\n%s\n' "----------------------------------------------------------"
printf 'project-freshness self-test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
