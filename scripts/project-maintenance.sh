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
#   bash scripts/project-maintenance.sh --suite    # also run the whole test suite, stamp it on green
#
# The suite command is the first non-comment line of .claude/.suite-command when the project
# declares one; otherwise a root `npm test` script, otherwise `dotnet test` (row 051). A detected
# `dotnet test` or bare `dotnet stryker` beside more than one .NET solution is refused, not run
# against whichever sits at the root (row 052).
#
# Every pass also runs each scripts/check-*.sh ratchet from the root (row 052); a non-zero exit is a
# finding. A ratchet opts out with `# maintenance: skip <reason>` in its first 30 lines.
# MAINTENANCE_RATCHET_TIMEOUT=N  seconds per ratchet (default 300; needs timeout or gtimeout).
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

# Every job that costs real time goes through the ledger (row 074), so the local-vs-cloud placement
# in row 075 is decided from measured duration and peak memory rather than a guess. The wrapper is
# transparent: same output, same exit code. Without python3 the job still runs, unmeasured, and the
# pass says so once -- an unmeasured run must not read like a cheap one.
PASS_START=$(date +%s)
LEDGER_OK=0
command -v python3 >/dev/null 2>&1 && [ -f scripts/maintenance_ledger.py ] && LEDGER_OK=1
[ "$LEDGER_OK" -eq 1 ] || note "[note] maintenance ledger: python3 or scripts/maintenance_ledger.py missing — this pass ran unmeasured."
measured() { # measured JOB CMD [ARGS...]
  local job=$1; shift
  if [ "$LEDGER_OK" -eq 1 ]; then python3 scripts/maintenance_ledger.py run "$job" -- "$@"; else "$@"; fi
}

# Every .NET solution a bare `dotnet test` / `dotnet stryker` could be meant for (row 052). Two or
# more with nothing declared means the root one gets built blind: ighweld-2026's root IGHWeld.Web.sln
# pointed at deleted projects, and both steps failed MSB3202 on 2026-09-18 while the real
# src/welding/Welding.sln was 7478/0 green. Same depth as the detection that picks `dotnet`.
dotnet_solutions() {
  find . -maxdepth 3 \( -name node_modules -o -name .git \) -prune -o \
    -type f \( -name '*.sln' -o -name '*.slnx' \) -print 2>/dev/null | sed 's|^\./||' | sort
}
solution_list() { # solution_list "<newline list>" — indented, for a finding
  printf '%s\n' "$1" | sed 's/^/    /'
}

# ---------------------------------------------------------------- 1. secrets + CVEs
if [ -f scripts/project-freshness.sh ]; then
  FRESH_OUT=$(measured secrets bash scripts/project-freshness.sh 2>&1)
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
#
# Row 008: a scenario-map file over the canary is also RECORDED in the project's own
# specs/FINDINGS.md, because a warning is not a record. Measured 2026-09-29, 17 map files across
# 17 projects sat over 25 KB. The template row tracking them named 4, and the line printed here
# scrolled away every time. Recording hands the decision to the 5-spec findings review, in the
# project that owns the map. Only an OPEN finding for the same path suppresses a new one: a map
# still oversize after a "live with it" decision is back in front of the next review, and that
# review comes only every 5 specs.
MAP_SPLIT=0
for f in specs/scenarios/*.md; do [ -f "$f" ] && { MAP_SPLIT=1; break; }; done
MAP_KEY_PREFIX="scenario-map canary: "
record_map_canary() { # record_map_canary PATH KB ROLE HINT
  local key="${MAP_KEY_PREFIX}$1 " out rc
  if [ ! -f scripts/finding.sh ]; then
    add "[SETUP] scripts/finding.sh missing — the scenario-map canary for $1 could not be recorded in specs/FINDINGS.md. Run /project-update to restore it."
    return
  fi
  if [ -f specs/FINDINGS.md ] && grep -Fq -e "$key" <<< "$(grep -E '^- \[ \] F[0-9]+ ' specs/FINDINGS.md)"; then
    return
  fi
  out=$(bash scripts/finding.sh --add "${key}is $2 KB ($3, canary 25 KB) — $4" --kind debt 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    add "[CONTEXT-COST] the scenario-map canary for $1 could not be recorded (finding.sh exit $rc): $out"
  else
    note "[CONTEXT-COST] recorded in specs/FINDINGS.md: $(printf '%s' "$out" | head -1)"
  fi
}
for f in specs/INDEX.md specs/SCENARIOS.md specs/scenarios/*.md; do
  [ -f "$f" ] || continue
  BYTES=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  case "$BYTES" in (''|*[!0-9]*) BYTES=0 ;; esac
  if [ "$BYTES" -gt 25600 ]; then
    # Which script to name depends on where the bytes are. Spec 007ce measured
    # specs/INDEX.md at 91.4% spec rows against 4.8% history, so naming the history
    # archiver on the register sent people at 1,918 bytes while 36,521 sat untouched.
    # A scenario map is the same trap one level down: the history archiver trims a few hundred
    # bytes of a 121 KB map and the warning comes back unchanged (row 008).
    ROLE=""
    case "$f" in
      */INDEX.md)
        HINT="scripts/archive-completed-rows.sh (rows), scripts/archive-spec-history.sh --keep 5 (history)"
        # Row 017: measure the parts; the hint is the moves that exist. With none, the register
        # complies with every budget and no script shrinks it, so a red verdict could never be
        # cleared: it is a note. A failing or missing helper keeps the old hint and the finding.
        if RB=$(bash scripts/register-bytes.sh "$f" 2>/dev/null) && [ -n "$RB" ]; then
          RB_PARTS=$(printf '%s\n' "$RB" | sed -nE 's/^(rows|prose|history)=([0-9]*) share=([0-9]*).*/\1 \3%/p' | paste -sd, - | sed 's/,/, /g')
          RB_MOVES=$(printf '%s\n' "$RB" | sed -n 's/^move=\([a-z]*\) \(.*\)/\1: \2/p' | paste -sd'|' - | sed 's/|/ · /g')
          if [ -z "$RB_MOVES" ]; then
            note "[note] context cost: $f is $((BYTES / 1024)) KB ($RB_PARTS) — every part complies; nothing archives it further. Read it targeted."
            continue
          fi
          HINT="$RB_PARTS. $RB_MOVES"
        fi ;;
      specs/scenarios/*)
        ROLE="feature file"
        HINT="split this feature into sub-feature files, or archive its history (scripts/archive-spec-history.sh --keep 5)" ;;
      *)
        if [ "$MAP_SPLIT" -eq 1 ]; then
          ROLE="split index"
          HINT="the index keeps one row per feature — archive its Scenario history (scripts/archive-spec-history.sh --keep 5) and move any feature prose into its file"
        else
          ROLE="single-file map"
          HINT="split it per .claude/rules/scenarios.md 'When to split'; prove the move with scripts/scenario-map-rows.sh + scripts/test-scenario-map-split.sh"
        fi ;;
    esac
    add "[CONTEXT-COST] $f is $((BYTES / 1024)) KB — read on every spec. Trim: $HINT"
    [ -n "$ROLE" ] && record_map_canary "$f" "$((BYTES / 1024))" "$ROLE" "$HINT"
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
  TRACE_OUT=$(measured traceability bash scripts/validate-scenario-traceability.sh --quiet 2>&1)
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
  [ "${BLOCKED:-0}" -gt 0 ] && add "[REGISTER] $BLOCKED row(s) marked blocked \`- [!]\` — a register-rewrite decision is pending."
  [ "${INPROG:-0}" -gt 1 ] && add "[REGISTER] $INPROG rows marked in-progress \`- [/]\` — only one spec runs at a time."
  # Integration-hardening checkpoint cadence (.claude/rules/spec-hardening.md), from the same engine
  # the SessionStart banner reads (spec 068 — this was `DONE % 5` over every ticked row).
  if [ -f scripts/checkpoint-cadence.sh ]; then
    CADENCE=$(bash scripts/checkpoint-cadence.sh 2>/dev/null)
    case "$CADENCE" in
      *due=1)
        if ! grep -qiE '^- \[[ /]\].*checkpoint' specs/INDEX.md 2>/dev/null; then
          CP_COUNT=$(printf '%s' "$CADENCE" | sed -n 's/.*count=\([0-9]*\).*/\1/p')
          CP_SINCE=$(printf '%s' "$CADENCE" | sed -n 's/^since=\([^ ]*\).*/\1/p')
          add "[HARDENING] $CP_COUNT feature specs since ${CP_SINCE/#none/the start of the register} but no pending checkpoint row — insert an integration-hardening checkpoint before the next feature spec."
        fi
        ;;
    esac
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
  # The freeze (row 077): a row added without an approved proposal is a finding; a freeze that can
  # lift is a note; a freeze line nobody can parse is a finding, because it would otherwise read as off.
  FRZ_OUT=$(bash scripts/register-convergence.sh --freeze 2>&1); FRZ_RC=$?
  case "$FRZ_RC" in
    2|4|5) add "[FREEZE] $FRZ_OUT" ;;
    3) note "[note] $FRZ_OUT" ;;
  esac
fi

# --------------------------------------------------- 3f. allium baseline census
# /tla compares its distilled spec against each spec.allium, so a baseline the CLI cannot parse
# makes the drift report meaningless. New writes are blocked by allium-check-hook.sh; this is
# the backlog, reported and never failed on (rocky carried 131 closed-row baselines with errors
# when the hook landed, and a run that is red every night is a run nobody reads).
if [ -f scripts/allium-census.sh ] && ls specs/*/spec.allium >/dev/null 2>&1; then
  ALLIUM_OUT=$(bash scripts/allium-census.sh 2>&1); ALLIUM_RC=$?
  case "$ALLIUM_RC" in
    0) : ;;
    1) note "[note] $(printf '%s\n' "$ALLIUM_OUT" | tail -1) — list: bash scripts/allium-census.sh" ;;
    *) note "[note] allium census could not tell: $(printf '%s\n' "$ALLIUM_OUT" | tail -1)" ;;
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
  SIM_OUT=$(measured similarity bash scripts/register-similarity.sh --open-only 2>/dev/null); SIM_RC=$?
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

# ------------------------------------------- 3h. BLOCKING skills the template does not ship
# CLAUDE.md calls frontend-design and humanizer BLOCKING, and neither arrives with a sync: one is a
# plugin, the other a git clone under ~/.claude/skills. Without them the gate is prose nobody can
# follow, and nothing said so (spec 006). Unlike §3b this is about the MACHINE, so it runs in the
# template too, whose own CLAUDE.md names both gates. Guarded on the checker existing, like 2c.
if [ -f scripts/skill-reachable.sh ]; then
  SR_OUT=$(bash scripts/skill-reachable.sh --required 2>&1)
  SR_RC=$?
  case "$SR_RC" in
    0) ;;
    1) while IFS= read -r line; do
         case "$line" in missing:*) add "[SKILLS] BLOCKING skill not reachable on this machine — ${line#missing: }" ;; esac
       done <<EOF
$SR_OUT
EOF
       ;;
    *) note "[SKILLS] could not tell whether the BLOCKING skills are installed (scripts/skill-reachable.sh exit $SR_RC): $(printf '%s' "$SR_OUT" | head -3 | tr '\n' ' ')" ;;
  esac
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

      # GNU form first (Linux, Git Bash), BSD second (macOS). The order is load-bearing:
      # on GNU, `stat -f` is --file-system and succeeds, printing a filesystem block to
      # stdout, so a BSD-first chain never reaches its fallback there. `stat -c` is an
      # unknown option to BSD stat and fails cleanly, which makes it the safe probe.
      # If both fail the age is omitted from the finding rather than printed as garbage.
      WT_MT=$(stat -c %Y "$wt" 2>/dev/null || stat -f %m "$wt" 2>/dev/null)
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
  #
  # The contract has a second half since row 043: the run must leave Stryker's JSON report
  # (`mutation-report.json`, or StrykerJS `mutation.json`) somewhere under the project root. The
  # headline is one number and `.claude/rules/spec-hardening.md` gates on the changed MODULE; the
  # per-module scores exist only in that report. Keep `"json"` in the config's `reporters`, and never
  # pass a CLI `--reporter` without also passing `--reporter json`: a CLI reporter REPLACES the
  # config's list, it does not add to it.
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

# THE HEADLINE IS NOT THE GATE (row 043). fundit spec 006 read 88.21% and PASS while PushEndpointPolicy,
# the SSRF decision, killed 65.79%. The rule gates on the changed critical module, and a module's score is
# only in the JSON report, so this reads every report THIS run wrote (newer than a marker touched just
# before it; yesterday's report is not today's evidence) and lists each file under the limit.
#
# Reports from one run are merged PER MUTANT, not per file: fundit runs a unit pass and a property pass,
# rocky one pass per module, and a mutant any pass killed is a mutant the suite kills. Best-of-files would
# call a file clean when two passes each killed a different half of it, and worst-of would fail a file
# the suite covers. The per-file score is Stryker's own, (Killed + Timeout) / valid, and says so.
#
# Output: "none" when no report was written by the run, "unreadable <path>" per report that is not JSON,
# and one "<score>%\t<file>\t<detected>/<valid>" line per file under the limit, lowest first.
mutation_modules_under() { # mutation_modules_under <marker> <limit>
  command -v python3 >/dev/null 2>&1 || { echo "nopython"; return 0; }
  find . -type d \( -name node_modules -o -name .git -o -name bin -o -name obj \) -prune -o \
    -type f \( -name mutation-report.json -o -name mutation.json \) -newer "$1" -print 2>/dev/null |
    LIMIT="$2" python3 -c '
import json, os, sys
paths = [p for p in sys.stdin.read().splitlines() if p]
if not paths:
    print("none"); raise SystemExit
DETECTED, VALID = {"Killed", "Timeout"}, {"Killed", "Timeout", "Survived", "NoCoverage"}
seen = {}  # (file, mutant key) -> detected by any report
for p in sorted(paths):
    try:
        files = json.load(open(p)).get("files") or {}
    except Exception:
        print("unreadable " + p); continue
    for f, body in files.items():
        name = os.path.relpath(f) if os.path.isabs(f) else f
        for m in body.get("mutants") or []:
            if m.get("status") not in VALID:
                continue
            loc = m.get("location") or {}
            key = (name, m.get("mutatorName"), m.get("replacement"), json.dumps(loc, sort_keys=True))
            seen[key] = seen.get(key, False) or m.get("status") in DETECTED
per = {}
for (name, *_), det in seen.items():
    d, v = per.get(name, (0, 0)); per[name] = (d + det, v + 1)
limit = float(os.environ["LIMIT"])
rows = sorted((100.0 * d / v, name, d, v) for name, (d, v) in per.items() if v and 100.0 * d / v < limit)
for score, name, d, v in rows:
    print("%.2f%%\t%s\t%d/%d" % (score, name, d, v))
'
}

# WHAT GOT MUTATED IS DECIDED BEFORE THE SCORE, AND NOTHING READ IT (row 047). ighweld-2026: a mutate
# pattern `'**/X.cs{845-1080}'` matched no file and the run still scored (F184); `{98..120}` is a
# CHARACTER span that was read as lines (F197); a well-formed span did not shrink the run (F185). Stryker
# reports none of it, so every pass -- not only --full -- checks the patterns in every committed config and
# the literal -m arguments of the project runner. The rules live in scripts/stryker_guard.py, which the
# PreToolUse guard asks too. Unchecked is said, never passed (mutation-timeouts.md trap 4).
# One owner for the rules: with python3 the helper finds the configs and the runner itself. Bash only
# decides, when it cannot ask, whether there was anything to leave unchecked.
HAVE_STRYKER_GUARD=0
command -v python3 >/dev/null 2>&1 && [ -f scripts/stryker_guard.py ] && HAVE_STRYKER_GUARD=1
if [ "$HAVE_STRYKER_GUARD" -eq 1 ] && MUT_PAT_OUT=$(python3 scripts/stryker_guard.py configs . 2>/dev/null); then
  # `skipped` (a runtime-assembled `-m "$P"`) is said as a note: unchecked, and not a defect either.
  MUT_PAT_BAD=$(printf '%s\n' "$MUT_PAT_OUT" | grep -v '^skipped' | grep .)
  MUT_PAT_SKIP=$(printf '%s\n' "$MUT_PAT_OUT" | grep '^skipped')
  if [ -n "$MUT_PAT_BAD" ]; then
    add "[MUTATION] $(printf '%s\n' "$MUT_PAT_BAD" | grep -c .) mutate pattern(s) select nothing, or not what they say — and the score still prints:
$(printf '%s\n' "$MUT_PAT_BAD" | awk -F'\t' '$3 == "-" { printf "  %s %s\n", $2, $4; next } { printf "  %s: \047%s\047 %s\n", $2, $3, $4 }')"
  fi
  [ -n "$MUT_PAT_SKIP" ] && note "[note] mutate patterns: $(printf '%s' "$MUT_PAT_SKIP" | awk -F'\t' '{ printf "%s %s", $2, $4 }')"
elif [ -f scripts/run-mutation-gate.sh ] ||
     [ -n "$(find . -type d \( -name node_modules -o -name StrykerOutput -o -name bin -o -name obj -o -name .git -o -name .stryker-tmp \) -prune -o \
               -type f -iname 'stryker-config*.json' -print -quit 2>/dev/null)" ]; then
  add "[MUTATION] mutate patterns UNCHECKED — python3 or scripts/stryker_guard.py is missing or failed, so a pattern
  that matches no file, or a span read as lines, would score as if it measured something (row 047)."
fi

# STRYKER RUNS ALONE (row 047, ighweld F069). A dotnet build or test in the same project overwrites the
# mutated assembly, and the run scores about 0% with no warning. --full looks once, before it starts; a
# build started in another terminal after that is outside what this can see.
# A process table it could not read is a note, not a refusal and not a silence: the run goes ahead and
# the report says the run-alone check was blind (Git Bash's ps cannot list dotnet.exe at all).
MUT_LIVE=""
if [ -n "$MUTATION_CMD" ] && [ "$FULL" -eq 1 ]; then
  if [ "$HAVE_STRYKER_GUARD" -eq 1 ]; then
    MUT_LIVE_OUT=$(python3 scripts/stryker_guard.py live . 2>/dev/null)
    MUT_LIVE=$(printf '%s\n' "$MUT_LIVE_OUT" | grep -E '^[0-9]')
    MUT_BLIND=$(printf '%s\n' "$MUT_LIVE_OUT" | awk -F'\t' '$1 == "unknown" { print $3 }' | paste -sd ';' -)
    [ -n "$MUT_BLIND" ] && note "[note] Stryker run-alone check was partly blind: $MUT_BLIND."
  else
    note "[note] Stryker run-alone check UNCHECKED — python3 or scripts/stryker_guard.py is missing."
  fi
fi

# Did this invocation actually MEASURE the gate? Not "did it try" — the due-state stamp below is a
# claim that the obligation was discharged, and a crash or an unreadable run discharges nothing.
# Set only on the two branches where a score came back (gate passed, or gate failed on the number —
# both are measurements and both leave the developer a result to act on).
MUT_MEASURED=0

if [ -n "$MUTATION_CMD" ]; then
  MUT_SLNS=""
  [ "$MUTATION_CMD" = "dotnet stryker" ] && MUT_SLNS=$(dotnet_solutions)
  if [ "$FULL" -eq 1 ] && [ "$(printf '%s' "$MUT_SLNS" | grep -c .)" -gt 1 ]; then
    # Row 052. Not stamped: nothing was measured, and the job stays due until the project says which.
    add "[MUTATION] NOT RUN — $(printf '%s\n' "$MUT_SLNS" | grep -c .) .NET solutions and no project-owned runner, so a bare \`dotnet stryker\` would
  mutate whichever one sits at the root, blind:
$(solution_list "$MUT_SLNS")
  Declare the run as scripts/run-mutation-gate.sh (project-owned; it must print \`mutation score N%\`)."
  elif [ "$FULL" -eq 1 ] && [ -n "$MUT_LIVE" ]; then
    add "[MUTATION] NOT RUN — Stryker must run alone, and this project already has one running:
$(printf '%s\n' "$MUT_LIVE" | awk -F'\t' '{ printf "  pid %s (%s): %s\n", $1, $2, $3 }')
  A build beside Stryker overwrites the mutated assembly and the run scores about 0% with no warning
  (ighweld F069). Not stamped: the job stays due. Re-run --full once it has finished."
  elif [ "$FULL" -eq 1 ] && [ "$HAVE_STRYKER_GUARD" -eq 1 ] &&
       MUT_SWEEP=$(python3 scripts/stryker_guard.py sweep . 2>/dev/null) &&
       grep -q '^backup' <<< "$MUT_SWEEP"; then
    # Row 053. The sweep below removes abandoned StrykerJS sandboxes before the run, but an in-place
    # backup can be the only copy of the original sources; a new run would back up the mutated ones.
    add "[MUTATION] NOT RUN — an interrupted in-place Stryker run left a backup in the tree:
$(printf '%s\n' "$MUT_SWEEP" | awk -F'\t' '$1 == "backup" { printf "  %s\n", $3 }')
  Not stamped: the job stays due."
  elif [ "$FULL" -eq 1 ]; then
    # Row 053: what the sweep just removed or kept (it ran in the condition above).
    [ -n "${MUT_SWEEP:-}" ] && note "[note] Stryker sweep before the run:
$(printf '%s\n' "$MUT_SWEEP" | awk -F'\t' '{ printf "  %s %s — %s\n", $1, $2, $3 }')"
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

    MUT_MARKER=$(mktemp "${TMPDIR:-/tmp}/mutation-marker.XXXXXX")
    MUT_OUT=$(measured mutation bash -c "$MUTATION_CMD" 2>&1)
    MUT_RC=$?
    SCORE=$(printf '%s' "$MUT_OUT" | grep -oE 'mutation score[^0-9]*[0-9]+(\.[0-9]+)?' | tail -1 | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1)
    INT_SCORE=${SCORE%%.*}

    MUT_BREAK=$(mutation_break_of "$MUT_CFG")
    if [ -n "$MUT_BREAK" ]; then
      MUT_LIMIT="$MUT_BREAK"; MUT_LIMIT_SRC="$MUT_CFG thresholds.break"
    else
      MUT_LIMIT=80;           MUT_LIMIT_SRC="the ~80% default target (this config states no break)"
    fi

    # The per-module half, read only when a score came back: a crashed run's reports are not a gate.
    MUT_MODULES=""
    if [ -n "$SCORE" ]; then
      MUT_MOD_OUT=$(mutation_modules_under "$MUT_MARKER" "$MUT_LIMIT")
      MUT_MOD_UNDER=$(printf '%s\n' "$MUT_MOD_OUT" | grep -E '^[0-9]' | awk -F'\t' '{ printf "    %s  %s (%s)\n", $1, $2, $3 }')
      MUT_MOD_BAD=$(printf '%s\n' "$MUT_MOD_OUT" | sed -n 's/^unreadable /    unreadable report: /p')
      case "$MUT_MOD_OUT" in
        none)
          MUT_MODULES="  Per module: UNMEASURED — this run wrote no JSON report, so only the headline was read and
  .claude/rules/spec-hardening.md gates on the changed module. List \"json\" in the config's \"reporters\";
  a CLI --reporter replaces that list rather than adding to it." ;;
        nopython)
          MUT_MODULES="  Per module: UNMEASURED — python3 is missing, so the JSON report could not be read." ;;
        *)
          [ -n "$MUT_MOD_UNDER" ] && MUT_MODULES="  Modules under $MUT_LIMIT% (Stryker's score per file, detected/valid, merged across this run's reports):
$MUT_MOD_UNDER"
          [ -n "$MUT_MOD_BAD" ] && MUT_MODULES="${MUT_MODULES:+$MUT_MODULES
}$MUT_MOD_BAD" ;;
      esac
    fi
    rm -f "$MUT_MARKER"

    if [ "$MUT_RC" -ne 0 ] && [ -n "$SCORE" ]; then
      # A number came back, so the tool ran. Non-zero here is the gate doing its job.
      MUT_MEASURED=1
      add "[MUTATION] GATE FAILED — Stryker's own score ${SCORE}% against $MUT_LIMIT_SRC ($MUT_LIMIT).
  This is the gate failing, not the tool crashing: Stryker exits non-zero when the score is under break.
  Scope: $MUT_SCOPE.
  NOTE: ${SCORE}% is Stryker's score, (Killed + Timeout) / valid. A Timeout is not a kill, so the strict
  score is this or lower — never higher (.claude/docs/testing.md).${MUT_MODULES:+
$MUT_MODULES}"
    elif [ "$MUT_RC" -ne 0 ]; then
      add "[MUTATION] \`$MUTATION_CMD\` failed to complete — no score was produced:
$(printf '%s' "$MUT_OUT" | tail -15)"
    elif [ -n "$SCORE" ]; then
      MUT_MEASURED=1
      if [ "${INT_SCORE:-0}" -lt "$MUT_LIMIT" ]; then
        add "[MUTATION] Stryker's own score ${SCORE}% is below $MUT_LIMIT_SRC ($MUT_LIMIT).
  Scope: $MUT_SCOPE.
  NOTE: ${SCORE}% counts a Timeout as a kill; the strict score (Killed / valid) is this or lower.${MUT_MODULES:+
$MUT_MODULES}"
      elif [ -n "$MUT_MODULES" ]; then
        # The fundit 006 shape: the headline passes and says nothing about the module under it.
        add "[MUTATION] The headline ${SCORE}% passes $MUT_LIMIT_SRC ($MUT_LIMIT), but the module gate does not.
  Scope: $MUT_SCOPE.
$MUT_MODULES"
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
elif [ "$FULL" -eq 1 ]; then
  # Row 051: a stack with no runner (PHP, bare node) heard nothing at all from --full, and the due
  # banner kept asking for a pass that had no way to happen. Not stamped, as before; now it is said.
  note "[note] --full: no mutation runner for this stack — nothing measured, not stamped. A project whose stack
  has none declares one as scripts/run-mutation-gate.sh (project-owned; it must print \`mutation score N%\`)."
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
$(printf '%s' "$FAST_OUT" | sed -n 1,8p)
  Re-run: python3 scripts/e2e-gate-census.py"
  fi
fi

CENSUS_SCRIPT="$ROOT/scripts/e2e-wait-audit.sh"
if [ -f "$CENSUS_SCRIPT" ]; then
  CENSUS_OUT="$(bash "$CENSUS_SCRIPT" 2>&1)"
  CENSUS_RC=$?
  if [ "$CENSUS_RC" -eq 0 ]; then
    :
  elif [ "$CENSUS_RC" -eq 2 ] || grep -qE ': error [A-Z]{2}[0-9]{4}|MSB[0-9]+|Build FAILED' <<< "$CENSUS_OUT"; then
    note "[note] census audit could not run — the E2E project did not build, so the four drift
  censuses were neither passed nor failed. Not counted as a finding (a build failure is not census
  drift), but recorded, because a maintenance pass that skipped its checks in silence is the false
  green spec 544 exists to remove. Re-run: bash scripts/e2e-wait-audit.sh"
  else
    add "[CENSUS] A drift census is RED. These are the instruments that pin the browser suite's own
  discipline, and spec 544 exists because four of them sat red for nine days unseen.
$(printf '%s' "$CENSUS_OUT" | grep -E '\S+\.cs:' | sed -n 1,12p)
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
$(printf '%s' "$CARVE_OUT" | sed -n 1,12p)
  Section 2 caps a spec at 2 carves; section 3 says there is no depth 3. Both were unmeasured until
  now, so these are pre-existing. Fold the excess into one consolidated row, or decide otherwise —
  but decide, rather than letting the tree keep growing."
  elif [ "$CARVE_RC" -eq 3 ]; then
    # No row names its parent, so the two limits were never measured -- which is not the same as
    # respected (row 027: agentcrm read "clean" over a depth-3 chain).
    add "[CARVE SHAPE] unmeasurable — no row in specs/INDEX.md says which spec carved it:
$(printf '%s' "$CARVE_OUT" | sed -n 1,12p)
  Budget (section 2) and depth (section 3) are unknown, not respected. Write 'carved by <id>' on the
  rows a spec carved, starting with the newest."
  elif [ "$CARVE_RC" -ne 0 ]; then
    add "[CARVE SHAPE] scripts/register-convergence.sh --carves could not run (exit $CARVE_RC):
$(printf '%s' "$CARVE_OUT" | sed -n 1,3p)"
  fi
fi

# ------------------------------------------------------ 6c. cross-platform portability
#
# Two developers, two platforms, and cross-platform is a base requirement rather than a preference.
# A construct that works on one is a script the other never successfully runs -- and it fails
# QUIETLY, because the usual symptom is an empty result, not an error.
#
# Both scripts are CORE, so a missing one is a sync defect and a [SETUP] finding. Until row 033 the
# guard had no else: fundit synced this call site without the two scripts and read "clean" (F002).
PORT_MISSING=""
for f in scripts/validate-portability.sh scripts/portability_audit.py; do
  [ -f "$f" ] || PORT_MISSING="${PORT_MISSING:+$PORT_MISSING, }$f"
done
if [ -n "$PORT_MISSING" ]; then
  add "[SETUP] portability check did not run — $PORT_MISSING missing. Run /project-update to restore it."
else
  PORT_OUT=$(measured portability bash scripts/validate-portability.sh --all 2>&1); PORT_RC=$?
  if [ "$PORT_RC" -eq 1 ]; then
    add "[PORTABILITY] construct(s) that run on one developer's platform and not the other's:
$(printf '%s' "$PORT_OUT" | grep -E '^\s+scripts/' -A2 | sed -n 1,12p)
  Run: bash scripts/validate-portability.sh --all"
  elif [ "$PORT_RC" -ne 0 ]; then
    add "[PORTABILITY] scripts/validate-portability.sh could not run (exit $PORT_RC):
$(printf '%s' "$PORT_OUT" | sed -n 1,3p)"
  fi
fi

# ------------------------------------------------------ 6d. narrow viewport in the shared suite
#
# fundit F024: the a11y/visual suite ran at Playwright's default 1280px, so a horizontal overflow at
# 375px shipped in spec 001 and was found by hand in spec 004. A width set inside one test is the
# per-spec pattern that let it through, so a TS suite is judged on its CONFIG, each config alone.
# .NET has no config file to read; there any test file setting a narrow width counts (the weaker
# check, and the finding says so). Narrow = below 480px or a phone device. Row 035.
VP_W='(3[0-9]{2}|4[0-7][0-9])([^0-9]|$)'
VP_OPTOUT='narrow-viewport:[[:space:]]*not-applicable'
VP_CFG_RE='(^|/)playwright[^/]*\.config\.(ts|js|mjs|cjs)$'
VP_FILES=$(git ls-files --cached --others --exclude-standard 2>/dev/null)
VP_CONFIGS=$(printf '%s\n' "$VP_FILES" | grep -E "$VP_CFG_RE")
VP_BAD=""
if [ -n "$VP_CONFIGS" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -Eq "width:[[:space:]]*$VP_W|devices\[[[:space:]]*.(iPhone|Pixel|Galaxy)|$VP_OPTOUT" "$f" 2>/dev/null ||
      VP_BAD="${VP_BAD}  $f
"
  done <<EOF
$VP_CONFIGS
EOF
else
  VP_CSPROJ=$(printf '%s\n' "$VP_FILES" | grep -E '\.csproj$' | while IFS= read -r f; do
    [ -f "$f" ] && grep -q 'Microsoft\.Playwright' "$f" 2>/dev/null && printf '%s\n' "$f"; done)
  # The hit list, not grep -q's status: under pipefail an early exit SIGPIPEs the loop upstream and
  # the pipeline reads as "no match" on a large repo -- a false finding (spec 024's class).
  VP_NET_HITS=""
  [ -n "$VP_CSPROJ" ] && VP_NET_HITS=$(printf '%s\n' "$VP_FILES" | grep -iE '(test|e2e|playwright)[^/]*(/.*)?\.cs$' |
      while IFS= read -r f; do [ -f "$f" ] && printf '%s\0' "$f"; done |
      xargs -0 grep -El "((SetViewportSizeAsync|TestFixture|TestCase|InlineData|DataRow)\([[:space:]]*|Width[[:space:]]*=[[:space:]]*)$VP_W|$VP_OPTOUT" 2>/dev/null)
  if [ -n "$VP_CSPROJ" ] && [ -z "$VP_NET_HITS" ]; then
    VP_BAD="$(printf '%s\n' "$VP_CSPROJ" | sed 's/^/  /')
  (.NET has no shared config to read: no test file sets a width below 480px)
"
  fi
fi
if [ -n "$VP_BAD" ]; then
  add "[VIEWPORT] Playwright suite runs at desktop width only — a horizontal overflow at phone width ships unseen (fundit F024):
${VP_BAD%
}
  Add a narrow project (375px) to the shared config per .claude/docs/testing.md (Viewports), or state why not with a 'narrow-viewport: not-applicable' comment."
fi

# ------------------------------------------------------ 6e. the project's own ratchets
# Row 052 (ighweld F062): projects write scripts/check-*.sh ratchets and nothing runs them. ighweld
# had thirteen and none was invoked by anything; a ratchet that runs when somebody remembers stops
# running. So every pass runs every one it finds: from the root, no arguments, stdin closed, exit 0
# passes. Green says nothing. A ratchet that cannot run here opts out with
# `# maintenance: skip <reason>` in its first 30 lines; the reason is required and printed, so a
# skip is never silent. Output goes to a file, not a pipe: a timed-out ratchet's orphaned children
# would hold a pipe open and the pass would wait for them anyway.
RATCHET_LIMIT=${MAINTENANCE_RATCHET_TIMEOUT:-300}
case "$RATCHET_LIMIT" in (''|*[!0-9]*) RATCHET_LIMIT=300 ;; esac
RATCHET_TIMEOUT=""
command -v timeout >/dev/null 2>&1 && RATCHET_TIMEOUT=timeout
[ -z "$RATCHET_TIMEOUT" ] && command -v gtimeout >/dev/null 2>&1 && RATCHET_TIMEOUT=gtimeout
RATCHET_SKIPS=""
RATCHET_UNBOUNDED=0
for ratchet in scripts/check-*.sh; do
  [ -f "$ratchet" ] || continue
  skip_line=$(head -30 "$ratchet" | grep -m1 -E '^#[[:space:]]*maintenance:[[:space:]]*skip([[:space:]]|$)')
  if [ -n "$skip_line" ]; then
    reason=$(printf '%s' "$skip_line" | sed -E 's/^#[[:space:]]*maintenance:[[:space:]]*skip[[:space:]]*//; s/^(—|–|-)[[:space:]]*//; s/[[:space:]]+$//')
    if [ -n "$reason" ]; then
      RATCHET_SKIPS="${RATCHET_SKIPS}  $ratchet — $reason
"
      continue
    fi
    note "[note] $ratchet: skip marker has no reason — ignored, so it ran. Write \`# maintenance: skip <why>\`."
  fi
  ratchet_out=$(mktemp "${TMPDIR:-/tmp}/ratchet.XXXXXX")
  if [ -n "$RATCHET_TIMEOUT" ]; then
    "$RATCHET_TIMEOUT" "$RATCHET_LIMIT" bash "$ratchet" </dev/null >"$ratchet_out" 2>&1; ratchet_rc=$?
  else
    RATCHET_UNBOUNDED=1
    bash "$ratchet" </dev/null >"$ratchet_out" 2>&1; ratchet_rc=$?
  fi
  if [ -n "$RATCHET_TIMEOUT" ] && [ "$ratchet_rc" -eq 124 ]; then
    add "[RATCHET] $ratchet timed out after ${RATCHET_LIMIT}s — it did not finish, so it neither passed nor failed.
  Raise MAINTENANCE_RATCHET_TIMEOUT, or mark it \`# maintenance: skip <why>\` if it cannot run here.
$(tail -8 "$ratchet_out" | sed 's/^/  /')"
  elif [ "$ratchet_rc" -ne 0 ]; then
    add "[RATCHET] $ratchet failed (exit $ratchet_rc):
$(tail -12 "$ratchet_out" | sed 's/^/  /')"
  fi
  rm -f "$ratchet_out"
done
[ -n "$RATCHET_SKIPS" ] && note "[note] ratchets skipped by their own marker:
${RATCHET_SKIPS%
}"
[ "$RATCHET_UNBOUNDED" -eq 1 ] && note "[note] ratchets ran unbounded — neither timeout nor gtimeout is installed, so a hung one hangs this pass."

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
  SUITE_FROM=""
  SUITE_PARTIAL=""
  # A DECLARATION OUTRANKS EVERY DETECTED STACK (row 051). Detection knew two stacks, so emaljen's
  # bare `node tests/*.mjs` suite could never be discharged here, and iskvalp's root .sln hid the
  # jest suite in client/package.json and got stamped green over half of it. The project says what
  # its whole suite is in .claude/.suite-command, first line that is neither blank nor a # comment.
  # Judged like a detected command (exit code + run-verdict.sh); a human chose it, so no evidence
  # gate, the same rule template-sync-verify.sh keeps.
  declared_command() { # declared_command FILE — first line neither blank nor a # comment; empty when unreadable
    [ -r "$1" ] && grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -v '^[[:space:]]*$' | sed -n 1p
  }
  SUITE_DECL=.claude/.suite-command
  SUITE_CMD=$(declared_command "$SUITE_DECL")
  [ -n "$SUITE_CMD" ] && SUITE_FROM="declared in $SUITE_DECL"
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
  if [ -n "$SUITE_CMD" ]; then
    :
  elif [ -f package.json ] && grep -q '"test"[[:space:]]*:' package.json 2>/dev/null; then
    SUITE_CMD="npm test"
    if [ -n "$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ] \
       && ! grep -q 'dotnet test' package.json 2>/dev/null; then
      note "[note] --suite: using \`npm test\`, which does not mention \`dotnet test\` on a project that has a .NET solution. If the .NET suite is not run by it, this step is not covering it."
    fi
  elif [ -n "$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ]; then
    SUITE_CMD="dotnet test"
    # `dotnet test` never runs a nested package.json's tests, so a green run here is half a suite
    # when one exists (iskvalp: 1194 .NET tests stamped, 4138 jest tests never run). It still runs,
    # because the result is information; only the stamp is refused.
    SUITE_PARTIAL=$(find . -maxdepth 3 -name node_modules -prune -o -name package.json -type f ! -path ./package.json -print 2>/dev/null |
      while IFS= read -r f; do grep -q '"test"[[:space:]]*:' "$f" 2>/dev/null && printf '%s ' "${f#./}"; done)
    SUITE_PARTIAL=${SUITE_PARTIAL% }
  fi
  [ -n "$SUITE_CMD" ] && [ -z "$SUITE_FROM" ] && SUITE_FROM="detected, not declared"
  SUITE_SLNS=""
  [ "$SUITE_CMD" = "dotnet test" ] && [ "$SUITE_FROM" = "detected, not declared" ] && SUITE_SLNS=$(dotnet_solutions)

  if [ "$(printf '%s' "$SUITE_SLNS" | grep -c .)" -gt 1 ]; then
    # Row 052: a detected `dotnet test` beside a second solution builds the root one blind. Not run,
    # not stamped — a red suite over a stale solution reads exactly like a real regression.
    add "[SUITE] NOT RUN — $(printf '%s\n' "$SUITE_SLNS" | grep -c .) .NET solutions and nothing declared, so \`dotnet test\` at the root would build
  whichever one sits there, blind:
$(solution_list "$SUITE_SLNS")
  Put the command that runs the whole suite on one line in $SUITE_DECL. Not stamped: the job stays due."
  elif [ -z "$SUITE_CMD" ]; then
    # Nothing detected is not the end: say where the project declares it. A .template-sync-verify
    # command is quoted as a candidate and NEVER run here. That file often declares a unit slice on
    # purpose (its own help recommends one), and stamping a slice as the whole suite is the iskvalp
    # failure this section just stopped.
    SUITE_SYNC=$(declared_command .claude/.template-sync-verify)
    note "[note] --suite: nothing declared in $SUITE_DECL, and no .NET solution or npm test script to detect — nothing to run. Not a pass.
  Put the command that runs the whole suite (unit + integration + E2E + visual regression) on one line in $SUITE_DECL.$([ -n "$SUITE_SYNC" ] && printf '\n  Candidate: .claude/.template-sync-verify declares `%s` — declare it here only if it is the whole suite, not a slice.' "$SUITE_SYNC")"
  else
    SUITE_OUT=$(measured suite bash -c "$SUITE_CMD" 2>&1); SUITE_RC=$?
    SUITE_TAIL=$(printf '%s' "$SUITE_OUT" | tail -12)
    # Spec 031: never `$?` alone. rocky's crashed test host printed `Passed!` for the 55% that ran,
    # and an abort that exits 0 would be stamped green here. The helper is CORE; without it the
    # verdict falls back to the exit code, and the pass says so.
    if [ -f scripts/run-verdict.sh ]; then
      . scripts/run-verdict.sh
      SUITE_VERDICT=$(run_verdict "$SUITE_RC" "$SUITE_OUT")
    else
      SUITE_VERDICT=$([ "$SUITE_RC" -eq 0 ] && echo passed || echo failed)
      note "[note] --suite: scripts/run-verdict.sh missing — judged by exit code alone, so an aborted run can read green."
    fi
    if [ "$SUITE_VERDICT" = aborted ]; then
      # NOT stamped, whatever the exit code. The summary counts only the tests that ran.
      add "[SUITE] \`$SUITE_CMD\` — the test run ABORTED (exit $SUITE_RC): the test host did not finish, so any
  Passed!/Total line below counts only the tests that ran. Not stamped: the job stays due.
$SUITE_TAIL"
    elif [ "$SUITE_VERDICT" = passed ] && [ -n "$SUITE_PARTIAL" ]; then
      add "[SUITE] \`$SUITE_CMD\` is green, but it is not the whole suite: it never runs the test script in
  $SUITE_PARTIAL. Not stamped: the job stays due. Put the command that runs every
  part on one line in $SUITE_DECL, and --suite runs that instead."
    elif [ "$SUITE_VERDICT" = passed ]; then
      note "[note] suite green — \`$SUITE_CMD\` ($SUITE_FROM)"
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
[ "$LEDGER_OK" -eq 1 ] && python3 scripts/maintenance_ledger.py record pass "$(( $(date +%s) - PASS_START ))" "$([ "$FINDINGS" -eq 0 ] && echo 0 || echo 1)" 2>/dev/null
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
