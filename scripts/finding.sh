#!/bin/bash
# finding.sh — record what a spec found, without growing the register.
#
# WHY. Every gate in this template finds things, and until now the only place to put a finding was a
# new register row. So a spec that closed one defect honestly produced two or three more rows, and
# the register grew faster than it closed: measured 2026-09-03, rocky 2.40, agentcrm 1.47,
# consultpilot 1.42, ighweld-2026 2.18. Nobody was careless. Every row was real. The mechanism was
# simply the only container on offer.
#
# A carve budget of two per spec still assumes carving is the normal outcome. It is not. The normal
# outcome is that a finding is WRITTEN DOWN and DECIDED LATER, in a batch, when there is enough of
# them to see the shape — the same pattern maintenance-due.sh uses for expensive work: the project
# collects, presents at a cadence, and the developer decides.
#
# So: findings land here. specs/FINDINGS.md is git-tracked and shared between lanes, because a
# finding David records is one Johan must see. Every 5 ticked specs it is presented for review, on
# the same cadence as the integration-hardening checkpoint, and only then does anything become a row.
#
# Usage:
#   bash scripts/finding.sh --add "<one line>" [--spec NNN] [--kind defect|gap|debt|idea]
#   bash scripts/finding.sh --list            # open findings
#   bash scripts/finding.sh --count           # how many are waiting
#   bash scripts/finding.sh --resolve N "<what was decided>"
#
# Exit: 0 ok · 2 usage
set -uo pipefail
export LC_ALL=C
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT="$PWD"
LEDGER="$ROOT/specs/FINDINGS.md"

MODE=""; TEXT=""; SPEC=""; KIND="defect"; NUM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --add)     MODE=add; TEXT="${2:-}"; shift 2 ;;
    --list)    MODE=list; shift ;;
    --count)   MODE=count; shift ;;
    --resolve) MODE=resolve; NUM="${2:-}"; TEXT="${3:-}"; shift 3 ;;
    --spec)    SPEC="${2:-}"; shift 2 ;;
    --kind)    KIND="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "finding.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

seed() {
  [ -f "$LEDGER" ] && return 0
  mkdir -p "$ROOT/specs"
  cat > "$LEDGER" <<'HDR'
# Findings

Things the pipeline found that are NOT yet register rows, and may never be.

A spec records what it found here and keeps going. Every 5 ticked specs these are presented as one
batch and the developer decides per finding: fix it now, make it a row, or drop it. That review is
the only thing that grows the register — see `.claude/rules/carve-budget.md`.

This file is git-tracked on purpose: a finding one lane records is one the other must see.

Status: `[ ]` open · `[x]` decided (the decision is on the line)

## Open

HDR
}

case "$MODE" in
  add)
    [ -n "$TEXT" ] || { echo "finding.sh: --add needs text" >&2; exit 2; }
    seed
    # `grep -c` PRINTS 0 and EXITS 1 when nothing matches, so `... || echo 0` emits "0\n0" and the
    # arithmetic dies. Capture, then normalise.
    N=$(grep -cE '^- \[[ x]\]' "$LEDGER" 2>/dev/null); N=$(printf '%s' "$N" | head -1)
    case "$N" in ''|*[!0-9]*) N=0 ;; esac
    N=$((N + 1))
    printf -- '- [ ] F%03d — %s — %s%s — %s\n' "$N" "$KIND" \
      "$(date +%Y-%m-%d)" "$([ -n "$SPEC" ] && printf ' · from spec %s' "$SPEC")" "$TEXT" >> "$LEDGER"
    echo "recorded F$(printf '%03d' "$N") in specs/FINDINGS.md — not a register row, and it will be reviewed at the next 5-spec checkpoint."
    ;;
  list)
    [ -f "$LEDGER" ] || { echo "no findings recorded"; exit 0; }
    grep -E '^- \[ \]' "$LEDGER" || echo "no open findings"
    ;;
  count)
    if [ -f "$LEDGER" ]; then
      C=$(grep -cE '^- \[ \]' "$LEDGER" 2>/dev/null); C=$(printf '%s' "$C" | head -1)
      case "$C" in ''|*[!0-9]*) C=0 ;; esac
      echo "$C"
    else echo 0; fi
    ;;
  resolve)
    [ -f "$LEDGER" ] || { echo "finding.sh: no ledger at $LEDGER" >&2; exit 2; }
    [ -n "$NUM" ] && [ -n "$TEXT" ] || { echo "finding.sh: --resolve needs a number and a decision" >&2; exit 2; }
    # STRIP LEADING ZEROS BEFORE printf, and refuse anything that is not digits.
    #
    # `printf 'F%03d' 033` reads 033 as OCTAL and yields F027. The ledger writes
    # ids as F027, F033, F090 — so "033" is the obvious thing to type, and it
    # silently resolved a DIFFERENT finding with the decision text meant for
    # another one. Found 2026-09-09 by doing exactly that: --resolve 033 071 044
    # 034 047 marked F027 F057 F036 F028 F039 resolved, each with a decision
    # about an unrelated issue, and reported success five times.
    #
    # An id above 07 with a leading zero is not even valid octal, so those
    # errored — printf emitted "F000", returned non-zero, and the `|| echo`
    # appended the raw argument, producing "F000090 not found". The two halves
    # of one bug: silently wrong below 070, confusingly wrong above it. The
    # failing half is how the working half got noticed.
    case "$NUM" in
      ''|*[!0-9]*) echo "finding.sh: --resolve takes a number, got '$NUM'" >&2; exit 2 ;;
    esac
    NUM=$(printf '%s' "$NUM" | sed 's/^0*//'); [ -n "$NUM" ] || NUM=0
    ID=$(printf 'F%03d' "$NUM")
    grep -q -- "$ID " "$LEDGER" || { echo "finding.sh: $ID not found" >&2; exit 2; }
    python3 - "$LEDGER" "$ID" "$TEXT" <<'PY'
import sys, pathlib
p, fid, why = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
out = []
for l in p.read_text(encoding="utf-8").split("\n"):
    if l.startswith("- [ ] " + fid + " "):
        l = l.replace("- [ ] ", "- [x] ", 1) + f"  →  {why}"
    out.append(l)
p.write_text("\n".join(out), encoding="utf-8")
PY
    echo "$ID decided: $TEXT"
    # DECIDING A FINDING *IS* THE REVIEW, so clear the due-state here rather than asking someone to
    # remember a second command. `maintenance-due.sh` has always had `--stamp findings`, and nothing
    # in the template ever called it: `project-maintenance.sh` stamps suite, secrets, mutation and
    # similarity, and the findings job was left to a hand-run `--stamp` nobody ran. So the banner
    # said "findings review — never run in this project" on agentcrm through four reviews that
    # decided 33 findings and produced three register rows, and a spec's own status report had to be
    # corrected against the register history because it had sourced that line.
    #
    # The instrument was right about its file and wrong about the world, which is the shape
    # `.claude/rules/spec-register.md` already names for the row archiver: a mechanism that depends
    # on memory has an expiry date. A review is not a command anyone types; it is a batch of
    # decisions, and this is where a decision lands.
    #
    # Silent and best-effort on purpose: a missing or failing due-state must never turn a recorded
    # decision into an error. The ledger write above has already happened.
    [ -f "$ROOT/scripts/maintenance-due.sh" ] &&
      bash "$ROOT/scripts/maintenance-due.sh" --stamp findings >/dev/null 2>&1 || true
    ;;
esac
