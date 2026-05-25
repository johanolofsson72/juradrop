#!/bin/bash
# TLC process cleanup — run after every TLC execution
# Also used by PostToolUse hook to catch orphaned processes

# Kill any TLC/tla2tools Java processes
pkill -f "tla2tools" 2>/dev/null
pkill -f "tlc2.TLC" 2>/dev/null

# Wait briefly for graceful shutdown
sleep 1

# Force kill if still alive
if pgrep -f "tla2tools|tlc2.TLC" >/dev/null 2>&1; then
  echo "WARNING: TLC processes still running after graceful kill — force killing"
  pkill -9 -f "tla2tools" 2>/dev/null
  pkill -9 -f "tlc2.TLC" 2>/dev/null
fi

# Report status
REMAINING=$(pgrep -f "tla2tools|tlc2.TLC" 2>/dev/null | wc -l | tr -d ' ')
if [ "$REMAINING" -gt 0 ]; then
  echo "ERROR: $REMAINING TLC processes still running after force kill"
  exit 1
fi
