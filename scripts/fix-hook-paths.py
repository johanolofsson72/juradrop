#!/usr/bin/env python3
"""
Rewrite settings.json hook commands so 'bash scripts/foo.sh' becomes
'bash "$CLAUDE_PROJECT_DIR/scripts/foo.sh"'. Idempotent.

Why: relative paths in hook commands depend on the cwd Claude was started in.
$CLAUDE_PROJECT_DIR is the harness-provided project root, available in every
hook event, and resolves correctly regardless of cwd.
"""
import json
import pathlib
import re
import sys

# Match `bash scripts/<name>.sh` where <name> contains no whitespace.
# Greedy \S+ backtracks so .sh anchors the suffix; trailing args/redirects stay outside.
PATTERN = re.compile(r'bash scripts/(\S+\.sh)')


def patch_text(text: str) -> tuple[str, int]:
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        count += 1
        # In JSON string context, the literal bytes need to be: bash \"$CLAUDE_PROJECT_DIR/scripts/foo.sh\"
        return 'bash \\"$CLAUDE_PROJECT_DIR/scripts/' + m.group(1) + '\\"'

    new = PATTERN.sub(repl, text)
    return new, count


def main(paths: list[str]) -> int:
    total = 0
    for p in paths:
        path = pathlib.Path(p)
        if not path.is_file():
            print(f"SKIP (no file)    {p}")
            continue
        original = path.read_text()
        new, count = patch_text(original)
        if count == 0:
            print(f"unchanged         {p}")
            continue
        try:
            json.loads(new)
        except json.JSONDecodeError as e:
            print(f"FAIL (bad JSON)   {p}: {e}")
            return 1
        path.write_text(new)
        print(f"patched ({count:>2})    {p}")
        total += count
    print(f"---\ntotal substitutions: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
