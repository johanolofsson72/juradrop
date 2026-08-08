#!/bin/bash
# Reclaim abandoned agent worktrees — WITHOUT eating the memory they hold.
#
# Agent worktrees (.claude/worktrees/agent-*, created by `isolation: worktree`)
# are meant to be disposable, but two things accumulate in them:
#
#   1. Disk. They are full checkouts. Eight of them in one repo is gigabytes.
#   2. Agent memory. A subagent running inside a worktree writes to that
#      worktree's .claude/agent-memory/, and nothing ever merges it back. In
#      originalilluminati the main repo had ZERO memory files while seven
#      throwaway directories held sixteen — including two OPEN security findings.
#      Deleting worktrees to reclaim disk destroys exactly the knowledge the
#      agents were run to produce.
#
# So this salvages first and deletes second, and it only deletes what is provably
# safe: a worktree whose branch is fully merged into HEAD and which has no
# modified TRACKED files. Anything else is reported and left alone — an agent may
# still be working in it.
#
# Usage:
#   prune-agent-worktrees.sh [--dry-run] [--repo <path>]
#     --dry-run   report what would be salvaged/removed, change nothing
#     --repo      operate on this repo (default: cwd's repo root)
#
# Exit codes: 0 = done (possibly nothing to do), 1 = something was left behind
# for a human to look at, 2 = usage error.
#
# bash 3.2-safe, cross-platform.

set -u

DRY=0
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --repo)    shift; REPO="${1:-}" ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$REPO" ] || REPO=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$REPO" ] && [ -d "$REPO/.git" ] || { echo "not a git repository: ${REPO:-$PWD}" >&2; exit 2; }
cd "$REPO" || exit 2

NAME=$(basename "$REPO")
ls -d .claude/worktrees/agent-* >/dev/null 2>&1 || { echo "$NAME: no agent worktrees"; exit 0; }

SALVAGED=0; REMOVED=0; KEPT=0

# ------------------------------------------------------------------- salvage
# Copy every memory file that exists ONLY inside a worktree into the main repo.
# Never overwrite: the main copy, if present, is the authority.
for f in $(find .claude/worktrees/*/.claude/agent-memory -type f 2>/dev/null); do
  rel=${f#*/.claude/agent-memory/}
  case "$rel" in */MEMORY.md|MEMORY.md) continue ;; esac   # indexes merged below
  dest=".claude/agent-memory/$rel"

  # Absent from the main repo → straight copy.
  if [ ! -f "$dest" ]; then
    [ "$DRY" -eq 0 ] && { mkdir -p "$(dirname "$dest")" && cp "$f" "$dest"; }
    SALVAGED=$((SALVAGED + 1)); continue
  fi

  # Present and identical → nothing to do.
  cmp -s "$f" "$dest" && continue

  # Present but DIFFERENT: the worktree holds edits that exist nowhere else
  # (an agent updated a tracked memory file and never committed it). Overwriting
  # the main copy could drop what is already there, so keep both and let a human
  # reconcile — losing either side silently is the failure this script exists to
  # prevent. The suffix names the worktree the version came from.
  agent=$(printf '%s' "$f" | sed -n 's#.*/worktrees/\([^/]*\)/.*#\1#p')
  base=${dest%.*}; ext=${dest##*.}
  [ "$base" = "$dest" ] && side="$dest.from-$agent" || side="$base.from-$agent.$ext"
  if [ ! -f "$side" ]; then
    [ "$DRY" -eq 0 ] && { mkdir -p "$(dirname "$side")" && cp "$f" "$side"; }
    SALVAGED=$((SALVAGED + 1))
    DIVERGED="${DIVERGED:-}$(printf '\n    %s (kept as %s)' "$rel" "$(basename "$side")")"
  fi
done

# Merge the per-worktree MEMORY.md index fragments into the main index, keeping
# every unique bullet. Each worktree only ever wrote its own run's line.
for idx in $(find .claude/worktrees/*/.claude/agent-memory -name MEMORY.md 2>/dev/null); do
  rel=${idx#*/.claude/agent-memory/}
  dest=".claude/agent-memory/$rel"
  [ "$DRY" -eq 1 ] && continue
  mkdir -p "$(dirname "$dest")"
  TMP="$dest.merge.$$"
  { [ -f "$dest" ] && cat "$dest"; cat "$idx"; } 2>/dev/null | grep '^- ' | sort -u > "$TMP.bullets"
  {
    if [ -f "$dest" ]; then grep -v '^- ' "$dest" 2>/dev/null; else
      printf '# MEMORY.md\n\nConsolidated from agent worktrees by scripts/prune-agent-worktrees.sh.\n\n'
    fi
    cat "$TMP.bullets"
  } > "$TMP" 2>/dev/null && mv "$TMP" "$dest"
  rm -f "$TMP" "$TMP.bullets" 2>/dev/null
done

# ------------------------------------------------------ remove what is safe
for d in .claude/worktrees/agent-*; do
  [ -d "$d" ] || continue
  BR=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)
  UNIQ=$(git rev-list --count "$BR" --not HEAD 2>/dev/null || echo 0)
  case "$UNIQ" in (''|*[!0-9]*) UNIQ=0 ;; esac

  # Modified tracked files block removal — EXCEPT under .claude/agent-memory/,
  # which the salvage above has already preserved (identical, copied, or kept
  # side-by-side). Memory edits are the normal end state of an agent run; if they
  # counted as "still working", these worktrees could never be reclaimed at all.
  OTHER=$(git -C "$d" status --porcelain 2>/dev/null | grep -vE '^\?\?' \
          | awk '{print $2}' | grep -v '^\.claude/agent-memory/' | head -3)
  if [ -n "$OTHER" ]; then
    echo "  KEEP $d — modified outside agent-memory: $(printf '%s' "$OTHER" | tr '\n' ' ')"
    KEPT=$((KEPT + 1)); continue
  fi
  if [ "$UNIQ" -gt 0 ]; then
    echo "  KEEP $d — branch $BR has $UNIQ commit(s) not in HEAD"
    KEPT=$((KEPT + 1)); continue
  fi

  # A locked worktree means an agent claimed it. The lock reason carries the pid;
  # if that process is gone the lock is a crash leftover and the worktree is just
  # abandoned. If it is alive, an agent is working in there right now — leave it.
  LOCKREASON=$(git worktree list --porcelain 2>/dev/null | awk -v w="$PWD/$d" '
    $1=="worktree"{cur=$2} $1=="locked"{if(cur==w){$1="";print;exit}}')
  if [ -n "$LOCKREASON" ]; then
    LOCKPID=$(printf '%s' "$LOCKREASON" | sed -n 's/.*pid \([0-9][0-9]*\).*/\1/p')
    if [ -n "$LOCKPID" ] && kill -0 "$LOCKPID" 2>/dev/null; then
      echo "  KEEP $d — locked by a RUNNING agent (pid $LOCKPID)"
      KEPT=$((KEPT + 1)); continue
    fi
    echo "  (stale lock on $d — pid ${LOCKPID:-?} is gone; unlocking)"
    [ "$DRY" -eq 0 ] && git worktree unlock "$d" >/dev/null 2>&1
  fi

  if [ "$DRY" -eq 0 ]; then
    git worktree remove --force "$d" >/dev/null 2>&1 || { echo "  KEEP $d — worktree remove failed"; KEPT=$((KEPT+1)); continue; }
    [ -n "$BR" ] && git branch -d "$BR" >/dev/null 2>&1
  fi
  REMOVED=$((REMOVED + 1))
done

[ "$DRY" -eq 0 ] && git worktree prune 2>/dev/null

printf '%s: %s memory file(s) salvaged · %s worktree(s) %s · %s kept\n' \
  "$NAME" "$SALVAGED" "$REMOVED" "$([ "$DRY" -eq 1 ] && echo 'would be removed' || echo removed)" "$KEPT"

[ "$SALVAGED" -gt 0 ] && [ "$DRY" -eq 0 ] && \
  echo "  → review + commit .claude/agent-memory/ — it was only in the worktrees until now"

[ -n "${DIVERGED:-}" ] && printf '  → %s\n%s\n' \
  "these memory files differed from the committed copy; BOTH versions kept, reconcile by hand:" "$DIVERGED"

[ "$KEPT" -gt 0 ] && exit 1
exit 0
