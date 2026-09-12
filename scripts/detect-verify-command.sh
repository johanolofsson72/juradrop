#!/bin/bash
# Derive the command that would prove a project still works, for spec 007at's verification
# obligation. Spec 007ba.
#
# 007at gives every project an obligation and a reminder that repeats at every session start
# until something discharges it. Discharging needs .claude/.template-sync-verify — and when
# 007ba was written, 42 projects carried the obligation and exactly ONE carried the declaration.
# The other 41 received, forever, a reminder whose only available response was a config chore.
#
# So: derive one. Echoes THREE lines, or nothing at all:
#
#   1  the command          dotnet test tests/X.Tests.Unit/X.Tests.Unit.csproj --nologo
#   2  the provenance       unit test project: tests/X.Tests.Unit/X.Tests.Unit.csproj
#   3  the evidence pattern (Passed!|Failed!|Total tests)      — may be EMPTY, see below
#
# Usage: detect-verify-command.sh [project-root] [--candidates]
#        --candidates   list what was found and rejected as ambiguous, one per line
#
# WHY LINE 3 EXISTS. A derived command is one nobody chose, so it is not allowed to discharge an
# obligation merely by exiting 0 — and it must not be, because exiting 0 proves nothing:
#
#   dotnet test <solution with no test project>  → exit 0, no test ran, nothing says so
#   dotnet test <test project with no [Fact]>    → exit 0, "No test is available" printed
#
# Both measured (007ba research.md M1, M2). template-sync-verify.sh therefore requires line 3's
# pattern in the run's output before a DERIVED command may discharge anything. Line 3 is empty
# when the command came from a human's own words (a package.json "test" script) — the evidence
# rule governs guesses, not declarations.
#
# WHY IT NEVER WRITES. The sync derives .claude/.sync-stack and writes it; this deliberately does
# not write .claude/.template-sync-verify. A stack keyword is a fact about a project; a command is
# an instruction that will be executed, and a guessed file that reads as declared destroys the one
# signal meaning "a human chose this". Re-derivation costs 70-357 ms (M5), so persistence would
# buy nothing but staleness.
#
# Executes nothing — it reads filenames and, at most, one package.json. The only thing that ever
# runs the command is template-sync-verify.sh, on an explicit human invocation.
#
# Silence is a valid answer, and the common one: 27 of the 42 projects measured are ambiguous
# (two or more test suites, or none at all) and get their candidates named rather than a guess.
# Same contract as detect-stack.sh, for the same reason — a detector that guesses under ambiguity
# is worse than one that declines.
#
# bash 3.2-safe, cross-platform. Never fails loudly; prints nothing when unsure.

set -u

ROOT=""
CANDIDATES=0
for arg in "$@"; do
  case "$arg" in
    --candidates) CANDIDATES=1 ;;
    -h|--help)
      awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
      exit 0 ;;
    -*) ;;   # an unknown flag is not worth a word: this must never break a caller
    *) [ -z "$ROOT" ] && ROOT="$arg" ;;
  esac
done
ROOT="${ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[ -d "$ROOT" ] || exit 0

# -prune, not -not -path. Filtering descends into node_modules/bin/obj/StrykerOutput and throws
# the results away afterwards; on the largest tree measured that cost 2238 ms against 357 ms for
# pruning (M5). This runs on the session-start path, so the difference is the whole feasibility
# of deriving on demand rather than caching an answer that could go stale.
_find() {
  find "$ROOT" \
    \( -name node_modules -o -name .git -o -name bin -o -name obj -o -name dist \
       -o -name build -o -name worktrees -o -name StrykerOutput -o -name TestResults \
       -o -name .venv -o -name vendor \) -prune \
    -o -maxdepth "$1" -name "$2" -print 2>/dev/null
}

# Relative to the project root, always. The command is run from there, and an absolute path would
# additionally bake one machine's layout into a string another machine reads out of a reminder.
# The root itself is "." — `${ROOT#$ROOT/}` does not strip it, there being no trailing slash.
rel() {
  case "$1" in
    "$ROOT") printf '.' ;;
    *) printf '%s' "${1#$ROOT/}" ;;
  esac
}

# ----------------------------------------------------------------- .NET candidates
# Matched on the FILENAME, never the path: ~/repos/testing/App.csproj is not a test project, and
# a rule that reads the directory would decide it was.
TEST_PROJECTS=$(_find 4 '*.csproj' | awk -F/ 'tolower($NF) ~ /test/' | LC_ALL=C sort)
N_TESTS=$(printf '%s\n' "$TEST_PROJECTS" | grep -c .)

UNIT_PROJECTS=$(printf '%s\n' "$TEST_PROJECTS" | awk -F/ 'NF && tolower($NF) ~ /unit/')
N_UNIT=$(printf '%s\n' "$UNIT_PROJECTS" | grep -c .)

# The vstest verdict. A run that printed none of these selected nothing, whatever it exited with.
DOTNET_EVIDENCE='(Passed!|Failed!|Total tests|Passed:[[:space:]]*[0-9])'

emit_dotnet() {
  printf 'dotnet test %s --nologo\n' "$(rel "$1")"
  printf '%s: %s\n' "$2" "$(rel "$1")"
  printf '%s\n' "$DOTNET_EVIDENCE"
  exit 0
}

# ----------------------------------------------------------------- node candidates
# scripts.test in package.json is a sentence a human wrote about their own project. Deferring to
# it is reading a declaration that happens to live in another file — which is why it ships with an
# EMPTY evidence pattern while a composed `dotnet test` does not.
read_test_script() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(((json.load(f).get("scripts") or {}).get("test") or "").strip())
except Exception:
    pass
PY
  else
    # Good enough for a well-formed one-line entry, and silent on anything else. A project whose
    # package.json defeats this gets the candidates arm, which is the safe direction.
    sed -n 's/.*"test"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1
  fi
}

is_placeholder() {
  # npm's generated stub: `echo "Error: no test specified" && exit 1`. Deriving from it would fail
  # on every run and stamp every branch known-bad — a lie in the other direction, and it poisons
  # the same reminder.
  case "$1" in *"no test specified"*) return 0 ;; *) return 1 ;; esac
}

needs_infrastructure() {
  # A browser harness needs a running server, a database and a downloaded browser, so it fails for
  # environmental reasons on a machine that has none of them — and a failed verification does not
  # say "unchecked", it stamps the branch result=failed, which reads as KNOWN BAD. Reporting a
  # healthy project as broken poisons this reminder exactly as thoroughly as a false green does.
  #
  # Measured, not hypothetical: of 22 projects this detector derived for, three (ighweld-2026,
  # noisycricket-joucbox, noisycricket-www) have a single package.json whose test script is
  # `playwright test`. A human did write it — but as the test command of an E2E package, not as
  # their project's regression command, and this cannot tell the difference. So it declines and
  # names the candidate instead.
  case "$1" in
    *playwright*|*cypress*|*webdriver*|*selenium*|*puppeteer*) return 0 ;;
    *) return 1 ;;
  esac
}

NODE_DIR=""
NODE_SCRIPT=""
N_NODE=0
NODE_REJECTED=""
for pj in $(_find 3 'package.json'); do
  script=$(read_test_script "$pj")
  [ -n "$script" ] || continue
  is_placeholder "$script" && continue
  if needs_infrastructure "$script"; then
    NODE_REJECTED="$pj"
    continue
  fi
  N_NODE=$((N_NODE + 1))
  NODE_DIR=$(dirname "$pj")
  NODE_SCRIPT="$script"
done

# ----------------------------------------------------------------- --candidates
if [ "$CANDIDATES" -eq 1 ]; then
  printf '%s\n' "$TEST_PROJECTS" | grep . | head -5 | while IFS= read -r p; do
    printf 'test project: %s\n' "$(rel "$p")"
  done
  [ "$N_NODE" -gt 0 ] && printf 'package.json test script: %s (%s)\n' "$NODE_SCRIPT" "$(rel "$NODE_DIR")"
  # Named even though it was refused: the developer may well want it, and "we found this and
  # would not choose it for you" is the actionable half of a decline.
  [ -n "$NODE_REJECTED" ] && printf 'browser suite (needs a server, not derived): %s\n' "$(rel "$NODE_REJECTED")"
  exit 0
fi

# ----------------------------------------------------------------- the decision
#
# .NET before node when both exist. Not taste: the sync rewrites scripts/, .claude/rules/ and
# .claude/settings.json, and in every project measured the tests covering that machinery live in
# the backend unit suite — msroute's own TemplateSync*Tests are in MSRoute.Tests.Unit. The one
# human declaration in existence was written on a project that has both, and chose the .NET one.
#
# Never the solution, however tempting the coverage: `dotnet test <sln>` on a solution holding no
# test project exits 0 having run nothing (M1), and on one that does hold them it drags in the
# integration and E2E suites, which want a server, a browser and a database — so it would fail
# environmentally and report a healthy project as known-bad.

if [ "$N_UNIT" -eq 1 ]; then
  emit_dotnet "$UNIT_PROJECTS" "unit test project"
fi

if [ "$N_TESTS" -eq 1 ]; then
  emit_dotnet "$TEST_PROJECTS" "only test project"
fi

if [ "$N_NODE" -eq 1 ]; then
  printf 'npm --prefix %s test\n' "$(rel "$NODE_DIR")"
  printf 'package.json scripts.test: %s\n' "$NODE_SCRIPT"
  printf '\n'   # empty evidence pattern — a human wrote this command, FR-008 does not apply
  exit 0
fi

# Two or more equally plausible suites, or none at all. Choosing between someone else's unit,
# integration and E2E projects is an opinion about their test topology, which 007at ruled out and
# this keeps out. The caller says what was found instead.
exit 0
