#!/bin/bash
# Self-test for scripts/project-maintenance.sh — the abandoned-agent-worktree section (spec 007bk).
#
# Travels with the script into every project, for the same reason test-project-freshness.sh and
# test-detect-verify-command.sh do: a report whose test stays behind is a report nobody can
# re-check where it actually runs.
#
#   bash scripts/test-project-maintenance.sh
#
# What is under test is the DECISION — which worktrees does the section call abandoned, what does
# it say about them, and does it still change nothing. Not the other five sections: every fixture
# gets a stub scripts/project-freshness.sh that exits 0, so the secrets/CVE pass is silent, and no
# fixture carries a manifest or a solution file, so the mutation section never arms. Nothing
# touches the network and the suite runs in about a second.
#
# C22-C25 cover section 2c (the SIGPIPE gate, row H7ax), which is likewise absent from every other
# fixture: the section is guarded on the gate script existing, so it stays silent for C1-C21 and speaks
# only for the four cases that plant a stub gate with a chosen exit code. What is under test there is
# the same kind of decision — which exit code becomes a finding, which stays silent, and whether a gate
# that could not run is ever allowed to read as a clean one.
#
# H1/F-04 is the failure this exists to prevent recurring: prune-agent-worktrees.sh existed the
# whole time and ran only when somebody remembered, while the fleet accumulated 7 abandoned
# worktrees, 733 MB, and 6 agent-memory files that existed nowhere else.
#
# The single most load-bearing case here is C8. This section reports on a destructive tool, and
# the moment it starts calling that tool it stops being a report — so C8 hashes the whole fixture
# before and after and fails on any difference at all.
#
# bash 3.2-safe (macOS system bash): no associative arrays, no mapfile, no ${var,,}.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
MAINT="$DIR/project-maintenance.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/project-maintenance-test.$$")
PASS=0
FAIL=0

cleanup() {
  # Registered worktrees inside the fixtures hold on after rm -rf; drop them first so the
  # temp dir actually goes away and nothing is left pointing into /var/folders.
  for wtrepo in "$TMP"/*; do
    [ -d "$wtrepo/.git" ] || continue
    ( cd "$wtrepo" && git worktree list --porcelain 2>/dev/null | awk '$1=="worktree"{print $2}' ) 2>/dev/null |
      while read -r w; do
        [ "$w" = "$wtrepo" ] && continue
        ( cd "$wtrepo" && git worktree unlock "$w" >/dev/null 2>&1; git worktree remove --force "$w" >/dev/null 2>&1 )
      done
  done
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}
trap cleanup EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }

# $1 name · $2 substring that must appear · $3 output
expect_contains() {
  if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else
    bad "$1" "output contains '$2'" "$(printf '%s' "$3" | tr '\n' '|')"; fi
}

# $1 name · $2 substring that must NOT appear · $3 output
expect_absent() {
  if grep -Fq -e "$2" <<< "$3"; then
    bad "$1" "output does NOT contain '$2'" "$(printf '%s' "$3" | tr '\n' '|')"; else ok "$1"; fi
}

# $1 name · $2 expected rc · $3 actual rc
expect_rc() {
  if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "exit $2" "exit $3"; fi
}

# A fixture is a git repo with the maintenance script's siblings stubbed out, so only the
# worktree section can speak.
mkfix() {
  d="$TMP/$1"
  mkdir -p "$d/scripts" "$d/.claude"
  ( cd "$d" && git init -q . >/dev/null 2>&1 )
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/project-freshness.sh"
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/prune-agent-worktrees.sh"
  # Section 6c now reports missing portability scripts as [SETUP] (row 033), so every fixture carries
  # a passing pair; C40-C45 take them away or change their exit on purpose.
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/validate-portability.sh"
  : > "$d/scripts/portability_audit.py"
  printf '%s' "$d"
}

# A directory under .claude/worktrees that looks like an agent left it behind. `touch -t` is the
# reliable way to age a fixture: relying on a zero-hour grace window would be testing find's
# rounding rather than this script's decision.
mkstale() {
  mkdir -p "$1"
  printf 'work in progress\n' > "$1/file.txt"
  find "$1" -exec touch -t 202001010000 {} + 2>/dev/null
}

# Every fixture stub is made executable before the run. A real project's scripts carry
# the bit, and project-maintenance.sh's [SCRIPT MODE] check reports the ones that do not
# -- so without this, seven assertions across this file failed on the fixtures rather
# than on the behaviour under test, and the two `expect_absent "worktree"` ones failed
# because the finding NAMES prune-agent-worktrees.sh. The check gets cases of its own
# (C26/C27) instead of being tripped by accident everywhere.
run() { ( cd "$1" && chmod +x scripts/*.sh 2>/dev/null; shift; env "$@" bash "$MAINT" 2>&1 ); }

snapshot() {
  ( cd "$1" && find . -type f -not -path './.git/*' -print0 2>/dev/null |
    xargs -0 shasum 2>/dev/null | sort )
}

printf 'project-maintenance self-test (abandoned agent worktrees)\n'

# --------------------------------------------------------------- C1 — no worktrees at all (AC1)
# The overwhelmingly common case: a project that never used worktree isolation. The section must
# not run, and must not contribute a reassurance line either — a weekly job that lists what did
# not happen is the noise attention mode exists to prevent.
D=$(mkfix c1)
OUT=$(run "$D"); RC=$?
expect_absent "C1 no .claude/worktrees — no WORKTREES finding" "[WORKTREES]" "$OUT"
expect_absent "C1 no .claude/worktrees — no reassurance line"  "worktree" "$OUT"
expect_rc     "C1 no .claude/worktrees — clean exit" 0 "$RC"

# -------------------------------------------------- C2 — the directory exists but is empty (AC2)
D=$(mkfix c2); mkdir -p "$D/.claude/worktrees"
OUT=$(run "$D"); RC=$?
expect_absent "C2 empty worktrees dir — no finding" "[WORKTREES]" "$OUT"
expect_rc     "C2 empty worktrees dir — clean exit" 0 "$RC"

# --------------------------------------------- C3 — a worktree an agent is using right now (AC3)
# The false positive that would make this section worthless. Agent worktrees are not locked, so
# the only signal is that something was written lately — and a run in progress must stay silent.
D=$(mkfix c3)
mkdir -p "$D/.claude/worktrees/agent-live"; printf 'fresh\n' > "$D/.claude/worktrees/agent-live/file.txt"
OUT=$(run "$D"); RC=$?
expect_absent "C3 worktree written to just now — presumed live, no finding" "[WORKTREES]" "$OUT"
expect_rc     "C3 worktree written to just now — clean exit" 0 "$RC"

# ------------------------------------------- C4 — an abandoned worktree, and what it says (AC4/5)
D=$(mkfix c4); mkstale "$D/.claude/worktrees/agent-dead"
OUT=$(run "$D"); RC=$?
expect_contains "C4 stale worktree — reported"            "[WORKTREES] 1 abandoned agent worktree(s)" "$OUT"
expect_contains "C4 stale worktree — age in days named"   "oldest " "$OUT"
expect_contains "C4 stale worktree — window named"        "untouched for over 24h" "$OUT"
expect_contains "C4 stale worktree — names the sweep"     "prune-agent-worktrees.sh --dry-run" "$OUT"
expect_rc       "C4 stale worktree — non-zero exit" 1 "$RC"

# ----------------------------------------------------- C5 — two worktrees, still one finding (AC4)
# One block regardless of count. Per-worktree detail is exactly what the sweep's --dry-run prints,
# and duplicating it here invites the two to disagree.
D=$(mkfix c5)
mkstale "$D/.claude/worktrees/agent-dead1"; mkstale "$D/.claude/worktrees/agent-dead2"
OUT=$(run "$D")
expect_contains "C5 two stale worktrees — counted together" "[WORKTREES] 2 abandoned agent worktree(s)" "$OUT"
expect_rc "C5 two stale worktrees — exactly one finding block" 1 \
  "$(printf '%s\n' "$OUT" | grep -c '\[WORKTREES\]')"

# ------------------------------------------------------ C6 — memory that exists only in here (AC6)
# The cost that is not disk. A file present in both places is already safe and must not inflate
# the number; a file present only in the worktree is what the developer needs to know about.
D=$(mkfix c6)
mkdir -p "$D/.claude/agent-memory/security-scanner" "$D/.claude/worktrees/agent-dead/.claude/agent-memory/security-scanner"
printf 'shared\n' > "$D/.claude/agent-memory/security-scanner/shared.md"
printf 'shared\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/security-scanner/shared.md"
printf 'only here\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/security-scanner/orphan.md"
printf '# index\n'  > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/MEMORY.md"
find "$D/.claude/worktrees" -exec touch -t 202001010000 {} + 2>/dev/null
OUT=$(run "$D")
expect_contains "C6 counts only the file with no counterpart, MEMORY.md excluded" \
  "1 agent-memory file(s) exist only inside them" "$OUT"

# -------------------------------------------------------------- C7 — the grace window is real (AC7)
# Aged two hours: silent at the 24h default, reported when the window is narrowed to one hour.
D=$(mkfix c7)
mkdir -p "$D/.claude/worktrees/agent-recent"
printf 'two hours ago\n' > "$D/.claude/worktrees/agent-recent/file.txt"
TS=$(date -v-2H '+%Y%m%d%H%M' 2>/dev/null || date -d '2 hours ago' '+%Y%m%d%H%M' 2>/dev/null)
if [ -n "$TS" ]; then
  find "$D/.claude/worktrees" -exec touch -t "$TS" {} + 2>/dev/null
  OUT=$(run "$D")
  expect_absent "C7 two hours old — silent at the 24h default" "[WORKTREES]" "$OUT"
  OUT=$(run "$D" MAINTENANCE_WORKTREE_GRACE_HOURS=1)
  expect_contains "C7 two hours old — reported at GRACE_HOURS=1" "[WORKTREES] 1 abandoned" "$OUT"
  expect_contains "C7 the narrowed window is named in the finding" "untouched for over 1h" "$OUT"
else
  ok "C7 skipped — no portable way to stamp a relative timestamp on this host"
fi

# ------------------------------------------------ C8 — the section changes NOTHING (AC10)
# The load-bearing one. This section reports on a destructive tool; the day it starts calling that
# tool it stops being a report. Hash everything before and after.
D=$(mkfix c8)
mkstale "$D/.claude/worktrees/agent-dead"
mkdir -p "$D/.claude/worktrees/agent-dead/.claude/agent-memory"
printf 'orphan\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/orphan.md"
find "$D/.claude/worktrees" -exec touch -t 202001010000 {} + 2>/dev/null
BEFORE=$(snapshot "$D")
OUT=$(run "$D")
AFTER=$(snapshot "$D")
if [ "$BEFORE" = "$AFTER" ]; then ok "C8 report-only — fixture byte-identical afterwards"
else bad "C8 report-only — fixture byte-identical afterwards" "no change" "$(diff <(printf '%s' "$BEFORE") <(printf '%s' "$AFTER") | head -5)"; fi
expect_contains "C8 …and it still reported the worktree" "[WORKTREES] 1 abandoned" "$OUT"

# ------------------------------------------------ C9 — the sweep the finding points at is gone (AC9)
# Pointing a developer at a command that is not there would be worse than the silence being fixed.
D=$(mkfix c9); rm -f "$D/scripts/prune-agent-worktrees.sh"
mkstale "$D/.claude/worktrees/agent-dead"
OUT=$(run "$D"); RC=$?
expect_contains "C9 missing sweep script — [SETUP] finding" "[SETUP]" "$OUT"
expect_contains "C9 missing sweep script — names it"        "prune-agent-worktrees.sh is missing" "$OUT"
expect_absent   "C9 missing sweep script — no dangling command to run" "--dry-run" "$OUT"
expect_rc       "C9 missing sweep script — non-zero exit" 1 "$RC"

# ------------------------------------------- C10 — a non-agent directory is not ours to judge (AC2)
D=$(mkfix c10); mkstale "$D/.claude/worktrees/my-own-branch"
OUT=$(run "$D"); RC=$?
expect_absent "C10 non-agent worktree dir — not reported" "[WORKTREES]" "$OUT"
expect_rc     "C10 non-agent worktree dir — clean exit" 0 "$RC"

# ------------------------------- C11 — a stale worktree locked by a live process is live (AC8)
# This rarely fires in the wild — the harness does not lock what it creates — but the sweep
# honours locks, and a report that disagreed about liveness with the tool it recommends would be
# worse than useless. Needs a genuinely registered worktree, so this fixture gets a commit.
D=$(mkfix c11)
( cd "$D" && printf 'x\n' > seed.txt && git add -A >/dev/null 2>&1 &&
  git -c user.email=t@t -c user.name=t commit -qm seed >/dev/null 2>&1 &&
  git worktree add -q .claude/worktrees/agent-locked -b wt-locked >/dev/null 2>&1 &&
  git worktree lock --reason "agent pid $$" .claude/worktrees/agent-locked >/dev/null 2>&1 )
if [ -e "$D/.claude/worktrees/agent-locked/.git" ]; then
  find "$D/.claude/worktrees/agent-locked" -exec touch -t 202001010000 {} + 2>/dev/null
  OUT=$(run "$D")
  expect_absent "C11 stale but locked by a live pid — not reported" "[WORKTREES]" "$OUT"
else
  ok "C11 skipped — git worktree add unavailable on this host"
fi

# ----------------------------- C12 — a find that cannot answer must not be believed (AC14)
# The nastiest failure this section can have. A find that cannot parse a relative -newermt
# matches nothing and says so only on stderr, which is byte-for-byte what "no recent writes"
# looks like — so every worktree on the machine gets declared abandoned at once, on a machine
# where the evidence was never gathered. Shim find so it refuses -newermt and delegates
# everything else, and require the section to say it could not tell rather than guess.
D=$(mkfix c12); mkstale "$D/.claude/worktrees/agent-dead"
mkdir -p "$TMP/shim"
cat > "$TMP/shim/find" <<'SHIM'
#!/bin/bash
for a in "$@"; do
  if [ "$a" = "-newermt" ]; then echo "find: Can't parse date/time" >&2; exit 1; fi
done
exec /usr/bin/find "$@"
SHIM
chmod +x "$TMP/shim/find"
OUT=$( cd "$D" && PATH="$TMP/shim:$PATH" bash "$MAINT" 2>&1 ); RC=$?
expect_contains "C12 unparseable -newermt — says it could not tell" "cannot evaluate a relative" "$OUT"
expect_absent   "C12 unparseable -newermt — does NOT claim worktrees are abandoned" "[WORKTREES]" "$OUT"
expect_rc       "C12 unparseable -newermt — non-zero exit" 1 "$RC"

# ------------------------------- C13 — a memory path with a space is still counted (AC6)
# Word-splitting a find's output loses these silently, and a silent miscount is the exact
# class of failure this section was written to end. Agent-generated names are slugs today,
# which is why this needs a test rather than trust.
D=$(mkfix c13)
mkdir -p "$D/.claude/worktrees/agent-dead/.claude/agent-memory"
printf 'x\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/two words.md"
printf 'y\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/plain.md"
find "$D/.claude/worktrees" -exec touch -t 202001010000 {} + 2>/dev/null
OUT=$(run "$D")
expect_contains "C13 space in a memory filename — counted, not split" \
  "2 agent-memory file(s) exist only inside them" "$OUT"

# ===================================================================================================
# The mutation section (section 5). Added after a measured audit found three defects in twelve lines,
# on the only command a default project has that asks for a mutation run at all.
#
# Every case here rigs `dotnet` on PATH: a stub that prints a chosen score and returns a chosen exit
# code. Nothing compiles, nothing mutates, and the suite still finishes in about a second. What is under
# test is the SENTENCE the section produces, because that sentence is the whole of what a developer
# hears about mutation coverage on a project with no rotation of its own.
# ===================================================================================================

mkfix_mut() { # mkfix_mut <name> <break or "none">
  d=$(mkfix "$1")
  mkdir -p "$d/bin" "$d/proj"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$d/proj/App.csproj"
  # Row 047: section 5 checks the config's mutate patterns on every pass, so the fixture carries the
  # helper that does it and one .cs file for `**/*.cs` to match. Without them every arm here would
  # carry a pattern finding for a reason its name does not state.
  printf 'class App {}\n' > "$d/proj/App.cs"
  cp "$DIR/stryker_guard.py" "$d/scripts/stryker_guard.py"
  if [ "$2" = "none" ]; then
    printf '%s\n' '{ "stryker-config": { "project": "App.csproj", "mutate": ["**/*.cs"] } }' > "$d/stryker-config.json"
  else
    printf '{ "stryker-config": { "project": "App.csproj", "mutate": ["**/*.cs"], "thresholds": { "high": 85, "low": 80, "break": %s } } }\n' "$2" > "$d/stryker-config.json"
  fi
  printf '%s' "$d"
}

# The stub is written per case rather than parameterised through the environment, because `run()` passes
# env through to project-maintenance.sh and NOT to the tool it invokes two layers down. An earlier draft
# of these cases did it the other way and every case printed the same output — four green assertions
# about one execution.
#
# Row 043: a scored run also writes a JSON report, because section 5 now reads the per-module scores out
# of the reports THIS run wrote and treats a run with none as unmeasured per module. By default the stub
# writes one clean report (a single file at 100%), so the arms above keep the verdict they were written
# for. A fixture steers it with two files: `.noreport` writes nothing, and `.fixture-reports/*.json` are
# copied in at run time, one Stryker output folder each, so their mtime is the run's and not the setup's.
mk_dotnet() { # mk_dotnet <dir> <score or "none"> <exit code>
  if [ "$2" = "none" ]; then
    printf '%s\n' '#!/bin/bash' 'echo "MSBUILD : error MSB1003: no project file"' "exit $3" > "$1/bin/dotnet"
  else
    printf '%s\n' '#!/bin/bash' 'echo "Stryker.NET"' \
      'if [ ! -f .noreport ]; then' \
      '  if [ -d .fixture-reports ]; then n=0; for f in .fixture-reports/*.json; do n=$((n+1)); mkdir -p "StrykerOutput/run$n/reports"; cp "$f" "StrykerOutput/run$n/reports/mutation-report.json"; done' \
      '  else mkdir -p StrykerOutput/run0/reports; printf "%s" '"'"'{"files":{"src/Clean.cs":{"mutants":[{"mutatorName":"m","replacement":"r","location":{"start":{"line":1,"column":1},"end":{"line":1,"column":2}},"status":"Killed"}]}}}'"'"' > StrykerOutput/run0/reports/mutation-report.json; fi' \
      'fi' \
      "echo \"The final mutation score is $2 %\"" "exit $3" > "$1/bin/dotnet"
  fi
  chmod +x "$1/bin/dotnet"
}

# chmod as run() does: without it every fixture carries a [SCRIPT MODE] finding, and an arm that reads
# the exit code would be red for that reason instead of the one it names (row 043's C54/C56).
run_full() { ( cd "$1" && chmod +x scripts/*.sh 2>/dev/null; PATH="$1/bin:$PATH" bash "$MAINT" --full 2>&1 ); }

# --- C14: a score that PASSES the config's own break is not a finding --------------------------------
# The defect this replaces: the comparison was a hardcoded 80 while the config said 79, so a run at 79.5
# passed its own gate and was reported as failing anyway. A config that states its threshold is the
# authority on its threshold.
D=$(mkfix_mut c14 79); mk_dotnet "$D" 79.50 0
OUT=$(run_full "$D")
expect_absent "C14 79.50 against break 79 — passes its own gate, no finding" "[MUTATION]" "$OUT"

# --- C15: and the 80 default still applies when the config states no break ---------------------------
D=$(mkfix_mut c15 none); mk_dotnet "$D" 79.50 0
OUT=$(run_full "$D")
expect_contains "C15 no break in the config — the 80 default applies" \
  "this config states no break" "$OUT"

# --- C16: a break failure is a GATE failure, not a tool crash ----------------------------------------
# Stryker exits non-zero when the score is under `break`, i.e. on the exact outcome the gate exists to
# produce. Reporting it as "failed to complete" plus fifteen lines of tail describes a crash and buries
# a finding.
D=$(mkfix_mut c16 79); mk_dotnet "$D" 70.00 1
OUT=$(run_full "$D")
expect_contains "C16 exit 1 with a score — reported as a gate failure" "GATE FAILED" "$OUT"
expect_absent   "C16 exit 1 with a score — NOT reported as a crash" "failed to complete" "$OUT"

# --- C17: a real crash still reads as a crash --------------------------------------------------------
# The other half of C16, and the reason the branch keys on the SCORE rather than on the exit code: a
# tool that never produced a number did not fail a gate.
D=$(mkfix_mut c17 79); mk_dotnet "$D" none 2
OUT=$(run_full "$D")
expect_contains "C17 exit 2 with no score — still a crash" "failed to complete — no score" "$OUT"

# --- C18: the number is labelled with its provenance -------------------------------------------------
# Stryker prints (Killed + Timeout) / valid. A Timeout is not a kill, so the strict score is this or
# lower and never higher. Printing the generous number under the label "kill rate" against a strict
# target is a claim about a measurement nobody made.
D=$(mkfix_mut c18 79); mk_dotnet "$D" 70.00 1
OUT=$(run_full "$D")
expect_contains "C18 the score is named as Stryker's own" "Stryker's own score" "$OUT"
expect_contains "C18 and the timeout caveat travels with it" "A Timeout is not a kill" "$OUT"

# --- C19: the section states its own coverage --------------------------------------------------------
# A bare `dotnet stryker` reads the config in the working directory. Reported without the ratio, one
# gate reads as a suite — on the project this was measured against, one of forty-five.
D=$(mkfix_mut c19 79); mk_dotnet "$D" 70.00 1
mkdir -p "$D/tests"
printf '{}\n' > "$D/tests/stryker-config.other.json"
printf '{}\n' > "$D/tests/stryker-config.third.json"
OUT=$(run_full "$D")
expect_contains "C19 coverage is stated, not implied" "1 of 3 config(s)" "$OUT"

# --- C20: exit 0 with no score is unclassifiable, and says so ----------------------------------------
# Not a pass. A run this section cannot classify must never be reported in the shape of a clean one.
D=$(mkfix_mut c20 79)
printf '%s\n' '#!/bin/bash' 'echo "nothing useful"' 'exit 0' > "$D/bin/dotnet"; chmod +x "$D/bin/dotnet"
OUT=$(run_full "$D")
expect_contains "C20 exit 0 with no score — reported as unclassifiable, never as clean" \
  "cannot be classified" "$OUT"

# --- C21: the maintenance pass never starts a sweep --------------------------------------------------
# A maintenance pass that silently launches a multi-hour run across every gate is a worse defect than
# the one it fixes. Asserted against the source, with comments stripped, because the file discusses the
# rule at length and an assertion that cannot tell a discussion from a call would forbid the discussion.
if ! grep -q 'rerun-refused\|mutation-rotation\|--include-unmeasured' <<< "$(sed 's/#.*//' "$MAINT")"; then
  ok "C21 the maintenance pass invokes no sweep of its own"
else
  bad "C21 the maintenance pass invokes no sweep" "no sweep invocation" "a sweep script is called"
fi

# --- C22: no gate script — the section is silent, not reassuring -------------------------------------
# Attention mode: a weekly report that lists what did not happen is the noise the mode exists to remove.
# It is also the shape of every project that has not synced the gate yet, so silence here is the common
# case, not an edge one.
D=$(mkfix c22)
OUT=$(run "$D"); RC=$?
expect_absent "C22 no gate script — no SIGPIPE line" "[SIGPIPE]" "$OUT"
expect_rc     "C22 no gate script — clean exit" 0 "$RC"

# --- C23: the gate reports hits — a FINDING, and the verdict turns red -------------------------------
# Deliberately the other side of 2b's asymmetry. An uncovered scenario is a backlog; a SIGPIPE assertion
# is a one-line mechanical defect that is zero on a healthy repo, so it votes.
D=$(mkfix c23)
printf '#!/bin/bash\necho "scripts/test-x.sh:4"\necho "    if printf %%s \\"\$O\\" | grep -q y; then"\nexit 1\n' \
  > "$D/scripts/validate-no-sigpipe-assertions.sh"
OUT=$(run "$D"); RC=$?
expect_contains "C23 gate reports hits — a SIGPIPE finding" "[SIGPIPE]" "$OUT"
expect_contains "C23 the finding names the silent direction" "NEGATED" "$OUT"
expect_contains "C23 the finding carries the gate's own output" "scripts/test-x.sh:4" "$OUT"
expect_rc       "C23 gate reports hits — verdict is red" 1 "$RC"

# --- C24: the gate could not run — still a finding, never a clean read -------------------------------
# Exit 2 means "nothing to scan" or "a boundary I refuse to guess". Reporting that as a pass is the exact
# defect row H7ax removed one level down: a gate that did not look must never read as a gate that did.
D=$(mkfix c24)
printf '#!/bin/bash\necho "ERROR: no scripts/test-*.sh under . — nothing was scanned." >&2\nexit 2\n' \
  > "$D/scripts/validate-no-sigpipe-assertions.sh"
OUT=$(run "$D"); RC=$?
expect_contains "C24 gate could not run — reported, with its exit code" "could not run (exit 2)" "$OUT"
expect_contains "C24 gate could not run — carries the reason" "nothing was scanned" "$OUT"
expect_rc       "C24 gate could not run — verdict is red" 1 "$RC"

# --- C25: a clean gate says nothing at all -----------------------------------------------------------
# Including the NOT RUN branch, which also exits 0: downstream a freshly synced project has no self-tests
# of its own, every one is sync-owned, and the template scans them. That is a normal state, not news.
D=$(mkfix c25)
printf '#!/bin/bash\necho "no-sigpipe-assertions: clean — 21 self-test(s)"\nexit 0\n' \
  > "$D/scripts/validate-no-sigpipe-assertions.sh"
OUT=$(run "$D"); RC=$?
expect_absent "C25 clean gate — no SIGPIPE line" "[SIGPIPE]" "$OUT"
expect_rc     "C25 clean gate — clean exit" 0 "$RC"


# --- C26: a script without the executable bit is a finding -------------------------------------------
# `bash X` runs it either way, so the defect is silent until something guards on `-x` -- which
# lane-catchup.sh did, and skipped its entire shared-machinery check on six projects in silence.
D=$(mkfix c26)
printf '#!/bin/bash\nexit 0\n' > "$D/scripts/some-helper.sh"
chmod -x "$D/scripts/some-helper.sh"
OUT=$( ( cd "$D" && bash "$MAINT" 2>&1 ) ); RC=$?
expect_contains "C26 non-exec script — a SCRIPT MODE finding" "[SCRIPT MODE]" "$OUT"
expect_contains "C26 the finding names the script"            "some-helper.sh"  "$OUT"
expect_rc       "C26 non-exec script — verdict is red" 1 "$RC"

# --- C27: every script executable says nothing -------------------------------------------------------
D=$(mkfix c27)
printf '#!/bin/bash\nexit 0\n' > "$D/scripts/some-helper.sh"
OUT=$(run "$D"); RC=$?
expect_absent "C27 all executable — no SCRIPT MODE line" "[SCRIPT MODE]" "$OUT"
expect_rc     "C27 all executable — clean exit" 0 "$RC"

# === the mutation due-state stamp (rocky F044) ========================================================
#
# The stamp is a CLAIM that a recurring obligation was discharged, and it is the only half of the
# mechanism nothing could see: every C14-C20 arm above reads the SENTENCE the section prints, and the
# stamp prints nothing at all. So `--stamp mutation` fired on `--full` alone — on a run this very
# section had just called unclassifiable, and on a project with no Stryker and no runner where nothing
# executed. The banner then went quiet about a gate nobody had measured.
#
# These arms stub scripts/maintenance-due.sh to record what it is asked to stamp. C29 is the one that
# matters and C28 is what keeps it honest: an arm that only demanded the absence would pass just as
# well against a stamp that never fires, which is the stricter defect of the two.
mkfix_stamp() { # mkfix_stamp <name> <break or "none">  -> dir with a recording maintenance-due stub
  d=$(mkfix_mut "$1" "$2")
  printf '%s\n' '#!/bin/bash' \
    'while [ $# -gt 0 ]; do [ "$1" = "--stamp" ] && { shift; printf "%s\n" "$1" >> "$PWD/.stamped"; }; shift; done' \
    'exit 0' > "$d/scripts/maintenance-due.sh"
  chmod +x "$d/scripts/maintenance-due.sh"
  printf '%s' "$d"
}

# --- C28: a run that produced a score DOES stamp -----------------------------------------------------
D=$(mkfix_stamp c28 79); mk_dotnet "$D" 90.00 0
OUT=$(run_full "$D")
expect_contains "C28 a measured gate stamps mutation" "mutation" "$(cat "$D/.stamped" 2>/dev/null)"

# --- C29: a run that produced NO score does not ------------------------------------------------------
# Same fixture, same --full, same everything but the tool's output. `secrets` must still be there:
# without that half, a stub that recorded nothing would satisfy this arm.
D=$(mkfix_stamp c29 79)
printf '%s\n' '#!/bin/bash' 'echo "nothing useful"' 'exit 0' > "$D/bin/dotnet"; chmod +x "$D/bin/dotnet"
OUT=$(run_full "$D")
expect_contains "C29 the run is still reported as unclassifiable" "cannot be classified" "$OUT"
expect_absent   "C29 an unclassifiable run does NOT stamp mutation" "mutation" "$(cat "$D/.stamped" 2>/dev/null)"
expect_contains "C29 and secrets still stamps, so the stub is live" "secrets" "$(cat "$D/.stamped" 2>/dev/null)"

# --- C30: no mutation tooling at all — nothing ran, so nothing is stamped -----------------------------
# The quietest case and the one the old code got most wrong: $MUTATION_CMD is empty, the section never
# executes a line, and the job was marked done anyway.
D=$(mkfix c30)
printf '%s\n' '#!/bin/bash' \
  'while [ $# -gt 0 ]; do [ "$1" = "--stamp" ] && { shift; printf "%s\n" "$1" >> "$PWD/.stamped"; }; shift; done' \
  'exit 0' > "$D/scripts/maintenance-due.sh"
chmod +x "$D/scripts/maintenance-due.sh"
OUT=$( cd "$D" && bash "$MAINT" --full 2>&1 )
expect_absent   "C30 no gate at all — mutation is not stamped" "mutation" "$(cat "$D/.stamped" 2>/dev/null)"
expect_contains "C30 and the pass still ran, so the absence means something" "secrets" "$(cat "$D/.stamped" 2>/dev/null)"

# ================================================ C31-C36 — the scenario-map canary is recorded (row 008)
# The canary printed and scrolled away while 17 map files sat over 25 KB, and its only remedy named
# the INDEX.md archivers, which never move an SC row. These arms pin the two halves of the fix: the
# hint fits the file's role, and the file lands in the project's own findings ledger exactly once
# while it is open.
mkbig() { # mkbig FILE — a map file past the 25 KB canary
  mkdir -p "$(dirname "$1")"
  printf '# Scenario map\n' > "$1"
  while [ "$(wc -c < "$1" | tr -d ' ')" -le 25600 ]; do
    printf -- '| SC-001 | padding row, present only to exceed the canary threshold | ✓ |\n' >> "$1"
  done
}
open_map_lines() { grep -E '^- \[ \] F[0-9]+ ' "$1/specs/FINDINGS.md" 2>/dev/null | grep -cF "scenario-map canary: $2 "; }

# --- C31: single-file map over the canary — split hint, recorded once as debt ---------------------
D=$(mkfix c31); cp "$DIR/finding.sh" "$D/scripts/"; mkbig "$D/specs/SCENARIOS.md"
OUT=$(run "$D"); RC=$?
expect_contains "C31 single-file map — the hint says split"        "split it per .claude/rules/scenarios.md" "$OUT"
expect_absent   "C31 single-file map — not the INDEX archiver"     "archive-completed-rows" "$OUT"
expect_contains "C31 the finding is recorded as debt"              "— debt —" "$(cat "$D/specs/FINDINGS.md" 2>/dev/null)"
expect_rc       "C31 exactly one open finding for the path" 1 "$(open_map_lines "$D" specs/SCENARIOS.md)"
expect_rc       "C31 an oversize map is still a red verdict" 1 "$RC"

# --- C32: a second pass does not duplicate the open finding --------------------------------------
OUT=$(run "$D")
expect_rc       "C32 second pass — still one open finding" 1 "$(open_map_lines "$D" specs/SCENARIOS.md)"
expect_absent   "C32 second pass — no 'recorded' note"      "recorded in specs/FINDINGS.md" "$OUT"

# --- C33: split layout, one oversize feature file — named, with the feature-file hint -------------
D=$(mkfix c33); cp "$DIR/finding.sh" "$D/scripts/"
mkdir -p "$D/specs/scenarios"; printf '# Scenario map (index)\n' > "$D/specs/SCENARIOS.md"
printf '# small\n' > "$D/specs/scenarios/001-small.md"; mkbig "$D/specs/scenarios/002-big.md"
OUT=$(run "$D")
expect_contains "C33 feature file — the hint says split the feature" "split this feature into sub-feature files" "$OUT"
expect_rc       "C33 the feature file is recorded" 1 "$(open_map_lines "$D" specs/scenarios/002-big.md)"
expect_rc       "C33 the small index is not" 0 "$(open_map_lines "$D" specs/SCENARIOS.md)"

# --- C34: a map under the canary — nothing recorded, no ledger created -----------------------------
D=$(mkfix c34); cp "$DIR/finding.sh" "$D/scripts/"; mkdir -p "$D/specs"; printf '# small map\n' > "$D/specs/SCENARIOS.md"
OUT=$(run "$D"); RC=$?
expect_absent   "C34 small map — no CONTEXT-COST line" "[CONTEXT-COST]" "$OUT"
if [ -f "$D/specs/FINDINGS.md" ]; then bad "C34 small map — no ledger created" "no specs/FINDINGS.md" "created"; else ok "C34 small map — no ledger created"; fi
expect_rc       "C34 small map — clean exit" 0 "$RC"

# --- C35: a DECIDED finding for the path does not suppress a new open one ---------------------------
D=$(mkfix c35); cp "$DIR/finding.sh" "$DIR/max-id-in-refs.sh" "$D/scripts/"; mkbig "$D/specs/SCENARIOS.md"
printf '# Findings\n\n## Open\n\n- [x] F001 — debt — 2026-09-01 — scenario-map canary: specs/SCENARIOS.md is 30 KB (single-file map, canary 25 KB) — split — decided: live with it\n' > "$D/specs/FINDINGS.md"
OUT=$(run "$D")
expect_rc       "C35 decided finding — a new open one is added" 1 "$(open_map_lines "$D" specs/SCENARIOS.md)"
expect_contains "C35 the new one takes the next id" "- [ ] F002 " "$(cat "$D/specs/FINDINGS.md")"

# --- C36: finding.sh missing — a SETUP finding, never a silent skip --------------------------------
D=$(mkfix c36); mkbig "$D/specs/SCENARIOS.md"
OUT=$(run "$D"); RC=$?
expect_contains "C36 no finding.sh — SETUP finding names it" "[SETUP] scripts/finding.sh missing" "$OUT"
expect_rc       "C36 no finding.sh — verdict is red" 1 "$RC"

# ================================================ C37-C39 — --suite reads the abort line (row 031)
# rocky's crashed test host printed `Passed!` between two abort lines with 45% of the suite unrun.
# --suite judged by `$?` alone, so an abort that exits 0 would be stamped green. A fake `dotnet`
# on PATH replays the captured transcript at a chosen exit code; a stub maintenance-due.sh records
# whether the suite was stamped.
mksuite() { # mksuite NAME RC — fixture whose `dotnet test` prints $SUITE_TEXT and exits RC
  local d; d=$(mkfix "$1")
  printf '<Project Sdk="Microsoft.NET.Sdk" />\n' > "$d/app.csproj"
  mkdir -p "$d/bin"
  printf '%s\n' "$SUITE_TEXT" > "$d/bin/transcript.txt"
  printf '#!/bin/bash\ncat "%s/bin/transcript.txt"\nexit %s\n' "$d" "$2" > "$d/bin/dotnet"
  chmod +x "$d/bin/dotnet"
  printf '#!/bin/bash\n[ "$1" = --stamp ] && echo "$2" >> "%s/stamped"\nexit 0\n' "$d" > "$d/scripts/maintenance-due.sh"
  cp "$DIR/run-verdict.sh" "$d/scripts/" 2>/dev/null
  printf '%s' "$d"
}
run_suite() { ( cd "$1" && chmod +x scripts/*.sh 2>/dev/null; PATH="$1/bin:$PATH" bash "$MAINT" --suite 2>&1 ); }
stamped_suite() { grep -cx suite "$1/stamped" 2>/dev/null; }

SUITE_TEXT='The active test run was aborted. Reason: Test host process crashed
Passed!  - Failed: 0, Passed: 1673, Skipped: 7, Total: 1680
Test Run Aborted.'

# --- C37: the abort at exit 0 — the case $? alone would stamp green --------------------------------
D=$(mksuite c37 0)
OUT=$(run_suite "$D"); RC=$?
expect_contains "C37 aborted run at exit 0 — a SUITE finding"   "[SUITE]" "$OUT"
expect_contains "C37 the finding says the run aborted"          "the test run ABORTED" "$OUT"
expect_absent   "C37 never reported green"                      "suite green" "$OUT"
expect_rc       "C37 not stamped" 0 "$(stamped_suite "$D")"
expect_rc       "C37 verdict is red" 1 "$RC"

# --- C38: the same transcript at exit 1 (what rocky measured) — named as an abort, not a failure --
D=$(mksuite c38 1)
OUT=$(run_suite "$D")
expect_contains "C38 aborted run at exit 1 — named as aborted"  "the test run ABORTED" "$OUT"
expect_rc       "C38 not stamped" 0 "$(stamped_suite "$D")"

# --- C39: a genuinely green run stays green and is stamped ----------------------------------------
SUITE_TEXT='Passed!  - Failed:     0, Passed:    12, Skipped:     0, Total:    12'
D=$(mksuite c39 0)
OUT=$(run_suite "$D"); RC=$?
expect_contains "C39 green run — suite green"                   "suite green" "$OUT"
expect_rc       "C39 green run — stamped" 1 "$(stamped_suite "$D")"
expect_rc       "C39 green run — clean exit" 0 "$RC"

# ================================================ C40-C45 — the portability check says when it did not run (row 033)
#
# fundit F002: a sync landed section 6c without its two scripts, the [ -f ] guard had no else, and the
# pass printed "clean". Every path that did not run the check must now be a finding. C44 and C45 keep
# the arms honest: a section that always complained would pass C40-C43 just as well.
port_stub() { # port_stub <dir> <exit> <output>
  printf '#!/bin/bash\necho "%s"\nexit %s\n' "$3" "$2" > "$1/scripts/validate-portability.sh"
}

# --- C40: neither script — the fundit case ---------------------------------------------------------
D=$(mkfix c40); rm -f "$D/scripts/validate-portability.sh" "$D/scripts/portability_audit.py"
OUT=$(run "$D"); RC=$?
expect_contains "C40 no portability scripts — a SETUP finding"      "[SETUP] portability check did not run" "$OUT"
expect_contains "C40 names validate-portability.sh"                 "scripts/validate-portability.sh" "$OUT"
expect_contains "C40 names portability_audit.py"                    "scripts/portability_audit.py" "$OUT"
expect_absent   "C40 never reads clean"                             "project-maintenance: clean" "$OUT"
expect_rc       "C40 verdict is red" 1 "$RC"

# --- C41: only the wrapper — names the engine alone ------------------------------------------------
D=$(mkfix c41); rm -f "$D/scripts/portability_audit.py"
OUT=$(run "$D"); RC=$?
expect_contains "C41 engine missing — named"                        "scripts/portability_audit.py missing" "$OUT"
expect_absent   "C41 the wrapper that is there is not named"        "scripts/validate-portability.sh" "$OUT"
expect_rc       "C41 verdict is red" 1 "$RC"

# --- C42: only the engine — names the wrapper alone ------------------------------------------------
D=$(mkfix c42); rm -f "$D/scripts/validate-portability.sh"
OUT=$(run "$D"); RC=$?
expect_contains "C42 wrapper missing — named"                       "scripts/validate-portability.sh missing" "$OUT"
expect_absent   "C42 the engine that is there is not named"         "scripts/portability_audit.py" "$OUT"
expect_rc       "C42 verdict is red" 1 "$RC"

# --- C43: both there, the run could not run --------------------------------------------------------
D=$(mkfix c43); port_stub "$D" 2 "validate-portability.sh: no scripts to scan"
OUT=$(run "$D"); RC=$?
expect_contains "C43 could not run — reported with its exit code"   "[PORTABILITY] scripts/validate-portability.sh could not run (exit 2)" "$OUT"
expect_contains "C43 carries the run's own reason"                  "no scripts to scan" "$OUT"
expect_rc       "C43 verdict is red" 1 "$RC"

# --- C44: a clean run says nothing ------------------------------------------------------------------
D=$(mkfix c44); port_stub "$D" 0 "portability: clean"
OUT=$(run "$D"); RC=$?
expect_absent   "C44 clean run — no PORTABILITY line"               "[PORTABILITY]" "$OUT"
expect_absent   "C44 clean run — no portability SETUP line"         "portability check did not run" "$OUT"
expect_rc       "C44 clean run — clean exit" 0 "$RC"

# --- C45: hits keep today's finding ----------------------------------------------------------------
D=$(mkfix c45); port_stub "$D" 1 "  scripts/x.sh:3  some-construct"
OUT=$(run "$D"); RC=$?
expect_contains "C45 hits — today's finding"                        "[PORTABILITY] construct(s)" "$OUT"
expect_contains "C45 carries the hit"                               "scripts/x.sh:3" "$OUT"
expect_rc       "C45 verdict is red" 1 "$RC"

# ================================================ C46-C53 — the shared suite runs at a narrow viewport (row 035)
#
# fundit F024: every a11y/visual test ran at Playwright's default 1280px, so a horizontal overflow at
# 375px shipped in spec 001 and was found by hand in spec 004. Section 6d reads the SHARED config,
# because a narrow width set inside one test is exactly the per-spec pattern that let it through.
vp_cfg() { # vp_cfg <dir> <file> <body>
  printf '%s\n' "$3" > "$1/$2"
}

# --- C46: a narrow project in the config ----------------------------------------------------------
D=$(mkfix c46); vp_cfg "$D" playwright.config.ts "export default { projects: [ { use: { viewport: { width: 1280, height: 800 } } }, { use: { viewport: { width: 375, height: 812 } } } ] }"
OUT=$(run "$D"); RC=$?
expect_absent   "C46 narrow project — no VIEWPORT finding"          "[VIEWPORT]" "$OUT"
expect_rc       "C46 narrow project — clean exit" 0 "$RC"

# --- C47: a phone device descriptor counts as narrow ----------------------------------------------
D=$(mkfix c47); vp_cfg "$D" playwright.config.ts "export default { projects: [ { use: { ...devices['Desktop Chrome'] } }, { use: { ...devices['iPhone 13'] } } ] }"
OUT=$(run "$D"); RC=$?
expect_absent   "C47 phone device — no VIEWPORT finding"            "[VIEWPORT]" "$OUT"
expect_rc       "C47 phone device — clean exit" 0 "$RC"

# --- C48: desktop only — the agentcrm/fundit shape ------------------------------------------------
D=$(mkfix c48); vp_cfg "$D" playwright.config.ts "export default { projects: [ { use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } } } ] }"
OUT=$(run "$D"); RC=$?
expect_contains "C48 desktop only — a VIEWPORT finding"             "[VIEWPORT]" "$OUT"
expect_contains "C48 names the config"                              "playwright.config.ts" "$OUT"
expect_contains "C48 points at the doc"                             ".claude/docs/testing.md" "$OUT"
expect_absent   "C48 never reads clean"                             "project-maintenance: clean" "$OUT"
expect_rc       "C48 verdict is red" 1 "$RC"

# --- C49: two configs, one narrow — only the other is named ---------------------------------------
D=$(mkfix c49)
vp_cfg "$D" playwright.config.ts "export default { projects: [ { use: { viewport: { width: 390, height: 844 } } } ] }"
vp_cfg "$D" playwright.site.config.ts "export default { use: { viewport: { width: 1440, height: 900 } } }"
OUT=$(run "$D"); RC=$?
expect_contains "C49 the desktop-only config is named"              "playwright.site.config.ts" "$OUT"
expect_absent   "C49 the narrow config is not named"                "playwright.config.ts" "$OUT"
expect_rc       "C49 verdict is red" 1 "$RC"

# --- C50: desktop only, and it says why --------------------------------------------------------------
D=$(mkfix c50); vp_cfg "$D" playwright.config.ts "// narrow-viewport: not-applicable — kiosk app, fixed 1920 display
export default { use: { viewport: { width: 1920, height: 1080 } } }"
OUT=$(run "$D"); RC=$?
expect_absent   "C50 marker — no VIEWPORT finding"                  "[VIEWPORT]" "$OUT"
expect_rc       "C50 marker — clean exit" 0 "$RC"

# --- C51: .NET suite that sets a narrow viewport in a test -------------------------------------------
D=$(mkfix c51); mkdir -p "$D/tests/App.E2E"
printf '<Project><ItemGroup><PackageReference Include="Microsoft.Playwright" /></ItemGroup></Project>\n' > "$D/tests/App.E2E/App.E2E.csproj"
printf 'await Page.SetViewportSizeAsync(375, 812);\n' > "$D/tests/App.E2E/LayoutTests.cs"
OUT=$(run "$D"); RC=$?
expect_absent   "C51 .NET narrow test — no VIEWPORT finding"        "[VIEWPORT]" "$OUT"
expect_rc       "C51 .NET narrow test — clean exit" 0 "$RC"

# --- C51b: .NET suite parameterized per width on the shared fixture (the testing.md pattern) ---------
D=$(mkfix c51b); mkdir -p "$D/tests/App.E2E"
printf '<Project><ItemGroup><PackageReference Include="Microsoft.Playwright" /></ItemGroup></Project>\n' > "$D/tests/App.E2E/App.E2E.csproj"
printf '[TestFixture(1280, 800)]\n[TestFixture(375, 812)]\npublic abstract class ScreenTest(int w, int h) : PageTest { }\n' > "$D/tests/App.E2E/ScreenTest.cs"
OUT=$(run "$D"); RC=$?
expect_absent   "C51b .NET fixture per width — no VIEWPORT finding" "[VIEWPORT]" "$OUT"
expect_rc       "C51b .NET fixture per width — clean exit" 0 "$RC"

# --- C52: .NET suite with a narrow width only in production code -------------------------------------
D=$(mkfix c52); mkdir -p "$D/tests/App.E2E" "$D/src/App"
printf '<Project><ItemGroup><PackageReference Include="Microsoft.Playwright" /></ItemGroup></Project>\n' > "$D/tests/App.E2E/App.E2E.csproj"
printf 'await Page.GotoAsync("/");\n' > "$D/tests/App.E2E/HomeTests.cs"
printf 'var box = new Box { Width = 350 };\n' > "$D/src/App/Box.cs"
OUT=$(run "$D"); RC=$?
expect_contains "C52 .NET desktop only — a VIEWPORT finding"        "[VIEWPORT]" "$OUT"
expect_contains "C52 names the Playwright project"                  "App.E2E.csproj" "$OUT"
expect_rc       "C52 verdict is red" 1 "$RC"

# --- C53: no Playwright at all -------------------------------------------------------------------------
D=$(mkfix c53); mkdir -p "$D/src"; printf 'const w = { width: 1280 };\n' > "$D/src/app.ts"
OUT=$(run "$D"); RC=$?
expect_absent   "C53 no Playwright — no VIEWPORT finding"           "[VIEWPORT]" "$OUT"
expect_rc       "C53 no Playwright — clean exit" 0 "$RC"

# ================================================ C54-C61 — the gate reads modules, not a headline (row 043)
# fundit spec 006: the headline read 88.21% and PASS while PushEndpointPolicy, the SSRF decision, killed
# 65.79%. `.claude/rules/spec-hardening.md` gates on the changed critical MODULE, and section 5 read one
# number. These arms hand the stub Stryker a report and read the sentence that comes back.
mkreport() { # mkreport <out.json> <file=Status,Status,...>... — one mutant per status, at line 1, 2, ...
  local out=$1; shift
  mkdir -p "$(dirname "$out")"
  {
    printf '{"schemaVersion":"1","files":{'
    local sep="" spec file statuses i st
    for spec in "$@"; do
      file=${spec%%=*}; statuses=${spec#*=}
      printf '%s"%s":{"language":"cs","source":"","mutants":[' "$sep" "$file"; sep=","
      i=0
      for st in $(printf '%s' "$statuses" | tr ',' ' '); do
        i=$((i + 1))
        [ "$i" -gt 1 ] && printf ','
        printf '{"id":"%s","mutatorName":"m","replacement":"r","location":{"start":{"line":%s,"column":1},"end":{"line":%s,"column":9}},"status":"%s"}' "$i" "$i" "$i" "$st"
      done
      printf ']}'
    done
    printf '}}'
  } > "$out"
}
rep() { # rep <status> <count> — "S,S,S"
  local i out=""; for i in $(seq 1 "$2"); do out="${out:+$out,}$1"; done; printf '%s' "$out"
}

# --- C54: the fundit shape — headline passes, one module under break ----------------------------------
D=$(mkfix_mut c54 79); mk_dotnet "$D" 88.21 0
mkreport "$D/.fixture-reports/a.json" \
  "src/PushEndpointPolicy.cs=$(rep Killed 25),$(rep Survived 13)" "src/Other.cs=$(rep Killed 10)"
OUT=$(run_full "$D"); RC=$?
expect_contains "C54 a module under break is a finding"           "[MUTATION]" "$OUT"
expect_contains "C54 it names the module"                         "src/PushEndpointPolicy.cs" "$OUT"
expect_contains "C54 with its score and counts"                   "65.79%  src/PushEndpointPolicy.cs (25/38)" "$OUT"
expect_absent   "C54 a module over break is not listed"           "src/Other.cs" "$OUT"
expect_rc       "C54 verdict is red" 1 "$RC"

# --- C55: every module over break — no finding ---------------------------------------------------------
D=$(mkfix_mut c55 79); mk_dotnet "$D" 90.00 0
mkreport "$D/.fixture-reports/a.json" "src/A.cs=$(rep Killed 9),Survived" "src/B.cs=Killed,Timeout"
OUT=$(run_full "$D")
expect_absent   "C55 every module over break — no MUTATION finding" "[MUTATION]" "$OUT"

# --- C56: a scored run that wrote no report — the module gate is unmeasured ---------------------------
D=$(mkfix_mut c56 79); mk_dotnet "$D" 90.00 0; touch "$D/.noreport"
OUT=$(run_full "$D"); RC=$?
expect_contains "C56 no report — said, not passed"                "no JSON report" "$OUT"
expect_contains "C56 and it names the fix"                        '"json"' "$OUT"
expect_contains "C56 and the replace-not-add trap"                "replaces" "$OUT"
expect_rc       "C56 verdict is red" 1 "$RC"

# --- C57: a stale report from an earlier run is not this run's evidence --------------------------------
D=$(mkfix_mut c57 79); mk_dotnet "$D" 90.00 0; touch "$D/.noreport"
mkreport "$D/StrykerOutput/old/reports/mutation-report.json" "src/Stale.cs=Survived,Survived"
touch -t 202001010000 "$D/StrykerOutput/old/reports/mutation-report.json"
OUT=$(run_full "$D")
expect_contains "C57 stale report ignored — still no report"      "no JSON report" "$OUT"
expect_absent   "C57 and the stale module is not read"            "src/Stale.cs" "$OUT"

# --- C58: two passes, each kills the other's survivors — the suite kills all of them -------------------
D=$(mkfix_mut c58 79); mk_dotnet "$D" 90.00 0
mkreport "$D/.fixture-reports/a.json" "src/Split.cs=Killed,Killed,Survived,Survived"
mkreport "$D/.fixture-reports/b.json" "src/Split.cs=NoCoverage,Survived,Killed,Timeout"
OUT=$(run_full "$D")
expect_absent   "C58 merged per mutant — no module under break"   "[MUTATION]" "$OUT"

# --- C59: headline fails too — the list rides in the one GATE FAILED finding ---------------------------
D=$(mkfix_mut c59 79); mk_dotnet "$D" 70.00 1
mkreport "$D/.fixture-reports/a.json" "src/Weak.cs=Killed,Survived"
OUT=$(run_full "$D")
expect_contains "C59 gate failure still reported as such"         "GATE FAILED" "$OUT"
expect_contains "C59 with the module inside it"                   "src/Weak.cs" "$OUT"
expect_rc       "C59 one gate failure is one finding" 1 "$(printf '%s\n' "$OUT" | grep -c '^\[MUTATION\]')"

# --- C60: a file with no valid mutant is not a module under break --------------------------------------
D=$(mkfix_mut c60 79); mk_dotnet "$D" 90.00 0
mkreport "$D/.fixture-reports/a.json" "src/Broken.cs=CompileError,Ignored" "src/Fine.cs=Killed"
OUT=$(run_full "$D")
expect_absent   "C60 no valid mutants — not listed"               "src/Broken.cs" "$OUT"
expect_absent   "C60 and no finding"                              "[MUTATION]" "$OUT"

# --- C61: an unreadable report is named, and the readable one is still read ----------------------------
D=$(mkfix_mut c61 79); mk_dotnet "$D" 90.00 0
mkdir -p "$D/.fixture-reports"; printf 'not json' > "$D/.fixture-reports/a.json"
mkreport "$D/.fixture-reports/b.json" "src/Weak.cs=Killed,Survived"
OUT=$(run_full "$D")
expect_contains "C61 the bad report is named unreadable"          "unreadable" "$OUT"
expect_contains "C61 the good report still reports its module"    "src/Weak.cs" "$OUT"

# --- C62: a module exactly at the limit passes, as the headline does at its limit ---------------------
D=$(mkfix_mut c62 80); mk_dotnet "$D" 90.00 0
mkreport "$D/.fixture-reports/a.json" "src/Edge.cs=$(rep Killed 4),Survived"
OUT=$(run_full "$D")
expect_absent   "C62 80.00 against 80 — not under the limit"      "src/Edge.cs" "$OUT"

# ================================================ C63-C71 — patterns that select nothing, and Stryker beside a build (row 047)
# ighweld-2026: `'**/X.cs{845-1080}'` matched no file and scored (F184); `{98..120}` is characters, not
# lines (F197); a span did not shrink the run (F185); a sibling `dotnet test` zeroed a run (F069). The
# pattern arms run WITHOUT --full: the check is static and belongs on every pass.
mkfix_pat() { # mkfix_pat <name> <mutate JSON array>
  d=$(mkfix_mut "$1" 79)
  mkdir -p "$d/src/Services"; printf 'class W {}\n' > "$d/src/Services/WpqrService.cs"
  printf '{ "stryker-config": { "project": "App.csproj", "mutate": %s, "thresholds": { "break": 79 } } }\n' "$2" > "$d/stryker-config.json"
  printf '%s' "$d"
}

# --- C63: the F184 hyphen — matches nothing, said so ----------------------------------------------------
D=$(mkfix_pat c63 '["**/WpqrService.cs{845-1080}"]')
OUT=$(run "$D"); RC=$?
expect_contains "C63 a hyphen span is a finding"                  "[MUTATION]" "$OUT"
expect_contains "C63 it names config and pattern"                 "stryker-config.json: '**/WpqrService.cs{845-1080}'" "$OUT"
expect_contains "C63 and says what the span should be"            "two dots" "$OUT"
expect_rc       "C63 verdict is red" 1 "$RC"

# --- C64: a glob that matches no .cs file -------------------------------------------------------------
D=$(mkfix_pat c64 '["**/Services/Nope.cs"]')
OUT=$(run "$D")
expect_contains "C64 a glob matching nothing is a finding"        "'**/Services/Nope.cs' matches no .cs file" "$OUT"

# --- C65: a well-formed span — characters, not lines, and not smaller -----------------------------------
D=$(mkfix_pat c65 '["**/WpqrService.cs{840..1140}"]')
OUT=$(run "$D")
expect_contains "C65 a valid span is a finding"                   "CHARACTER offsets" "$OUT"
expect_contains "C65 that names F185"                             "F185" "$OUT"

# --- C66: what is fine stays silent: a wildcard, a path suffix, an exclude that excludes nothing ----------
D=$(mkfix_pat c66 '["**/*.cs", "Services/WpqrService.cs", "src/Services/W*.cs", "!**/*.Generated.cs"]')
OUT=$(run "$D"); RC=$?
expect_absent   "C66 good patterns — no MUTATION finding"         "[MUTATION]" "$OUT"
expect_rc       "C66 good patterns — clean exit" 0 "$RC"

# --- C67: the runner's literal -m is read; a runtime-assembled one is not guessed at ---------------------
D=$(mkfix_pat c67 '["**/*.cs"]')
printf '%s\n' '#!/bin/bash' 'P="**/*.cs"' 'dotnet stryker -m "$P"' "dotnet stryker -m '**/WpqrService.cs{1-2}' --break-at 79" > "$D/scripts/run-mutation-gate.sh"
OUT=$(run "$D")
expect_contains "C67 runner literal is checked, with its line"    "scripts/run-mutation-gate.sh:4" "$OUT"
expect_absent   "C67 a \$ pattern is skipped, not guessed"        "run-mutation-gate.sh:3" "$OUT"

# --- C68: the helper missing is UNCHECKED, never clean --------------------------------------------------
D=$(mkfix_pat c68 '["**/WpqrService.cs{845-1080}"]'); rm -f "$D/scripts/stryker_guard.py"
OUT=$(run "$D"); RC=$?
expect_contains "C68 missing helper — said unchecked"             "UNCHECKED" "$OUT"
expect_rc       "C68 verdict is red" 1 "$RC"

# --- C69: a config that is not JSON is named -----------------------------------------------------------
D=$(mkfix_pat c69 '["**/*.cs"]'); printf '{ "stryker-config": { "mutate": [ oops\n' > "$D/stryker-config.json"
OUT=$(run "$D")
expect_contains "C69 unreadable config named"                     "stryker-config.json is not JSON" "$OUT"

# --- C70: --full with a dotnet test live in the project does not start Stryker ---------------------------
# A real process, found the way the helper finds it: by its arguments and its working directory. The stub
# loops until TERM so it is killed by PID, never by a pattern (the 056 trap).
mklive() { # mklive <dir> — a script named dotnet; echo the PID of `dotnet test` running in <dir>
  mkdir -p "$1/live"
  printf '%s\n' '#!/bin/bash' "trap 'exit 0' TERM" 'while :; do sleep 0.2; done' > "$1/live/dotnet"
  chmod +x "$1/live/dotnet"
  ( cd "$1" && exec "$1/live/dotnet" test ) >/dev/null 2>&1 &
  printf '%s' "$!"
}
D=$(mkfix_mut c70 79); mk_dotnet "$D" 90.00 0
LIVE=$(mklive "$D"); sleep 0.5
OUT=$(run_full "$D"); RC=$?
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null
expect_contains "C70 live build — Stryker NOT RUN"                "NOT RUN" "$OUT"
expect_contains "C70 it names the process"                        "pid $LIVE (build)" "$OUT"
expect_contains "C70 and why"                                     "F069" "$OUT"
if [ -d "$D/StrykerOutput" ]; then bad "C70 the stub Stryker never started" "no StrykerOutput" "StrykerOutput exists"; else ok "C70 the stub Stryker never started"; fi
expect_rc       "C70 verdict is red" 1 "$RC"

# --- C71: the same build outside the project does not stop it ------------------------------------------
D=$(mkfix_mut c71 79); mk_dotnet "$D" 90.00 0
O=$(mkfix c71other); LIVE=$(mklive "$O"); sleep 0.5
OUT=$(run_full "$D")
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null
expect_absent   "C71 a build in another project is not this run's" "NOT RUN" "$OUT"
expect_absent   "C71 and the run is clean"                        "[MUTATION]" "$OUT"

# --- C72: a runner with a literal -m and a config with no mutate key is still checked --------------------
D=$(mkfix_mut c72 79); printf '{ "stryker-config": { "project": "App.csproj" } }\n' > "$D/stryker-config.json"
printf '%s\n' '#!/bin/bash' "dotnet stryker -m '**/App.cs{1-2}'" > "$D/scripts/run-mutation-gate.sh"
OUT=$(run "$D")
expect_contains "C72 runner-only pattern is checked"              "scripts/run-mutation-gate.sh:2" "$OUT"

# --- C73-C76: the adversarial review's false findings and silent skips (row 047) ---------------------------
# C73: the .NET config reader takes a BOM, comments and trailing commas; "not JSON" there was a lie.
D=$(mkfix_pat c73 '[]')
printf '\357\273\277{ // written by Visual Studio\n "stryker-config": { "mutate": ["**/WpqrService.cs{845-1080}",], },\n}\n' > "$D/stryker-config.json"
OUT=$(run "$D")
expect_absent   "C73 a BOM-and-comments config is not called unreadable" "is not JSON" "$OUT"
expect_contains "C73 and its pattern is checked"                  "two dots" "$OUT"
# C74: .NET binds configuration keys case-insensitively.
D=$(mkfix_pat c74 '[]'); printf '{ "Stryker-Config": { "Mutate": ["**/Nope.cs"] } }\n' > "$D/stryker-config.json"
OUT=$(run "$D")
expect_contains "C74 a Mutate key in another case is checked"     "'**/Nope.cs' matches no .cs file" "$OUT"
# C75: only a Stryker line's -m is a pattern; a runtime one is said as a note, not passed silently.
D=$(mkfix_pat c75 '["**/*.cs"]')
printf '%s\n' '#!/bin/bash' 'dotnet stryker -m "$SCOPE"' 'grep -m 1 "mutation score" out.log' 'python3 -m json.tool r.json' > "$D/scripts/run-mutation-gate.sh"
OUT=$(run "$D"); RC=$?
expect_absent   "C75 grep -m / python3 -m are not patterns"       "[MUTATION]" "$OUT"
expect_contains "C75 the runtime pattern is said, as a note"      "runtime-assembled" "$OUT"
expect_rc       "C75 a note is not a finding" 0 "$RC"
# C76: one pattern the checker cannot parse does not blind it to the rest.
D=$(mkfix_pat c76 '["src/[z-a].cs", "**/Nope.cs"]')
OUT=$(run "$D")
expect_contains "C76 the unparseable pattern is named"            "could not be parsed" "$OUT"
expect_contains "C76 and the next pattern is still checked"       "'**/Nope.cs' matches no .cs file" "$OUT"

# --- C77: a runner that puts -m on a continuation line is still read (/simplify, row 047) -----------------
# The first draft pre-filtered the runner in bash, one line at a time, and never asked the helper.
D=$(mkfix_mut c77 79); printf '{ "stryker-config": { "project": "App.csproj" } }\n' > "$D/stryker-config.json"
printf '%s\n' '#!/bin/bash' 'dotnet stryker \' "  -m '**/App.cs{1-2}'" > "$D/scripts/run-mutation-gate.sh"
OUT=$(run "$D")
expect_contains "C77 a continued -m line is checked"             "scripts/run-mutation-gate.sh:2" "$OUT"

# --- C78: --full without the helper says the run-alone check was not made -------------------------------
D=$(mkfix_mut c78 79); mk_dotnet "$D" 90.00 0; rm -f "$D/scripts/stryker_guard.py"
OUT=$(run_full "$D")
expect_contains "C78 no helper — run-alone check said UNCHECKED"  "run-alone check UNCHECKED" "$OUT"

# ================================================ C79-C87 — the suite a project declares (row 051)
#
# emaljen runs its suite as bare `node tests/*.mjs` with no package.json, so --suite found nothing and
# the job could never be discharged by the command meant to discharge it. iskvalp keeps jest in
# client/package.json beside a root .sln, so --suite ran `dotnet test` alone and stamped "unit +
# integration + E2E + visual regression" over half of it. .claude/.suite-command is the declaration.
mkdecl() { # mkdecl NAME — a suite fixture with no stack; tests/run.sh prints $SUITE_TEXT, exits $2
  local d; d=$(mkfix "$1")
  mkdir -p "$d/bin" "$d/tests"
  printf '%s\n' "$SUITE_TEXT" > "$d/tests/transcript.txt"
  printf '#!/bin/sh\ncat "%s/tests/transcript.txt"\necho ran >> "%s/ran"\nexit %s\n' "$d" "$d" "${2:-0}" > "$d/tests/run.sh"
  printf '#!/bin/bash\n[ "$1" = --stamp ] && echo "$2" >> "%s/stamped"\nexit 0\n' "$d" > "$d/scripts/maintenance-due.sh"
  cp "$DIR/run-verdict.sh" "$d/scripts/" 2>/dev/null
  printf '%s' "$d"
}
SUITE_TEXT='20 passed, 0 failed'

# --- C79: a declaration with no stack at all — the emaljen case, discharged ---------------------------
D=$(mkdecl c79 0); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(run_suite "$D"); RC=$?
expect_contains "C79 declared command — suite green"             "suite green — \`sh tests/run.sh\`" "$OUT"
expect_contains "C79 provenance is said"                         "declared in .claude/.suite-command" "$OUT"
expect_rc       "C79 declared green — stamped" 1 "$(stamped_suite "$D")"
expect_rc       "C79 clean exit" 0 "$RC"

# --- C80: the declaration outranks a detected stack ---------------------------------------------------
D=$(mkdecl c80 0); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' > "$D/app.csproj"
printf '#!/bin/bash\necho DOTNET-RAN\nexit 0\n' > "$D/bin/dotnet"; chmod +x "$D/bin/dotnet"
OUT=$(run_suite "$D")
expect_absent   "C80 dotnet test is not run"                     "dotnet test" "$OUT"
expect_rc       "C80 the declared command ran" 1 "$(cat "$D/ran" 2>/dev/null | grep -c ran)"
expect_rc       "C80 stamped" 1 "$(stamped_suite "$D")"

# --- C81: comments and blanks before the command are skipped ------------------------------------------
D=$(mkdecl c81 0); printf '# the whole suite: unit + e2e + vrt\n\n   \nsh tests/run.sh\necho second-line\n' > "$D/.claude/.suite-command"
OUT=$(run_suite "$D")
expect_contains "C81 first non-comment line is the command"      "suite green — \`sh tests/run.sh\`" "$OUT"
expect_absent   "C81 later lines are not run"                    "second-line" "$OUT"

# --- C82: a declared command that fails is a finding, and not stamped ---------------------------------
SUITE_TEXT='3 passed, 2 failed'
D=$(mkdecl c82 1); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(run_suite "$D"); RC=$?
expect_contains "C82 declared red — SUITE finding"               "[SUITE] \`sh tests/run.sh\` failed (exit 1)" "$OUT"
expect_rc       "C82 not stamped" 0 "$(stamped_suite "$D")"
expect_rc       "C82 verdict is red" 1 "$RC"

# --- C83: a declared command is still read for an abort -----------------------------------------------
SUITE_TEXT='The active test run was aborted. Reason: Test host process crashed
Passed!  - Failed: 0, Passed: 10, Skipped: 0, Total: 10'
D=$(mkdecl c83 0); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(run_suite "$D")
expect_contains "C83 declared abort — named as aborted"          "the test run ABORTED" "$OUT"
expect_rc       "C83 not stamped" 0 "$(stamped_suite "$D")"
SUITE_TEXT='Passed!  - Failed:     0, Passed:    12, Skipped:     0, Total:    12'

# --- C84: the iskvalp shape — dotnet green, jest beside it, nothing declared ---------------------------
D=$(mksuite c84 0); mkdir -p "$D/client"
printf '{ "scripts": { "test": "jest" } }\n' > "$D/client/package.json"
mkdir -p "$D/client/node_modules/dep"; printf '{ "scripts": { "test": "x" } }\n' > "$D/client/node_modules/dep/package.json"
mkdir -p "$D/node_modules/dep"; printf '{ "scripts": { "test": "x" } }\n' > "$D/node_modules/dep/package.json"
OUT=$(run_suite "$D"); RC=$?
expect_contains "C84 half suite — a SUITE finding"               "[SUITE] \`dotnet test\` is green, but it is not the whole suite" "$OUT"
expect_contains "C84 names the uncovered manifest"               "client/package.json" "$OUT"
expect_absent   "C84 node_modules is not a test surface"         "node_modules" "$OUT"
expect_contains "C84 names the declaration"                      ".claude/.suite-command" "$OUT"
expect_rc       "C84 not stamped" 0 "$(stamped_suite "$D")"
expect_rc       "C84 verdict is red" 1 "$RC"

# --- C85: the same shape with a nested manifest that has no test script stays green --------------------
D=$(mksuite c85 0); mkdir -p "$D/client"; printf '{ "scripts": { "build": "vite" } }\n' > "$D/client/package.json"
OUT=$(run_suite "$D")
expect_rc       "C85 no nested test script — stamped" 1 "$(stamped_suite "$D")"

# --- C86: the emaljen shape with no declaration — says where to declare, runs nothing -----------------
D=$(mkdecl c86 0)
printf '# unit slice\nsh tests/run.sh --unit\n' > "$D/.claude/.template-sync-verify"
OUT=$(run_suite "$D"); RC=$?
expect_contains "C86 nothing to run — names the declaration"     ".claude/.suite-command" "$OUT"
expect_contains "C86 the sync-verify command is a quoted candidate" "sh tests/run.sh --unit" "$OUT"
expect_rc       "C86 the sync-verify command is never run" 0 "$(cat "$D/ran" 2>/dev/null | grep -c ran)"
expect_rc       "C86 not stamped" 0 "$(stamped_suite "$D")"
expect_rc       "C86 a note, not a finding" 0 "$RC"

# --- C87: --full on a stack with no mutation runner says so -------------------------------------------
D=$(mkfix c87)
OUT=$(run_full "$D")
expect_contains "C87 no mutation runner — said"                  "no mutation runner" "$OUT"
expect_contains "C87 names the project-owned runner"             "scripts/run-mutation-gate.sh" "$OUT"

# ============================================================== row 052: ratchets + the build target
# Half 1: every scripts/check-*.sh runs in every pass (ighweld F062 — thirteen ratchets, none invoked).
# Half 2: a bare `dotnet test` / `dotnet stryker` at a root beside a second solution builds whichever
# one sits there; ighweld's dead root .sln turned a 7478/0 green project red on 2026-09-18.
mkratchet() { # mkratchet DIR NAME BODY — a ratchet script with the given body
  printf '#!/bin/bash\n%s\n' "$3" > "$1/scripts/$2"
}

# --- C88: a failing ratchet is a finding with its name, exit code and output (AC1) ------------------
D=$(mkfix c88); mkratchet "$D" check-silent-catches.sh 'echo "3 silent catch(es) over the floor of 0"; exit 1'
OUT=$(run "$D"); RC=$?
expect_contains "C88 failing ratchet — a RATCHET finding"        "[RATCHET] scripts/check-silent-catches.sh failed (exit 1)" "$OUT"
expect_contains "C88 its output is quoted"                       "3 silent catch(es) over the floor of 0" "$OUT"
expect_rc       "C88 verdict is red" 1 "$RC"

# --- C89: a passing ratchet says nothing (AC2) -------------------------------------------------------
D=$(mkfix c89); mkratchet "$D" check-css-classes.sh 'echo "all classes defined"; exit 0'
OUT=$(run "$D"); RC=$?
expect_absent   "C89 green ratchet — no finding"                 "[RATCHET]" "$OUT"
expect_absent   "C89 green ratchet — its output is not echoed"   "all classes defined" "$OUT"
expect_rc       "C89 verdict is green" 0 "$RC"

# --- C90: it runs from the root, with no arguments and stdin closed --------------------------------
D=$(mkfix c90); mkratchet "$D" check-where.sh 'pwd > .ratchet-pwd; echo "$#" > .ratchet-argc; if read -r _; then exit 3; fi; exit 0'
OUT=$(run "$D"); RC=$?
expect_rc       "C90 ran from the repo root" 0 "$( [ "$(cat "$D/.ratchet-pwd" 2>/dev/null)" = "$(cd "$D" && pwd -P)" ] || [ "$(cat "$D/.ratchet-pwd" 2>/dev/null)" = "$(cd "$D" && pwd)" ]; echo $?)"
expect_rc       "C90 no arguments" 0 "$(cat "$D/.ratchet-argc" 2>/dev/null)"
expect_rc       "C90 stdin closed — green" 0 "$RC"

# --- C91: a hanging ratchet is bounded and said to have timed out (AC3) -----------------------------
D=$(mkfix c91); mkratchet "$D" check-hangs.sh 'sleep 6; exit 0'
T0=$(date +%s); OUT=$(run "$D" MAINTENANCE_RATCHET_TIMEOUT=1); RC=$?; T1=$(date +%s)
expect_contains "C91 hanging ratchet — timed out"                "[RATCHET] scripts/check-hangs.sh timed out after 1s" "$OUT"
expect_rc       "C91 the pass did not wait for it" 0 "$( [ $((T1 - T0)) -lt 5 ]; echo $?)"
expect_rc       "C91 verdict is red" 1 "$RC"

# --- C92: a reasoned skip marker keeps it from running and says why (AC4) ---------------------------
D=$(mkfix c92); mkratchet "$D" check-env.sh '# maintenance: skip needs the production .env
echo ran > .ratchet-ran; exit 1'
OUT=$(run "$D"); RC=$?
expect_absent   "C92 skipped — no finding"                       "[RATCHET]" "$OUT"
expect_rc       "C92 skipped — never executed" 1 "$( [ -f "$D/.ratchet-ran" ]; echo $?)"
expect_contains "C92 the note names the ratchet and the reason"  "scripts/check-env.sh — needs the production .env" "$OUT"
expect_rc       "C92 verdict is green" 0 "$RC"

# --- C93: a skip marker with no reason is ignored, and the note says so (AC5) -----------------------
D=$(mkfix c93); mkratchet "$D" check-lazy.sh '# maintenance: skip
echo "lazy ratchet ran"; exit 1'
OUT=$(run "$D"); RC=$?
expect_contains "C93 reasonless skip — it ran and failed"        "[RATCHET] scripts/check-lazy.sh failed (exit 1)" "$OUT"
expect_contains "C93 the note says the marker was ignored"       "scripts/check-lazy.sh: skip marker has no reason — ignored" "$OUT"

# --- C94: no ratchets, no ratchet output (AC6) — and a non-.sh check file is not one -----------------
D=$(mkfix c94); printf '12\n' > "$D/scripts/check-e2e-typecheck.floor"
OUT=$(run "$D"); RC=$?
expect_absent   "C94 no ratchets — nothing said"                 "ratchet" "$OUT"
expect_rc       "C94 verdict is green" 0 "$RC"

# The ighweld shape: a dead solution at the root and the real one two levels down. Every dotnet
# invocation is recorded, so "never invoked" is measured rather than inferred from the output.
two_solutions() { # two_solutions DIR
  printf 'Microsoft Visual Studio Solution File\n' > "$1/IGHWeld.Web.sln"
  mkdir -p "$1/src/welding"; printf 'Microsoft Visual Studio Solution File\n' > "$1/src/welding/Welding.sln"
  printf '#!/bin/bash\necho "$*" >> "%s/dotnet-ran"\ncat "%s/bin/transcript.txt" 2>/dev/null\nexit 0\n' "$1" "$1" > "$1/bin/dotnet"
  chmod +x "$1/bin/dotnet"
}
SUITE_TEXT='Passed!  - Failed:     0, Passed:    12, Skipped:     0, Total:    12'

# --- C95: two solutions, nothing declared, --suite — refused, named, nothing run (AC7) --------------
D=$(mksuite c95 0); two_solutions "$D"
OUT=$(run_suite "$D"); RC=$?
expect_contains "C95 ambiguous build target — a SUITE finding"   "[SUITE] NOT RUN — 2 .NET solutions and nothing declared" "$OUT"
expect_contains "C95 names the root solution"                    "IGHWeld.Web.sln" "$OUT"
expect_contains "C95 names the nested solution"                  "src/welding/Welding.sln" "$OUT"
expect_contains "C95 names the declaration"                      ".claude/.suite-command" "$OUT"
expect_rc       "C95 dotnet never invoked" 1 "$( [ -f "$D/dotnet-ran" ]; echo $?)"
expect_rc       "C95 not stamped" 0 "$(stamped_suite "$D")"
expect_rc       "C95 verdict is red" 1 "$RC"

# --- C96: the same shape with a declaration runs the declaration and stamps (AC8) -------------------
D=$(mksuite c96 0); two_solutions "$D"
printf 'dotnet test src/welding/Welding.sln\n' > "$D/.claude/.suite-command"
OUT=$(run_suite "$D")
expect_contains "C96 declared — suite green"                     "suite green — \`dotnet test src/welding/Welding.sln\`" "$OUT"
expect_rc       "C96 stamped" 1 "$(stamped_suite "$D")"

# --- C97: two solutions, --full, no runner — the bare stryker is refused (AC9) ----------------------
D=$(mkfix_mut c97 80); two_solutions "$D"
printf '#!/bin/bash\n[ "$1" = --stamp ] && echo "$2" >> "%s/stamped"\nexit 0\n' "$D" > "$D/scripts/maintenance-due.sh"
OUT=$(run_full "$D"); RC=$?
expect_contains "C97 ambiguous build target — a MUTATION finding" "[MUTATION] NOT RUN — 2 .NET solutions and no project-owned runner" "$OUT"
expect_contains "C97 names both solutions"                       "src/welding/Welding.sln" "$OUT"
expect_contains "C97 names the runner to declare"                "scripts/run-mutation-gate.sh" "$OUT"
expect_rc       "C97 dotnet never invoked" 1 "$( [ -f "$D/dotnet-ran" ]; echo $?)"
expect_rc       "C97 mutation not stamped" 0 "$(grep -cx mutation "$D/stamped" 2>/dev/null)"
expect_rc       "C97 verdict is red" 1 "$RC"

# --- C98: no timeout binary — the ratchet still runs, and the pass says it ran unbounded --------------
# Only measurable where /usr/bin:/bin carries no timeout (macOS without coreutils on that PATH); on
# Linux coreutils puts it there, and the arm is reported as not exercised rather than passed.
if ! PATH=/usr/bin:/bin command -v timeout >/dev/null 2>&1 && ! PATH=/usr/bin:/bin command -v gtimeout >/dev/null 2>&1; then
  D=$(mkfix c98); mkratchet "$D" check-plain.sh 'echo ran > .ratchet-ran; exit 0'
  OUT=$(run "$D" PATH=/usr/bin:/bin); RC=$?
  expect_rc       "C98 no timeout binary — the ratchet still ran" 0 "$( [ -f "$D/.ratchet-ran" ]; echo $?)"
  expect_contains "C98 the pass says it ran unbounded"            "ratchets ran unbounded" "$OUT"
else
  printf '  --   C98 not exercised: this host has timeout in /usr/bin:/bin\n'
fi

# --- C99/C100: an abandoned StrykerJS sandbox is swept before the run starts (row 053) ----------------
mk_dotnet_ran() { # mk_dotnet_ran <dir> — a dotnet that records it ran and scores 90
  printf '%s\n' '#!/bin/bash' 'touch dotnet-ran' 'echo "The final mutation score is 90.00 %"' 'exit 0' > "$1/bin/dotnet"
  chmod +x "$1/bin/dotnet"
}
D=$(mkfix_mut c99 80); mk_dotnet_ran "$D"
mkdir -p "$D/client/.stryker-tmp/sandbox-a1b2/src"; printf '{}\n' > "$D/client/.stryker-tmp/sandbox-a1b2/package.json"
OUT=$(run_full "$D")
expect_rc       "C99 the abandoned sandbox is gone" 1 "$( [ -d "$D/client/.stryker-tmp" ]; echo $?)"
expect_contains "C99 the pass says what it swept"   "client/.stryker-tmp" "$OUT"
expect_rc       "C99 the run still ran"             0 "$( [ -f "$D/dotnet-ran" ]; echo $?)"

D=$(mkfix_mut c100 80); mk_dotnet_ran "$D"
printf '#!/bin/bash\n[ "$1" = --stamp ] && echo "$2" >> "%s/stamped"\nexit 0\n' "$D" > "$D/scripts/maintenance-due.sh"
mkdir -p "$D/.stryker-tmp/backup-9f/src"; printf 'original\n' > "$D/.stryker-tmp/backup-9f/src/a.js"
OUT=$(run_full "$D"); RC=$?
expect_contains "C100 an in-place backup refuses the run" "[MUTATION] NOT RUN — an interrupted in-place Stryker run" "$OUT"
expect_contains "C100 names the backup"                   ".stryker-tmp" "$OUT"
expect_rc       "C100 the backup is untouched"            0 "$( [ -f "$D/.stryker-tmp/backup-9f/src/a.js" ]; echo $?)"
expect_rc       "C100 dotnet never invoked"               1 "$( [ -f "$D/dotnet-ran" ]; echo $?)"
expect_rc       "C100 mutation not stamped"               0 "$(grep -cx mutation "$D/stamped" 2>/dev/null)"
expect_rc       "C100 verdict is red"                     1 "$RC"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
