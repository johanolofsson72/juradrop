#!/bin/bash
# core-gates.sh — which of the scripts the sync delivers are gates, and which only look like one.
#
# A project that runs its gates through a registry (consultpilot's run-gates.sh: GATES, EXCLUDED,
# and a drift check over scripts/(test|validate|verify|check)-*.sh) used to learn about a new CORE
# gate from its own drift check, and then register it by hand. On 2026-09-29 fourteen CORE gates sat
# in consultpilot registered nowhere, and the runner printed "this report is incomplete" over every
# verdict it gave (row 014, consultpilot H7av). The template is the only party that knows whether
# its own test-scenario-map-fixtures.sh is a library or a gate, so this file says it once, and a
# runner asks instead of working it out again.
#
# Gate by default. A gate-shaped name added to CORE_SCRIPTS is a gate the moment it ships; nothing
# else has to be edited. Only the opposite takes a decision, and the decision is a line in NON_GATES
# with its reason in words. consultpilot's H7be argued against the sync REFUSING an unregistered gate
# (a second oracle, in CORE, blind to the project's registry). This is not that: it refuses nothing,
# it is the CORE half of the registry, shipped in the same sync as the files it describes.
#
# Usage:
#   bash scripts/core-gates.sh              # every CORE gate, one basename per line, sorted
#   bash scripts/core-gates.sh --non-gates  # name|reason for each gate-shaped script that is not one
#
# Exit: 0 answered · 2 cannot answer — template-autosync.sh missing or its query failed, no CORE
#       gate at all, or a malformed NON_GATES line. A consumer must never read 2 as an empty list:
#       an empty registry reports every gate passed about nothing.
#
# Scenario ids: none here; scripts/test-core-gates.sh is the proof.
set -uo pipefail
export LC_ALL=C
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The discovery pattern consultpilot's runner uses. One definition, so two runners cannot disagree
# about what a gate looks like.
GATE_SHAPE='^(test|validate|verify|check)-.*\.sh$'

# name|reason. Gate-shaped scripts that must NOT be run as a gate, CORE and template-only alike: a
# project can hold a stale copy of a template-only file from an old prose sync, and a runner that
# globs the shape would run it (F004: test-coverage-hook.sh waits on stdin for hook JSON and hangs).
# Every reason rests on running the file or reading its header (spec 014, run-log).
NON_GATES='test-scenario-map-fixtures.sh|a sourced fixture library: it defines makers and runs nothing, so as a gate it exits 0 without asserting anything. Its three consumers, test-scenario-map-{layouts,canary,reminder}.sh, are gates and are where a break in it shows
validate-scenario-traceability.sh|a coverage report whose uncovered direction is a per-feature backlog, red for as long as a roadmap has unbuilt rows. project-maintenance.sh runs it and reports uncovered as a note, dangling as a finding. Its self-test, test-validate-scenario-traceability.sh, is a gate
test-coverage-hook.sh|template-only. A PostToolUse hook that reads hook JSON on stdin; run with no input it waits forever (F004)
verify-local-llm-hooks.sh|template-only. Needs the template settings.json as an argument and exits 2 without one
test-install-global-skills.sh|template-only. Tests install-global-skills.sh, which ships to no project
test-on-linux.sh|template-only. Runs the template suite in a Linux container; needs Docker and the template tree'

die() { echo "core-gates.sh: $*" >&2; exit 2; }

MODE=gates
case "${1:-}" in
  "") ;;
  --non-gates) MODE=non-gates ;;
  -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown argument '$1'" ;;
esac

# Validate the table before answering from it. A malformed line would otherwise drop silently out of
# the exclusions, and the runner would run a library or hang on a hook.
TABLE_NAMES=$(printf '%s\n' "$NON_GATES" | awk -v shape="$GATE_SHAPE" '
  /^[[:space:]]*$/ { next }
  {
    i = index($0, "|")
    if (i == 0) { print "no | in line: " $0 > "/dev/stderr"; bad = 1; next }
    name = substr($0, 1, i - 1); reason = substr($0, i + 1)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", reason)
    if (reason == "")        { print "empty reason for " name > "/dev/stderr"; bad = 1 }
    if (name !~ shape)       { print name " is not gate-shaped, so no runner would find it" > "/dev/stderr"; bad = 1 }
    if (seen[name]++)        { print name " is listed twice" > "/dev/stderr"; bad = 1 }
    print name
  }
  END { exit bad }') || die "the NON_GATES table is malformed (above)"

if [ "$MODE" = non-gates ]; then
  printf '%s\n' "$NON_GATES" | grep -v '^[[:space:]]*$' | sort
  exit 0
fi

[ -f "$SD/template-autosync.sh" ] || die "scripts/template-autosync.sh is missing, so CORE cannot be listed"
CORE=$(bash "$SD/template-autosync.sh" --list-core-scripts) || die "template-autosync.sh --list-core-scripts failed"
GATES=$(printf '%s\n' "$CORE" | grep -E "$GATE_SHAPE" | grep -vxF -f <(printf '%s\n' "$TABLE_NAMES") | sort -u)
[ -n "$GATES" ] || die "no CORE gate at all; an empty list here would read as every gate passing"
printf '%s\n' "$GATES"
