#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on *.cs. Scans for sync-over-async
# anti-patterns: .Result / .Wait() blocking on Task, missing await on
# Task-returning calls, blocking I/O inside async methods.
#
# These are the most common source of deadlocks and thread-pool
# starvation in .NET — well within llama3 8B's pattern-matching range.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

case "$FILE" in *.cs) ;; *) exit 0 ;; esac
case "$(basename "$FILE")" in
  *Tests.cs|*Test.cs) exit 0 ;;
esac
case "$FILE" in
  *Migrations/*|*/Migrations/*|*/bin/*|*/obj/*|*.g.cs|*.designer.cs) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 200 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

# Content gate: the audit looks for async/await anti-patterns. A POCO,
# constant class, or pure-data DTO has nothing to audit. Skip the LLM
# call entirely when the file contains no async tokens. Saves ~30-40%
# of the 100+ daily fires on rocky-sized projects.
grep -qE '\b(async|await|\.Result\b|\.Wait\(\)|Task[<.]|Thread\.Sleep|ConfigureAwait|ValueTask)' "$FILE" || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are reviewing C#/.NET code for async/await anti-patterns.

Scan for these specific issues:
- .Result or .Wait() called on a Task (blocks the calling thread, can deadlock under sync context)
- Task.Run() wrapping CPU-bound code inside an already-async method (double scheduling)
- Missing await on Task-returning calls (fire-and-forget without intention)
- Blocking I/O inside an async method (File.ReadAllText, Thread.Sleep, db.SaveChanges instead of SaveChangesAsync)
- async void on non-event-handler methods (exceptions cannot be caught)
- Returning Task without async/await when the caller cares about exceptions (loses stack trace context)
- Missing ConfigureAwait(false) in library code (less critical in app code, only flag in *.csproj that looks like a library)

For each issue found, output one line:
- ISSUE: <one-line description with method/line context if visible> | FIX: <concrete remediation>

If no issues, output exactly: CLEAN
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
NON_SENTINEL=$(printf '%s\n' "$REPORT" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*CLEAN[[:space:]]*$' | head -1)
[ -z "$NON_SENTINEL" ] && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM async/await audit on " + $f + ":\n" + $r)}'
