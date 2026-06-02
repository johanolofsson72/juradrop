#!/usr/bin/env python3
"""Sync the template's *core* (non-LLM, non-graphify) script-backed hooks into a project.

Third sibling of `sync-local-llm-hooks.py` and `sync-graphify-wiring.py`. Those two
own the local-LLM and graphify hook families deterministically; this one owns the
remaining script-backed hooks — the pipeline/spec-register/execution enforcement
hooks and the tech-stack hooks (tla, allium, sqlite, ui-design, test-coverage, …).

Why this exists: before this script, core-hook wiring was the ONE part of the sync
still done by prose ("UNION of hooks — add template hooks without removing the
project's own"). Prose merge is unreliable — old syncs left projects missing the
pipeline reminders, the spec-register guard, the state guard, the continuous-execution
backstop, etc. That is the gap that forced a `/project-update` after `/project-wizard`.
This makes core-hook wiring deterministic, so the wizard's full sync truly is complete.

Model (mirrors sync-local-llm-hooks.py):
  - A "core script hook" is a hook whose command references at least one
    `scripts/<name>.sh|.py` that is NOT a local-llm-* or graphify-* script.
  - Identity of a core hook = the frozenset of script basenames it references.
    Two hooks with the same script set are "the same hook" for replace purposes
    (this also normalizes un-normalized `bash scripts/foo.sh` → templated paths).
  - Wiring: strip from the project every core hook whose identity matches a
    template core hook, then re-append the template's current core hooks —
    BUT only those whose every referenced script already exists in the project.
    Script-presence is the tech-stack gate: a project that dropped tla-hook.sh
    (not a UI/spec project) simply never gets the tla hook re-added.
  - Inline hooks (no script reference), local-LLM hooks, graphify hooks, and any
    project-specific script hook the template does not ship are preserved verbatim.
  - Permissions and every other top-level key are never touched.

Usage:
    scripts/sync-core-hooks.py <template-settings.json>
Run from the project root (where .claude/settings.json lives). Idempotent.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SCRIPT_RE = re.compile(r"scripts/([A-Za-z0-9._-]+\.(?:sh|py))")


def script_refs(hook: dict) -> set[str]:
    return set(SCRIPT_RE.findall(hook.get("command", "")))


def is_managed_elsewhere(name: str) -> bool:
    """local-LLM and graphify scripts are owned by their own sync helpers."""
    return name.startswith("local-llm-") or name.startswith("graphify-")


def core_scripts(hook: dict) -> set[str]:
    """Script basenames this hook references that are NOT llm/graphify-owned."""
    return {n for n in script_refs(hook) if not is_managed_elsewhere(n)}


def is_core_hook(hook: dict) -> bool:
    cmd = hook.get("command", "")
    if "local-llm-" in cmd or "graphify" in cmd:
        return False
    return bool(core_scripts(hook))


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: sync-core-hooks.py <template-settings.json>", file=sys.stderr)
        return 2

    template_path = Path(sys.argv[1]).resolve()
    project_path = Path(".claude/settings.json")
    if not template_path.is_file():
        print(f"template not found: {template_path}", file=sys.stderr)
        return 2
    if not project_path.is_file():
        print(f"project settings not found: {project_path}", file=sys.stderr)
        return 2

    project_scripts = Path("scripts")
    template = json.loads(template_path.read_text())
    project = json.loads(project_path.read_text())

    # Template core hooks grouped by (event, matcher), plus the set of identities.
    template_core: dict[tuple[str, str], list[dict]] = {}
    template_identities: set[frozenset] = set()
    for event, configs in template.get("hooks", {}).items():
        for config in configs:
            matcher = config.get("matcher", "")
            for h in config.get("hooks", []):
                if is_core_hook(h):
                    ident = frozenset(core_scripts(h))
                    template_identities.add(ident)
                    template_core.setdefault((event, matcher), []).append(h)

    # 1. Strip project core hooks whose identity matches a template core hook.
    removed = 0
    for event in list(project.get("hooks", {}).keys()):
        kept_configs: list[dict] = []
        for config in project["hooks"][event]:
            kept_hooks = []
            for h in config.get("hooks", []):
                if is_core_hook(h) and frozenset(core_scripts(h)) in template_identities:
                    removed += 1
                else:
                    kept_hooks.append(h)
            if kept_hooks:
                nc = {k: v for k, v in config.items() if k != "hooks"}
                nc["hooks"] = kept_hooks
                kept_configs.append(nc)
        if kept_configs:
            project["hooks"][event] = kept_configs
        else:
            del project["hooks"][event]

    # 2. Re-append template core hooks whose scripts ALL exist in the project
    #    (script-presence = tech-stack gate). Skipped hooks are reported.
    added = 0
    skipped: list[str] = []
    for (event, matcher), hooks in template_core.items():
        qualifying = []
        for h in hooks:
            needed = core_scripts(h)
            missing = [n for n in needed if not (project_scripts / n).is_file()]
            if missing:
                skipped.append(f"{event}/{matcher or '*'}: {','.join(sorted(needed))} (missing {','.join(missing)})")
            else:
                qualifying.append(h)
        if qualifying:
            block: dict = {}
            if matcher:
                block["matcher"] = matcher
            block["hooks"] = qualifying
            project.setdefault("hooks", {}).setdefault(event, []).append(block)
            added += len(qualifying)

    project_path.write_text(json.dumps(project, indent=2) + "\n")

    # 3. Post-check: every wired core hook has its scripts on disk.
    settings_text = project_path.read_text()
    dangling = sorted(
        n for n in SCRIPT_RE.findall(settings_text)
        if not is_managed_elsewhere(n) and not (project_scripts / n).is_file()
    )

    print(f"core-hooks: removed {removed} stale, added {added} from template")
    if skipped:
        print(f"skipped {len(skipped)} tech-stack hook(s) whose scripts are absent (pruned by stack):")
        for s in skipped:
            print(f"  - {s}")
    if dangling:
        print("", file=sys.stderr)
        print(f"[FAIL] {len(dangling)} wired core hook script(s) missing on disk:", file=sys.stderr)
        for n in dangling:
            print(f"  - scripts/{n}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
