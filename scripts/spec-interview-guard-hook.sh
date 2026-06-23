#!/bin/bash
# PreToolUse guard: blocks Edit/Write/MultiEdit on SOURCE-CODE files until the
# project's active spec has a COMPLETED anti-drift interview per
# .claude/rules/spec-interview.md.
#
# Third sibling of the pipeline guards:
#   - spec-register-guard  ensures specs/INDEX.md exists (the register).
#   - pipeline-state-guard ensures the active spec progressed through its
#     pipeline phases (specify → clarify → allium_elicit → plan → tasks).
#   - spec-interview-guard (THIS) ensures the active spec recorded a
#     human-answered interview of 15–25 questions BEFORE source code is touched.
#
# Why: /speckit-clarify runs in auto-pick mode (answers are chosen silently),
# so a spec can reach implementation without a human ever engaging with its
# scope, edge cases, error states, or non-goals. That is the drift this gate
# closes — EVERY spec, regardless of track, must answer 15–25 questions, and
# the answers are recorded in <spec-dir>/interview.md.
#
# Artifact contract (must match .claude/rules/spec-interview.md):
#   - File:   <spec-dir>/interview.md
#   - Each answered question is a line that begins with "**A:**" followed by
#     a non-empty answer (markdown bold answer marker). The hook counts these.
#   - DONE = at least 15 answered questions (the floor of the 15–25 band).
#     25 is guidance, not a hard ceiling — more is fine, the hook never blocks
#     for "too many".
#
# Detection mirrors pipeline-state-guard-hook.sh:
#   - Walks up from the file path to the project root (.git boundary +
#     language marker). Silent on template/scratch repos with no marker.
#   - Reads $PROJECT_ROOT/specs/INDEX.md and picks the active spec
#     (the "- [/]" in-progress row, falling back to the first "- [ ]" row).
#   - Resolves the spec directory and counts answered questions in interview.md.
#
# Allowed without the interview check (so the pipeline itself can run):
#   - anything under specs/, .specify/, .claude/, scripts/
#   - markdown, config, README/CHANGELOG/LICENSE, Dockerfile, .env*, etc.
#   - any non-source-code extension
#
# Returns:
#   - permissionDecision deny when the interview is missing/short (with reason)
#   - silent allow otherwise (and fail-open on any internal error)

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

# 4) Parse register + count answered interview questions in Python.
MIN_QUESTIONS="${SPEC_INTERVIEW_MIN:-15}"
RESULT=$(REGISTER_PATH="$REGISTER" PROJECT_ROOT_PATH="$PROJECT_ROOT" MIN_Q="$MIN_QUESTIONS" python3 <<'PY' 2>/dev/null
import json
import os
import re
import sys

reg_path = os.environ["REGISTER_PATH"]
root = os.environ["PROJECT_ROOT_PATH"]
try:
    min_q = int(os.environ.get("MIN_Q", "15"))
except ValueError:
    min_q = 15

# Register row: "- [x] 003 — search — full track — short goal"
# Track word ("track") is optional to accept both documented and shorthand forms.
# Checkpoint rows (e.g. "H1 — integration-hardening — checkpoint — ...") never
# reach the artifact check because they touch no source code, but if one is the
# active row we still resolve its slug harmlessly.
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
            status, num, slug = m.group(1), m.group(2), m.group(3)
            if status == "/":
                active = (num, slug)
                break
            if status == " ":
                pending.append((num, slug))
except Exception:
    sys.exit(0)

if active is None and pending:
    active = pending[0]
if active is None:
    # All done or unparseable register — allow.
    sys.exit(0)

num, slug = active

# Resolve spec dir
candidates = [
    os.path.join(root, "specs", f"{num}-{slug}"),
    os.path.join(root, ".specify", "specs", f"{num}-{slug}"),
]
spec_dir = next((c for c in candidates if os.path.isdir(c)), None)

interview = os.path.join(spec_dir, "interview.md") if spec_dir else None

answered = 0
if interview and os.path.isfile(interview) and os.path.getsize(interview) > 0:
    try:
        with open(interview, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                # An answered question = a "**A:**" marker with non-empty answer.
                m = re.match(r"^\s*\*\*A:\*\*\s*(.+\S)\s*$", line)
                if m and len(m.group(1).strip()) >= 2:
                    answered += 1
    except Exception:
        answered = 0

if answered >= min_q:
    sys.exit(0)

print(
    json.dumps(
        {
            "spec_id": num,
            "slug": slug,
            "spec_dir": spec_dir if spec_dir else "(missing — run /speckit-specify first)",
            "interview": interview if interview else "(spec dir missing)",
            "answered": answered,
            "min": min_q,
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
SPEC_DIR=$(printf '%s' "$RESULT" | jq -r '.spec_dir')
INTERVIEW=$(printf '%s' "$RESULT" | jq -r '.interview')
ANSWERED=$(printf '%s' "$RESULT" | jq -r '.answered')
MIN=$(printf '%s' "$RESULT" | jq -r '.min')

REASON="BLOCKED — anti-drift interview incomplete for active spec ${SPEC_ID}-${SLUG}.

Answered questions: ${ANSWERED} / ${MIN} required (target 15–25).
Interview file: ${INTERVIEW}
File you tried to edit: ${FILE}

Per .claude/rules/spec-interview.md, EVERY spec — regardless of track — must answer 15–25 questions BEFORE source code is touched. This exists because /speckit-clarify auto-picks its answers silently; the interview is where a human actually pins down scope, data model, edge cases, error/empty/loading states, security/authorization, integration points, acceptance criteria, and non-goals. Skipping it is exactly how a spec drifts.

To unblock:
  1. Conduct the interview with AskUserQuestion — ONE question per turn, NO auto-pick.
     Cover the categories in .claude/rules/spec-interview.md until you have 15–25 answers.
  2. Record every Q&A in ${INTERVIEW} using this exact shape per question:

       ## Q1 — <short topic>
       **Q:** <the question>
       **A:** <the answer the user gave>

     The hook counts lines starting with \"**A:**\" that have a non-empty answer.
  3. Once ≥${MIN} questions are answered, source-code edits unlock automatically.

The block scope is strictly source-code extensions. Edits to markdown, config, .claude/**, scripts/**, and specs/** remain allowed — including interview.md itself — so you can write the interview now.

This is NOT a permission stop: do not ask the user whether to run the interview. Run it (per .claude/rules/continuous-execution.md), record the answers, then continue."

jq -n --arg r "$REASON" '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
