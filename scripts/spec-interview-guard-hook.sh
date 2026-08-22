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
HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

RESULT=$(PROJECT_ROOT_PATH="$PROJECT_ROOT" MIN_Q="$MIN_QUESTIONS" MODE="$INTERVIEW_MODE" HOOK_DIR="$HOOK_DIR" python3 <<'PY' 2>/dev/null
import glob
import json
import os
import re
import sys

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


# Spec 007m — resolve the active spec through the ONE canonical resolver.
#
# This block used to carry its own copy of the register parser, and its id regex
# was numeric-only:  r"^\**\s*([0-9]+)\b".  "\b" is a word boundary and there is
# none between "7" and "m", so "007m" matched NOTHING and every letter-suffixed
# row (004a, 007a..007o) was skipped exactly like an H1 checkpoint. The loop then
# settled on the next NUMERIC row and demanded ITS artifacts, so when that later
# spec's artifacts happened to exist this guard APPROVED source edits for a spec
# that had none. Fixed once (spec 004a, 9e32986) and reverted by a template
# autosync (e17fd50) because this file is in CORE_SCRIPTS — each guard carrying
# its own copy is what made the revert invisible. The lane-ownership rules moved
# into the module with it, so both guards and the orientation hook share one
# implementation and cannot drift apart again.
#
# Imported into THIS interpreter rather than shelled out to: `python3 -c pass`
# costs ~50 ms and this hook fires on every source edit; resolution is ~2 ms.
sys.path.insert(0, os.environ["HOOK_DIR"])
try:
    from spec_active import RegisterUnreadable, resolve
except Exception:
    # A gate that cannot establish what it is guarding must NOT allow.
    sys.exit(98)

try:
    info = resolve(root)
except RegisterUnreadable:
    sys.exit(98)

kind = info["kind"]

# "No active row" is an ANSWER (every row ticked), not a resolution failure.
if kind == "none":
    sys.exit(0)

# A checkpoint (H1) is not a spec. The old code's comment claimed this exemption,
# but `continue` meant "keep looking", so the loop landed on the next numeric
# spec and demanded ITS artifacts — an H1 checkpoint denied every edit while
# citing a spec nobody was working on.
if kind == "checkpoint":
    sys.exit(0)

if kind == "unparseable":
    sys.exit(98)

spec_id = info["id"]
spec_dir = os.path.join(root, info["dir"]) if info["dir"] else None
slug = info["slug"] if info["found"] else "(not created — run /speckit-specify)"
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

# Fail CLOSED when resolution itself fails (spec 007m FR-007m-04).
#
# A register exists and names an active spec, but we could not work out which
# spec that is (shared resolver missing/unimportable, or a malformed register).
# A gate that cannot establish what it is guarding must not wave work through.
# Note the deliberate asymmetry: "the resolver answered NONE" (every row ticked)
# is an answer and allows; only "the resolver could not answer" denies.
if [ "$RC" -eq 98 ]; then
  cat <<JSON
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED — cannot determine which spec is active.\n\nA spec register exists at $REGISTER, but the canonical resolver (scripts/spec_active.py) could not be loaded or the register could not be parsed.\n\nThis guard fails CLOSED on resolution failure by design: a gate that cannot establish what it is guarding must not allow edits. Before this, a resolution failure silently allowed everything — which is how a numeric-only spec-id parser approved source edits for specs with zero artifacts, unnoticed, for ten days.\n\nTo fix:\n  1. Confirm scripts/spec_active.py exists next to this hook and is readable.\n     (If a template sync removed it, re-run the sync — it is in CORE_SCRIPTS.)\n  2. Check specs/INDEX.md parses: bash scripts/resolve-active-spec.sh\n     Exit 0 = resolved · 3 = no active row (fine) · 4 = cannot answer.\n  3. Confirm the active row matches the register format:\n     - [/] 007m — prereq-spec-resolution — spec-only track — goal\n\nMarkdown, config, .claude/**, scripts/** and specs/** edits remain allowed, so you can fix the tooling or the register right now."
  }
}
JSON
  exit 0
fi

# Allow on any other unexpected exit (fail-open — never break the user's workflow
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
