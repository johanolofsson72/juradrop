#!/bin/bash
# PreToolUse guard: blocks Edit/Write/MultiEdit on SOURCE-CODE files when the
# project's active spec hasn't completed its required pipeline phases per
# .claude/rules/feature-pipeline.md.
#
# Companion to spec-register-guard-hook.sh:
#   - spec-register-guard ensures specs/INDEX.md exists (the register).
#   - pipeline-state-guard ensures the active spec has progressed through its
#     required phases (specify → clarify → allium_elicit → plan → tasks)
#     BEFORE source-code edits are allowed.
#
# Detection:
#   - Walks up from the file path to find the project root (.git boundary +
#     language marker). Silent on template/scratch repos with no marker.
#   - Reads $PROJECT_ROOT/specs/INDEX.md and picks the active spec
#     (the "- [/]" in-progress row, falling back to the first "- [ ]" row).
#   - Parses the track (full / light / spec-only) from the register row.
#   - Inspects the spec directory ($PROJECT_ROOT/specs/<id>-<slug>/ or
#     $PROJECT_ROOT/.specify/specs/<id>-<slug>/) for required artifacts.
#
# Required artifacts per track:
#   - full / light : spec.md (with "## Clarifications"), spec.allium, plan.md, tasks.md
#   - spec-only    : spec.md (with "## Clarifications"), plan.md, tasks.md
#
# /speckit.analyze is intentionally NOT in the artifact check — analyze
# produces no clear on-disk artifact (it edits spec/plan/tasks in place).
# The UserPromptSubmit reminder hook (emit-analyze-reminder.sh) plus the
# rule in feature-pipeline.md cover that phase.
#
# Allowed without state check (so the pipeline itself can run):
#   - anything under specs/, .specify/, .claude/, scripts/
#   - markdown, config, README/CHANGELOG/LICENSE, Dockerfile, .env*, etc.
#   - any non-source-code extension
#
# Returns:
#   - permissionDecision deny on missing phases (with specific reason)
#   - silent allow otherwise

set -u

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# 1) Path allowlist — pipeline-running edits and tooling pass through
case "$FILE" in
  */specs/*|*/.specify/*) exit 0 ;;
  */.claude/*) exit 0 ;;
  */scripts/*) exit 0 ;;
  */CLAUDE.md|*/CLAUDE.local.md|*/README*|*/LICENSE*|*/CHANGELOG*) exit 0 ;;
  */.gitignore|*/.env|*/.env.*|*/.editorconfig|*/.gitattributes) exit 0 ;;
  */Dockerfile|*/docker-compose*|*/.dockerignore) exit 0 ;;
esac

# 2) Extension allowlist — only block clearly-source-code extensions
EXT="${FILE##*.}"
EXT_LC=$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')
case "$EXT_LC" in
  cs|ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|rb|php|swift|kt|kts|cpp|cxx|cc|c|h|hpp|hxx|razor|cshtml|vbhtml|vue|svelte|astro|dart|scala|clj|cljs|ex|exs|erl|hrl|fs|fsx|fsi|hs|elm|lua|jl|nim|zig|sh|bash|zsh|pl|pm)
    ;;
  *)
    exit 0
    ;;
esac

# 3) Walk up to find project root + language marker
DIR=$(dirname "$FILE")
LANG_MARKER=""
PROJECT_ROOT=""
REPO_FOUND=0
while [ "$DIR" != "/" ] && [ -n "$DIR" ] && [ "$DIR" != "." ]; do
  if [ -z "$LANG_MARKER" ]; then
    for marker in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile build.gradle build.gradle.kts pom.xml pubspec.yaml; do
      if [ -f "$DIR/$marker" ]; then LANG_MARKER="$marker"; PROJECT_ROOT="$DIR"; break; fi
    done
  fi
  if [ -z "$LANG_MARKER" ] && ls "$DIR"/*.csproj >/dev/null 2>&1; then
    LANG_MARKER="*.csproj"; PROJECT_ROOT="$DIR"
  fi
  if [ -z "$LANG_MARKER" ] && ls "$DIR"/*.sln >/dev/null 2>&1; then
    LANG_MARKER="*.sln"; PROJECT_ROOT="$DIR"
  fi
  if [ -d "$DIR/.git" ]; then
    REPO_FOUND=1
    [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done

[ "$REPO_FOUND" -eq 0 ] && exit 0
[ -z "$LANG_MARKER" ] && exit 0

REGISTER="$PROJECT_ROOT/specs/INDEX.md"
[ ! -f "$REGISTER" ] && exit 0

# 4) Parse register + check artifacts in Python (regex + filesystem)
RESULT=$(REGISTER_PATH="$REGISTER" PROJECT_ROOT_PATH="$PROJECT_ROOT" python3 <<'PY' 2>/dev/null
import json
import os
import re
import sys

reg_path = os.environ["REGISTER_PATH"]
root = os.environ["PROJECT_ROOT_PATH"]

# Register row: "- [x] 003 — search — full track — short goal"
# Track word ("track") is optional to accept both documented and shorthand forms.
row_re = re.compile(
    r"^-\s+\[(.)\]\s+(\S+)\s+—\s+(\S+)\s+—\s+(\S+)(?:\s+track)?\s+—.*$"
)

active = None
pending = []
try:
    with open(reg_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            m = row_re.match(line.rstrip())
            if not m:
                continue
            status, num, slug, track = m.group(1), m.group(2), m.group(3), m.group(4)
            if status == "/":
                active = (num, slug, track)
                break
            if status == " ":
                pending.append((num, slug, track))
except Exception:
    sys.exit(0)

if active is None and pending:
    active = pending[0]
if active is None:
    # All done or unparseable register — allow.
    sys.exit(0)

num, slug, track = active
track = track.lower().strip()
if track not in ("full", "light", "spec-only"):
    track = "full"  # most conservative

# Resolve spec dir
candidates = [
    os.path.join(root, "specs", f"{num}-{slug}"),
    os.path.join(root, ".specify", "specs", f"{num}-{slug}"),
]
spec_dir = next((c for c in candidates if os.path.isdir(c)), None)

needs_allium = track in ("full", "light")
required = ["specify", "clarify"]
if needs_allium:
    required.append("allium_elicit")
required += ["plan", "tasks"]

missing = []

if spec_dir is None:
    missing = required[:]
else:
    spec_md = os.path.join(spec_dir, "spec.md")
    plan_md = os.path.join(spec_dir, "plan.md")
    tasks_md = os.path.join(spec_dir, "tasks.md")
    allium_file = os.path.join(spec_dir, "spec.allium")

    spec_text = ""
    if os.path.isfile(spec_md) and os.path.getsize(spec_md) > 0:
        try:
            with open(spec_md, "r", encoding="utf-8", errors="ignore") as f:
                spec_text = f.read()
        except Exception:
            spec_text = ""
    else:
        missing.append("specify")

    if "specify" not in missing:
        if not re.search(
            r"^\s*##+\s*Clarifications?\b",
            spec_text,
            flags=re.MULTILINE | re.IGNORECASE,
        ):
            missing.append("clarify")
    else:
        missing.append("clarify")

    if needs_allium and not os.path.isfile(allium_file):
        missing.append("allium_elicit")

    if not os.path.isfile(plan_md):
        missing.append("plan")
    if not os.path.isfile(tasks_md):
        missing.append("tasks")

    order = {p: i for i, p in enumerate(required)}
    missing = sorted(set(missing), key=lambda p: order.get(p, 999))

if not missing:
    sys.exit(0)

print(
    json.dumps(
        {
            "spec_id": num,
            "slug": slug,
            "track": track,
            "spec_dir": spec_dir if spec_dir else "(missing — run /specify first)",
            "missing": missing,
        }
    )
)
sys.exit(99)
PY
)
RC=$?

# Allow on any unexpected exit (fail-open — never break the user's workflow
# because of a tooling bug in this hook).
if [ "$RC" -ne 99 ]; then
  exit 0
fi

SPEC_ID=$(printf '%s' "$RESULT" | jq -r '.spec_id')
SLUG=$(printf '%s' "$RESULT" | jq -r '.slug')
TRACK=$(printf '%s' "$RESULT" | jq -r '.track')
SPEC_DIR=$(printf '%s' "$RESULT" | jq -r '.spec_dir')
MISSING=$(printf '%s' "$RESULT" | jq -r '.missing | join(", ")')

REASON="BLOCKED — pipeline phases incomplete for active spec ${SPEC_ID}-${SLUG} (${TRACK} track).

Missing phases: ${MISSING}
Spec directory: ${SPEC_DIR}
File you tried to edit: ${FILE}

Per .claude/rules/feature-pipeline.md, the full pipeline runs end-to-end as ONE task before source code is touched. You are trying to edit source code while the active spec has unfinished pipeline phases. Run them in order:

  1. /specify         → produces spec.md
  2. /clarify         → adds a Clarifications section to spec.md
  3. /allium:elicit   → produces spec.allium  (full/light tracks only)
  4. /plan            → produces plan.md
  5. /tasks           → produces tasks.md
  6. /speckit.analyze → consistency check + auto-apply remediation
  7. /implement       → source-code edits become allowed once tasks.md exists

The block scope is strictly source-code extensions. Edits to markdown, config, .claude/**, scripts/**, and specs/** remain allowed — including the spec/plan/tasks files themselves, so the pipeline can produce its artifacts.

If this is genuinely a trivial fix (typo, one-line bug, single-variable rename), classify it explicitly in your first sentence and edit a non-source file path, OR finish the active spec, tick it off in the register, and start the next one."

jq -n --arg r "$REASON" '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
