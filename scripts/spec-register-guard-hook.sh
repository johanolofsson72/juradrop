#!/bin/bash
# PreToolUse guard: blocks Edit/Write/MultiEdit on source code when no spec
# register (specs/INDEX.md) exists in the project. Per .claude/rules/spec-register.md
# the register MUST exist before any development starts.
#
# Allowed without register (so bootstrap can happen):
#   - The register itself and anything under specs/
#   - .claude/**, scripts/**
#   - Markdown, README/CHANGELOG/LICENSE/CLAUDE.md
#   - .gitignore, .env*, .editorconfig, Dockerfile, docker-compose*
#   - Anything that is not in the source-code extension allowlist below
#
# Detection of "this is a real project":
#   - Walks up from the file path until it hits a .git directory (repo root).
#   - Along the way, looks for a language marker (package.json, *.csproj, etc.).
#   - If no .git is reached, or the repo has no language marker, the hook is
#     silent — this protects the template repo and scratch dirs from false
#     positives.

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

# 1) Path-based allow list — always pass these through, no register needed
case "$FILE" in
  */specs/*) exit 0 ;;
  */.claude/*) exit 0 ;;
  */scripts/*) exit 0 ;;
  */CLAUDE.md|*/CLAUDE.local.md|*/README*|*/LICENSE*|*/CHANGELOG*) exit 0 ;;
  */.gitignore|*/.env|*/.env.*|*/.editorconfig|*/.gitattributes) exit 0 ;;
  */Dockerfile|*/docker-compose*|*/.dockerignore) exit 0 ;;
esac

# 2) Extension-based allow list — only block clearly-source-code extensions
EXT="${FILE##*.}"
EXT_LC=$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')
[[ $EXT_LC =~ ^($SOURCE_EXTS)$ ]] || exit 0

# 3) Walk up from the file's dir to the .git boundary, collecting three separate
#    things. They are separate on purpose: this hook used to conflate the first
#    two and pinned the "project root" to whichever directory happened to hold a
#    language marker. On the template's own recommended .NET layout — a solution
#    with src/<Project>/<Project>.csproj — that is the csproj directory, so a repo
#    with a perfectly good specs/INDEX.md at its root got every source edit under
#    src/ denied, with instructions to create a SECOND register at
#    src/<Project>/specs/INDEX.md. An agent that followed them produced exactly
#    the nested bogus register the message asked for.
#
#      LANG_MARKER  is this a real project at all (anywhere in the walk)
#      REGISTER     a specs/INDEX.md anywhere between the file and the git root
#      GIT_ROOT     where a register belongs when there is none
#
#    pipeline-state-guard and spec-interview-guard already resolve it this way,
#    and .claude/rules/spec-register.md requires all three to agree — three gates
#    that disagree about which spec you are on block work for opposite reasons.
# Builtin stand-in for `ls "$DIR"/*.csproj >/dev/null 2>&1` (spec 073, R9): true when the glob
# matched anything. The walk below visits every directory from the file up to the git root, and an
# `ls` plus a `dirname` per level was most of this hook's own cost — processes, not work.
has_match() { local f; for f in "$@"; do { [ -e "$f" ] || [ -L "$f" ]; } && return 0; done; return 1; }
DIR=$(dirname "$FILE")
LANG_MARKER=""
REGISTER=""
GIT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ] && [ "$DIR" != "." ]; do
  if [ -z "$LANG_MARKER" ]; then
    for marker in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile build.gradle build.gradle.kts pom.xml pubspec.yaml; do
      if [ -f "$DIR/$marker" ]; then LANG_MARKER="$marker"; break; fi
    done
  fi
  if [ -z "$LANG_MARKER" ]; then
    if has_match "$DIR"/*.csproj; then LANG_MARKER="*.csproj"; fi
  fi
  if [ -z "$LANG_MARKER" ]; then
    if has_match "$DIR"/*.sln; then LANG_MARKER="*.sln"; fi
  fi
  if [ -z "$REGISTER" ] && [ -f "$DIR/specs/INDEX.md" ]; then REGISTER="$DIR/specs/INDEX.md"; fi
  if [ -d "$DIR/.git" ]; then GIT_ROOT="$DIR"; break; fi
  # `dirname` without the process: "/a/b" -> "/a", "/a" -> "/", "a" -> ".".
  case "$DIR" in */*) DIR="${DIR%/*}"; [ -n "$DIR" ] || DIR="/" ;; *) DIR="." ;; esac
done

# Not in a git repo OR no language marker in this repo → silent (template/scratch)
[ -z "$GIT_ROOT" ] && exit 0
[ -z "$LANG_MARKER" ] && exit 0

# 4) Register check — any register between the file and the git root satisfies it.
if [ -n "$REGISTER" ]; then
  exit 0
fi

# There is none, so name the place it belongs: the repo root, never whichever
# subdirectory happened to carry the language marker.
PROJECT_ROOT="$GIT_ROOT"

# 5) Block — no register, but this is a code project and a code file edit
REASON="BLOCKED — no spec register at ${PROJECT_ROOT}/specs/INDEX.md. Per .claude/rules/spec-register.md, a register MUST exist BEFORE any development. This project has a language marker (${LANG_MARKER}) and you are about to edit a source file (${FILE}).

Bootstrap the register first:
  1. Use AskUserQuestion to identify the initial set of specs and their order.
  2. Triage each per .claude/rules/specs.md (full / light / spec-only).
  3. Write ${PROJECT_ROOT}/specs/INDEX.md with the register + a dated Register history entry.
  4. git commit + git push origin main.
  5. THEN start spec 001 with /specify.

Edits ALLOWED while no register exists: anything under specs/, .claude/**, scripts/**, README/CHANGELOG/LICENSE/CLAUDE.md, .gitignore, .env*, .editorconfig, Dockerfile, docker-compose*, and any non-source-code extension (markdown, yaml, json, toml, etc.). The block is scoped strictly to source code."

jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
