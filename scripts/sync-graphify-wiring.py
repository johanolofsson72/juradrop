#!/usr/bin/env python3
"""Sync Graphify wiring in this project to match the template's exactly.

Parallel to sync-local-llm-hooks.py but for the Graphify integration. Owns
both ends of the wiring:

  1. The hook entries in .claude/settings.json
       - PreToolUse Bash nudge (suggests `graphify query` over grep/rg/find)
       - PostToolUse Bash telemetry entry (logs every `graphify query|path|
         explain|update` invocation to .claude/graphify-fire.log)

  2. The graphify-* scripts on disk in scripts/
       - graphify-bootstrap.sh (cross-platform self-installer)
       - graphify-fire-hook.sh (PostToolUse telemetry hook)
       - graphify-stats.sh (ROI reporter)

Why this exists: project-wizard's sync step was supposed to handle this
via prose ("execute the sync-prompt instructions"), but in practice the
PostToolUse telemetry entry got dropped in roughly one project in ten —
graphify-out/ would exist but the fire log never accumulated. The
ighweld-2026 / juradrop pattern (scripts copied, bootstrap never run,
telemetry entry missing) is the symptom this script eliminates.

Both wiring entries are safe to inject unconditionally:

  - The PreToolUse nudge guards on `[ -f graphify-out/graph.json ]` and
    silently no-ops if the graph file doesn't exist. Safe to wire before
    graphify is bootstrapped.
  - The PostToolUse hook (graphify-fire-hook.sh) bails out cleanly when
    the tool_input doesn't contain `graphify (query|path|explain|update)`,
    and reads graph node/edge counts opportunistically. Safe to wire
    before graphify is installed.

So the helper is decoupled from `graphify-bootstrap.sh` — wiring can be
present even on projects that haven't bootstrapped yet, and the hooks
will start producing real data the moment the bootstrap runs.

Usage:
    scripts/sync-graphify-wiring.py <template-settings.json>

Run from the project root (where .claude/settings.json lives).

Idempotent — running twice produces the same result as running once.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

# A hook entry is "graphify-related" if its command references graphify in
# any way. Both entries the template ships meet this: the PreToolUse Bash
# nudge mentions `graphify-out/graph.json` and `graphify query`, and the
# PostToolUse hook command runs `bash .../graphify-fire-hook.sh`. No
# unrelated hook command should contain the literal "graphify".
GRAPHIFY_RE = re.compile(r"graphify")

# Script set the template owns. Anything matching this glob in the project
# that isn't in the template gets deleted (template is source of truth).
HOOK_SCRIPT_GLOB = "graphify-*.sh"


def is_graphify(hook: dict) -> bool:
    return bool(GRAPHIFY_RE.search(hook.get("command", "")))


def sync_wiring(template: dict, project: dict) -> tuple[int, int]:
    """Mirror template's graphify wiring into project. Returns (removed, added)."""
    template_wiring: dict[tuple[str, str], list[dict]] = {}
    for event, configs in template.get("hooks", {}).items():
        for config in configs:
            matcher = config.get("matcher", "")
            for h in config.get("hooks", []):
                if is_graphify(h):
                    template_wiring.setdefault((event, matcher), []).append(h)

    removed_count = 0
    for event in list(project.get("hooks", {}).keys()):
        kept_configs: list[dict] = []
        for config in project["hooks"][event]:
            kept_hooks = []
            for h in config.get("hooks", []):
                if is_graphify(h):
                    removed_count += 1
                else:
                    kept_hooks.append(h)
            if kept_hooks:
                new_config = {k: v for k, v in config.items() if k != "hooks"}
                new_config["hooks"] = kept_hooks
                kept_configs.append(new_config)
        if kept_configs:
            project["hooks"][event] = kept_configs
        else:
            del project["hooks"][event]

    added_count = 0
    for (event, matcher), hooks in template_wiring.items():
        block: dict = {}
        if matcher:
            block["matcher"] = matcher
        block["hooks"] = hooks
        project.setdefault("hooks", {}).setdefault(event, []).append(block)
        added_count += len(hooks)

    return removed_count, added_count


def sync_scripts(template_scripts_dir: Path, project_scripts_dir: Path) -> tuple[list[str], list[str]]:
    """Mirror template's graphify-* scripts on disk.

    Returns (copied, deleted) lists of basenames.
    """
    project_scripts_dir.mkdir(parents=True, exist_ok=True)

    template_files = {p.name: p for p in template_scripts_dir.glob(HOOK_SCRIPT_GLOB)}
    project_files = {p.name: p for p in project_scripts_dir.glob(HOOK_SCRIPT_GLOB)}

    copied: list[str] = []
    for name, src in sorted(template_files.items()):
        dst = project_scripts_dir / name
        if dst.is_file() and dst.read_bytes() == src.read_bytes():
            continue
        shutil.copy2(src, dst)
        copied.append(name)

    deleted: list[str] = []
    for name in sorted(project_files):
        if name not in template_files:
            (project_scripts_dir / name).unlink()
            deleted.append(name)

    return copied, deleted


def verify_post_sync(project_settings_path: Path, project_scripts_dir: Path) -> list[str]:
    """Return list of wired-but-missing graphify hook script basenames."""
    settings_text = project_settings_path.read_text()
    # Only the PostToolUse telemetry entry references a script by name; the
    # PreToolUse nudge is pure inline shell. Match `graphify-*-hook.sh` (or
    # similar) referenced via the bash command.
    wired = set(re.findall(r"(graphify-[a-z0-9-]+\.sh)", settings_text))
    missing = [name for name in sorted(wired) if not (project_scripts_dir / name).is_file()]
    return missing


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: sync-graphify-wiring.py <template-settings.json>",
            file=sys.stderr,
        )
        return 2

    template_settings_path = Path(sys.argv[1]).resolve()
    project_settings_path = Path(".claude/settings.json")

    if not template_settings_path.is_file():
        print(f"template not found: {template_settings_path}", file=sys.stderr)
        return 2
    if not project_settings_path.is_file():
        print(f"project settings not found: {project_settings_path}", file=sys.stderr)
        return 2

    template_root = template_settings_path.parent.parent
    template_scripts_dir = template_root / "scripts"
    if not template_scripts_dir.is_dir():
        print(f"template scripts/ not found: {template_scripts_dir}", file=sys.stderr)
        return 2

    project_scripts_dir = Path("scripts")

    template = json.loads(template_settings_path.read_text())
    project = json.loads(project_settings_path.read_text())

    removed, added = sync_wiring(template, project)
    project_settings_path.write_text(json.dumps(project, indent=2) + "\n")

    copied, deleted = sync_scripts(template_scripts_dir, project_scripts_dir)

    missing = verify_post_sync(project_settings_path, project_scripts_dir)

    print(f"wiring: removed {removed} stale entries, added {added} from template")
    print(f"scripts: copied {len(copied)}, deleted {len(deleted)}")
    if copied:
        for name in copied:
            print(f"  + {name}")
    if deleted:
        for name in deleted:
            print(f"  - {name}")
    if missing:
        print("", file=sys.stderr)
        print(f"[FAIL] {len(missing)} wired graphify hook(s) still missing their script:", file=sys.stderr)
        for name in missing:
            print(f"  - scripts/{name}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
