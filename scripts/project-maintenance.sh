#!/bin/bash
# project-maintenance.sh — the recurring local maintenance pass.
#
# WHY THIS EXISTS. Three documents (.claude/docs/testing.md, spec-testing-checklist.md,
# .claude/rules/tests.md) describe the mutation gate as running "nightly/on-demand",
# and .claude/rules/github-actions.md correctly bans `schedule:` triggers after the
# iskvalp incident (3000 Actions minutes in four days). Net result: "nightly" ran
# never. Same for scripts/project-freshness.sh — a secret + CVE scan nobody schedules
# is a secret + CVE scan that does not happen. This script is the local, zero-minute
# answer: one command a recurring loop can call.
#
# ATTENTION MODE. A recurring job that reports at length when nothing changed teaches
# you to ignore it, and then you ignore the one run that mattered. Clean run → one
# line. Findings → the full report, loudest first. Exit code carries the verdict, so
# a scheduler can branch on it.
#
# Usage:
#   bash scripts/project-maintenance.sh            # report-only sweep (fast)
#   bash scripts/project-maintenance.sh --full     # also run the mutation pass (slow)
#   bash scripts/project-maintenance.sh --quiet    # findings only, no clean-run line
#
# MAINTENANCE_WORKTREE_GRACE_HOURS=N  how long an agent worktree may sit untouched
#   before it is reported as abandoned (default 24). Agent worktrees are not locked,
#   so recency of writes is the only signal that one is still in use; the window keeps
#   a healthy in-progress agent run from producing a finding.
#
# Wire it to a recurring run WITHOUT touching CI minutes:
#   /schedule  — a cloud routine, e.g. weekly Monday 08:00:
#                "run bash scripts/project-maintenance.sh and report only if it exits non-zero"
#   /loop 7d   — a session-bound repeat while you are working
#   crontab    — 0 8 * * 1 cd /path/to/repo && bash scripts/project-maintenance.sh
# NEVER as a GitHub Action `schedule:` trigger — that is the banned pattern.
#
# Exit codes: 0 = clean · 1 = findings reported · 2 = a requested step could not run.
#
# bash 3.2-safe (macOS system bash), cross-platform (macOS / Linux / Windows Git Bash).

set -uo pipefail

FULL=0
IF_DUE=0
SUITE=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --full)  FULL=1 ;;
    --if-due) IF_DUE=1 ;;
    --suite) SUITE=1 ;;
    --quiet) QUIET=1 ;;
    # Print the whole leading comment block, not a hardcoded line range: this header
    # has grown twice now, and a range silently truncates --help when it does.
    -h|--help) awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$ROOT" || exit 2

# --if-due: the whole point of scripts/maintenance-due.sh. A scheduled run that has nothing to do
# should cost nothing, so a cron entry stops being a bet that tonight is a night with work in it.
#
# It FAILS OPEN. If the due engine cannot answer -- missing, unreadable, a python3 that is not there
# -- this runs the full pass rather than skipping it. The opposite default would turn any breakage
# in a reporting script into a maintenance pass that silently never runs again, which is the exact
# shape .claude/rules/github-actions.md records twice as "nightly quietly meaning never".
if [ "$IF_DUE" -eq 1 ]; then
  if [ -f scripts/maintenance-due.sh ]; then
    if bash scripts/maintenance-due.sh --any >/dev/null 2>&1; then
      : # something is due -- fall through and do the work
    elif [ "$?" -eq 1 ]; then
      [ "$QUIET" -eq 1 ] || echo "project-maintenance: nothing due — skipped (bash scripts/maintenance-due.sh to see why)."
      exit 0
    fi
  fi
fi

FINDINGS=0
REPORT=""
add() { REPORT="${REPORT}$1
"; FINDINGS=$((FINDINGS + 1)); }

# A second buffer, for sections that must REPORT without FAILING. `add` is both the finding
# counter and the only route to output, so a section using it can only speak by making the run
# red -- and a run that is red forever is a run nobody reads. `note` speaks without voting, and
# the verdict prints NOTES in BOTH branches (clean and findings), or a note would only ever
# surface when something else had already gone wrong.
NOTES=""
note() { NOTES="${NOTES}$1
"; }

# ---------------------------------------------------------------- 1. secrets + CVEs
if [ -f scripts/project-freshness.sh ]; then
  FRESH_OUT=$(bash scripts/project-freshness.sh 2>&1)
  FRESH_RC=$?
  if [ "$FRESH_RC" -ne 0 ]; then
    add "[SECRETS/DEPS] scripts/project-freshness.sh reported findings:
$(printf '%s' "$FRESH_OUT" | tail -25)"
  fi
else
  add "[SETUP] scripts/project-freshness.sh missing — run /project-update to restore it."
fi

# ------------------------------------------------------- 2. per-spec-read file bloat
# Same 25 KB threshold as the SessionStart canary in spec-register-orientation-hook.sh.
#
# Spec 007bl added the second shape a scenario map can take: an index plus per-feature files
# under specs/scenarios/. Every one of those is read when its feature is worked, so each is
# measured on its own. They are never summed — nothing reads all of them in one spec, so a sum
# would fire forever on a map that is behaving exactly as designed, and an un-actionable
# warning is the thing this section exists to remove rather than reproduce. The glob simply
# matches nothing on the 41 projects that never split, so their output is unchanged.
for f in specs/INDEX.md specs/SCENARIOS.md specs/scenarios/*.md; do
  [ -f "$f" ] || continue
  BYTES=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  case "$BYTES" in (''|*[!0-9]*) BYTES=0 ;; esac
  if [ "$BYTES" -gt 25600 ]; then
    # Which script to name depends on where the bytes are. Spec 007ce measured
    # specs/INDEX.md at 91.4% spec rows against 4.8% history, so naming the history
    # archiver on the register sent people at 1,918 bytes while 36,521 sat untouched.
    case "$f" in
      */INDEX.md) HINT="scripts/archive-completed-rows.sh (rows), scripts/archive-spec-history.sh --keep 5 (history)" ;;
      *)          HINT="scripts/archive-spec-history.sh --keep 5" ;;
    esac
    add "[CONTEXT-COST] $f is $((BYTES / 1024)) KB — read on every spec. Trim: $HINT"
  fi
done

# ------------------------------------------------------------ 2b. SC-id traceability
# Both directions over the scenario map (spec 007bs):
#   uncovered  a row claims it is tested or validated, and no test names its id
#   dangling   a test names an id the map does not have
#
# UNCOVERED IS A NOTE, NOT A FINDING -- the deliberate asymmetry. On the project that built this
# gate the honest first report was 122 of 150, and closing the other 28 is a register row's worth
# of work per feature. Wiring that into the exit code would make maintenance permanently red, and
# .claude/rules/github-actions.md already argues that a permanently-red signal is an absent one.
# DANGLING IS A FINDING -- that direction is never a backlog. A test naming an id the map does not
# have is a typo or a row deleted out from under a test, and it is zero on a healthy repo, so the
# signal stays quiet until something actually breaks.
if [ -f scripts/validate-scenario-traceability.sh ] && [ -f specs/SCENARIOS.md ]; then
  TRACE_OUT=$(bash scripts/validate-scenario-traceability.sh --quiet 2>&1)
  TRACE_RC=$?
  case "$TRACE_RC" in
    # 6 is a VERDICT, not a failure to run: it is exit 1 with the duplicate-id half
    # split out so a collision cannot hide behind a permanently-red coverage
    # backlog. Leaving it in the catch-all turned the very finding that split
    # earned into "could not run", which is the report the split existed to stop.
    # 7 is NOT APPLICABLE: the project has no scenario map. Silent on purpose --
    # a project that legitimately owns no scenarios should not carry a finding
    # every pass for not having them.
    7) : ;;
    0|1|6)
      TRACE_COV=$(printf '%s\n' "$TRACE_OUT" | grep '^coverage:' | head -1)
      [ -n "$TRACE_COV" ] && note "[TRACEABILITY] $TRACE_COV"
      TRACE_DANGL=$(printf '%s\n' "$TRACE_OUT" | sed -n 's/^dangling .*(\([0-9]*\)):$/\1/p')
      if [ -n "$TRACE_DANGL" ] && [ "$TRACE_DANGL" -gt 0 ]; then
        add "[TRACEABILITY] $TRACE_DANGL test reference(s) name an SC-id the scenario map does not have. Run: bash scripts/validate-scenario-traceability.sh"
      fi
      # A FINDING for the same reason dangling is one: an id is a permanent handle, so a repeat is a
      # mistake and not a backlog. It is also the one that quietly degrades the coverage line printed
      # as a note two lines up -- with two rows under one id, "429 of 472" is counting handles, not
      # scenarios.
      TRACE_DUP=$(printf '%s\n' "$TRACE_OUT" | sed -n 's/^duplicate .*(\([0-9]*\)):$/\1/p')
      if [ -n "$TRACE_DUP" ] && [ "$TRACE_DUP" -gt 0 ]; then
        add "[TRACEABILITY] $TRACE_DUP scenario id(s) appear on more than one row. Run: bash scripts/validate-scenario-traceability.sh"
      fi
      ;;
    *)
      # 2, 3 and 4 all mean "the gate could not answer" -- never reported as coverage.
      add "[TRACEABILITY] scripts/validate-scenario-traceability.sh could not run (exit $TRACE_RC):
$(printf '%s' "$TRACE_OUT" | tail -5)"
      ;;
  esac
fi

# --------------------------------------------- 2c. SIGPIPE assertions in self-tests
# `printf '%s' "$OUT" | grep -q PAT` under `set -o pipefail`: grep leaves at the match, printf keeps
# writing into a reader-less pipe, takes SIGPIPE, and the PIPELINE returns 141 rather than grep's 0. A
# positive assertion then reads a true claim as FALSE; a negated one reports PASS for exactly the state
# it forbids -- the silent direction, and 46 of the 215 sites the gate was first written against. Rows
# H7x and H7aw swept 52 such sites out of eight self-tests; nothing stops the idiom coming back, and a
# template is where one reintroduced line reaches every project on its next session start.
#
# A FINDING, NOT A NOTE -- deliberately the other side of 2b's asymmetry. Uncovered scenarios are a
# backlog and wiring a backlog into the exit code makes maintenance permanently red; this is not a
# backlog. Every hit has a one-line mechanical fix (a here-string), and the gate already declines to
# report what this tree cannot durably fix: downstream it exempts the sync-owned files because those are
# scanned in the template itself (row H7ax). So the number is zero on a healthy repo, and it cannot creep
# up merely because a project got large.
if [ -f scripts/validate-no-sigpipe-assertions.sh ]; then
  SIGPIPE_OUT=$(bash scripts/validate-no-sigpipe-assertions.sh 2>&1)
  SIGPIPE_RC=$?
  case "$SIGPIPE_RC" in
    0) : ;;   # clean, or NOT RUN because every self-test here is sync-owned. Attention mode: say nothing.
    1)
      add "[SIGPIPE] self-test assertion(s) pipe into an early-exit consumer. Under set -o pipefail a true
claim reads as false, and a NEGATED one passes for the state it forbids. Run: bash scripts/validate-no-sigpipe-assertions.sh
$(sed -n '1,6p' <<< "$SIGPIPE_OUT")"
      ;;
    *)
      # 2 is "nothing to scan" or "a boundary I refuse to guess" -- never reported as a clean tree.
      add "[SIGPIPE] scripts/validate-no-sigpipe-assertions.sh could not run (exit $SIGPIPE_RC):
$(tail -5 <<< "$SIGPIPE_OUT")"
      ;;
  esac
fi

# ------------------------------------------------------ 2d. register id health
# Classifiable, unique, unambiguous. The first is row H7b's check and it has run in this project since
# the day it shipped -- in the template's other projects, via scripts/run-gates.sh. Here there is no
# run-gates.sh, so until row 007ch the gate had no caller at all and its own header still named one.
# A gate nobody runs is the shape this repo keeps paying for: 007ce found archive-completed-rows.sh had
# stopped running, and .claude/rules/github-actions.md records "nightly" quietly meaning "never" for the
# mutation gate and the secret scan. This is the caller.
#
# A FINDING, not a note -- the same argument 2b makes for duplicate SC-ids, an id is a permanent handle
# so a repeat is a mistake and not a backlog, with a sharper consequence. A duplicate SPEC id miscounts
# nothing; it makes both BLOCKING PreToolUse guards read another row's artifacts and approve a source
# edit for a spec that has none (007ch research.md M4, measured against a control).
if [ -f scripts/validate-register-ids.sh ] && [ -f specs/INDEX.md ]; then
  REGID_OUT=$(bash scripts/validate-register-ids.sh 2>&1)
  REGID_RC=$?
  case "$REGID_RC" in
    0) : ;;   # classifiable, unique, unambiguous. Attention mode: say nothing.
    1)
      # No silent cap. An excerpt that stops without saying so reads as the whole finding -- the rule
      # scripts/bash-write-detect-hook.sh states for its own report, and the gate's output is long
      # precisely because each failure explains itself.
      REGID_DETAIL=$(sed -n '/^FAIL/,$p' <<< "$REGID_OUT")
      REGID_LINES=$(wc -l <<< "$REGID_DETAIL" | tr -dc '0-9'); REGID_LINES=${REGID_LINES:-0}
      REGID_MORE=""
      [ "$REGID_LINES" -gt 8 ] && REGID_MORE="
    ... $((REGID_LINES - 8)) more line(s) — run the gate for the rest."
      add "[REGISTER-IDS] the register has an id the resolver cannot classify, or one id on two rows or two
directories. Both PreToolUse pipeline guards resolve the active row's id, so this is an edit block or a
bypass, not a cosmetic complaint. Run: bash scripts/validate-register-ids.sh
$(sed -n '1,8p' <<< "$REGID_DETAIL")$REGID_MORE"
      ;;
    *)
      # 2 is "the register could not be read" -- a different fact from "the register is bad", and the
      # distinction is the whole reason that gate has three exit codes. Never reported as clean.
      add "[REGISTER-IDS] scripts/validate-register-ids.sh could not run (exit $REGID_RC):
$(tail -5 <<< "$REGID_OUT")"
      ;;
  esac
fi

# --------------------------------------------------------- 3. blocked / stalled rows
if [ -f specs/INDEX.md ]; then
  BLOCKED=$(grep -cE '^- \[!\]' specs/INDEX.md 2>/dev/null | tr -dc '0-9'); BLOCKED=${BLOCKED:-0}
  INPROG=$(grep -cE '^- \[/\]' specs/INDEX.md 2>/dev/null | tr -dc '0-9'); INPROG=${INPROG:-0}
  DONE=$(grep -cE '^- \[x\]' specs/INDEX.md 2>/dev/null | tr -dc '0-9'); DONE=${DONE:-0}
  [ "${BLOCKED:-0}" -gt 0 ] && add "[REGISTER] $BLOCKED row(s) marked blocked \`- [!]\` — a register-rewrite decision is pending."
  [ "${INPROG:-0}" -gt 1 ] && add "[REGISTER] $INPROG rows marked in-progress \`- [/]\` — only one spec runs at a time."
  # Integration-hardening checkpoint cadence (.claude/rules/spec-hardening.md).
  if [ "${DONE:-0}" -gt 0 ] && [ $((DONE % 5)) -eq 0 ]; then
    if ! grep -qiE '^- \[[ /]\].*checkpoint' specs/INDEX.md 2>/dev/null; then
      add "[HARDENING] $DONE specs done (multiple of 5) but no pending checkpoint row — insert an integration-hardening checkpoint before the next feature spec."
    fi
  fi
fi

# ------------------------------------------------- 3c. does the register converge?
# The one measurement that says whether the pipeline is finishing anything. Every
# other check here finds work; this one asks whether the finding is outrunning the
# closing. Measured 2026-09-03 across five projects: rocky 2.15, agentcrm 2.08,
# consultpilot 1.30 -- all diverging. See .claude/rules/carve-budget.md.
if [ -f specs/INDEX.md ] && [ -x scripts/register-convergence.sh ]; then
  CONV_OUT=$(bash scripts/register-convergence.sh --quiet 2>&1); CONV_RC=$?
  case "$CONV_RC" in
    2) add "[CONVERGENCE] $CONV_OUT" ;;
    1) note "[note] $CONV_OUT" ;;
    3|4) : ;;  # too little history, or no register -- not a finding
  esac
fi

# ------------------------------------------------------- 3e. script mode drift
# A .sh without its executable bit still runs as `bash X`, so nothing fails --
# it fails only where something guards with `-x`, and then it fails SILENTLY.
# Eight CORE scripts shipped that way and the sync copied the modes faithfully
# to every project; the defect surfaced only when a new script guarded with -x
# and skipped its whole check without a word.
if [ -d scripts ]; then
  NOEXEC=$(for f in scripts/*.sh; do [ -f "$f" ] && [ ! -x "$f" ] && basename "$f"; done | tr '\n' ' ')
  [ -n "$NOEXEC" ] && add "[SCRIPT MODE] shell script(s) without the executable bit: $NOEXEC
Harmless under \`bash X\`, silent under an \`-x\` guard. Fix: chmod +x scripts/<name>"
fi

# ------------------------------------------------- 3d. is a row already written?
# Local embedding pass over every register on the machine. Slow-ish (minutes on a
# few hundred rows) and needs Ollama, so it runs only in --full, and its absence is
# not a finding -- a maintenance pass that fails because a service is off gets
# switched off.
if [ "$FULL" -eq 1 ] && [ -f specs/INDEX.md ] && [ -x scripts/register-similarity.sh ]; then
  SIM_OUT=$(bash scripts/register-similarity.sh --open-only 2>/dev/null); SIM_RC=$?
  case "$SIM_RC" in
    1) add "[DUPLICATE ROWS] $(printf '%s' "$SIM_OUT" | head -20)" ;;
    2) note "[note] duplicate-row check skipped — no local embedding model reachable. It is the
only check here that needs one; everything else above ran. \`ollama pull paraphrase-multilingual\`
to enable it, or ignore this line: a machine without Ollama is a supported configuration." ;;
  esac
fi

# ------------------------------------------------------- 3b. spec-kit installation
# The blind spot this section closes. Nothing in the template ever noticed that a
# project's spec-kit was missing or years behind, because template-autosync.sh does
# not install spec-kit -- only /project-update does -- and no check compared the two.
# The result, measured across 42 projects: eight with no .specify at all (seven of
# them with zero speckit skills, so /speckit-specify could not run and the pipeline
# was decorative), one on 0.8.14, one on 0.9.1 -- versions predating the hyphenated
# skill names every rule in .claude/rules/ refers to. All of them looked healthy: the
# template sync reported "already at template" because the template half WAS current.
#
# Report-only. Installing spec-kit needs a real /project-update (it re-inits, merges
# CLAUDE.md and re-decides the tech stack), which is a judgment pass, not a sweep.
# A repo with no LANGUAGE MARKER is a template or scratch tree, and every guard in
# this family already stays silent on one -- spec-register-guard, the orientation
# hook, the pipeline state guard. The condition here was "has a register OR has
# .specify", and the template acquired a register on 2026-09-03 for its own
# machinery rows. It has no source code, so /speckit-specify has nothing to
# specify, and the pass began telling the config repo to run /project-update on
# itself. Same not-applicable-is-not-broken distinction as the traceability
# gate's exit 7.
SK_IS_PROJECT=0
for marker in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile build.gradle build.gradle.kts pom.xml pubspec.yaml; do
  [ -f "$marker" ] && SK_IS_PROJECT=1 && break
done
if [ "$SK_IS_PROJECT" -eq 0 ]; then
  ls ./*.csproj ./*.sln >/dev/null 2>&1 && SK_IS_PROJECT=1
fi

if [ "$SK_IS_PROJECT" -eq 1 ] && { [ -f specs/INDEX.md ] || [ -d .specify ]; }; then
  SK_SKILLS=$(find .claude/skills -maxdepth 1 -type d -name 'speckit*' 2>/dev/null | wc -l | tr -d ' ')
  case "$SK_SKILLS" in (''|*[!0-9]*) SK_SKILLS=0 ;; esac
  SK_VER=""
  if [ -f .specify/init-options.json ] && command -v python3 >/dev/null 2>&1; then
    SK_VER=$(python3 -c 'import json,sys
try: print(json.load(open(".specify/init-options.json")).get("speckit_version",""))
except Exception: print("")' 2>/dev/null)
  fi

  if [ ! -d .specify ]; then
    add "[SPECKIT] no .specify/ — spec-kit is not installed, so the pipeline's phases (/speckit-specify … /speckit-implement) cannot run. ${SK_SKILLS} speckit skill(s) on disk. Run /project-update."
  elif [ "$SK_SKILLS" -eq 0 ]; then
    add "[SPECKIT] .specify/ exists but no speckit skills are installed — the phases cannot be invoked. Run /project-update."
  elif [ -z "$SK_VER" ]; then
    add "[SPECKIT] .specify/init-options.json records no speckit_version — the install predates version stamping. Run /project-update to land a current spec-kit."
  else
    case "$SK_VER" in
      1.*) ;;                                   # current line
      0.16.*) ;;                                # previous line, still supported
      *) add "[SPECKIT] spec-kit $SK_VER is well behind the 1.x line — versions before 0.10 use unhyphenated phase names (/specify, not /speckit-specify), which every rule in .claude/rules/ assumes. Run /project-update." ;;
    esac
  fi
fi

# ------------------------------------------------------------ 4. stale attempt state
if [ -d .claude/state/attempts ]; then
  STALE=$(find .claude/state/attempts -type f -mtime +1 2>/dev/null | wc -l | tr -d ' ')
  case "$STALE" in (''|*[!0-9]*) STALE=0 ;; esac
  [ "$STALE" -gt 0 ] && find .claude/state/attempts -type f -mtime +1 -delete 2>/dev/null
fi

# ------------------------------------------------- 4b. abandoned agent worktrees
# WHY. scripts/prune-agent-worktrees.sh was written because agent worktrees
# (.claude/worktrees/agent-*, created by `isolation: worktree`) accumulate disk AND
# strand agent memory -- a subagent writes to ITS worktree's .claude/agent-memory/ and
# nothing merges it back. Nothing ever ran it, which is the same defect this whole
# script exists to end: see the header, "nightly ran never".
#
# Measured across ~/repos on 2026-08-26: 7 abandoned worktrees in 4 projects, 733 MB,
# the oldest 149 days, holding 6 memory files that existed nowhere else -- one of them
# a security-scanner adversarial review in a checkout twelve days dead.
#
# REPORT-ONLY, deliberately. Not one agent worktree in that fleet was locked, so
# nothing here can tell a live agent from a dead one with certainty, and an unattended
# job that deletes checkouts on that guess is a bad trade for 733 MB. Section 4 above
# is not a precedent: an attempt-state file is a byte-sized counter with nothing
# salvageable inside, and a worktree is the opposite on both counts.
#
# The grace window is the honest substitute for a lock. A worktree written to recently
# is presumed live and stays out of the report entirely, so a healthy agent run in
# progress never produces a finding -- which is what keeps this section from becoming
# the noise the header's attention-mode rule warns about.
if [ -d .claude/worktrees ]; then
  GRACE_H=${MAINTENANCE_WORKTREE_GRACE_HOURS:-24}
  case "$GRACE_H" in (''|*[!0-9]*) GRACE_H=24 ;; esac

  WT_N=0; WT_KB=0; WT_OLDEST=0; WT_MEM=0
  WT_NOW=$(date +%s 2>/dev/null); case "$WT_NOW" in (''|*[!0-9]*) WT_NOW=0 ;; esac

  # Does this host's find understand a RELATIVE -newermt at all? It matters more than it
  # looks: a find that cannot parse the expression prints to stderr and matches nothing,
  # which is indistinguishable from "no recent writes" -- so every worktree on the machine
  # would be declared abandoned at once. That is the noisiest possible failure for a
  # recurring job, and it would arrive looking like a real finding.
  #
  # The control is a hundred-year window, which must match the directory that is certainly
  # there. Empty means the option did not evaluate, not that the directory is old.
  if [ -z "$(find .claude/worktrees -maxdepth 0 -newermt "-876000 hours" -print 2>/dev/null)" ]; then
    add "[SETUP] this host's \`find\` cannot evaluate a relative \`-newermt\`, so a live agent worktree cannot be told from an abandoned one — worktree reporting skipped rather than guessed. Sweep by hand: bash scripts/prune-agent-worktrees.sh --dry-run"
  else

    for wt in .claude/worktrees/agent-*; do
      [ -d "$wt" ] || continue

      # Live #1 -- something was written in here inside the window. The heavy directories
      # are pruned so this stays milliseconds (18 ms on a 190 MB worktree, worst case: a
      # full walk that finds nothing), and -quit stops the positive case at the first hit.
      if [ -n "$(find "$wt" \( -name node_modules -o -name .git -o -name bin -o -name obj \
                               -o -name dist -o -name .stryker-tmp \) -prune \
                 -o -newermt "-${GRACE_H} hours" -print -quit 2>/dev/null)" ]; then
        continue
      fi

      # Live #2 -- a lock naming a process that still exists. In practice the harness does
      # not lock what it creates, so this rarely fires; it stays because
      # prune-agent-worktrees.sh honours it, and disagreeing about liveness with the very
      # tool this finding tells you to run would be worse than the cost of asking.
      WT_LOCK=$(git worktree list --porcelain 2>/dev/null | awk -v w="$PWD/$wt" '
        $1=="worktree"{cur=$2} $1=="locked"{if(cur==w){$1="";print;exit}}')
      if [ -n "$WT_LOCK" ]; then
        WT_PID=$(printf '%s' "$WT_LOCK" | sed -n 's/.*pid \([0-9][0-9]*\).*/\1/p')
        if [ -n "$WT_PID" ] && kill -0 "$WT_PID" 2>/dev/null; then continue; fi
      fi

      WT_N=$((WT_N + 1))

      # Everything below degrades rather than aborts. The secrets and CVE sections above
      # matter more than this one and must not be taken down by a `du` that failed.
      WT_SZ=$(du -sk "$wt" 2>/dev/null | cut -f1)
      case "$WT_SZ" in (''|*[!0-9]*) WT_SZ=0 ;; esac
      WT_KB=$((WT_KB + WT_SZ))

      # BSD form first (macOS), GNU second (Linux, Git Bash). If both fail the age is
      # omitted from the finding rather than printed as garbage.
      WT_MT=$(stat -f %m "$wt" 2>/dev/null || stat -c %Y "$wt" 2>/dev/null)
      case "$WT_MT" in (''|*[!0-9]*) WT_MT=0 ;; esac
      if [ "$WT_MT" -gt 0 ] && [ "$WT_NOW" -gt "$WT_MT" ]; then
        WT_AGE=$(( (WT_NOW - WT_MT) / 86400 ))
        [ "$WT_AGE" -gt "$WT_OLDEST" ] && WT_OLDEST=$WT_AGE
      fi

      # Memory that exists ONLY in here. MEMORY.md index fragments are excluded because
      # the sweep merges those rather than salvaging them, so counting them would
      # overstate what is actually at risk.
      while read -r wt_f; do
        [ -n "$wt_f" ] || continue
        wt_rel=${wt_f#*/.claude/agent-memory/}
        case "$wt_rel" in MEMORY.md|*/MEMORY.md) continue ;; esac
        [ -f ".claude/agent-memory/$wt_rel" ] || WT_MEM=$((WT_MEM + 1))
      done < <(find "$wt/.claude/agent-memory" -type f 2>/dev/null)
    done

    if [ "$WT_N" -gt 0 ]; then
      if [ ! -f scripts/prune-agent-worktrees.sh ]; then
        add "[SETUP] $WT_N abandoned agent worktree(s) under .claude/worktrees/ but scripts/prune-agent-worktrees.sh is missing — run /project-update to restore it."
      else
        WT_AGE_TXT=""
        [ "$WT_OLDEST" -gt 0 ] && WT_AGE_TXT=", oldest $WT_OLDEST days"
        add "[WORKTREES] $WT_N abandoned agent worktree(s) under .claude/worktrees/ — $((WT_KB / 1024)) MB${WT_AGE_TXT}, untouched for over ${GRACE_H}h.
  $WT_MEM agent-memory file(s) exist only inside them; removing the worktrees takes that with them.
  Sweep (salvages memory first, removes only what is provably safe):
    bash scripts/prune-agent-worktrees.sh --dry-run"
      fi
    fi
  fi
fi

# ------------------------------------------------------------- 5. mutation kill rate
MUTATION_CMD=""
# `find`, not a glob: bash globstar is off by default, so `./**/*.csproj` would
# silently only match one level deep — and would miss src/Foo/Foo.csproj.
if [ -x scripts/run-mutation-gate.sh ]; then
  # A project-local bounded runner wins when there is one. This line is the fix
  # for a real runaway: on 2026-09-08 the bare form below was started twice on
  # fundit, ran for five hours at 400% CPU across 63 test workers, and produced
  # no score at all — Stryker scopes to the test project it is RUN FROM, so at a
  # repo root it discovers the whole suite, integration containers included. A
  # runner cds into the fast test projects and wraps each pass in `timeout`.
  #
  # The `eval` further down has no timeout of its own, so whatever is chosen
  # here runs until somebody notices. That is the whole reason to prefer a
  # bounded command when the project ships one.
  #
  # run-mutation-gate.sh is deliberately NOT a CORE script (see the
  # not-shipped list in template-autosync.sh): the bounding logic is general but
  # the test-project names are not. Absence is normal and falls through here.
  #
  # ITS OUTPUT CONTRACT, because a project-local script and a CORE reader are two files nobody
  # diffs. The classifier below greps `mutation score` followed by a number, so a runner MUST
  # print a line containing that phrase and its percentage; Stryker own summary already does, so
  # a wrapper that forwards Stryker output satisfies it for free and one that reformats must
  # reproduce the phrase. Rocky F045: its runner printed `Score: 94.1%`, every field correct and
  # the phrase absent, so a completed gate was discarded as unclassifiable and the developer was
  # told the run could not be read. The script output was fine; the contract with its reader was
  # never written down, and the runner own smoke test could not see that because it only read the
  # script own output. This comment is that contract, and the unclassifiable branch below quotes
  # it so the next reader does not have to find their way here.
  MUTATION_CMD="bash scripts/run-mutation-gate.sh"
elif [ -n "$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ]; then
  MUTATION_CMD="dotnet stryker"
elif [ -f package.json ] && grep -q '"@stryker-mutator/core"' package.json 2>/dev/null; then
  MUTATION_CMD="npx stryker run"
fi

# THREE THINGS THIS SECTION USED TO GET WRONG, all measured on a real project (2026-08-28) and all
# fixed below. They mattered because this is the ONLY command in a default project that asks for a
# mutation run at all, so whatever it says is the whole of what the developer hears.
#
#   1. THE NUMBER WAS STRYKER'S, THE LABEL WAS NOT. Stryker prints (Killed + Timeout) / valid; a Timeout
#      is not a kill. On one measured gate that gap was 2.31 points in the flattering direction (strict
#      97.69, Stryker 100.00). This section is generic template code and should NOT reimplement a strict
#      scorer -- but printing the generous number as "kill rate" against a strict target is a claim about
#      a measurement nobody made. It is now labelled with its provenance.
#
#   2. THE THRESHOLD WAS HARDCODED 80 WHILE THE CONFIG CARRIED ITS OWN. That project's root config has
#      `break: 79`, so a run at 79.5 PASSED its own gate and was reported as a finding, and a run at 79.0
#      failed nothing and was reported the same way. A config that states its threshold is the authority
#      on its threshold; 80 is the fallback for a config that states none.
#
#   3. A GATE FAILURE WAS REPORTED AS A TOOL CRASH. Stryker exits non-zero when the score is under
#      `break` -- i.e. on the exact outcome the gate exists to produce. "`dotnet stryker` failed to
#      complete:" followed by fifteen lines of tail describes a crash and buries a finding.
#
# And it names its own coverage. A bare `dotnet stryker` reads the config in the working directory, so a
# repo with forty-five committed configs gets exactly one of them measured. Reported without that ratio,
# one gate reads as a suite.
#
# WHAT IT DELIBERATELY DOES NOT DO: start a sweep. A maintenance pass that silently launches a multi-hour
# mutation run across every gate is a worse defect than the one it fixes -- a project that wants that
# owns its own rotation script and schedules it separately.
mutation_break_of() { # mutation_break_of <config path>; echoes the integer break, or nothing
  [ -f "$1" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  CFG="$1" python3 - <<'PY' 2>/dev/null
import json, os
try:
    d = json.load(open(os.environ["CFG"]))
except Exception:
    raise SystemExit(0)
d = d.get("stryker-config", d)
b = (d.get("thresholds") or {}).get("break")
if isinstance(b, (int, float)):
    print(int(b))
PY
}

# Did this invocation actually MEASURE the gate? Not "did it try" — the due-state stamp below is a
# claim that the obligation was discharged, and a crash or an unreadable run discharges nothing.
# Set only on the two branches where a score came back (gate passed, or gate failed on the number —
# both are measurements and both leave the developer a result to act on).
MUT_MEASURED=0

if [ -n "$MUTATION_CMD" ]; then
  if [ "$FULL" -eq 1 ]; then
    # Which config this bare invocation will actually read, and how many exist. Both tools default to a
    # config in the working directory; the count is what turns "one gate" into an honest sentence.
    case "$MUTATION_CMD" in
      dotnet*) MUT_CFG="stryker-config.json" ;;
      *)       MUT_CFG="stryker.conf.json" ;;
    esac
    MUT_CFG_TOTAL=$(find . -type d \( -name node_modules -o -name StrykerOutput -o -name bin -o -name obj -o -name .git \) -prune -o \
                      -type f \( -name 'stryker-config*.json' -o -name 'stryker.conf*.json' \) -print 2>/dev/null | wc -l | tr -d ' ')
    case "$MUT_CFG_TOTAL" in (''|*[!0-9]*) MUT_CFG_TOTAL=1 ;; esac
    [ "$MUT_CFG_TOTAL" -lt 1 ] && MUT_CFG_TOTAL=1
    MUT_SCOPE="1 of $MUT_CFG_TOTAL config(s) — a bare \`$MUTATION_CMD\` reads only $MUT_CFG"

    MUT_OUT=$(eval "$MUTATION_CMD" 2>&1)
    MUT_RC=$?
    SCORE=$(printf '%s' "$MUT_OUT" | grep -oE 'mutation score[^0-9]*[0-9]+(\.[0-9]+)?' | tail -1 | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1)
    INT_SCORE=${SCORE%%.*}

    MUT_BREAK=$(mutation_break_of "$MUT_CFG")
    if [ -n "$MUT_BREAK" ]; then
      MUT_LIMIT="$MUT_BREAK"; MUT_LIMIT_SRC="$MUT_CFG thresholds.break"
    else
      MUT_LIMIT=80;           MUT_LIMIT_SRC="the ~80% default target (this config states no break)"
    fi

    if [ "$MUT_RC" -ne 0 ] && [ -n "$SCORE" ]; then
      # A number came back, so the tool ran. Non-zero here is the gate doing its job.
      MUT_MEASURED=1
      add "[MUTATION] GATE FAILED — Stryker's own score ${SCORE}% against $MUT_LIMIT_SRC ($MUT_LIMIT).
  This is the gate failing, not the tool crashing: Stryker exits non-zero when the score is under break.
  Scope: $MUT_SCOPE.
  NOTE: ${SCORE}% is Stryker's score, (Killed + Timeout) / valid. A Timeout is not a kill, so the strict
  score is this or lower — never higher (.claude/docs/testing.md)."
    elif [ "$MUT_RC" -ne 0 ]; then
      add "[MUTATION] \`$MUTATION_CMD\` failed to complete — no score was produced:
$(printf '%s' "$MUT_OUT" | tail -15)"
    elif [ -n "$SCORE" ]; then
      MUT_MEASURED=1
      if [ "${INT_SCORE:-0}" -lt "$MUT_LIMIT" ]; then
        add "[MUTATION] Stryker's own score ${SCORE}% is below $MUT_LIMIT_SRC ($MUT_LIMIT).
  Scope: $MUT_SCOPE.
  NOTE: ${SCORE}% counts a Timeout as a kill; the strict score (Killed / valid) is this or lower."
      fi
    else
      # Exit 0 and no parseable score is not a pass -- it is a run this section cannot classify, and
      # saying nothing about it would report an unmeasured gate as a measured one.
      add "[MUTATION] \`$MUTATION_CMD\` exited 0 but printed no mutation score — the run cannot be classified.
  Scope: $MUT_SCOPE.
  The classifier greps the phrase \`mutation score\` followed by a number. A run that finished but
  worded its summary differently lands here with everything measured and nothing readable; fix the
  runner to print the phrase rather than widening this grep, which would start reading numbers out
  of any tool that happens to be in the output. Not stamped: the job stays due."
    fi
  else
    REPORT="${REPORT}[skipped] mutation pass — re-run with --full to execute \`$MUTATION_CMD\` (slow, and it covers only the working-directory config).
"
  fi
fi

# ---------------------------------------------------------------- 6. census audits
#
# template-autosync: optional-project-script scripts/e2e-gate-census.py
# template-autosync: optional-project-script scripts/e2e-wait-audit.sh
# template-autosync: optional-project-script scripts/install-git-hooks.sh
#
# Those three lines are machine-read by unlisted_core_shaped in scripts/template-autosync.sh, and
# they are the declaration this note has always been making in prose. The first two are guarded on
# the file existing, a few lines below each. The third is never CALLED at all — it appears only
# inside a diagnostic string, telling a reader which command they skipped. All three are
# project-specific by design (a C# Playwright ledger, a dotnet-test wrapper, a hook installer that
# names this project own hooks), so the template must not ship them; without the declaration the
# predicate reads the reference as proof that it must, and denies every register tick on the
# project that authored them. Rocky F042.
#
# TEMPLATE NOTE. Both halves of this section are guarded on a script existing, so on a project that
# has neither they are a silent no-op and cost one `test -f` each. They live here rather than in the
# project that uses them because this file is CORE: a caller added downstream is deleted by the next
# sync, which is exactly what had happened to the first half — spec 544 wired it in the project only,
# and it survived four days on borrowed time until spec 523 went looking.
# Spec 544 (T027/FR-023..FR-027). The four census tests that pin the browser suite's own discipline
# had been RED FOR NINE DAYS before anyone noticed, and the gate pin among them had been found stale
# four specs running. The cause was never carelessness -- it was that nothing ran them. They live in
# the E2E project, so they surface only on a full suite run: about once per spec, by whoever is
# unlucky. scripts/e2e-wait-audit.sh existed as a wrapper and had no caller anywhere.
#
# This is that caller. Three properties are load-bearing:
#   * A clean census adds NO output. Attention mode is why this script is readable, and a recurring
#     job that speaks when nothing changed is how you learn to ignore the run that mattered -- the
#     same disease as a red-by-default census, which is what spec 544 is about. (FR-024)
#   * The verdict is never `$?`. `dotnet test` has been measured in this project exiting 0 on a run
#     with five failures; the wrapper parses the summary line instead, in both of its verbosity
#     wordings, and that is why the wrapper is reused rather than reimplemented here. (FR-026)
#   * A tree whose E2E project does not BUILD is a NOTE, not a finding and not silence. A build
#     failure is not census drift, so reporting it as one shows a census failure that is not
#     happening; but a pass that silently skipped its checks is the exact false green this whole
#     section exists to remove. `note` is the script's non-voting channel and prints in both the
#     clean and the findings branch. (FR-027)
# Spec 523 (FR-016). The wrapper below needs the E2E project to BUILD, and when it does not, the
# ledger goes unchecked entirely — the note further down records that honestly but checks nothing.
# The fast census reads the same ledger from source in under half a second with no compiler, so it
# still answers in exactly the case the wrapper cannot. It is also the pre-commit gate, so a finding
# here means a commit was made without it (a fresh clone that never ran install-git-hooks.sh, or
# --no-verify). Clean adds NO output, per this script's attention-mode contract.
FAST_CENSUS="$ROOT/scripts/e2e-gate-census.py"
if [ -f "$FAST_CENSUS" ] && command -v python3 >/dev/null 2>&1; then
  FAST_OUT="$(python3 "$FAST_CENSUS" --repo-root "$ROOT" 2>&1)"
  FAST_RC=$?
  if [ "$FAST_RC" -eq 1 ]; then
    add "[GATE LEDGER] The E2E gate ledger has drifted, and it got past the pre-commit gate — either
  this clone never ran scripts/install-git-hooks.sh, or a commit used --no-verify.
$(printf '%s' "$FAST_OUT" | sed -n '3,12p')
  Fix at the SITE. An added class is an APPEND; a CHANGED treatment is the erosion the ledger exists
  to catch and no appended line will satisfy it."
  elif [ "$FAST_RC" -eq 2 ]; then
    add "[GATE LEDGER] The fast census REFUSED — it could not read what it was asked to read, which
  is never a pass. A parser gone blind on a C# declaration form, or a ledger that moved.
$(printf '%s' "$FAST_OUT" | head -8)
  Re-run: python3 scripts/e2e-gate-census.py"
  fi
fi

CENSUS_SCRIPT="$ROOT/scripts/e2e-wait-audit.sh"
if [ -f "$CENSUS_SCRIPT" ]; then
  CENSUS_OUT="$(bash "$CENSUS_SCRIPT" 2>&1)"
  CENSUS_RC=$?
  if [ "$CENSUS_RC" -eq 0 ]; then
    :
  elif [ "$CENSUS_RC" -eq 2 ] || printf '%s' "$CENSUS_OUT" | grep -qE ': error [A-Z]{2}[0-9]{4}|MSB[0-9]+|Build FAILED'; then
    note "[note] census audit could not run — the E2E project did not build, so the four drift
  censuses were neither passed nor failed. Not counted as a finding (a build failure is not census
  drift), but recorded, because a maintenance pass that skipped its checks in silence is the false
  green spec 544 exists to remove. Re-run: bash scripts/e2e-wait-audit.sh"
  else
    add "[CENSUS] A drift census is RED. These are the instruments that pin the browser suite's own
  discipline, and spec 544 exists because four of them sat red for nine days unseen.
$(printf '%s' "$CENSUS_OUT" | grep -E '\S+\.cs:' | head -12)
  Fix at the SITE, never by raising a record until the red stops.
  Full output: bash scripts/e2e-wait-audit.sh"
  fi
fi

# ------------------------------------------------------- 6b. carve SHAPE (budget + depth)
#
# The convergence ratio above answers "is the register closing". It cannot answer "was the budget
# respected", and until 2026-09-04 nothing could: carve-budget.md sections 2 and 3 were prose.
# Reported, never fatal on its own -- an over-budget carve is a fact about rows already written, and
# the decision it wants is the developer's.
if [ -f scripts/register-convergence.sh ] && [ -f scripts/carve_audit.py ] && [ -f specs/INDEX.md ]; then
  CARVE_OUT=$(bash scripts/register-convergence.sh --carves 2>&1); CARVE_RC=$?
  if [ "$CARVE_RC" -eq 1 ]; then
    add "[CARVE SHAPE] the carve budget or the depth limit is exceeded (.claude/rules/carve-budget.md):
$(printf '%s' "$CARVE_OUT" | head -12)
  Section 2 caps a spec at 2 carves; section 3 says there is no depth 3. Both were unmeasured until
  now, so these are pre-existing. Fold the excess into one consolidated row, or decide otherwise —
  but decide, rather than letting the tree keep growing."
  fi
fi

# ------------------------------------------------------ 6c. cross-platform portability
#
# Two developers, two platforms, and cross-platform is a base requirement rather than a preference.
# A construct that works on one is a script the other never successfully runs -- and it fails
# QUIETLY, because the usual symptom is an empty result, not an error.
if [ -f scripts/validate-portability.sh ] && [ -f scripts/portability_audit.py ]; then
  PORT_OUT=$(bash scripts/validate-portability.sh --all 2>&1); PORT_RC=$?
  if [ "$PORT_RC" -eq 1 ]; then
    add "[PORTABILITY] construct(s) that run on one developer's platform and not the other's:
$(printf '%s' "$PORT_OUT" | grep -E '^\s+scripts/' -A2 | head -12)
  Run: bash scripts/validate-portability.sh --all"
  fi
fi

# ------------------------------------------------------------- 7. the test suite (--suite)
#
# THE PART THAT ACTUALLY COST THE DAYS. Sections 1-6 are hygiene: seconds to minutes. What made
# afternoons disappear is the thing none of them ran — the suite itself. CLAUDE.md's Definition of
# Done requires unit + integration + E2E + visual regression, and every one of those was invoked by
# hand, in the middle of the work, competing with it. agentcrm's integration suite grew the test
# host to 11.5 GB over 45 minutes and ended a session on 2026-09-01 by OOM-killing it.
#
# So it moves here, behind its own flag, and `maintenance-due.sh` decides when it is stale: one
# ticked spec. Not a clock — a green suite is invalidated by code landing, and specs are how code
# lands.
#
# THE STACK IS DETECTED, NEVER ASSUMED, and a project with no detectable suite says so rather than
# reporting a pass. An unrun suite and a green one must not render identically
# (.claude/rules/mutation-timeouts.md, trap 4).
if [ "$SUITE" -eq 1 ]; then
  SUITE_CMD=""
  # THE PROJECT'S OWN `test` SCRIPT WINS, and this order used to be reversed.
  # On a project that is both .NET and web, `dotnet test` matched first and
  # `npm test` was never reached — so the step ran unit and integration tests,
  # skipped E2E and visual regression entirely, and then STAMPED the obligation
  # that maintenance-due.sh describes as "unit + integration + E2E + visual
  # regression". A green half-suite marked the job done and stopped reporting
  # it, which is the failure this whole mechanism exists to prevent.
  #
  # A package.json `test` script is the project's own statement of what its
  # suite is. Preferring it is also why it must not be ASSUMED to cover .NET on
  # a project where it only covers the frontend — hence the note rather than
  # silence.
  if [ -f package.json ] && grep -q '"test"[[:space:]]*:' package.json 2>/dev/null; then
    SUITE_CMD="npm test"
    if [ -n "$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ] \
       && ! grep -q 'dotnet test' package.json 2>/dev/null; then
      note "[note] --suite: using \`npm test\`, which does not mention \`dotnet test\` on a project that has a .NET solution. If the .NET suite is not run by it, this step is not covering it."
    fi
  elif [ -n "$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ]; then
    SUITE_CMD="dotnet test"
  fi

  if [ -z "$SUITE_CMD" ]; then
    note "[note] --suite: no .NET solution and no npm test script — nothing to run. Not a pass."
  else
    SUITE_OUT=$(eval "$SUITE_CMD" 2>&1); SUITE_RC=$?
    SUITE_TAIL=$(printf '%s' "$SUITE_OUT" | tail -12)
    if [ "$SUITE_RC" -eq 0 ]; then
      note "[note] suite green — \`$SUITE_CMD\`"
      [ -f scripts/maintenance-due.sh ] && bash scripts/maintenance-due.sh --stamp suite 2>/dev/null
    else
      # NOT stamped. A red suite has not satisfied the obligation, and stamping it would mark the
      # job done and stop reporting it — the failure this whole mechanism exists to prevent.
      add "[SUITE] \`$SUITE_CMD\` failed (exit $SUITE_RC). Not stamped: the job stays due until it is green.
$SUITE_TAIL"
    fi
  fi
fi

# --------------------------------------------------------------------- stamp what ran
# Only what this invocation actually performed. Sections 1-6 always run, so `secrets` is stamped on
# every pass; mutation and similarity are --full only. `suite` is stamped above, and only on green.
#
# MUTATION IS STAMPED ONLY ON A RUN THAT PRODUCED A SCORE, which until rocky F044 it was not: the
# stamp fired on `--full` alone, so a run this section had ITSELF just called unclassifiable cleared
# the due-state and the banner went quiet — and on a project with no Stryker config and no runner,
# where $MUTATION_CMD is empty and nothing executes at all, the job was marked done by a pass that
# never touched it. Its sibling twelve lines above already had this right and said why: "a red suite
# has not satisfied the obligation, and stamping it would mark the job done and stop reporting it".
# Two stamps for two recurring jobs in one file, one of them honest. A gate failing on the NUMBER
# does stamp: that is a measurement, and it leaves a finding the developer can act on.
if [ -f scripts/maintenance-due.sh ]; then
  bash scripts/maintenance-due.sh --stamp secrets 2>/dev/null
  if [ "$FULL" -eq 1 ]; then
    [ "$MUT_MEASURED" -eq 1 ] && bash scripts/maintenance-due.sh --stamp mutation 2>/dev/null
    bash scripts/maintenance-due.sh --stamp similarity 2>/dev/null
  fi
fi

# ------------------------------------------------------------------------ verdict
if [ "$FINDINGS" -eq 0 ]; then
  [ "$QUIET" -eq 1 ] && exit 0
  echo "project-maintenance: clean — no secrets, no CVEs, no register drift, no context bloat.$([ "$FULL" -eq 0 ] && [ -n "$MUTATION_CMD" ] && printf ' (mutation pass skipped — use --full)')"
  [ -n "$NOTES" ] && printf '%s' "$NOTES"
  exit 0
fi

echo "project-maintenance: $FINDINGS finding(s) — $(date -u +%Y-%m-%d)"
echo
printf '%s' "$REPORT"
[ -n "$NOTES" ] && printf '%s' "$NOTES"
echo "Each finding needs an explicit fix / defer / dismiss decision per .claude/rules/validation-followup.md."
exit 1
