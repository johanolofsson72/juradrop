#!/usr/bin/env bash
# PostToolUse Bash hook. Fires when the Claude Code session shells out to
# `graphify <query|path|explain>` and logs the invocation + response size
# to .claude/graphify-fire.log. Telemetry only — never modifies output,
# never blocks. Symmetric in shape with local-llm-fire.log so the stats
# reporter can be written the same way.
#
# Log schema (TSV, append-only):
#   TS  SUBCMD  EXIT  ARG_BYTES  RESPONSE_BYTES  GRAPH_NODES  GRAPH_EDGES
#
# GRAPH_NODES/EDGES come from graphify-out/graph.json if present (cheap
# stat-and-cache; reads file size from a stamp file invalidated whenever
# the graph mtime changes). When the graph file is missing they are 0.
#
# Why the log matters: there is no API key cost on local AST queries, but
# every `graphify query` invocation that returns a focused subgraph
# replaces what would otherwise be one or more `Grep`/`Read` calls in the
# main Anthropic session. The savings counterfactual is fuzzy, but the
# raw invocation count + per-call response bytes are hard numbers — a
# stats report ("you ran 142 graphify queries this week, returning ~310
# KB of structured context") is the honest answer to "is this thing
# saving us anything?"
#
# Disable with GRAPHIFY_TELEMETRY_DISABLE=1 if a developer wants to opt
# out without removing the hook entry from settings.json.

set -uo pipefail

[ "${GRAPHIFY_TELEMETRY_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

# jq is the universal parser the rest of the template depends on — bail
# silently if it isn't present rather than parsing JSON in bash.
command -v jq >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Match `graphify query|path|explain|update`. The leading word boundary
# ensures we don't accidentally fire on a command that merely mentions
# graphify as an argument (e.g. `echo "see graphify"`).
SUBCMD=$(printf '%s' "$CMD" | grep -oE '(^|[[:space:];|&]+)graphify[[:space:]]+(query|path|explain|update)' | head -1 | awk '{print $NF}')
[ -n "$SUBCMD" ] || exit 0

EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // .tool_response.returncode // 0' 2>/dev/null)
STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
STDERR=$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null)
RESPONSE_BYTES=$(( ${#STDOUT} + ${#STDERR} ))
ARG_BYTES=${#CMD}

# Project root anchor — telemetry log sits next to local-llm-fire.log.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="$PROJECT_ROOT/.claude"
LOG_FILE="${GRAPHIFY_TELEMETRY_LOG:-$LOG_DIR/graphify-fire.log}"
ERR_FILE="${LOG_FILE}.errors"
mkdir -p "$LOG_DIR" 2>>"$ERR_FILE" || exit 0

# Read graph node/edge counts opportunistically. Cache the parsed counts
# next to the graph file with the graph's mtime as the cache key so we
# don't re-parse multi-MB JSON on every hook fire.
GRAPH_FILE="$PROJECT_ROOT/graphify-out/graph.json"
NODES=0
EDGES=0
if [ -f "$GRAPH_FILE" ]; then
  GRAPH_MTIME=$(stat -f %m "$GRAPH_FILE" 2>/dev/null || stat -c %Y "$GRAPH_FILE" 2>/dev/null || echo 0)
  CACHE_FILE="$PROJECT_ROOT/graphify-out/.fire-hook-cache"
  if [ -f "$CACHE_FILE" ]; then
    read -r CACHED_MTIME CACHED_NODES CACHED_EDGES < "$CACHE_FILE" 2>/dev/null || true
  fi
  if [ "${CACHED_MTIME:-0}" = "$GRAPH_MTIME" ]; then
    NODES=${CACHED_NODES:-0}
    EDGES=${CACHED_EDGES:-0}
  else
    COUNTS=$(jq -r '[(.nodes // [] | length), (.edges // .links // [] | length)] | @tsv' < "$GRAPH_FILE" 2>/dev/null || echo "0	0")
    NODES=$(printf '%s' "$COUNTS" | cut -f1)
    EDGES=$(printf '%s' "$COUNTS" | cut -f2)
    printf '%s %s %s\n' "$GRAPH_MTIME" "$NODES" "$EDGES" > "$CACHE_FILE" 2>/dev/null || true
  fi
fi

TS=$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo "?")
printf '%s\t%s\t%d\t%d\t%d\t%d\t%d\n' \
  "$TS" "$SUBCMD" "${EXIT_CODE:-0}" "$ARG_BYTES" "$RESPONSE_BYTES" "$NODES" "$EDGES" \
  >> "$LOG_FILE" 2>>"$ERR_FILE" || true

exit 0
