#!/bin/bash
# lane-catchup.sh — bring a second lane's machine level with the register.
#
# WHY THIS EXISTS. A two-lane project shares a git repo and nothing else. When
# one lane changes the config, the rules, or the shared machinery, the other
# lane finds out by pulling -- and on a lane that sets CLAUDE_TEMPLATE_AUTOSYNC=0
# (which .claude/rules/spec-register.md tells the second machine to do, so the
# two do not race each other's config commits) nothing arrives on its own.
#
# The alternative was a written list of steps sent to a person. That fails three
# ways and did, on the first draft: the step that stops permission prompts sat
# fourth, so the developer clicked through prompts to reach it; the paths were
# guesses about someone else's disk; and it ended with "report back", which makes
# a person the transport between two machines that already share a disk -- the
# exact anti-pattern .claude/rules/lane-handoff.md exists to remove.
#
# So: one command, ordered so each step clears the way for the next, and its
# findings are WRITTEN to specs/INDEX.pending.md rather than relayed by hand.
#
# Reports by default and changes nothing. --apply makes the two machine-local
# changes (permission denies, nightly cron); everything else is read-only.
#
# Usage:
#   bash scripts/lane-catchup.sh              # report only
#   bash scripts/lane-catchup.sh --apply      # also make the machine-local fixes
#   bash scripts/lane-catchup.sh --apply --at 03:00
#
# Exit: 0 nothing needs a human · 1 something does · 2 could not run

set -uo pipefail
export LC_ALL=C

APPLY=0; AT="02:30"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --at) AT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "lane-catchup.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "lane-catchup: run this from inside the project repo." >&2; exit 2; }
cd "$ROOT" || exit 2

NEEDS_HUMAN=0
say()  { printf '%s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*" 2>/dev/null || printf '\n%s\n' "$*"; }
todo() { NEEDS_HUMAN=1; printf '  → %s\n' "$*"; }

# ── 1. Permissions FIRST. Every step below runs shell commands, and if this is
#      unfixed the developer approves each one by hand on the way to the fix.
head_ "1. Permission prompts"
GS="$HOME/.claude/settings.json"
if [ ! -f "$GS" ]; then
  say "  no global settings at $GS — nothing to change"
else
  DENIES=$(python3 - "$GS" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
bad = [r for r in d.get("permissions", {}).get("deny", [])
       if r.startswith(("Read(~/", "Edit(~/"))]
print("\n".join(bad))
PY
)
  if [ -z "$DENIES" ]; then
    say "  no Read(~/…) deny rules — prompts are not coming from here"
  elif [ "$APPLY" -eq 1 ]; then
    python3 - "$GS" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
perm = d.setdefault("permissions", {})
before = perm.get("deny", [])
perm["deny"] = [r for r in before if not r.startswith(("Read(~/", "Edit(~/"))]
open(p, "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
print(f"  removed {len(before) - len(perm['deny'])} Read/Edit home-dir deny rule(s); "
      f"{len(perm['deny'])} deny rule(s) kept")
PY
    say "  every Bash deny is kept — rm -rf, sudo, force-push, hard reset"
  else
    say "  these deny rules are why ordinary commands prompt:"
    printf '    %s\n' $DENIES
    todo "run with --apply to remove them (Bash denies are kept)"
  fi
fi

# ── 2. Is the working tree even able to take an update?
head_ "2. Repository state"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
say "  branch $BRANCH · $DIRTY uncommitted file(s)"
git fetch -q origin 2>/dev/null || true
BEHIND=$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)
if [ "${BEHIND:-0}" -gt 0 ]; then
  say "  $BEHIND commit(s) behind origin/$BRANCH"
  todo "git pull  — this is where the rules, scripts and settings arrive"
else
  say "  up to date with origin/$BRANCH"
fi
[ "${AHEAD:-0}" -gt 0 ] && todo "$AHEAD commit(s) not pushed — the other lane cannot see them"

# ── 3. Did the shared machinery actually land?
head_ "3. Shared machinery"
# ASKED, not listed. This used to name four files, and the list was written before
# maintenance-due.sh, carve_audit.py and validate-portability.sh existed -- so on the day
# those landed, the one command whose job is "tell me what my machine is missing" would
# have said everything was present. That is the third time today the same shape has bitten:
# an enumeration is a list of what somebody thought of, and it goes stale silently because
# there is no error state for "you forgot to add it here too". The Bash allow list and
# sync-prompt.md's 27-script list were the other two.
#
# template-autosync.sh --list-core-scripts is the manifest, and it answers locally without
# a clone or a network round.
MISS=""
CORE_LIST=""
[ -f scripts/template-autosync.sh ] && \
  CORE_LIST=$(bash scripts/template-autosync.sh --list-core-scripts 2>/dev/null)
if [ -n "$CORE_LIST" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "scripts/$f" ] || MISS="$MISS scripts/$f"
  done <<< "$CORE_LIST"
  N_CORE=$(printf '%s\n' "$CORE_LIST" | grep -c .)
else
  # No manifest to ask: fall back to the rules, which are not in it.
  N_CORE=0
fi
for f in .claude/rules/carve-budget.md .claude/rules/spec-register.md .claude/rules/lane-handoff.md; do
  [ -f "$f" ] || MISS="$MISS $f"
done
if [ -n "$MISS" ]; then
  say "  missing:$MISS"
  todo "git pull first, then re-run this"
else
  say "  $N_CORE CORE script(s) + the lane rules — all present"
  # -f, not -x. Eight CORE scripts in the template were shipped without their
  # executable bit and the sync copies modes faithfully, so an -x guard here
  # skipped this entire check in silence on all six projects. The SessionStart
  # hook already learned this and tests `-x || -f`; this is the same lesson.
  if [ -f scripts/template-autosync.sh ]; then
    OUT=$(timeout 240 bash scripts/template-autosync.sh --force --dry-run 2>&1)
    printf '%s\n' "$OUT" | grep -E '^\[check\] would' | sed 's/^/  /'
    SKIPS=$(printf '%s\n' "$OUT" | grep '^  SKIP' | sed 's/^  SKIP   //; s/ (differs.*//')
    if [ -n "$SKIPS" ]; then
      say "  locally-edited docs the sync will not touch:"
      printf '    %s\n' $SKIPS
      todo "these need /project-update (a prose merge) or --accept-local"
    fi
  fi
fi

# ── 4. Recurring work: what this project owes, not what a timer says.
#
# This section used to install a crontab entry. That was the wrong answer and it is now the
# rule's own example of the wrong answer (.claude/rules/github-actions.md): a cron runs whether
# or not there is anything to do, runs at 02:00 on a sleeping laptop, and does not catch up a
# job it missed. Seven were installed on 2026-09-03 and not one had produced a log by morning.
#
# The project keeps its own due-state instead, and the developer plans the expensive work around
# their day. Reported in section 6 below, with the rest of what is true of THIS machine.
head_ "4. Recurring work"
if [ -f scripts/maintenance-due.sh ]; then
  say "  tracked by scripts/maintenance-due.sh — reported at every session start and after"
  say "  every ticked row, so an expensive pass is planned rather than scheduled. See section 6."
else
  say "  scripts/maintenance-due.sh is not here yet (pull first)"
fi

# ── 5. Where the register stands, and what this lane owns.
#
# DELEGATED, not reimplemented. .claude/rules/lane-handoff.md is explicit: "There is
# exactly one engine, scripts/lane_status.py. The hook renders the brief at session
# start, the script the full report on demand. Two readers of one register that
# could answer differently about who owns what is precisely what
# .claude/rules/spec-register.md warns about."
#
# The first draft of this file grepped for "@$OWNER" itself, which made three
# implementations of one question -- and they did not agree: spec_active.py requires
# an em-dash before the tag (OWNER_RE), that grep did not. It also answered far less:
# your rows and nothing about what the other lane holds, what is unclaimed and
# actually runnable, or what is held and why.
head_ "5. This lane"
if [ -z "${SPEC_OWNER:-}" ]; then
  say "  SPEC_OWNER is unset — set it in .claude/settings.local.json so the"
  say "  guards resolve YOUR row and not the other lane's:"
  say '    { "env": { "SPEC_OWNER": "yourname", "CLAUDE_TEMPLATE_AUTOSYNC": "0" } }'
  todo "set SPEC_OWNER"
elif [ -f scripts/lane-status.sh ]; then
  bash scripts/lane-status.sh 2>/dev/null | sed 's/^/  /'
else
  say "  scripts/lane-status.sh is not here yet (pull first)"
fi

# Convergence is a different question from ownership -- how fast the register closes,
# not who owns what -- so it keeps its own engine and its own line.
if [ -f scripts/register-convergence.sh ]; then
  CONV_RAW=$(bash scripts/register-convergence.sh 2>&1); RC=$?
  say "  $(printf '%s\n' "$CONV_RAW" | head -1)"
  [ "$RC" = 2 ] && todo "convergence stop — see .claude/rules/carve-budget.md before carving any row"
  # The two limits the ratio does not measure. Reported here because a lane arriving at a
  # register that already breaches them should know before it carves anything of its own.
  if [ -f scripts/carve_audit.py ]; then
    CARVE_RAW=$(bash scripts/register-convergence.sh --carves 2>&1)
    printf '%s\n' "$CARVE_RAW" | grep -E '^\[CARVE|^carve shape' | sed 's/^/  /' | head -4
  fi
fi

# ── 6. Does the shared machinery run on THIS machine?
#
# The point of this section is the asymmetry: Johan is on macOS and David on Linux, and a
# construct that works on one is a script the other never successfully runs -- usually with
# an empty result rather than an error. agentcrm's test-order-varied.sh enumerated 0 of 135
# test classes on macOS for months because of `find -printf`.
head_ "6. This machine"
if [ -f scripts/validate-portability.sh ]; then
  PORT_RAW=$(bash scripts/validate-portability.sh --all 2>&1); PRC=$?
  say "  $(printf '%s\n' "$PORT_RAW" | grep -E '^portability:' | head -1)"
  [ "$PRC" = 1 ] && todo "portability findings — bash scripts/validate-portability.sh --all"
else
  say "  scripts/validate-portability.sh is not here yet (pull first)"
fi
if [ -f scripts/maintenance-due.sh ]; then
  DUE_RAW=$(bash scripts/maintenance-due.sh --brief 2>&1)
  if [ -n "$DUE_RAW" ]; then
    printf '%s\n' "$DUE_RAW" | sed 's/^/  /'
    todo "maintenance is due on this machine — bash scripts/project-maintenance.sh --full --suite"
  else
    say "  maintenance: nothing due on this machine"
  fi
fi

head_ "Summary"
if [ "$NEEDS_HUMAN" -eq 0 ]; then
  say "  Nothing needs a human. This lane is level."
else
  say "  The arrows above are what is left. Findings that concern the OTHER lane"
  say "  belong in specs/INDEX.pending.md or a new register row, committed and"
  say "  pushed — not in a chat message (.claude/rules/lane-handoff.md)."
fi
exit "$NEEDS_HUMAN"
