#!/usr/bin/env python3
"""Remove hooks from .claude/settings.json whose scripts do not exist on disk.

A hook wired to a missing script is the worst kind of broken: it never errors, it
just silently does nothing, and every audit that checks "is it wired?" reports
green. That is exactly how a project ends up believing it has enforcement it does
not have.

This happens legitimately: settings.json is seeded wholesale from the template
(so it references the graphify and local-LLM families), while the script sets are
owned by separate sync helpers that are gated on the project's stack and opt-ins.
Whatever did not land should not stay wired.

Only hooks referencing `scripts/<name>.sh|.py` are considered. Inline hooks (jq
one-liners, echo reminders) reference no script and are always preserved, as are
hooks whose every referenced script is present.

Usage:  prune-dangling-hooks.py [--dry-run]
Run from the project root. Idempotent. Exits 0 on success, 2 on a usage error.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SCRIPT_RE = re.compile(r"scripts/([A-Za-z0-9._-]+\.(?:sh|py))")


def main() -> int:
    dry = "--dry-run" in sys.argv[1:]
    settings = Path(".claude/settings.json")
    if not settings.is_file():
        print("no .claude/settings.json — nothing to prune", file=sys.stderr)
        return 0

    data = json.loads(settings.read_text())
    hooks = data.get("hooks", {})
    removed: list[str] = []

    for event in list(hooks.keys()):
        kept_configs = []
        for config in hooks[event]:
            kept = []
            for hook in config.get("hooks", []):
                refs = SCRIPT_RE.findall(hook.get("command", ""))
                missing = [r for r in refs if not Path("scripts", r).is_file()]
                if missing:
                    removed.append(f"{event}: {', '.join(sorted(set(missing)))}")
                else:
                    kept.append(hook)
            if kept:
                nc = {k: v for k, v in config.items() if k != "hooks"}
                nc["hooks"] = kept
                kept_configs.append(nc)
        if kept_configs:
            hooks[event] = kept_configs
        else:
            del hooks[event]

    if not removed:
        print("no dangling hooks")
        return 0

    for r in removed:
        print(f"{'would prune' if dry else 'pruned'} {r}")
    if not dry:
        settings.write_text(json.dumps(data, indent=2) + "\n")
    print(f"{len(removed)} dangling hook(s) {'found' if dry else 'removed'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
