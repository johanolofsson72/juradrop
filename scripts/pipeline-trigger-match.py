#!/usr/bin/env python3
"""
UserPromptSubmit helper — Python core.

Decides whether a prompt is a *clean invocation* of a speckit pipeline
subcommand (specify / clarify / plan / tasks / implement / analyze), versus
an incidental substring match in pasted / quoted content (markdown code
blocks, inline code, blockquotes, table cells, Claude transcript bullets,
pipeline-flow diagrams with arrows or multiple slash commands on one line).

Reads the prompt text on stdin. Exits 0 on a clean invocation, 1 otherwise.

Usage:
    python3 pipeline-trigger-match.py <subcommand>
    <subcommand> ∈ {specify, clarify, plan, tasks, implement, analyze}
"""

import re
import sys

# Subcommand → (body regex, allow bare /slash form without speckit prefix)
SUBCOMMANDS = {
    "specify":   (r"specify",                       True),
    "clarify":   (r"clarif(y|ies|ication)",         True),
    "plan":      (r"plan",                          False),
    "tasks":     (r"tasks",                         False),
    "implement": (r"implement",                     False),
    "analyze":   (r"(analyz|analys)e?",             False),
}

# Alias: matches any of the five core pipeline subcommands. Used by the
# "MANDATORY PIPELINE" UserPromptSubmit hook, which fires the orientation
# reminder when the user is starting any speckit workflow.
PIPELINE_ANY = ["specify", "clarify", "plan", "tasks", "implement"]

VERB = r"(run|kör|do|execute|please|now|gör|göra)"

ARROW_RE = re.compile(r"[→⇒]|->|=>")
SLASHCMD_RE = re.compile(r"/[A-Za-z][A-Za-z0-9._:-]*")
BOX_DRAWING = set("│─┌┐└┘├┤┬┴┼╔╗╚╝╠╣╦╩╬")
# Backtick written as chr(96) so this file can be embedded in shell heredocs
# without bash's $(...) parser tripping on unbalanced backticks.
BT = chr(96)
FENCE_RE = re.compile(BT * 3 + r"[^\n]*\n.*?" + BT * 3, flags=re.DOTALL)
INLINE_CODE_RE = re.compile(BT + r"[^" + BT + r"\n]*" + BT)


def clean(text: str) -> str:
    text = FENCE_RE.sub("", text)
    text = INLINE_CODE_RE.sub("", text)
    kept = []
    for raw in text.splitlines():
        if not raw:
            kept.append(raw)
            continue
        stripped = raw.lstrip()
        if stripped.startswith(">"):
            continue
        if stripped.startswith("⏺"):
            continue
        if any(c in raw for c in BOX_DRAWING):
            continue
        if ARROW_RE.search(raw):
            continue
        if len(SLASHCMD_RE.findall(raw)) > 1:
            continue
        kept.append(raw)
    return "\n".join(kept)


def match_one(cleaned: str, sub: str) -> bool:
    body, slash_form = SUBCOMMANDS[sub]
    tail = r"([ \t]|$|[.,;:!?])"
    if slash_form:
        pattern = rf"^[ \t]*({VERB}[ \t]+)?/?(speckit[.:_-])?{body}{tail}"
    else:
        pattern = rf"^[ \t]*({VERB}[ \t]+)?/?speckit[.:_-]{body}{tail}"
    return re.compile(pattern, re.IGNORECASE | re.MULTILINE).search(cleaned) is not None


def main() -> int:
    if len(sys.argv) < 2:
        return 1
    sub = sys.argv[1]

    text = sys.stdin.read()
    if not text:
        return 1
    cleaned = clean(text)

    if sub == "pipeline":
        return 0 if any(match_one(cleaned, s) for s in PIPELINE_ANY) else 1

    if sub not in SUBCOMMANDS:
        return 1
    return 0 if match_one(cleaned, sub) else 1


if __name__ == "__main__":
    sys.exit(main())
