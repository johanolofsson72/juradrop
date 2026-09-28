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
    project-specific script hook the template does not ship are preserved verbatim
    — with ONE exception, added by spec 046: a payload that Claude Code would
    discard is repaired in place. See `repair_payload` below.
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

# --- spec 046: repair payloads Claude Code silently discards ------------------
#
# "Preserved verbatim" is right for what an inline hook SAYS and wrong for
# whether it is heard at all. Two shapes are dropped by the CLI without a word:
#
#   * `hookSpecificOutput` with no `hookEventName` — the field is the schema's
#     discriminator, so the whole object fails to match and is thrown away.
#     Proven live: the same edit was ALLOWED without it and DENIED with it.
#   * a TOP-LEVEL `additionalContext` — "Did you mean
#     hookSpecificOutput.additionalContext (with a hookEventName)?"
#
# The template fixed both in its own settings.json and nothing moved, because
# this file preserves inline hooks verbatim by design. 41 projects were left
# with an inert `.ssh` / `.aws` / `.env` read-block — a security rule that
# looked present in the file and did nothing.
#
# So this is a repair, not an overwrite: it adds a missing field and re-nests a
# misplaced one. It never changes what a hook says, which script it calls, or
# whether it fires, so a project's own inline hooks keep their behaviour and
# gain the one thing they need to be heard.

_MISSING_EVENT = re.compile(
    r'("hookSpecificOutput"\s*:\s*\{)(?!\s*\\?"hookEventName)', re.S)
_MISSING_EVENT_ESC = re.compile(
    r'(\\"hookSpecificOutput\\"\s*:\s*\{)(?!\s*\\\\?"hookEventName)', re.S)


# Inline hooks the TEMPLATE itself shipped, matched by their exact old text so a
# project's own inline hooks are never touched. These were not discarded — they
# worked, on the wrong channel. "Reminder: run dotnet build" fired as a red
# warning on every single .cs edit; the compaction note is an instruction to
# Claude; the PreCompact line has a documented channel of its own (exit-0 stdout
# is appended as compact instructions).
_TEMPLATE_INLINE_MIGRATIONS: list[tuple[str, str, str]] = [
    ("PostToolUse",
     '{"systemMessage": "Reminder: run dotnet build to verify compilation"}',
     '{"hookSpecificOutput":{"hookEventName":"PostToolUse",'
     '"additionalContext":"Reminder: run dotnet build to verify compilation"}}'),
    ("SessionStart",
     '{"systemMessage": "Context was compacted. Re-read any files you were working on before continuing."}',
     '{"hookSpecificOutput":{"hookEventName":"SessionStart",'
     '"additionalContext":"Context was compacted. Re-read any files you were working on before continuing."}}'),
]

# Spec 073 (R9) — the same two inline hooks, made cheap to run. Each gained a precheck that exits
# before any jq when the raw payload cannot match (the read-block runs on every Read/Edit/Write, the
# E2E reminder on every Bash). What they say and when they fire is unchanged. Keyed on the template's
# exact previous text, like the list above, so a project's own inline hooks are never touched; and
# idempotent, because the new text does not contain the old.
_TEMPLATE_INLINE_SPEEDUPS: list[tuple[str, str, str]] = [
    ("PreToolUse",
     "INPUT=$(cat); FILE=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty' 2>/dev/null); if [ -n \"$FILE\" ] && echo \"$FILE\" | grep -qE '(/\\.ssh/|/\\.aws/|/\\.azure/|/\\.git-credentials|/\\.docker/config\\.json|/\\.config/gh/|\\.env$|\\.env\\.)'; then echo '{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"Blocked: access to sensitive files is not allowed\"}}'; fi",
     "INPUT=$(cat); if [ \"${#INPUT}\" -le 4096 ]; then case \"$INPUT\" in *.ssh/*|*.aws/*|*.azure/*|*.git-credentials*|*.docker/config.json*|*.config/gh/*|*.env*) ;; *) exit 0 ;; esac; fi; FILE=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty' 2>/dev/null); if [ -n \"$FILE\" ] && echo \"$FILE\" | grep -qE '(/\\.ssh/|/\\.aws/|/\\.azure/|/\\.git-credentials|/\\.docker/config\\.json|/\\.config/gh/|\\.env$|\\.env\\.)'; then echo '{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"Blocked: access to sensitive files is not allowed\"}}'; fi"),
    ("PostToolUse",
     "INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r '.tool_input.command // empty' 2>/dev/null); EXIT=$(echo \"$INPUT\" | jq -r '.tool_response.interrupted // false' 2>/dev/null); if echo \"$CMD\" | grep -qiE '(Category=UI|playwright|npx playwright|pnpm.*playwright|yarn.*playwright|maestro|patrol|integration_test|flutter drive)'; then jq -n '{hookSpecificOutput: {hookEventName: \"PostToolUse\", additionalContext: \"UI / E2E TESTS COMPLETED — BLOCKING VALIDATION REQUIRED before declaring work done:\\n\\n(1) SPEC COMPLIANCE: Open the feature spec and its FUNCTIONAL COVERAGE section. Enumerate every implemented function. Confirm each has a passing test (browser / Maestro / Patrol / widget) AND that the assertion actually verifies the spec behavior (not just that the screen rendered). If ANY function lacks a real test, the task is NOT done — write the missing tests now.\\n\\n(2) DESIGN COMPLIANCE: Invoke the frontend-design skill via the Skill tool and verify the UI follows its recommendations (typography scale, spacing rhythm, color palette, component polish, accessibility, responsive / safe-area behavior, distinctive design — not generic AI aesthetic). If any violations exist, fix them before declaring done.\\n\\nDo NOT skip either step. Do NOT declare the task complete until both validations pass. Report findings explicitly: which functions were verified, which design checks passed/failed.\"}}'; fi",
     "INPUT=$(cat); printf '%s' \"$INPUT\" | grep -qiE '(Category=UI|playwright|maestro|patrol|integration_test|flutter drive)' || exit 0; CMD=$(echo \"$INPUT\" | jq -r '.tool_input.command // empty' 2>/dev/null); EXIT=$(echo \"$INPUT\" | jq -r '.tool_response.interrupted // false' 2>/dev/null); if echo \"$CMD\" | grep -qiE '(Category=UI|playwright|npx playwright|pnpm.*playwright|yarn.*playwright|maestro|patrol|integration_test|flutter drive)'; then jq -n '{hookSpecificOutput: {hookEventName: \"PostToolUse\", additionalContext: \"UI / E2E TESTS COMPLETED — BLOCKING VALIDATION REQUIRED before declaring work done:\\n\\n(1) SPEC COMPLIANCE: Open the feature spec and its FUNCTIONAL COVERAGE section. Enumerate every implemented function. Confirm each has a passing test (browser / Maestro / Patrol / widget) AND that the assertion actually verifies the spec behavior (not just that the screen rendered). If ANY function lacks a real test, the task is NOT done — write the missing tests now.\\n\\n(2) DESIGN COMPLIANCE: Invoke the frontend-design skill via the Skill tool and verify the UI follows its recommendations (typography scale, spacing rhythm, color palette, component polish, accessibility, responsive / safe-area behavior, distinctive design — not generic AI aesthetic). If any violations exist, fix them before declaring done.\\n\\nDo NOT skip either step. Do NOT declare the task complete until both validations pass. Report findings explicitly: which functions were verified, which design checks passed/failed.\"}}'; fi"),
]


# PreCompact is special: its documented channel is plain stdout, not JSON.
#
# Matched by SHAPE, not by exact text. The first version of this compared the
# whole string and missed cv, whose copy drifted by three words ("modified
# files, error messages, and current task context" — no "test commands").
# Projects edit these notes; a migration keyed to one exact wording repairs the
# projects that never touched theirs and silently skips the ones that did.
_PRECOMPACT_RE = re.compile(
    r"""echo\s+'\{"systemMessage":\s*"(?P<body>[^"]*Preserve the full list[^"]*)"\}'""")


def migrate_template_inline(cmd: str, event: str) -> tuple[str, list[str]]:
    notes: list[str] = []
    if event == "PreCompact":
        m = _PRECOMPACT_RE.search(cmd)
        if m:
            return (cmd[:m.start()] + 'echo "%s"' % m.group("body") + cmd[m.end():],
                    ["PreCompact note -> stdout"])
    for ev, old, new in _TEMPLATE_INLINE_MIGRATIONS:
        if ev == event and old in cmd:
            cmd = cmd.replace(old, new)
            notes.append("systemMessage -> additionalContext")
    for ev, old, new in _TEMPLATE_INLINE_SPEEDUPS:
        if ev == event and cmd == old:
            cmd = new
            notes.append("spec 073 precheck added")
    return cmd, notes


def repair_payload(cmd: str, event: str) -> tuple[str, list[str]]:
    """Return (repaired command, list of what was repaired)."""
    notes: list[str] = []
    if "hookSpecificOutput" not in cmd:
        return cmd, notes

    # Escaped form first (a JSON string inside a shell single-quoted echo, as
    # settings.json stores it); then the plain form.
    for rx, ins in ((_MISSING_EVENT_ESC, '\\1\\\\"hookEventName\\\\": \\\\"%s\\\\", ' % event),
                    (_MISSING_EVENT, '\\1"hookEventName": "%s", ' % event)):
        if "hookEventName" in cmd:
            break
        new = rx.sub(ins, cmd, count=1)
        if new != cmd:
            cmd = new
            notes.append(f"added hookEventName={event}")
            break
    return cmd, notes



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

    # 2b. Repair payloads the CLI would discard — inline hooks included.
    repaired: list[str] = []
    for event, configs in project.get("hooks", {}).items():
        for config in configs:
            for h in config.get("hooks", []):
                cmd = h.get("command", "")
                if not cmd:
                    continue
                new, notes = migrate_template_inline(cmd, event)
                new2, notes2 = repair_payload(new, event)
                new, notes = new2, notes + notes2
                if notes:
                    h["command"] = new
                    repaired.append(f"{event}: {'; '.join(notes)} — {cmd[:60]}")

    project_path.write_text(json.dumps(project, indent=2) + "\n")

    # 3. Post-check: every wired core hook has its scripts on disk.
    settings_text = project_path.read_text()
    dangling = sorted(
        n for n in SCRIPT_RE.findall(settings_text)
        if not is_managed_elsewhere(n) and not (project_scripts / n).is_file()
    )

    print(f"core-hooks: removed {removed} stale, added {added} from template")
    if repaired:
        print(f"repaired {len(repaired)} hook payload(s) the CLI would have discarded:")
        for r in repaired:
            print(f"  - {r}")
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
