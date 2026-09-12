#!/bin/bash
# next-register-id.sh — the next free id in this project's register.
#
# WHY THIS EXISTS. On 2026-09-03 I picked a colliding row id three times in one
# session: rocky 578-580 and H12, the template's 021, film-i-vast's 032. Every
# one was caught by validate-register-ids.sh, which is the gate working exactly
# as designed — and every one still cost a commit, a renumber and a second push.
#
# A gate that catches a mistake is not the same as a mistake that cannot be made.
# An id is a permanent handle: spec_active.py resolves it, both PreToolUse guards
# glob specs/<id>-* from it, and the archiver keys on it. Guessing the next one by
# eye over a 150-row register is a coin toss.
#
# Reads the register, returns ids nothing has claimed. Numeric by default because
# that is what a product row uses; --alpha for a letter-led series (S, H, T, M, Q)
# and --checkpoint for the next H.
#
# Usage:
#   bash scripts/next-register-id.sh              # next free numeric, e.g. 037
#   bash scripts/next-register-id.sh --count 3    # the next three
#   bash scripts/next-register-id.sh --alpha S    # next free S-row, e.g. S21
#   bash scripts/next-register-id.sh --checkpoint # next free H-row, e.g. H3
#
# Exit: 0 with ids on stdout · 2 no register, or the series is exhausted

set -uo pipefail
export LC_ALL=C

COUNT=1; SERIES=""; MODE="numeric"; DIR="."
while [ $# -gt 0 ]; do
  case "$1" in
    --count) COUNT="${2:-1}"; shift 2 ;;
    --alpha) MODE="alpha"; SERIES="${2:-}"; shift 2 ;;
    --checkpoint) MODE="alpha"; SERIES="H"; shift ;;
    --dir) DIR="${2:-.}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "next-register-id.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$COUNT" in ''|*[!0-9]*) echo "next-register-id.sh: --count wants an integer" >&2; exit 2 ;; esac
[ "$COUNT" -ge 1 ] || { echo "next-register-id.sh: --count must be >= 1" >&2; exit 2; }
if [ "$MODE" = alpha ] && [ -z "$SERIES" ]; then
  echo "next-register-id.sh: --alpha needs a series letter, e.g. --alpha S" >&2; exit 2
fi

ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || ROOT="$DIR"
REG="$ROOT/specs/INDEX.md"
[ -f "$REG" ] || { echo "next-register-id.sh: no register at $REG" >&2; exit 2; }

MODE="$MODE" SERIES="$SERIES" COUNT="$COUNT" REG="$REG" python3 - <<'PY'
import os, re, sys

reg, mode, series, count = os.environ["REG"], os.environ["MODE"], os.environ["SERIES"], int(os.environ["COUNT"])
text = open(reg, encoding="utf-8").read()

# Every id the register mentions as a ROW, whatever its state. A ticked row's id
# is as taken as an open one's -- ids are permanent handles and are never reused,
# so `- [x]` counts. The archives count too: a row moved to INDEX.completed.md is
# gone from the register and its id is still spoken for.
used = set(re.findall(r"^- \[[ xX/!]\] +\*{0,2}([^\s—*]+)", text, re.M))
# Every INDEX*.md sibling, not a fixed list of two. rocky keeps INDEX-done.md
# besides INDEX.completed.md and INDEX.pending.md, and an id this script cannot
# see is an id it will hand out twice.
import glob
for side in glob.glob(os.path.join(os.path.dirname(reg), "INDEX*.md")):
    if os.path.abspath(side) == os.path.abspath(reg):
        continue
    body = open(side, encoding="utf-8", errors="replace").read()
    used |= set(re.findall(r"^## +(\S+)", body, re.M))
    used |= set(re.findall(r"^- \[[ xX/!]\] +\*{0,2}([^\s—*]+)", body, re.M))

out = []
if mode == "numeric":
    # APPEND, not fill-the-lowest-gap. .claude/rules/spec-register.md: "Append new
    # specs to the end unless renumbering is justified." The first draft returned
    # the lowest free id and offered rocky "001" — a project whose live rows run
    # 404..587, because its earlier ids sit in an archive. Even where a low id is
    # genuinely free, handing it out on a mature register reads as a renumber
    # nobody decided. max+1 also cannot collide with an archive this script failed
    # to read, which the lowest-gap answer very much can.
    nums = [int(u) for u in used if u.isdigit()]
    width = max((len(u) for u in used if u.isdigit()), default=3)
    n = (max(nums) + 1) if nums else 1
    while len(out) < count and n < 10000:
        cand = f"{n:0{width}d}"
        if cand not in used:
            out.append(cand)
        n += 1
else:
    # Same append rule for a letter series: agentcrm is at S20, so the next is
    # S21 even if some earlier S-row was retired.
    snums = [int(m.group(1)) for u in used
             for m in [re.fullmatch(rf"{re.escape(series)}(\d+)", u)] if m]
    n = (max(snums) + 1) if snums else 1
    while len(out) < count and n < 10000:
        cand = f"{series}{n}"
        if cand not in used:
            out.append(cand)
        n += 1

if len(out) < count:
    print(f"next-register-id.sh: could not find {count} free id(s)", file=sys.stderr)
    sys.exit(2)
print("\n".join(out))
PY
