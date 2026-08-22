#!/bin/bash
# Keep .specify/feature.json — spec-kit's feature-directory cache — in agreement
# with the register. Spec 007q.
#
# WHY THIS FILE EXISTS
# --------------------
# Spec 007m demoted .specify/feature.json from a fourth independent opinion about
# "which spec is active?" to a CACHE of the register's answer. It did not give the
# refresh a home. The refresh lived in two places, and both were side effects:
#
#   1. spec-register-orientation-hook.sh — inside `if [ "$PROG" -gt 0 ]`, a block
#      that exists to print the run-log tail for an IN-PROGRESS row. At the start
#      of a spec the row is still "- [ ]", so PROG=0 and the refresh never ran.
#      The register row for 007q called the exposure "narrow (session start
#      re-syncs)". There was no session-start re-sync.
#   2. spec-run-log-hook.sh — at the tail of HOOK mode, reachable only with jq
#      installed, a PostToolUse Write/Edit payload, and a basename in
#      {spec.md, interview.md, *.allium, plan.md, tasks.md}. A spec directory made
#      by a heredoc, a script, an editor outside the session, or a git checkout
#      refreshed nothing.
#
# A refresh that is a side effect of a logging hook is a refresh nobody audits,
# which is why both holes sat in plain sight inside the spec that created them.
# This file is that refresh, named, with one job.
#
# WHAT IT GUARANTEES — and what it deliberately does not
# -----------------------------------------------------
# NOT freshness. No set of triggers catches every writer, and a design that needs
# them all fails silently the first time it misses one. The guarantee is the one
# in spec_active.py:
#
#     feature.json names the active spec, or it names nothing. Never a DIFFERENT
#     spec.
#
# So a missed trigger costs a loud "Feature directory not found" from spec-kit's
# own common.sh, instead of /speckit-plan, -tasks, -analyze and -implement each
# silently reading the previous spec's artifacts and reporting themselves
# satisfied. Fail closed, the way spec 007m made the two PreToolUse guards fail.
#
# THE GATE
# --------
# SessionStart: always sync. PostToolUse: sync only when the payload plausibly
# touched the register or a spec directory, decided by a raw string match on the
# UNPARSED stdin — no jq, no python3, no JSON parsing on the reject path, because
# this is wired to Bash and would otherwise pay ~50 ms of interpreter start on
# every shell command in the session (NFR-007q-02).
#
# The match is deliberately a SUPERSET: a Write to specs/SCENARIOS.md, or a grep
# whose arguments merely mention specs/, syncs needlessly. That costs one
# idempotent resolve which writes nothing. Being wrong toward an extra no-op is
# the cheap direction; the expensive direction is the one this spec is fixing.
#
# Git is matched by SUB-COMMAND, not by the bare word "git": a checkout or pull
# can rewrite the register and every spec directory at once while naming no path,
# but `git status` and `git log` are the two most frequent commands in this repo
# and must not pay for a sync.
#
# KNOWN RESIDUAL GAP, stated rather than left to be discovered: a spec directory
# created by a command naming neither specs/ nor a git sub-command (`cd specs &&
# mkdir 007z-foo`) still misses. The clearing behaviour above is what makes that
# survivable — stale-but-loud, never wrong-and-confident.
#
# Never blocks, never prints, always exits 0. Disable with SYNCFJ_DISABLE=1.

set -u

[ "${SYNCFJ_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)

# A PostToolUse payload carries tool_name/tool_input; a SessionStart one does not.
# Only the former is gated — session start is the guaranteed correctness point and
# must run unconditionally, which is precisely what the PROG>0 gate broke.
case "$INPUT" in
  *'"tool_input"'*|*'"tool_name"'*)
    case "$INPUT" in
      *specs/*|*INDEX.md*) ;;
      *'git checkout'*|*'git switch'*|*'git pull'*|*'git merge'*|*'git rebase'*|*'git reset'*|*'git stash'*|*'git clone'*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

# Walk up from $PWD to the .git boundary — the same walk the orientation hook
# uses, i.e. the one resolver that was right the whole time. CLAUDE_PROJECT_DIR is
# only a fallback: preferring it would make this hook answer about a different
# repo than the one the tool call actually touched.
ROOT=""
DIR="$PWD"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -f "$DIR/specs/INDEX.md" ]; then ROOT="$DIR"; break; fi
  if [ -d "$DIR/.git" ]; then break; fi
  DIR=$(dirname "$DIR")
done
if [ -z "$ROOT" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "${CLAUDE_PROJECT_DIR}/specs/INDEX.md" ]; then
  ROOT="$CLAUDE_PROJECT_DIR"
fi

# No register (template/scratch repo) — silent, like every other hook here.
[ -n "$ROOT" ] || exit 0

# Code comes from beside THIS FILE; data comes from the project (template spec
# H6s2). Looking the resolver up under "$ROOT/scripts/" would mean this hook goes
# hunting for its own sibling inside the directory of the data it was asked to
# read — and wherever that root is not also a checkout of this template (a test
# fixture, a project whose autosync was cut short before the .py pass, a bare
# directory) the lookup finds nothing and the refresh is skipped IN SILENCE.
#
# That is this spec's own defect arriving by a third route: not the id parser
# (007m), not the trigger set (007q above), but the lookup path. H6s2 found it in
# the orientation and run-log hooks and its note says exactly what it costs:
# "--sync-feature-json did not run, leaving spec-kit's feature.json naming the
# PREVIOUS spec". Writing this hook with the same bug it was created to fix would
# have been a fine joke and a bad hook.
_SYNCFJ_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
RESOLVER="$_SYNCFJ_SCRIPT_DIR/resolve-active-spec.sh"
[ -f "$RESOLVER" ] || exit 0

# The resolver owns the decision AND the write. This hook never parses the
# register: a second parser is how three call sites came to disagree (007m).
bash "$RESOLVER" --root "$ROOT" --sync-feature-json >/dev/null 2>&1 || true
exit 0
