#!/usr/bin/env bash
# PreToolUse guard on Bash: a Stryker.NET run that would measure nothing is refused before it starts
# (row 047), and a Stryker run of either kind first sweeps the StrykerJS sandboxes an abandoned run left
# in the tree (row 053).
#
# Two shapes, both measured on ighweld-2026, both invisible in Stryker's output:
#
#   * A mutate pattern that selects nothing, or not what it says. `'**/X.cs{845-1080}'` matches no file
#     (F184); `{98..120}` is a CHARACTER span, not lines (F197); and a span did not shrink the run
#     (F185). Stryker still prints a score.
#   * Stryker beside a build. A `dotnet build` or `dotnet test` in the same project overwrites the
#     mutated assembly and the run scores about 0% with no warning (F069).
#
# The rules live in scripts/stryker_guard.py, which section 5 of project-maintenance.sh asks as well.
# This file only decides whether to ask, and turns the answer into the PreToolUse deny shape.
#
# FAILS OPEN on everything it cannot read: no python3, no jq, input that is not JSON, no `ps`, a process
# whose working directory it cannot see. A guard that locked `dotnet` up would be unwired within a day,
# and its protection with it. Declared bound: on Windows Git Bash `ps` lists MSYS processes only, so a
# native dotnet.exe is invisible and only the pattern half works there.
#
# Overrides, both named in the deny text: `STRYKER_GUARD=off` (in the command or the environment) turns
# the guard off; `STRYKER_SPANS_ARE_CHARACTERS=1` in the command accepts a well-formed span.
#
# The sweep is the one side effect. It removes a temp dir only when it is plainly an abandoned sandbox
# and no Stryker run is live; an in-place `backup-*` is never removed and denies the run instead. What
# it removed or kept reaches the model as additionalContext. The rules are in stryker_guard.py.
#
# Exit: always 0. A deny is permissionDecision JSON on stdout, with hookEventName (spec 029).

[ "${STRYKER_GUARD:-}" = "off" ] && { cat >/dev/null; exit 0; }
command -v jq >/dev/null 2>&1 || { cat >/dev/null; exit 0; }
command -v python3 >/dev/null 2>&1 || { cat >/dev/null; exit 0; }

IFS= read -r -d '' INPUT || true
# Cheap exit before any fork, on the raw JSON: the words survive JSON encoding, so this only ever lets
# more through than the exact check below. It runs on every Bash call Claude makes.
case "$INPUT" in
  *dotnet*|*stryker*|*run-mutation-gate*) ;;
  *) exit 0 ;;
esac

# One jq for both fields: the cwd on the first line, the command (which may span lines) after it.
FIELDS=$(printf '%s' "$INPUT" | jq -r '(.cwd // "" | gsub("\n"; " ")), (.tool_input.command // "")' 2>/dev/null) || exit 0
CWD=${FIELDS%%$'\n'*}
CMD=${FIELDS#*$'\n'}
[ "$CMD" != "$FIELDS" ] && [ -n "$CMD" ] || exit 0
case "$CMD" in
  *dotnet*|*stryker*|*run-mutation-gate*) ;;
  *) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$CWD}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || exit 0

case "${BASH_SOURCE[0]}" in */*) HELPER="${BASH_SOURCE[0]%/*}/stryker_guard.py" ;; *) HELPER="./stryker_guard.py" ;; esac
[ -f "$HELPER" ] || exit 0

# The command goes through the environment, never argv: the helper reads the process table, and a
# `dotnet test` in its own arguments would be found running in the project.
VERDICT=$(STRYKER_GUARD_CMD="$CMD" python3 "$HELPER" command "$ROOT" 2>/dev/null) || exit 0
case "$VERDICT" in
  deny"	"*) ;;
  allow"	"*)
    jq -n --arg c "${VERDICT#allow	}" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}'
    exit 0 ;;
  *) exit 0 ;;
esac

REASON="Denied: ${VERDICT#deny	}"
jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
