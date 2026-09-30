#!/bin/bash
# hook-verdict.sh — read a PreToolUse hook's answer the way Claude Code reads it.
#
#   . scripts/hook-verdict.sh
#   hook_verdict "$OUT"     # deny | ask | allow | dropped | none | invalid
#
# Spec 029. A guard test that reads `.hookSpecificOutput.permissionDecision` and
# nothing else accepts a payload the CLI throws away: without
# `hookEventName: "PreToolUse"` the whole hookSpecificOutput is dropped, and the
# edit goes through. That is how rocky's checkpoint H13 fed five guards their
# payloads, saw five denies, watched the live Edit pass, and blamed the
# permission mode. Proven 2026-09-29 under bypassPermissions: the bare shape
# passes, the discriminated shape blocks. Every guard test decodes through this
# rule so a guard that loses the field goes red, not green.
#
#   deny/ask/allow  well-formed PreToolUse decision
#   dropped         hookSpecificOutput present, hookEventName is not PreToolUse
#   none            empty output, or a well-formed object with no decision
#   invalid         output that is not JSON

hook_verdict() {
  local out="$1"
  # A glob, not ${out//[[:space:]]/}: bash 3.2's pattern substitution never finished on a 40 KB
  # deny reason (row 047, found by a mutant that let an over-long pattern through).
  case "$out" in *[![:space:]]*) ;; *) echo none; return 0 ;; esac
  local v
  v=$(printf '%s' "$out" | jq -r '
    if (type != "object") then "invalid"
    elif (.hookSpecificOutput == null) then "none"
    elif (.hookSpecificOutput.hookEventName != "PreToolUse") then "dropped"
    else (.hookSpecificOutput.permissionDecision // "none")
    end' 2>/dev/null) || v=invalid
  case "$v" in *"
"*) v=invalid ;; esac   # more than one JSON value: the CLI would not read it either
  echo "$v"
}
