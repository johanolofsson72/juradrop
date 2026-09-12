#!/bin/bash
# install-lane-merge-drivers.sh — stop two lanes conflicting on the files that
# are append-only by design.
#
# WHY THIS EXISTS. Measured on agentcrm 2026-08-20..09-02, the files both
# developers touched most were not source files. They were the coordination
# files:
#
#     specs/INDEX.md          117 touches   (johan 70, david 47)
#     specs/INDEX.pending.md   50           (17 / 33)
#     specs/SCENARIOS.md       49           (30 / 19)
#     specs/PHASE-DEBT.md      25           (10 / 15)
#
# Only two source files made the top fifteen. So "we spend hours merging" is
# mostly two people appending to the same four markdown files and git treating
# every append at the same end as a conflict.
#
# These files are LISTS. Two lanes appending different rows is not a semantic
# conflict, it is two additions -- which is exactly what git's `union` merge is
# for. The project already accepted this shape once: scripts/merge-locale-json.py
# was written for the same problem in the i18n locale files.
#
# THE TRADE, STATED PLAINLY. `union` never reports a conflict; it keeps both
# sides. That is right for an append and wrong for two lanes editing the SAME
# row -- there you would get the row twice instead of a conflict marker. Two
# things bound that risk:
#   - .claude/rules/spec-register.md already forbids touching the other lane's
#     row, so same-row edits are a rule violation before they are a merge bug.
#   - scripts/validate-register-ids.sh FAILS on a duplicated id, so the doubled
#     row is caught at the next gate rather than shipped. Run it after a merge.
# A merge driver that silently doubles a row with no gate behind it would be a
# bad trade. With the gate, it is a good one.
#
# Usage:
#   bash scripts/install-lane-merge-drivers.sh           # install
#   bash scripts/install-lane-merge-drivers.sh --check   # report, change nothing
#   bash scripts/install-lane-merge-drivers.sh --remove

set -uo pipefail
export LC_ALL=C

MODE="install"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --remove) MODE="remove"; shift ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install-lane-merge-drivers.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "install-lane-merge-drivers.sh: not inside a git repository" >&2; exit 2; }
GA="$ROOT/.gitattributes"
BEGIN="# >>> claude lane merge drivers (scripts/install-lane-merge-drivers.sh)"
END="# <<< claude lane merge drivers"

BLOCK=$(cat <<'BLK'
# >>> claude lane merge drivers (scripts/install-lane-merge-drivers.sh)
# Append-only coordination files. Two lanes adding different entries is two
# additions, not a conflict -- `union` keeps both instead of stopping the merge.
# Backstop: scripts/validate-register-ids.sh fails on a duplicated id, so a row
# edited by both lanes surfaces at the next gate. Run it after every merge.
specs/INDEX.md           merge=union
specs/INDEX.pending.md   merge=union
specs/INDEX.completed.md merge=union
specs/INDEX.history.md   merge=union
specs/PHASE-DEBT.md      merge=union
specs/scenarios/*.md     merge=union
# NOT specs/SCENARIOS.md: under the single-file layout it carries Mermaid
# diagrams, where union would interleave two graphs into one unparseable block.
# A project whose map is this contended should split it per
# .claude/rules/scenarios.md -- then each lane owns its own feature file above.
# <<< claude lane merge drivers
BLK
)

has_block() { [ -f "$GA" ] && grep -qF "$BEGIN" "$GA"; }

if [ "$MODE" = "check" ]; then
  if has_block; then
    echo "lane merge drivers: installed in $GA"
    if [ -f "$ROOT/specs/SCENARIOS.md" ] && [ ! -d "$ROOT/specs/scenarios" ]; then
      sz=$(wc -c < "$ROOT/specs/SCENARIOS.md" | tr -d ' ')
      [ "$sz" -gt 25600 ] && echo "  note: specs/SCENARIOS.md is $((sz/1024)) KB and single-file — split it (.claude/rules/scenarios.md) so each lane owns a feature file"
    fi
    exit 0
  fi
  echo "lane merge drivers: NOT installed"; exit 1
fi

if [ "$MODE" = "remove" ]; then
  has_block || { echo "lane merge drivers: nothing to remove"; exit 0; }
  # sed range delete on the markers; the block is contiguous by construction.
  tmp=$(mktemp); sed "/^${BEGIN//\//\\/}\$/,/^${END//\//\\/}\$/d" "$GA" > "$tmp" && mv "$tmp" "$GA"
  echo "lane merge drivers: removed from $GA"; exit 0
fi

if has_block; then
  echo "lane merge drivers: already installed in $GA (no change)"
else
  [ -f "$GA" ] && printf '\n' >> "$GA"
  printf '%s\n' "$BLOCK" >> "$GA"
  echo "lane merge drivers: installed in $GA"
fi

# Quoted delimiter: the body contains backticks, and an unquoted heredoc runs them
# as command substitution -- which it did, printing "union: command not found"
# into the middle of a success message on the first real run.
cat <<'MSG'

  `union` is a built-in git merge strategy — nothing to register per clone, unlike
  a custom driver. Commit .gitattributes so both lanes get it.

  After every merge, run:  bash scripts/validate-register-ids.sh
  That is what catches a row union kept twice.
MSG

if [ -f "$ROOT/specs/SCENARIOS.md" ] && [ ! -d "$ROOT/specs/scenarios" ]; then
  sz=$(wc -c < "$ROOT/specs/SCENARIOS.md" | tr -d ' ')
  if [ "$sz" -gt 25600 ]; then
    echo "  NOTE: specs/SCENARIOS.md is $((sz/1024)) KB and still single-file. It is deliberately"
    echo "        NOT union-merged (Mermaid). Split it per .claude/rules/scenarios.md so each"
    echo "        lane owns its own feature file — that removes the contention structurally."
  fi
fi
