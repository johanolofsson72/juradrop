#!/usr/bin/env bash
# Detect whether a local LLM (Ollama) is reachable and export config.
#
# Sourced by the local-llm-* hook scripts. After sourcing, callers should
# check $LOCAL_LLM_AVAILABLE (1 = ready, 0 = offline / disabled / missing).
#
# Honored env vars (all optional):
#   OLLAMA_HOST                 base URL, default http://127.0.0.1:11434
#   LOCAL_LLM_MODEL             explicit model tag (overrides auto-detection)
#   LOCAL_LLM_PROFILE           fast | standard | deep (default standard)
#   LOCAL_LLM_MODEL_PREF_ORDER  preference list for the standard/deep profiles
#   LOCAL_LLM_MODEL_PREF_ORDER_FAST   preference list for the fast profile
#   LOCAL_LLM_TIMEOUT           seconds per call; default comes from the
#                               profile (fast 10, standard 20, deep 35)
#   LOCAL_LLM_KEEP_ALIVE        how long Ollama holds the model, default 15m
#   LOCAL_LLM_DETECT_TIMEOUT    seconds for the reachability ping, default 1
#   LOCAL_LLM_DISABLE           set to 1 to force-disable the offload hooks
#
# Model resolution order:
#   1. $LOCAL_LLM_MODEL if set (user override always wins)
#   2. First match from the ACTIVE profile's preference list against /api/tags
#   3. llama3 (last-resort default; will fail at generate time if not pulled)

LOCAL_LLM_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
LOCAL_LLM_DETECT_TIMEOUT="${LOCAL_LLM_DETECT_TIMEOUT:-1}"

# ---------------------------------------------------------------- profiles
# One model for every hook was the wrong shape. Measured on an M2 Max against
# the real prompt sizes in .claude/local-llm-fire.log, a dense 14B ingests
# prompts at ~140 tok/s — so a 10 KB hook prompt costs ~17 s of PROMPT EVAL
# before the first output token, and blows any sane timeout. Meanwhile a 4B
# ingests the same prompt at ~460 tok/s. The work splits cleanly:
#
#   fast     — routing hints and digests. Short outputs, latency is the whole
#              point, a small model is indistinguishable in quality.
#   standard — code advisories (N+1, async, deps). Needs real code sense.
#   deep     — artifact drafts (commit/PR/plan). Biggest prompts, longest
#              outputs, quality matters most and a few extra seconds are fine.
#
# Callers select with `LOCAL_LLM_PROFILE=fast` before invoking the caller.
# Unset means standard. LOCAL_LLM_MODEL / LOCAL_LLM_TIMEOUT still override.
LOCAL_LLM_PROFILE="${LOCAL_LLM_PROFILE:-standard}"

# Preference orders are per profile; first installed tag wins. Ordering is
# measured, not guessed — see .claude/docs/local-llm.md for the benchmark.
# qwen3-coder:30b leads every profile: it is a 30B MoE with only 3.3B active
# params, so it ingests prompts at ~450-550 tok/s where a dense 14B manages
# ~140, and it still scored 5/5 on the classify hook's strict output format.
# One primary for all three profiles is deliberate: mixing models forces
# Ollama to swap 18 GB in and out between hooks.
#
# Explicitly NOT in these lists: qwen3:4b and llama3.2:3b. Both are fast and
# both FAIL the format-constrained hooks — qwen3:4b emits chain-of-thought as
# plain response text even with think:false (0/5 on classify), llama3.2:3b
# scored 1/5. Speed is worthless when the output cannot be parsed.
LOCAL_LLM_MODEL_PREF_ORDER="${LOCAL_LLM_MODEL_PREF_ORDER:-qwen3-coder:30b qwen2.5-coder:14b qwen2.5-coder:7b mistral-small:24b qwen2.5:7b llama3:latest llama3}"
LOCAL_LLM_MODEL_PREF_ORDER_FAST="${LOCAL_LLM_MODEL_PREF_ORDER_FAST:-qwen3-coder:30b qwen2.5-coder:7b qwen2.5-coder:14b gemma3:4b qwen2.5:7b llama3:latest llama3}"
LOCAL_LLM_MODEL_PREF_ORDER_DEEP="${LOCAL_LLM_MODEL_PREF_ORDER_DEEP:-$LOCAL_LLM_MODEL_PREF_ORDER}"

case "$LOCAL_LLM_PROFILE" in
  fast) LOCAL_LLM_ACTIVE_PREFS="$LOCAL_LLM_MODEL_PREF_ORDER_FAST"; LOCAL_LLM_PROFILE_TIMEOUT=10 ;;
  deep) LOCAL_LLM_ACTIVE_PREFS="$LOCAL_LLM_MODEL_PREF_ORDER_DEEP"; LOCAL_LLM_PROFILE_TIMEOUT=35 ;;
  *)    LOCAL_LLM_ACTIVE_PREFS="$LOCAL_LLM_MODEL_PREF_ORDER";      LOCAL_LLM_PROFILE_TIMEOUT=20 ;;
esac
LOCAL_LLM_TIMEOUT="${LOCAL_LLM_TIMEOUT:-$LOCAL_LLM_PROFILE_TIMEOUT}"

# Ollama's default keep_alive is 5 minutes. An 18 GB model evicted between
# hook fires means the next hook pays a cold load inside its timeout budget —
# which is exactly how a 0.5 s call turns into a timeout. Hold it a little
# longer. Lower this on a memory-tight box.
LOCAL_LLM_KEEP_ALIVE="${LOCAL_LLM_KEEP_ALIVE:-15m}"

OLLAMA_TAGS=""
LOCAL_LLM_AVAILABLE=0

if [ "${LOCAL_LLM_DISABLE:-0}" = "1" ]; then
  LOCAL_LLM_AVAILABLE=0
elif command -v curl >/dev/null 2>&1; then
  OLLAMA_TAGS=$(curl -sf --max-time "$LOCAL_LLM_DETECT_TIMEOUT" \
                  "${LOCAL_LLM_HOST}/api/tags" 2>/dev/null) \
    && LOCAL_LLM_AVAILABLE=1
fi

# Auto-pick the best installed model when the caller has not pinned one.
# Iteration uses a here-string + while-read pair instead of `for pref in
# $VAR` because zsh does NOT word-split unquoted parameter expansions by
# default — that breakage cost an afternoon. `tr` normalizes whitespace
# so the loop works identically in bash and zsh when the script is
# sourced (the shebang is irrelevant for sourced files).
if [ -z "${LOCAL_LLM_MODEL:-}" ]; then
  if [ "$LOCAL_LLM_AVAILABLE" = "1" ] \
    && [ -n "$OLLAMA_TAGS" ] \
    && command -v jq >/dev/null 2>&1; then
    AVAILABLE_MODELS=$(printf '%s' "$OLLAMA_TAGS" | jq -r '.models[]?.name' 2>/dev/null)
    PREFS_NL=$(printf '%s' "$LOCAL_LLM_ACTIVE_PREFS" | tr -s ' \t' '\n')
    while IFS= read -r pref; do
      [ -n "$pref" ] || continue
      if printf '%s\n' "$AVAILABLE_MODELS" | grep -Fxq "$pref"; then
        LOCAL_LLM_MODEL="$pref"
        break
      fi
    done <<< "$PREFS_NL"
  fi
  # Last-resort default if Ollama is unreachable or jq is missing.
  LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-llama3}"
fi

export LOCAL_LLM_HOST LOCAL_LLM_MODEL LOCAL_LLM_MODEL_PREF_ORDER \
       LOCAL_LLM_MODEL_PREF_ORDER_FAST LOCAL_LLM_MODEL_PREF_ORDER_DEEP \
       LOCAL_LLM_PROFILE LOCAL_LLM_TIMEOUT LOCAL_LLM_DETECT_TIMEOUT \
       LOCAL_LLM_KEEP_ALIVE LOCAL_LLM_AVAILABLE
