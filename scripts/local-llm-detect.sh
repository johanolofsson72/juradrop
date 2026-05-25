#!/usr/bin/env bash
# Detect whether a local LLM (Ollama) is reachable and export config.
#
# Sourced by the local-llm-* hook scripts. After sourcing, callers should
# check $LOCAL_LLM_AVAILABLE (1 = ready, 0 = offline / disabled / missing).
#
# Honored env vars (all optional):
#   OLLAMA_HOST                 base URL, default http://127.0.0.1:11434
#   LOCAL_LLM_MODEL             explicit model tag (overrides auto-detection)
#   LOCAL_LLM_MODEL_PREF_ORDER  space-separated preference list for auto-detection
#   LOCAL_LLM_TIMEOUT           seconds for generation calls, default 15
#   LOCAL_LLM_DETECT_TIMEOUT    seconds for the reachability ping, default 1
#   LOCAL_LLM_DISABLE           set to 1 to force-disable the offload hooks
#
# Model resolution order:
#   1. $LOCAL_LLM_MODEL if set (user override always wins)
#   2. First match from $LOCAL_LLM_MODEL_PREF_ORDER against /api/tags
#   3. llama3 (last-resort default; will fail at generate time if not pulled)

LOCAL_LLM_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
LOCAL_LLM_TIMEOUT="${LOCAL_LLM_TIMEOUT:-15}"
LOCAL_LLM_DETECT_TIMEOUT="${LOCAL_LLM_DETECT_TIMEOUT:-1}"

# Default preference order biased toward coding-capable models. Tune by
# exporting LOCAL_LLM_MODEL_PREF_ORDER (space-separated tags).
LOCAL_LLM_MODEL_PREF_ORDER="${LOCAL_LLM_MODEL_PREF_ORDER:-qwen2.5-coder:14b qwen2.5-coder:7b qwen2.5-coder:32b mistral-small:24b qwen2.5:7b llama3:latest llama3}"

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
    PREFS_NL=$(printf '%s' "$LOCAL_LLM_MODEL_PREF_ORDER" | tr -s ' \t' '\n')
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
       LOCAL_LLM_TIMEOUT LOCAL_LLM_DETECT_TIMEOUT LOCAL_LLM_AVAILABLE
