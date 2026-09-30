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

# The extensions this guard blocks. One list, read by both the raw precheck below and step 2, so the
# precheck can never quietly disagree with the test it stands in front of. Markup and stylesheets are
# source too (spec 032): fundit's 016a shipped a whole static site as .html/.css with no spec at all.
# The three path guards carry this list byte-identical; test-spec-dir-absent.sh fails if one drifts.
SOURCE_EXTS='cs|ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|rb|php|swift|kt|kts|cpp|cxx|cc|c|h|hpp|hxx|razor|cshtml|vbhtml|vue|svelte|astro|dart|scala|clj|cljs|ex|exs|erl|hrl|fs|fsx|fsi|hs|elm|lua|jl|nim|zig|sh|bash|zsh|pl|pm|html|htm|css|scss|sass|less'

# Cheapest exit first (spec 073, R9). This hook runs on every Edit/Write in every project, and nearly
# every one of those is to a file it ignores — but the extension test in step 2 needs FILE, and FILE
# costs a jq process. The raw payload already rules most edits out: a path ending in a source
# extension appears in the JSON as `.<ext>"`, because JSON escaping never touches letters, dots or
# the closing quote. So an input without one cannot pass step 2 either. The converse is not claimed —
# a match means only "look properly", and steps 1-2 still decide. Case-folded because step 2
# lower-cases the extension.
#
# Bounded to small payloads on purpose. Bash's matchers are slow on long strings — measured, a 200 KB
# Write took longer to scan than jq takes to start — so a large payload skips the precheck and goes
# straight to the exact test, at exactly the cost it had before.
if [ "${#INPUT}" -le 4096 ]; then
  shopt -s nocasematch
  [[ $INPUT =~ \.($SOURCE_EXTS)\" ]] || exit 0
  shopt -u nocasematch
fi

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
[[ $EXT_LC =~ ^($SOURCE_EXTS)$ ]] || exit 0

# 3) Walk up to the .git boundary, collecting: a language marker (anywhere in
#    the path — gates out template/scratch repos), and the spec register
#    (specs/INDEX.md, searched independently because it may live at the repo
#    root while the language marker sits in a subdir — e.g. an extension/ or
#    backend/ package.json with the register at the git root).
# Builtin stand-in for `ls "$DIR"/*.csproj >/dev/null 2>&1` (spec 073, R9): true when the glob
# matched anything. The walk below visits every directory from the file up to the git root, and an
# `ls` plus a `dirname` per level was most of this hook's own cost — processes, not work.
has_match() { local f; for f in "$@"; do { [ -e "$f" ] || [ -L "$f" ]; } && return 0; done; return 1; }
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
  [ -z "$LANG_MARKER" ] && has_match "$DIR"/*.csproj && LANG_MARKER="*.csproj"
  [ -z "$LANG_MARKER" ] && has_match "$DIR"/*.sln && LANG_MARKER="*.sln"
  if [ -z "$REGISTER" ] && [ -f "$DIR/specs/INDEX.md" ]; then
    REGISTER="$DIR/specs/INDEX.md"; PROJECT_ROOT="$DIR"
  fi
  if [ -d "$DIR/.git" ]; then GIT_ROOT="$DIR"; break; fi
  # `dirname` without the process: "/a/b" -> "/a", "/a" -> "/", "a" -> ".".
  case "$DIR" in */*) DIR="${DIR%/*}"; [ -n "$DIR" ] || DIR="/" ;; *) DIR="." ;; esac
done

[ -z "$GIT_ROOT" ] && exit 0      # not inside a git repo
[ -z "$LANG_MARKER" ] && exit 0   # template/scratch repo — no code project
[ -z "$REGISTER" ] && exit 0      # no spec register up to the git root

# 3b) MID-MERGE (row 059, agentcrm F094). Ticking a row moves "the active spec" on, and the merge that
# closes the previous row finishes AFTER the tick — so an edit the merge still needs was judged against
# a spec that had not started, and denied. While MERGE_HEAD exists, a file that either side of the
# merge changed since the merge base is part of finishing that merge, not new work, and passes.
# Scoped to that set on purpose: "any edit while a merge is open" would make `git merge --no-commit`
# a way past this guard. A file neither side touched is judged as usual. If git cannot answer, the
# check falls through to the normal verdict — never to allow.
if git -C "$GIT_ROOT" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  REL="${FILE#"$GIT_ROOT"/}"
  MERGE_FILES=$(git -C "$GIT_ROOT" diff --name-only HEAD...MERGE_HEAD 2>/dev/null
                git -C "$GIT_ROOT" diff --name-only MERGE_HEAD...HEAD 2>/dev/null)
  grep -qxF -- "$REL" <<< "$MERGE_FILES" && exit 0
fi

# 4) Parse register + check artifacts in Python (regex + filesystem)
HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

RESULT=$(PROJECT_ROOT_PATH="$PROJECT_ROOT" HOOK_DIR="$HOOK_DIR" python3 <<'PY' 2>/dev/null
import glob
import json
import os
import re
import sys

root = os.environ["PROJECT_ROOT_PATH"]


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

# An unrecognized ID FORM is not the same fact as "the register could not be
# read", and merging them cost a project 56 register rows (consultpilot H7b). 98's
# text says the resolver could not be loaded or the register could not be parsed
# — both healthy, every time — so the reader was sent to verify a file that was
# fine while the actual defect (the id grammar) stood for 18 days. Consultpilot
# fixed it locally and two template syncs reverted it, because the fix never
# lived here (spec 076, found as consultpilot Q2 / H7ai).
#
# Still DENY. Without a usable id there is no way to tell whether this row owes
# artifacts, and answering "allow" would be choosing the checkpoint reading with
# no evidence — fail-open, the defect 007m was opened for.
if kind == "unparseable":
    print(json.dumps({"token": info["id"], "status": info["status"]}))
    sys.exit(97)

num = info["id"]
track = info["track"]
spec_dir = os.path.join(root, info["dir"]) if info["dir"] else None
slug = info["slug"] if info["found"] else "(not created — run /speckit-specify)"

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

# 97 — the register was READ, the active row was FOUND, and only its id token is
# outside the grammar. Deny (same verdict as 98) but never the same text: 98's
# text sends the reader to check that scripts/spec_active.py exists, and here it
# does. See the comment at the sys.exit(97) above.
if [ "$RC" -eq 97 ]; then
  TOKEN=$(printf '%s' "$RESULT" | jq -r '.token // "(empty)"')
  ROWSTATUS=$(printf '%s' "$RESULT" | jq -r '.status // "?"')
  REASON="BLOCKED — the active register row has an id this parser does not recognise: \"${TOKEN}\"

The register at ${REGISTER} was read without error and the active row (status \"[${ROWSTATUS}]\") was found. Its track, owner and slug all parsed. The ONE thing that failed is sorting the id token into a known form, and without that there is no way to tell whether this row owes pipeline artifacts (a spec) or owes none (a checkpoint).

This denies rather than guesses. Guessing 'no artifacts owed' is fail-open, which is the defect the resolver was written to remove.

The id grammar lives in scripts/spec_active.py (NUMERIC_ID_RE / ALPHA_ID_RE):
  numeric-led : 007, 007m, 007ab, 501.1
  letter-led  : H1, H6a, H6s2, F2b        (letters, then a digit, then anything alphanumeric)
Anything else — a hyphen, letters with no digit, a dot anywhere but between digits — is malformed.

To fix, do ONE of:
  1. Correct the row's id in specs/INDEX.md to one of the two forms above.
  2. If \"${TOKEN}\" IS the house convention and the grammar is what is behind,
     widen the grammar in scripts/spec_active.py and add a case to
     scripts/test-register-ids.sh so it cannot narrow again.
  Check either with:  bash scripts/validate-register-ids.sh

Markdown, config, .claude/**, scripts/** and specs/** edits remain allowed, so you can fix the register or the grammar right now."
  jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
fi

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
    "hookEventName": "PreToolUse",
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

jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
