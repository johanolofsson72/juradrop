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
# Row proposals (row 077). During a freeze a new row exists only when the developer approved a
# proposal for it, and a proposal has to show its need rather than assert it:
#   bash scripts/finding.sh --add "<one line>" --propose-row --need "<who is hurt, where it was seen>"
#   bash scripts/finding.sh --review [--proposals]   # open findings with overlap / citation checks
#   bash scripts/finding.sh --approve N              # prints the id and the tag the new row carries
#   bash scripts/finding.sh --decline N "<why>"
#
# Exit: 0 ok · 2 usage
set -uo pipefail
export LC_ALL=C
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT="$PWD"
LEDGER="$ROOT/specs/FINDINGS.md"

MODE=""; TEXT=""; SPEC=""; KIND="defect"; NUM=""; PROPOSE=0; NEED=""; ONLY_PROPOSALS=""
APPROVE=0; DECLINE=0   # never inherited from the environment
KIND_GIVEN=0
# A failed `shift` leaves $# unchanged, so an option missing its argument (`--approve` alone) spun
# this loop forever. Every argument-taking option refuses instead.
missing() { echo "finding.sh: $1 is missing its argument(s)" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --add)     MODE=add; TEXT="${2:-}"; shift 2 || missing "$1" ;;
    --list)    MODE=list; shift ;;
    --count)   MODE=count; shift ;;
    --resolve) MODE=resolve; NUM="${2:-}"; TEXT="${3:-}"; shift 3 || missing "$1" ;;
    --spec)    SPEC="${2:-}"; shift 2 || missing "$1" ;;
    --kind)    KIND="${2:-}"; KIND_GIVEN=1; shift 2 || missing "$1" ;;
    --propose-row) PROPOSE=1; shift ;;
    --need)    NEED="${2:-}"; shift 2 || missing "$1" ;;
    --review)  MODE=review; shift ;;
    --proposals) ONLY_PROPOSALS=--proposals; shift ;;
    --approve) MODE=resolve; NUM="${2:-}"; APPROVE=1; shift 2 || missing "$1" ;;
    --decline) MODE=resolve; NUM="${2:-}"; TEXT="${3:-}"; DECLINE=1; shift 3 || missing "$1" ;;
    -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "finding.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

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

# One finding is one line. A newline in the text would write a second, forged ledger line -- for
# instance one that reads as an approved finding to register_freeze.py.
TEXT=$(printf '%s' "$TEXT" | tr '\r\n' '  '); NEED=$(printf '%s' "$NEED" | tr '\r\n' '  ')
# `proposal` is reachable only through --propose-row, which requires --need; a free-form kind with a
# space or an em-dash would also make the line invisible to --review.
case "$KIND" in defect|gap|debt|idea) ;; *) echo "finding.sh: --kind must be defect, gap, debt or idea (a row proposal is --propose-row)" >&2; exit 2 ;; esac
SPEC=$(printf '%s' "$SPEC" | tr '\r\n' '  ')
[ -n "$NEED" ] && [ "$PROPOSE" -eq 0 ] && {
  echo "finding.sh: --need belongs to a row proposal; add --propose-row, or put the evidence in the text" >&2; exit 2; }
if [ "$PROPOSE" -eq 1 ]; then
  [ "$KIND_GIVEN" -eq 1 ] && { echo "finding.sh: --propose-row sets the kind to proposal; drop --kind" >&2; exit 2; }
  # A proposal without evidence is exactly what the freeze exists to stop: a row asserted, not shown.
  [ -n "$(printf '%s' "$NEED" | tr -d '[:space:]')" ] || {
    echo "finding.sh: a row proposal needs --need: who is hurt and where it was observed" >&2; exit 2; }
  KIND=proposal
fi
if [ "$APPROVE" -eq 1 ]; then
  TEXT="approved as a register row"
fi
if [ "$DECLINE" -eq 1 ]; then
  [ -n "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ] || {
    echo "finding.sh: --decline needs a reason — a decline nobody can read back cannot be revisited" >&2; exit 2; }
  TEXT="declined: $TEXT"
fi

case "$MODE" in
  review)
    command -v python3 >/dev/null 2>&1 || { echo "finding.sh: --review needs python3" >&2; exit 2; }
    ENGINE="$(dirname "$0")/finding_review.py"
    [ -f "$ENGINE" ] || { echo "finding.sh: scripts/finding_review.py is missing" >&2; exit 2; }
    if [ -f "$ROOT/specs/INDEX.md" ]; then
      FRZ=""
      [ -f "$(dirname "$0")/register-convergence.sh" ] &&
        FRZ=$(bash "$(dirname "$0")/register-convergence.sh" --dir "$ROOT" --freeze 2>/dev/null | head -1)
      case "$FRZ" in
        *" ON "*|*MALFORMED*|*ERROR*) printf '%s\n' "$FRZ" ;;
        *) printf 'register: %s open · no freeze\n' "$(grep -cE '^- \[[ /!]\] ' "$ROOT/specs/INDEX.md")" ;;
      esac
    else
      echo "register: no specs/INDEX.md — overlap with existing rows cannot be checked"
    fi
    ROOT="$ROOT" LEDGER="$LEDGER" REG="$ROOT/specs/INDEX.md" python3 "$ENGINE" $ONLY_PROPOSALS
    ;;
  add)
    [ -n "$TEXT" ] || { echo "finding.sh: --add needs text" >&2; exit 2; }
    seed
    # `grep -c` PRINTS 0 and EXITS 1 when nothing matches, so `... || echo 0` emits "0\n0" and the
    # arithmetic dies. Capture, then normalise.
    # A ledger saved without a final newline would glue this line onto the last one, hide it from
    # the count, and hand the NEXT add a duplicate id.
    [ -s "$LEDGER" ] && [ -n "$(tail -c1 "$LEDGER")" ] && printf '\n' >> "$LEDGER"
    # THE HIGHEST ID, NEVER A COUNT, and read across every branch (row 054). Counting local rows
    # handed two lanes the same F141–F143 on agentcrm, silently, because merge=union keeps both
    # sides; and a deleted line freed its number for reuse. max-id-in-refs.sh reads the working
    # tree plus every local and remote-tracking ref, so a pushed branch's ids are taken already.
    N=$(bash "$(dirname "$0")/max-id-in-refs.sh" --dir "$ROOT" \
          --regex '^- \[[ xX]\] F[0-9]+' -- 'specs/FINDINGS*.md' 2>/dev/null)
    N=$(printf '%s' "$N" | sed 's/^0*//')
    case "$N" in ''|*[!0-9]*) N=0 ;; esac
    N=$((N + 1))
    printf -- '- [ ] F%03d — %s — %s%s — %s%s\n' "$N" "$KIND" \
      "$(date +%Y-%m-%d)" "$([ -n "$SPEC" ] && printf ' · from spec %s' "$SPEC")" "$TEXT" \
      "$([ "$PROPOSE" -eq 1 ] && printf ' — need: %s' "$NEED")" >> "$LEDGER"
    if [ "$PROPOSE" -eq 1 ]; then
      echo "recorded F$(printf '%03d' "$N") as a row PROPOSAL — it is presented for approve/decline at this spec's stop (finding.sh --review --proposals)."
      exit 0
    fi
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
    NUM=${NUM#[Ff]}   # --review prints F012; accept what people copy
    case "$NUM" in
      ''|*[!0-9]*) echo "finding.sh: --resolve takes a number, got '$NUM'" >&2; exit 2 ;;
    esac
    NUM=$(printf '%s' "$NUM" | sed 's/^0*//'); [ -n "$NUM" ] || NUM=0
    ID=$(printf 'F%03d' "$NUM")
    # Only an OPEN finding can be decided. A decided one used to print "decided" and exit 0 while the
    # ledger stayed as it was -- an --approve on a declined finding then handed out a tag the freeze
    # would reject.
    if ! grep -q "^- \[ \] $ID " "$LEDGER"; then
      if grep -q "^- \[x\] $ID " "$LEDGER"; then echo "finding.sh: $ID is already decided" >&2
      else echo "finding.sh: $ID not found" >&2; fi
      exit 2
    fi
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
    if [ "$APPROVE" -eq 1 ]; then
      NEXT=""
      [ -f "$ROOT/scripts/next-register-id.sh" ] && NEXT=$(cd "$ROOT" && bash scripts/next-register-id.sh 2>/dev/null)
      echo "Add the row${NEXT:+ (next free id right now: $NEXT — re-run next-register-id.sh when you write it)} and end it with: — approved $ID"
      echo "Without that tag, register-convergence.sh --freeze counts it as a row added during the freeze."
    fi
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
