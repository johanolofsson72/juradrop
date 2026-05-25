#!/bin/bash
# Stop hook: blocks the session from ending when the assistant is about to ask
# "should I continue with the next phase?" — the canonical phase-splitting
# anti-pattern documented in .claude/rules/continuous-execution.md.
#
# Reads the transcript, extracts the most recent assistant text message,
# splits it into sentences, and checks whether any QUESTION (sentence ending
# with `?`) matches a tight phase-continuation pattern. Pure statements like
# "Moving on to phase 2." are not blocked — only actual permission-asking is.
#
# Returns:
#   exit 0 — allow stop
#   exit 2 — block stop (phase-splitting question detected; reason on stderr)

set -u

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

# All matching logic lives in Python: read transcript → last assistant text →
# split into sentences → match phase-continuation pattern only on `?` sentences.
RESULT=$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null
import json, re, sys
path = sys.argv[1]

last = ""
try:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            msg = obj.get("message") or {}
            if msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            if isinstance(content, list):
                texts = [
                    c.get("text", "")
                    for c in content
                    if isinstance(c, dict) and c.get("type") == "text" and c.get("text")
                ]
                if texts:
                    last = "\n".join(texts)
            elif isinstance(content, str) and content:
                last = content
except Exception:
    pass

if not last:
    sys.exit(0)

tail = last[-2000:]

pattern = re.compile(
    r"("
    r"should i (continue|proceed|move on|go on|start (the )?next)"
    r"|shall i (continue|proceed|move on|start (the )?next)"
    r"|want me to (continue|proceed|move on|start (the )?next|do the next|"
    r"go ahead with (phase|step|the next))"
    r"|do you want me to (continue|proceed|move on|start (the )?next)"
    r"|ready (for|to (continue|proceed|move on|start)) (the )?next"
    r"|continue (with )?(the )?next (phase|step|task|item)"
    r"|move on to (phase|step|task|the next)"
    r"|on to (phase|step) [0-9]"
    r"|next (phase|step|task)\?"
    r"|proceed (with|to) (phase|step|the next)"
    r")",
    re.IGNORECASE,
)

# Split into sentences. We treat ., !, ? as sentence terminators and keep the
# terminator on the preceding sentence so we can tell questions from statements.
sentences = re.split(r"(?<=[.!?])\s+", tail)

for s in sentences:
    s_stripped = s.strip()
    # Only consider sentences that are actually questions
    if not s_stripped.endswith("?"):
        continue
    if pattern.search(s_stripped):
        # Print the offending sentence (truncated) so the agent sees what tripped
        offender = s_stripped if len(s_stripped) <= 200 else s_stripped[:200] + "..."
        print(offender)
        sys.exit(99)

sys.exit(0)
PY
)
RC=$?

if [ "$RC" -eq 99 ]; then
  cat <<EOF >&2
STOP BLOCKED — phase-splitting detected.

Triggering question: "$RESULT"

This is the anti-pattern documented in .claude/rules/continuous-execution.md.
A multi-phase plan is ONE task, not N tasks. The user has already approved
the work. Asking again wastes their time and breaks context.

Do NOT stop. Continue executing the remaining work right now.

You may stop ONLY when:
  (a) you have a genuine ambiguity that requires user input
      → use AskUserQuestion, do not stop with a free-text question
  (b) you are blocked by something you cannot resolve autonomously
      → say so plainly and explain what you need
  (c) the entire plan is complete — every phase done, every test passing
      → then you may stop and report

If none of (a)/(b)/(c) apply: keep going. The fix is not to rephrase the
question — the fix is to stop asking and just continue the work.
EOF
  exit 2
fi

exit 0
