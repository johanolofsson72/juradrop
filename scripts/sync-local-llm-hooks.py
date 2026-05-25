#!/usr/bin/env python3
"""Sync local-LLM hooks in this project to match the template's exactly.

This script owns BOTH ends of local-LLM hook state:
  1. The wiring in .claude/settings.json
  2. The hook script files on disk in scripts/

They are coupled — a wired hook with no script on disk fires "No such
file or directory" on every Edit/Bash, and a script on disk with no
wiring is dead weight. Keeping them in sync is one logical operation,
so this script does both atomically.

Why this exists: prose-only merge rules in the sync-template skill
("REPLACE the project's local-LLM hook entries with the template's";
"Glob: every scripts/local-llm-*-hook.sh and copy from template")
proved unreliable. The LLM driving the sync hedged on the wiring
trim AND short-circuited the script-copy glob, producing settings
that referenced ghost scripts that did not exist on disk. This
script removes the ambiguity from both ends.

Behavior:
  Wiring (.claude/settings.json):
    - Walks every hooks config in the project. Strips out every entry
      whose command matches `bash scripts/local-llm-*-hook.sh`. Other
      hook entries (project-specific or non-local-LLM template hooks)
      are preserved verbatim.
    - Removes config blocks that become empty after the strip.
    - Then appends fresh config blocks copied from the template, one
      per (event, matcher) pair that the template has local-LLM
      wiring for.
    - Writes the result back with stable 2-space indentation.

  Scripts on disk (scripts/local-llm-*-hook.sh):
    - Copies every local-llm-*-hook.sh from the template's scripts/
      to the project's scripts/ (creating the directory if needed).
    - Deletes any local-llm-*-hook.sh in the project that is NOT in
      the template. The template is the source of truth for the
      hook-script set.
    - File modes are preserved (executable bit copied).

  Post-condition check:
    - After the sync, verifies that every wired hook has its script
      on disk. If anything is still missing, exits non-zero with the
      list of broken refs — this should never happen under normal
      operation, so a failure here means a bug in this script or a
      race with a concurrent edit.

Usage:
    scripts/sync-local-llm-hooks.py <template-settings.json>

Run from the project root (where .claude/settings.json lives).
The template's scripts/ directory is derived from the template
settings.json path: <template-root>/scripts/ where <template-root>
is the parent of the .claude/ directory containing settings.json.

Idempotent — running twice produces the same result as running once.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

# Match any reference to a local-LLM hook script anywhere in the command.
# Older template versions used `bash scripts/foo-hook.sh`; the 2026-05-16
# hook-paths migration switched to `bash "$CLAUDE_PROJECT_DIR/scripts/foo-hook.sh"`.
# Keeping the regex anchored to a specific prefix silently broke this script
# after the migration — every sync became a no-op on the wiring step because
# nothing matched. Match by script basename instead, which is invariant.
LOCAL_LLM_RE = re.compile(r"(local-llm-[a-z0-9-]+-hook\.sh)")
HOOK_SCRIPT_GLOB = "local-llm-*-hook.sh"


def is_local_llm(hook: dict) -> bool:
    return bool(LOCAL_LLM_RE.search(hook.get("command", "")))


def sync_wiring(template: dict, project: dict) -> tuple[int, int]:
    """Mirror template's local-LLM wiring into project. Returns (removed, added)."""
    template_wiring: dict[tuple[str, str], list[dict]] = {}
    for event, configs in template.get("hooks", {}).items():
        for config in configs:
            matcher = config.get("matcher", "")
            for h in config.get("hooks", []):
                if is_local_llm(h):
                    template_wiring.setdefault((event, matcher), []).append(h)

    removed_count = 0
    for event in list(project.get("hooks", {}).keys()):
        kept_configs: list[dict] = []
        for config in project["hooks"][event]:
            kept_hooks = []
            for h in config.get("hooks", []):
                if is_local_llm(h):
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
    """Mirror template's local-LLM hook scripts on disk.

    Returns (copied, deleted) lists of basenames.
    """
    project_scripts_dir.mkdir(parents=True, exist_ok=True)

    template_files = {p.name: p for p in template_scripts_dir.glob(HOOK_SCRIPT_GLOB)}
    project_files = {p.name: p for p in project_scripts_dir.glob(HOOK_SCRIPT_GLOB)}

    copied: list[str] = []
    for name, src in sorted(template_files.items()):
        dst = project_scripts_dir / name
        # Skip if identical (idempotency + faster no-op runs)
        if dst.is_file() and dst.read_bytes() == src.read_bytes():
            continue
        shutil.copy2(src, dst)  # copy2 preserves mode + mtime
        copied.append(name)

    deleted: list[str] = []
    for name in sorted(project_files):
        if name not in template_files:
            (project_scripts_dir / name).unlink()
            deleted.append(name)

    return copied, deleted


def verify_post_sync(project_settings_path: Path, project_scripts_dir: Path) -> list[str]:
    """Return list of wired-but-missing hook script basenames. Empty list = healthy."""
    settings_text = project_settings_path.read_text()
    wired = set(LOCAL_LLM_RE.findall(settings_text))
    missing = [name for name in sorted(wired) if not (project_scripts_dir / name).is_file()]
    return missing


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: sync-local-llm-hooks.py <template-settings.json>",
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

    # Derive template root: <template-settings>/.. = .claude/, ../.. = root
    template_root = template_settings_path.parent.parent
    template_scripts_dir = template_root / "scripts"
    if not template_scripts_dir.is_dir():
        print(f"template scripts/ not found: {template_scripts_dir}", file=sys.stderr)
        return 2

    project_scripts_dir = Path("scripts")

    template = json.loads(template_settings_path.read_text())
    project = json.loads(project_settings_path.read_text())

    # 1. Mirror wiring.
    removed, added = sync_wiring(template, project)
    project_settings_path.write_text(json.dumps(project, indent=2) + "\n")

    # 2. Mirror hook script files on disk.
    copied, deleted = sync_scripts(template_scripts_dir, project_scripts_dir)

    # 3. Verify no wired hook is missing its script. This is the gate that
    #    would have caught the ighweld-2026 ghost-refs regression at sync
    #    time instead of at first-Edit time.
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
        print(f"[FAIL] {len(missing)} wired hook(s) still missing their script:", file=sys.stderr)
        for name in missing:
            print(f"  - scripts/{name}", file=sys.stderr)
        print(
            "This is a bug — wiring referenced scripts the template no longer "
            "ships, or the script-copy step failed. Investigate before running "
            "anything that fires hooks.",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
