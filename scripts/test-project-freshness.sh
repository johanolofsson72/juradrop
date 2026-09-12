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

# Run the real script in a fixture and capture everything it says.
run() { ( cd "$1" && bash "$FRESH" --deps --no-install 2>&1 ); }

# $1 name · $2 expected count · $3 output
expect_pkg_count() {
  actual=$(printf '%s\n' "$3" | grep -c '^  package: ')
  actual=$(printf '%s' "$actual" | tr -d ' ')
  if [ "$actual" = "$2" ]; then ok "$1"; else bad "$1" "$2 audited manifest(s)" "$actual"; fi
}

# $1 name · $2 substring that must appear · $3 output
expect_contains() {
  if grep -Fq "$2" <<< "$3"; then ok "$1"; else bad "$1" "output contains '$2'" "not found"; fi
}

# $1 name · $2 substring that must NOT appear · $3 output
expect_absent() {
  if grep -Fq "$2" <<< "$3"; then bad "$1" "output does NOT contain '$2'" "found"; else ok "$1"; fi
}

mkpkg() { mkdir -p "$(dirname "$1")"; printf '{ "name": "%s", "version": "1.0.0" }\n' "$2" > "$1"; }
mkrepo() {
  mkdir -p "$TMP/$1"
  ( cd "$TMP/$1" && git init -q . >/dev/null 2>&1 )
  printf '%s' "$TMP/$1"
}

printf 'project-freshness self-test (deps walk + filters)\n'

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
expect_absent    "…and does not report deps as clean" "Deps:    clean" "$OUT"

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
OUT=$(run "$P")
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

# ------------------------------------------------------------------------------- verdict
printf '\n%s\n' "----------------------------------------------------------"
printf 'project-freshness self-test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
