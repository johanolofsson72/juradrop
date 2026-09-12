#!/bin/bash
# hook-notice.sh — the one place that decides WHICH CHANNEL a hook speaks on.
#
# Source it; do not execute it:
#     . "$(dirname "${BASH_SOURCE[0]}")/hook-notice.sh"
#
# WHY THIS FILE EXISTS
# -------------------------------------------------------------------------
# Claude Code gives a hook three ways to say something, and they are not
# interchangeable. Quoting the reference shipped inside the CLI binary
# (2.1.269, `strings` on the bundle — the published docs are thinner):
#
#   "systemMessage"    - "Warning shown to user in UI"
#                        "Display a message to the user (all hooks)"
#   hookSpecificOutput.additionalContext
#                      - "Context injected back to model"
#                        (the doc's own example carries hookEventName PostToolUse)
#   plain stdout, exit 0, SessionStart
#                      - "stdout shown to Claude"
#
# and, for a top-level additionalContext, the CLI answers:
#
#   "Did you mean hookSpecificOutput.additionalContext (with a hookEventName)?"
#
# Before this file every advisory hook in the template used `systemMessage` to
# talk to THE MODEL. The model did receive it — and so did the developer, as a
# red warning per line, on every edit. That is the wall of "PostToolUse:Edit
# says:" entries: a reminder written for the model, delivered to the person.
#
# The mirror-image defect sat in 42 other hooks, which emitted a TOP-LEVEL
# `additionalContext` and therefore said nothing to anybody. Four of those were
# wired as UserPromptSubmit hooks — the whole first enforcement layer of
# `.claude/rules/feature-pipeline.md` had been silent since it was written.
#
# Both are the same mistake: picking the channel at each call site. So the
# channel is picked here, once, and the call sites say who they are talking to.
#
# THE RULE
#   Talking to the model  -> notice_model / notice_once / notice_session
#   Talking to the person -> notice_user, and it must fit on one line
#
# A hook that wants both says both. What it must not do is use the developer's
# channel because it is the one that was easiest to type.

# --- helper: JSON-encode a string without assuming jq is installed ----------
# The template lands on machines with nothing provisioned yet, which is why
# template-sync-verify-hook.sh already hand-rolls its escaping. Same trade here.
_hn_json_escape() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs .
  else
    printf '"%s"' "$(printf '%s' "$1" \
      | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r//g' -e 's/$/\\n/' \
      | tr -d '\n' | sed -e 's/\\n$//')"
  fi
}

# notice_model <hookEventName> <text>
#
# Reaches the model. Produces NO transcript entry. This is the default for
# every reminder, every "you should also run X", every piece of orientation —
# anything phrased as an instruction to Claude rather than as news for a human.
notice_model() {
  local event="$1" text="$2"
  [ -z "$text" ] && return 0
  printf '{"hookSpecificOutput":{"hookEventName":%s,"additionalContext":%s}}\n' \
    "$(_hn_json_escape "$event")" "$(_hn_json_escape "$text")"
}

# notice_session <text>
#
# SessionStart only. Plain stdout on exit 0 is "shown to Claude" — no JSON, no
# transcript entry. Orientation banners belong here: the model needs the
# register state, the developer does not need it recited at every /clear.
notice_session() {
  [ -z "$1" ] && return 0
  printf '%s\n' "$1"
}

# notice_user <text>
#
# The developer's channel. Reserve it for what a person must act on and the
# model cannot: a hook changed files on disk, a gate is known-broken, a run
# timed out halfway. NOT for reminders.
#
# One line, enforced. The UI renders a system notification per line, so a
# 26-line systemMessage becomes 26 warnings — which is how the register banner
# came to look like a stack trace. Newlines collapse to " · " rather than being
# rejected: a hook that has something urgent to say should not lose it to a
# formatting rule.
notice_user() {
  local text="$1"
  [ -z "$text" ] && return 0
  text=$(printf '%s' "$text" | tr '\n' '\036' | sed -e 's/\036\{1,\}/ · /g' -e 's/ · $//')
  printf '{"systemMessage":%s}\n' "$(_hn_json_escape "$text")"
}

# notice_both <hookEventName> <user-line> <model-text>
#
# For the genuine case where the developer needs a headline and the model needs
# the detail. The headline is still one line.
notice_both() {
  local event="$1" user_line="$2" model_text="$3"
  local u m
  user_line=$(printf '%s' "$user_line" | tr '\n' '\036' | sed -e 's/\036\{1,\}/ · /g' -e 's/ · $//')
  u=$(_hn_json_escape "$user_line")
  m=$(_hn_json_escape "$model_text")
  printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":%s,"additionalContext":%s}}\n' \
    "$u" "$(_hn_json_escape "$event")" "$m"
}

# --- once-per-session de-duplication ---------------------------------------
#
# A PostToolUse reminder fires on every edit of a matching file. Writing a
# Playwright spec in six passes produced six identical TLA+ reminders, and the
# sixth taught the reader to skip the first. Repetition is not emphasis; it is
# how a real reminder gets filtered out.
#
# State lives under TMPDIR keyed by session id, so it dies with the machine's
# temp sweep and never touches the repo. No session id (a hook invoked by hand,
# a test) means no de-duplication — the safe direction, since the cost of a
# duplicate is noise and the cost of a false suppression is a lost reminder.

_hn_state_dir() {
  local sid="${1:-}"
  [ -z "$sid" ] && return 1
  local base="${TMPDIR:-/tmp}"
  base="${base%/}/claude-hook-notices"
  # Session ids come from the harness, but this path is built from one, so it is
  # reduced to characters that cannot climb out of the directory.
  sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64)
  printf '%s/%s' "$base" "$sid"
}

# hn_session_id <raw stdin json>
hn_session_id() {
  printf '%s' "${1:-}" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# hn_first_time <session_id> <key>  → 0 the first time, 1 afterwards
hn_first_time() {
  local sid="$1" key="$2" dir stamp
  dir=$(_hn_state_dir "$sid") || return 0     # no session id → always "first"
  stamp=$(printf '%s' "$key" | cksum | tr -d ' ' | cut -c1-24)
  [ -z "$stamp" ] && return 0
  mkdir -p "$dir" 2>/dev/null || return 0     # cannot record → always "first"
  if [ -e "$dir/$stamp" ]; then
    return 1
  fi
  : > "$dir/$stamp" 2>/dev/null
  # Cheap sweep so the temp dir does not accumulate one directory per session
  # forever on a machine whose TMPDIR is never cleared.
  find "${dir%/*}" -maxdepth 1 -type d -mtime +2 -exec rm -rf {} + 2>/dev/null
  return 0
}

# notice_once <hookEventName> <session_id> <key> <text>
#
# notice_model, at most once per session per key. The key is what "the same
# reminder" means — usually the hook's name plus the file it is about.
notice_once() {
  local event="$1" sid="$2" key="$3" text="$4"
  hn_first_time "$sid" "$key" || return 0
  notice_model "$event" "$text"
}
