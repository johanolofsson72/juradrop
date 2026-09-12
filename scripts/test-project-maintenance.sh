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
mk_dotnet() { # mk_dotnet <dir> <score or "none"> <exit code>
  if [ "$2" = "none" ]; then
    printf '%s\n' '#!/bin/bash' 'echo "MSBUILD : error MSB1003: no project file"' "exit $3" > "$1/bin/dotnet"
  else
    printf '%s\n' '#!/bin/bash' 'echo "Stryker.NET"' "echo \"The final mutation score is $2 %\"" "exit $3" > "$1/bin/dotnet"
  fi
  chmod +x "$1/bin/dotnet"
}

run_full() { ( cd "$1" && PATH="$1/bin:$PATH" bash "$MAINT" --full 2>&1 ); }

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

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
