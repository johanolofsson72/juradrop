#!/bin/bash
# max-id-in-refs.sh — the highest id any lane has written, not just this checkout.
#
# WHY THIS EXISTS. Two allocators counted the LOCAL file and nothing else, and both collided the
# moment a second developer worked in parallel:
#
#   finding.sh (row 054)   numbered by counting ledger rows. agentcrm, 2026-09-17: origin/main held
#                          F141–F143 and the branch spec/044-named-refusals held three DIFFERENT
#                          F141–F143. merge=union on FINDINGS.md kept both sides without a conflict
#                          marker, so the collision was silent. A deleted line also freed its number.
#   scenario ids (060)     had no allocator at all. agentcrm measured 47 colliding SC-ids on
#                          2026-09-21; 26 of them were specs 052 and 055 both taking ids 1625..1650.
#
# The cure for both is the same: read the MAXIMUM id, never a count, and read it everywhere this
# clone can see — the working tree (uncommitted and untracked edits included) AND every local and
# remote-tracking branch. The other lane's pushed spec branch is a remote-tracking ref, so its ids
# are seen before its merge instead of at it.
#
# WHAT IT CANNOT SEE: ids the other lane has written but not pushed, and anything newer than this
# clone's last fetch. No local scan can; the residual is a push-early habit, and the stderr line
# says how old the fetch is so the reader can judge it.
#
# Usage:
#   bash scripts/max-id-in-refs.sh --regex '<ERE ending in the digits>' [--dir D] -- <pathspec>...
#
# Prints the highest id's digits exactly as written (padding kept, so a caller can keep the width),
# or nothing when no id exists anywhere. The digits are the trailing run of each match.
#
# Exit: 0 ok (with or without a result) · 2 usage
set -uo pipefail
export LC_ALL=C

RE=""; DIR="."
while [ $# -gt 0 ]; do
  case "$1" in
    --regex) RE="${2:-}"; shift 2 || { echo "max-id-in-refs.sh: --regex needs a pattern" >&2; exit 2; } ;;
    --dir)   DIR="${2:-.}"; shift 2 || { echo "max-id-in-refs.sh: --dir needs a path" >&2; exit 2; } ;;
    --)      shift; break ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "max-id-in-refs.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$RE" ] || { echo "max-id-in-refs.sh: --regex is required" >&2; exit 2; }
[ $# -gt 0 ] || { echo "max-id-in-refs.sh: name at least one pathspec after --" >&2; exit 2; }

hits() {
  if ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null); then
    # Working tree first: an id minted a minute ago and not yet committed is the likeliest to be
    # handed out twice. --untracked, because a new ledger or map file is untracked until its commit.
    git -C "$ROOT" grep --untracked -ohE "$RE" -- "$@" 2>/dev/null
    local refs n=0 age=""
    refs=$(git -C "$ROOT" for-each-ref --format='%(refname)' refs/heads refs/remotes | grep -v '/HEAD$')
    if [ -n "$refs" ]; then
      n=$(printf '%s\n' "$refs" | grep -c .)
      # One call over every tree: git grep takes many revisions and -h drops the rev:path prefix.
      # shellcheck disable=SC2086
      git -C "$ROOT" grep -ohE "$RE" $refs -- "$@" 2>/dev/null
    fi
    local fh; fh="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)/FETCH_HEAD"
    case "$fh" in /*) ;; *) fh="$ROOT/$fh" ;; esac
    [ -f "$fh" ] && age=" · last fetch $(( ( $(date +%s) - $(stat -c %Y "$fh" 2>/dev/null || stat -f %m "$fh") ) / 60 )) min ago"
    echo "max-id-in-refs: working tree + $n ref(s)${age:- · never fetched}" >&2
  else
    # Not a repository (a test fixture, a fresh scaffold): the files are all there is.
    ( cd "$DIR" && for p in "$@"; do for f in $p; do [ -f "$f" ] && grep -ohE "$RE" "$f"; done; done ) 2>/dev/null
    echo "max-id-in-refs: working tree only (not a git repository)" >&2
  fi
}

hits "$@" | sed -E 's/.*[^0-9]//' | grep -E '^[0-9]+$' |
  awk '{ n = $0 + 0; if (!seen || n > best) { best = n; raw = $0; seen = 1 } } END { if (seen) print raw }'
exit 0
