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
#     15–25 question anti-drift interview BEFORE source code is touched
#     (base auto-answered by default; fully-human in MANUAL mode — see below).
#
# Why: without a per-spec interview a spec can reach implementation without any
# deliberate pass over its scope, edge cases, error states, and non-goals. That
# is the drift this gate closes — EVERY spec, regardless of track, must carry a
# 15–25 question interview recorded in <spec-dir>/interview.md before code is
# touched.
#
# Two answer modes (see .claude/rules/spec-interview.md):
#   - AUTO  (default) — Claude auto-answers the base 15–25 with the RECOMMENDED
#     option (escalating only genuinely-ambiguous questions to the human), and
#     asks the human the OVERFLOW questions when it judges the spec
#     large/advanced. Auto answers are tagged "**A (auto):**"; human answers are
#     plain "**A:**". Both count toward the floor.
#   - MANUAL — a project that wants the old fully-human behaviour sets
#     SPEC_INTERVIEW_MODE=manual (settings.json env or CLAUDE.local.md). In that
#     mode ONLY human "**A:**" answers count, so auto answers do not unblock
#     code — forcing a genuine human interview.
#
# Artifact contract (must match .claude/rules/spec-interview.md):
#   - File:   <spec-dir>/interview.md
#   - Human answer  = a line beginning with "**A:**"        + non-empty text.
#   - Auto answer   = a line beginning with "**A (auto):**" + non-empty text.
#   - DONE = at least 15 answered questions (the floor of the 15–25 band):
#       AUTO mode   → human + auto answers counted.
#       MANUAL mode → only human answers counted.
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

# 3) Walk up to the .git boundary, collecting: a language marker (anywhere in
#    the path — gates out template/scratch repos), and the spec register
#    (specs/INDEX.md, searched independently because it may live at the repo
#    root while the language marker sits in a subdir — e.g. an extension/ or
#    backend/ package.json with the register at the git root).
DIR=$(dirname "$FILE")
LANG_MARKER=""
GIT_ROOT=""
REGISTER=""
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ] && [ "$DIR" != "." ]; do
  if [ -z "$LANG_MARKER" ]; then
    for marker in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile build.gradle build.gradle.kts pom.xml pubspec.yaml; do
      if [ -f "$DIR/$marker" ]; then LANG_MARKER="$marker"; break; fi
    done
  fi
  [ -z "$LANG_MARKER" ] && ls "$DIR"/*.csproj >/dev/null 2>&1 && LANG_MARKER="*.csproj"
  [ -z "$LANG_MARKER" ] && ls "$DIR"/*.sln >/dev/null 2>&1 && LANG_MARKER="*.sln"
  if [ -z "$REGISTER" ] && [ -f "$DIR/specs/INDEX.md" ]; then
    REGISTER="$DIR/specs/INDEX.md"; PROJECT_ROOT="$DIR"
  fi
  if [ -d "$DIR/.git" ]; then GIT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done

[ -z "$GIT_ROOT" ] && exit 0      # not inside a git repo
[ -z "$LANG_MARKER" ] && exit 0   # template/scratch repo — no code project
[ -z "$REGISTER" ] && exit 0      # no spec register up to the git root

# 4) Parse register + count answered interview questions in Python.
MIN_QUESTIONS="${SPEC_INTERVIEW_MIN:-15}"
INTERVIEW_MODE="${SPEC_INTERVIEW_MODE:-auto}"
RESULT=$(REGISTER_PATH="$REGISTER" PROJECT_ROOT_PATH="$PROJECT_ROOT" MIN_Q="$MIN_QUESTIONS" MODE="$INTERVIEW_MODE" python3 <<'PY' 2>/dev/null
import glob
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
# Answer mode: "manual" counts only human answers; anything else (default
# "auto") counts human + auto answers.
mode = os.environ.get("MODE", "auto").strip().lower()
if mode != "manual":
    mode = "auto"

# Register row, tolerant form. Accepts the canonical
#   "- [x] 003 — search — full track — short goal"
# AND heavily-formatted real-world rows like
#   "- [ ] **364 — inbound-reply (mail / Slack)** — full [hardened] — NOT STARTED"
# We only need the checkbox state + the leading spec id; the id is extracted
# separately (stripping markdown ** and whitespace), and the spec directory is
# resolved by globbing "<id>-*" rather than reconstructing "<id>-<slug>" from a
# possibly-messy slug. Same parser is used by pipeline-state-guard-hook.sh.
row_re = re.compile(r"^-\s+\[([ xX/!])\]\s+(.+?)\s+—\s+.*$")
id_re = re.compile(r"^\**\s*([0-9]+)\b")  # numeric spec ids only — H1/checkpoint rows are skipped

active = None
pending = []
try:
    with open(reg_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            m = row_re.match(line.rstrip())
            if not m:
                continue
            status = m.group(1)
            idm = id_re.match(m.group(2).strip())
            if not idm:
                # Non-numeric id (e.g. "H1" integration-hardening checkpoint) —
                # not a spec, no interview required.
                continue
            spec_id = idm.group(1)
            if status == "/":
                active = spec_id
                break
            if status == " ":
                pending.append(spec_id)
except Exception:
    sys.exit(0)

if active is None and pending:
    active = pending[0]
if active is None:
    # All done or unparseable register — allow.
    sys.exit(0)

spec_id = active

# Resolve spec dir by globbing "<id>-*" so a parenthesized / bold slug in the
# register doesn't break dir resolution.
candidates = sorted(glob.glob(os.path.join(root, "specs", f"{spec_id}-*"))) + \
             sorted(glob.glob(os.path.join(root, ".specify", "specs", f"{spec_id}-*")))
spec_dir = next((c for c in candidates if os.path.isdir(c)), None)
slug = os.path.basename(spec_dir)[len(spec_id) + 1:] if spec_dir else "(not created — run /speckit-specify)"
num = spec_id

interview = os.path.join(spec_dir, "interview.md") if spec_dir else None

# Human answer = "**A:**"; auto answer = "**A (auto):**". The auto marker is
# matched FIRST so an auto line is never miscounted as a human line.
auto_re = re.compile(r"^\s*\*\*A \(auto\):\*\*\s*(.+\S)\s*$")
human_re = re.compile(r"^\s*\*\*A:\*\*\s*(.+\S)\s*$")

human = 0
auto = 0
if interview and os.path.isfile(interview) and os.path.getsize(interview) > 0:
    try:
        with open(interview, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                m = auto_re.match(line)
                if m and len(m.group(1).strip()) >= 2:
                    auto += 1
                    continue
                m = human_re.match(line)
                if m and len(m.group(1).strip()) >= 2:
                    human += 1
    except Exception:
        human = 0
        auto = 0

answered = human if mode == "manual" else human + auto

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
            "human": human,
            "auto": auto,
            "mode": mode,
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
HUMAN=$(printf '%s' "$RESULT" | jq -r '.human')
AUTO=$(printf '%s' "$RESULT" | jq -r '.auto')
MODE=$(printf '%s' "$RESULT" | jq -r '.mode')
MIN=$(printf '%s' "$RESULT" | jq -r '.min')

if [ "$MODE" = "manual" ]; then
  HOWTO="This project runs the interview in MANUAL mode (SPEC_INTERVIEW_MODE=manual), so ONLY human-answered questions count.

To unblock:
  1. Conduct the interview with AskUserQuestion — ONE question per turn, NO auto-pick.
     Cover the categories in .claude/rules/spec-interview.md until you have 15–25 answers.
  2. Record every Q&A in ${INTERVIEW} using this exact shape per question:

       ## Q1 — <short topic>
       **Q:** <the question>
       **A:** <the answer the user gave>

     The hook counts \"**A:**\" lines (human answers) with non-empty text. Auto
     answers (\"**A (auto):**\") do NOT count in manual mode."
else
  HOWTO="This project runs the interview in AUTO mode (the default). You may auto-answer the base 15–25.

To unblock:
  1. Auto-answer the base 15–25 questions with the RECOMMENDED option for each,
     covering the categories in .claude/rules/spec-interview.md. Record each as:

       ## Q1 — <short topic>
       **Q:** <the question>
       **A (auto):** <the recommended answer + one-line reason>

  2. Escalate ONLY the genuinely-ambiguous, spec-affecting questions to the user
     via AskUserQuestion (auto-pick OFF) and record those as human answers:

       **A:** <the answer the user gave>

  3. If you judge this spec LARGE or ADVANCED (hardened triggers: auth / payments /
     PII / upload / new external surface, full-track state machine or concurrency,
     new entity or ≥6 files, or a [hardened] register tag), also ask the user the
     OVERFLOW questions the complexity demands (beyond 25) as human \"**A:**\" answers.

  The hook counts human \"**A:**\" + auto \"**A (auto):**\" lines with non-empty text."
fi

REASON="BLOCKED — anti-drift interview incomplete for active spec ${SPEC_ID}-${SLUG}.

Answered questions: ${ANSWERED} / ${MIN} required (target 15–25).  [mode: ${MODE} · human: ${HUMAN} · auto: ${AUTO}]
Interview file: ${INTERVIEW}
File you tried to edit: ${FILE}

Per .claude/rules/spec-interview.md, EVERY spec — regardless of track — must carry a 15–25 question interview BEFORE source code is touched. The interview is where scope, data model, edge cases, error/empty/loading states, security/authorization, integration points, acceptance criteria, and non-goals get pinned down. Skipping it is exactly how a spec drifts.

${HOWTO}

Once ≥${MIN} questions are counted, source-code edits unlock automatically.

The block scope is strictly source-code extensions. Edits to markdown, config, .claude/**, scripts/**, and specs/** remain allowed — including interview.md itself — so you can write the interview now.

This is NOT a permission stop: do not ask the user whether to run the interview. Run it (per .claude/rules/continuous-execution.md), record the answers, then continue."

jq -n --arg r "$REASON" '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
