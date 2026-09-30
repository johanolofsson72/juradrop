#!/bin/bash
# probe-live-deny.sh — ask the installed Claude Code whether a PreToolUse deny holds.
#
#   bash scripts/probe-live-deny.sh            # acceptEdits + bypassPermissions
#   PROBE_MODEL=claude-haiku-4-5-20251001 PROBE_TIMEOUT=180 bash scripts/probe-live-deny.sh
#
# Spec 029. Every other test of the guards feeds a hook its stdin and reads the
# answer. That proves what the hook SAYS, not what the CLI DOES with it, and the
# gap between the two is where rocky's checkpoint H13 lost a week: five guards
# said deny, the live Edit went through, and the permission mode got the blame.
# The cause was a missing hookEventName (spec 046). This asks the CLI itself.
#
# Per permission mode, two arms in a throwaway git repo, one Edit each:
#   control  deny WITHOUT hookEventName — the CLI must discard it, so the edit lands.
#            If it does not land, the probe cannot tell a hook from a refusal and
#            proves nothing.
#   guard    deny WITH hookEventName — the edit must not land.
# `default` mode is not probed: headless -p refuses an unapproved Edit on its own,
# so the control arm could not land and the probe could not discriminate.
#
# Costs 4 model calls. Opt-in, never part of a default suite. Rerun after a CLI upgrade.
#
# Exit: 0 the deny holds in every mode · 1 a well-formed deny was NOT applied ·
#       2 claude CLI or jq not found, or a bad PROBE_* value ·
#       3 inconclusive (a control arm was blocked; a guard arm hung, failed, or never fired the hook;
#         no mode ran)

set -u
command -v claude >/dev/null 2>&1 || { echo "probe-live-deny: claude CLI not found on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe-live-deny: jq not found" >&2; exit 2; }

MODEL="${PROBE_MODEL:-claude-haiku-4-5-20251001}"
LIMIT="${PROBE_TIMEOUT:-180}"
MODES="${PROBE_MODES:-acceptEdits bypassPermissions}"
case "$LIMIT" in ''|*[!0-9]*) echo "probe-live-deny: PROBE_TIMEOUT must be whole seconds, got '$LIMIT'" >&2; exit 2 ;; esac
for m in $MODES; do
  case "$m" in acceptEdits|bypassPermissions) ;; *) echo "probe-live-deny: unsupported mode '$m' (acceptEdits, bypassPermissions)" >&2; exit 2 ;; esac
done
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout $LIMIT"
[ -z "$TO" ] && command -v gtimeout >/dev/null 2>&1 && TO="gtimeout $LIMIT"
[ -z "$TO" ] && { echo "probe-live-deny: no timeout/gtimeout on PATH, so a hung arm could not be cut off (macOS: brew install coreutils)" >&2; exit 3; }

WORK=$(mktemp -d) || exit 3
trap 'rm -rf "$WORK"' EXIT
# An interrupted arm must not be read as "held": leave, and let the EXIT trap clean up.
trap 'exit 130' INT TERM

# $1 arm (control|guard) · $2 mode → prints landed | held | hung | silent | failed
#   held    the edit did not land, the hook fired, and the CLI exited cleanly
#   silent  the hook never fired (the model never called Edit, or the CLI died first)
#   failed  the CLI exited non-zero (auth, rate limit, crash) — nothing is proven
run_arm() {
  local arm="$1" mode="$2" dir="$WORK/$1-$2" rc
  mkdir -p "$dir" && git -C "$dir" init -q
  printf 'export const a = 1;\n' > "$dir/probe.ts"
  local payload
  if [ "$arm" = guard ]; then
    payload='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"probe-live-deny: guard arm"}}'
  else
    payload='{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"probe-live-deny: control arm"}}'
  fi
  # The hook leaves a marker, so an arm where it never ran cannot pass as one it blocked.
  jq -n --arg c "touch '$dir/fired'; echo '$payload'" \
    '{hooks:{PreToolUse:[{matcher:"Edit|Write|MultiEdit",hooks:[{type:"command",command:$c}]}]}}' \
    > "$dir/settings.json"
  # Confined: Edit and Read only (no shell to fall back to after a deny), no user or project
  # settings, hooks, plugins or MCP servers — only the probe hook from --settings.
  ( cd "$dir" && $TO claude -p --model "$MODEL" --permission-mode "$mode" \
      --tools Edit Read --setting-sources "" --strict-mcp-config \
      --settings "$dir/settings.json" \
      "Use the Edit tool once to change '= 1' to '= 2' in probe.ts. Do not use Bash. Do not retry. Reply DONE or BLOCKED." \
      </dev/null >"$dir/out.txt" 2>&1 )
  rc=$?
  if grep -q '= 2;' "$dir/probe.ts"; then echo landed
  elif [ "$rc" -eq 124 ]; then echo hung
  elif [ ! -e "$dir/fired" ]; then echo silent
  elif [ "$rc" -ne 0 ]; then echo failed
  else echo held; fi
}

echo "probe-live-deny: $(claude --version 2>/dev/null | head -1), model $MODEL"
printf '%-18s %-9s %-9s %s\n' mode control guard verdict
BROKEN=0; UNSURE=0; RAN=0
for mode in $MODES; do
  RAN=$((RAN+1))
  echo "  … $mode" >&2
  C=$(run_arm control "$mode"); G=$(run_arm guard "$mode")
  if [ "$G" = landed ]; then V="BROKEN — a well-formed deny was not applied"; BROKEN=1
  elif [ "$C" != landed ]; then V="INCONCLUSIVE — control $C, the probe cannot discriminate"; UNSURE=1
  elif [ "$G" != held ]; then V="INCONCLUSIVE — guard arm $G"; UNSURE=1
  else V="holds"; fi
  printf '%-18s %-9s %-9s %s\n' "$mode" "$C" "$G" "$V"
done
# 1 outranks 3: a deny that failed to apply is a finding even if another mode was inconclusive.
[ "$BROKEN" -eq 1 ] && exit 1
[ "$UNSURE" -eq 1 ] && exit 3
[ "$RAN" -eq 0 ] && { echo "probe-live-deny: no mode was probed" >&2; exit 3; }
exit 0
