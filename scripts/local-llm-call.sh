#!/usr/bin/env bash
# Generic non-streaming Ollama caller.
#
# Usage:  echo "user prompt" | local-llm-call.sh "system prompt" [num_predict]
#
# Prints model output on stdout. Exits 0 on success, non-zero on any failure
# (offline, timeout, missing model, malformed response). Callers should treat
# non-zero / empty stdout as "no offload available, carry on".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve a per-project log directory. When invoked inside a git repo we
# write logs to <repo>/.claude/ so each project gets its own telemetry
# stream — no env-var management needed. Falls back to ~/.claude/ when
# not in a repo.
LOCAL_LLM_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
LOCAL_LLM_LOG_DIR="${LOCAL_LLM_REPO_ROOT:-$HOME}/.claude"

# Entry tracer — proves the script was invoked at all. Survives every
# downstream early-exit, so a missing telemetry row that has a tracer line
# means the failure is in the telemetry block (not before).
TRACE_LOG="${LOCAL_LLM_TRACE_LOG:-$LOCAL_LLM_LOG_DIR/local-llm-trace.log}"
{
  mkdir -p "$(dirname "$TRACE_LOG")" 2>/dev/null
  PARENT_CMD=$(ps -o args= -p "$PPID" 2>/dev/null | head -c 200)
  printf '%s\tpid=%s\tppid=%s\tparent=%s\n' \
    "$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null)" "$$" "$PPID" "$PARENT_CMD" \
    >> "$TRACE_LOG" 2>/dev/null
} || true

# shellcheck disable=SC1091
source "$SCRIPT_DIR/local-llm-detect.sh"

[ "${LOCAL_LLM_AVAILABLE:-0}" = "1" ] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

SYSTEM_PROMPT="${1:-}"
NUM_PREDICT="${2:-256}"

USER_PROMPT="$(cat)"
[ -n "$USER_PROMPT" ] || exit 1

# Millisecond-precision wall clock. macOS `date` does not support %3N, so
# fall back through gdate (homebrew coreutils), python3, then plain
# seconds × 1000 as a last resort.
now_ms() {
  if command -v gdate >/dev/null 2>&1; then
    gdate +%s%3N
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null
  else
    echo "$(($(date +%s) * 1000))"
  fi
}

# Portable SHA-256 hashing (macOS ships `shasum`, Linux ships `sha256sum`).
# Returns 64-char hex on stdout. Empty string on hashing failure — caller
# treats empty as "no cache key, skip cache".
sha256_hex() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum 2>/dev/null | awk '{print $1}'
  else
    echo ""
  fi
}

# Cache layer. SHA-256 of (model || system || user || num_predict) keys
# the response file under .claude/.local-llm-cache/<sha>.txt with TTL
# enforced via mtime. Identical hook fires on identical inputs within
# the TTL window return the previous response without burning a curl.
#
# Zero quality loss by construction: identical input bytes -> identical
# cache key -> identical output. Files mutate -> new hash -> cache miss.
# Disable globally with LOCAL_LLM_CACHE_DISABLE=1.
CACHE_DIR="${LOCAL_LLM_CACHE_DIR:-$LOCAL_LLM_LOG_DIR/.local-llm-cache}"
CACHE_TTL="${LOCAL_LLM_CACHE_TTL:-600}"
CACHE_HIT=0
CACHE_KEY=""
CACHED_RESPONSE=""

if [ "${LOCAL_LLM_CACHE_DISABLE:-0}" != "1" ]; then
  CACHE_KEY=$(printf '%s\n%s\n%s\n%s' \
    "$LOCAL_LLM_MODEL" "$SYSTEM_PROMPT" "$USER_PROMPT" "$NUM_PREDICT" \
    | sha256_hex)
fi

if [ -n "$CACHE_KEY" ] && [ -f "$CACHE_DIR/$CACHE_KEY.txt" ]; then
  # Cross-platform mtime: try GNU stat, fall back to BSD stat.
  MTIME=$(stat -c %Y "$CACHE_DIR/$CACHE_KEY.txt" 2>/dev/null \
       || stat -f %m "$CACHE_DIR/$CACHE_KEY.txt" 2>/dev/null \
       || echo 0)
  NOW_S=$(date +%s 2>/dev/null || echo 0)
  if [ "$MTIME" -gt 0 ] && [ $((NOW_S - MTIME)) -lt "$CACHE_TTL" ]; then
    CACHED_RESPONSE=$(cat "$CACHE_DIR/$CACHE_KEY.txt" 2>/dev/null || true)
    [ -n "$CACHED_RESPONSE" ] && CACHE_HIT=1
  else
    rm -f "$CACHE_DIR/$CACHE_KEY.txt" 2>/dev/null || true
  fi
fi

T0=$(now_ms)
if [ "$CACHE_HIT" = "1" ]; then
  RESPONSE_TEXT="$CACHED_RESPONSE"
  CURL_EXIT=0
else
  PAYLOAD=$(jq -nc \
    --arg model "$LOCAL_LLM_MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg prompt "$USER_PROMPT" \
    --argjson num_predict "$NUM_PREDICT" \
    '{
      model: $model,
      system: $system,
      prompt: $prompt,
      stream: false,
      options: { temperature: 0.2, num_predict: $num_predict }
    }')

  RESPONSE=$(curl -sf --max-time "$LOCAL_LLM_TIMEOUT" \
    -X POST "${LOCAL_LLM_HOST}/api/generate" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null)
  CURL_EXIT=$?

  RESPONSE_TEXT=""
  if [ $CURL_EXIT -eq 0 ]; then
    RESPONSE_TEXT=$(printf '%s' "$RESPONSE" | jq -r '.response // empty' 2>/dev/null)
    if [ -n "$CACHE_KEY" ] && [ -n "$RESPONSE_TEXT" ]; then
      mkdir -p "$CACHE_DIR" 2>/dev/null || true
      printf '%s' "$RESPONSE_TEXT" > "$CACHE_DIR/$CACHE_KEY.txt" 2>/dev/null || true
    fi
  fi
fi
T1=$(now_ms)

if [ "${LOCAL_LLM_TELEMETRY_DISABLE:-0}" != "1" ]; then
  # Pipefail off for the ps|grep|head pipeline — head -1 closing early can
  # otherwise mark the assignment "failed" under set -uo pipefail and
  # interact badly with later steps.
  set +o pipefail
  HOOK_NAME=$(ps -o args= -p "$PPID" 2>/dev/null \
    | grep -oE 'local-llm-[a-z0-9-]+-hook' | head -1 || true)
  set -o pipefail
  HOOK_NAME=${HOOK_NAME:-unknown}
  TELEMETRY_LOG="${LOCAL_LLM_TELEMETRY_LOG:-$LOCAL_LLM_LOG_DIR/local-llm-fire.log}"
  TELEMETRY_ERR="${TELEMETRY_LOG}.errors"
  mkdir -p "$(dirname "$TELEMETRY_LOG")" 2>>"$TELEMETRY_ERR" || true
  TS=$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo "?")
  DURATION_MS=$((T1 - T0))
  PROMPT_BYTES=${#USER_PROMPT}
  RESPONSE_BYTES=${#RESPONSE_TEXT}
  # Schema v4: 8 columns adds model tag (audit trail — proves WHICH model
  # served each fire, not just that one did). v3 had 7 (added cache_hit),
  # v2 had 6, v1 had 5. local-llm-stats.sh autodetects via NF.
  if ! printf '%s\t%s\t%d\t%d\t%d\t%d\t%d\t%s\n' \
    "$TS" "$HOOK_NAME" "${CURL_EXIT:-99}" "$DURATION_MS" \
    "$PROMPT_BYTES" "$RESPONSE_BYTES" "$CACHE_HIT" "$LOCAL_LLM_MODEL" \
    >> "$TELEMETRY_LOG" 2>>"$TELEMETRY_ERR"; then
    printf 'WRITE_FAIL %s pid=%s ppid=%s\n' "$TS" "$$" "$PPID" \
      >> "$TELEMETRY_ERR" 2>/dev/null || true
  fi
fi

[ $CURL_EXIT -eq 0 ] || exit 1
printf '%s' "$RESPONSE_TEXT"
