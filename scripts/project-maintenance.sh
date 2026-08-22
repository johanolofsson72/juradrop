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
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --full)  FULL=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$ROOT" || exit 2

FINDINGS=0
REPORT=""
add() { REPORT="${REPORT}$1
"; FINDINGS=$((FINDINGS + 1)); }

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
for f in specs/INDEX.md specs/SCENARIOS.md; do
  [ -f "$f" ] || continue
  BYTES=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  case "$BYTES" in (''|*[!0-9]*) BYTES=0 ;; esac
  if [ "$BYTES" -gt 25600 ]; then
    add "[CONTEXT-COST] $f is $((BYTES / 1024)) KB — read on every spec. Trim: scripts/archive-spec-history.sh --keep 5"
  fi
done

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
if [ -f specs/INDEX.md ] || [ -d .specify ]; then
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

# ------------------------------------------------------------- 5. mutation kill rate
MUTATION_CMD=""
# `find`, not a glob: bash globstar is off by default, so `./**/*.csproj` would
# silently only match one level deep — and would miss src/Foo/Foo.csproj.
if [ -n "$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ]; then
  MUTATION_CMD="dotnet stryker"
elif [ -f package.json ] && grep -q '"@stryker-mutator/core"' package.json 2>/dev/null; then
  MUTATION_CMD="npx stryker run"
fi

if [ -n "$MUTATION_CMD" ]; then
  if [ "$FULL" -eq 1 ]; then
    MUT_OUT=$(eval "$MUTATION_CMD" 2>&1)
    MUT_RC=$?
    SCORE=$(printf '%s' "$MUT_OUT" | grep -oE 'mutation score[^0-9]*[0-9]+(\.[0-9]+)?' | tail -1 | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1)
    if [ "$MUT_RC" -ne 0 ]; then
      add "[MUTATION] \`$MUTATION_CMD\` failed to complete:
$(printf '%s' "$MUT_OUT" | tail -15)"
    elif [ -n "$SCORE" ]; then
      INT_SCORE=${SCORE%%.*}
      if [ "${INT_SCORE:-0}" -lt 80 ]; then
        add "[MUTATION] kill rate ${SCORE}% — below the ~80% target on critical modules. The suite is green but does not bite (.claude/docs/testing.md)."
      fi
    fi
  else
    REPORT="${REPORT}[skipped] mutation pass — re-run with --full to execute \`$MUTATION_CMD\` (slow).
"
  fi
fi

# ------------------------------------------------------------------------ verdict
if [ "$FINDINGS" -eq 0 ]; then
  [ "$QUIET" -eq 1 ] && exit 0
  echo "project-maintenance: clean — no secrets, no CVEs, no register drift, no context bloat.$([ "$FULL" -eq 0 ] && [ -n "$MUTATION_CMD" ] && printf ' (mutation pass skipped — use --full)')"
  exit 0
fi

echo "project-maintenance: $FINDINGS finding(s) — $(date -u +%Y-%m-%d)"
echo
printf '%s' "$REPORT"
echo "Each finding needs an explicit fix / defer / dismiss decision per .claude/rules/validation-followup.md."
exit 1
