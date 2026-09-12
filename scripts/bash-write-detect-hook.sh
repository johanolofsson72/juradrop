#!/usr/bin/env bash
# PostToolUse detector on Bash: reports source-file writes the pipeline guard would have denied, no matter
# how the command spelled them (row H7b).
#
# WHY A SECOND LAYER
# ------------------
# scripts/bash-write-guard-hook.sh reads the command string, and a string parser has a hard ceiling: it
# cannot see a write performed inside `python3 - <<PY`, behind `eval`, through `xargs`, or via a path built
# from a variable at runtime. Shipping only that layer would be partial coverage that LOOKS complete —
# which is the failure class this register row was carved out of.
#
# This layer does not read the command. It compares the filesystem against a marker stamped before the
# command ran, and asks the guards about whatever actually changed. How the write was spelled is then
# irrelevant, which is the whole point.
#
# IT ASKS ALL FIVE GUARDS — IT USED TO ASK THREE (row S5)
# -------------------------------------------------------
# The claim above was false for two years' worth of paths. This layer asked spec-register,
# pipeline-state and spec-interview, and all three exit early on scripts/**, .claude/** and specs/**
# by design. The two guards that own exactly those paths — core-machinery and core-owed-tick — were
# in the PRE-layer's delegate list and missing from this one.
#
# So the pre-layer's header, which sends every uncovered form here, was writing a cheque this file
# did not honour: a CORE file changed by an interpreter passed BOTH layers in silence. Measured
# 2026-09-02 — with a CORE file touched and the marker stamped, this hook said nothing, while
# core-machinery-guard-hook.sh asked directly about the same path answered `deny`. A register tick
# went through that gap for real.
#
# The list is now the pre-layer's five, in the pre-layer's order. Two readings of "which guard
# speaks first" that could differ is the trap spec 007m's regression came out of.
#
# PREVENTION vs DETECTION — stated plainly
# ----------------------------------------
# This runs AFTER the tool. It cannot stop the write; it makes the write impossible to make silently. That
# is a real downgrade from the pre-layer and it is why both exist: the pre-layer prevents the common
# shapes, this one guarantees nothing gets through unnoticed.
#
# THE ESCAPE HATCH (FR-008)
# -------------------------
# A hook with no escape converts a helpful gate into a hostage situation, and the rational response to that
# is to delete the hook — which costs the whole feature (the run-gates-stop-hook.sh lesson). So: it blocks
# ONCE per distinct finding. .claude/.bash-write-blocked holds the file set of the last block; the same set
# again is silent, a different set arms it again.
#
# Note the deliberate separation from .bash-write-marker: the marker is a TIMESTAMP that is re-stamped on
# every single Bash call, so an escape hatch that lived in it would forget it had ever blocked. Two facts,
# two files.
#
# EXEMPTIONS (FR-009) — argued, never silent. Same idiom as EXCLUDED in scripts/run-gates.sh: a reason a
# reviewer can contest is fine, an unexplained omission is not.
#
#   git checkout|switch|restore|stash|reset|clean|pull|merge|rebase
#       These move the tree between states that were already authored, and every state they can move to was
#       authored under this gate. Gating them would mean a branch switch reports every file it touched.
#
#   NOT exempt: git apply | git am | git cherry-pick | git revert
#       These introduce content that may never have passed the gate at all. `git apply` in particular is
#       "write these files" wearing a git verb.
#
#   template-autosync.sh (row S5)
#       The sync is the SANCTIONED writer of CORE files — core-machinery-guard's own refusal ends with
#       "land the change in the template instead", and this is what doing that looks like arriving back.
#       Adding core-machinery to this layer's delegates made every sync that updated a CORE file report
#       itself; measured on the sync that landed row S5, which named its own four files. A report that
#       fires on correct routine work is one the reader learns to wave through, and then it is not a
#       report (the argument row S6 makes about `npm run build`).
#
#       The bound, stated rather than glossed: this matches the command string, so
#       `echo template-autosync.sh; sed -i s/a/b/ scripts/spec_active.py` suppresses this layer. It does
#       NOT suppress the write — the PRE-layer reads the same command, finds the real target and denies
#       it before anything runs. So the abuse costs detection of a write that prevention already stopped,
#       which is the same trade every exemption in this list makes.
#
# SECRETS (FR-015): the command string is never echoed. Only derived file paths appear in output.
#
# HOW IT REPORTS (FR-016) — to the developer, not only to the model
# ------------------------------------------------------------------
# It emits JSON with BOTH `decision: block` + `reason` (which the model must answer) and
# `systemMessage` (which the developer sees in the terminal). The first draft used `exit 2`, whose stderr
# reaches the model alone — and a detection only the model sees is a detection that can be summarised
# away, which is the same silence this row was carved out of, one layer up.
#
# Exit: always 0. The verdict is the JSON on stdout, per the PostToolUse contract.
#
# Covers: SC-1438 SC-1439 SC-1440 SC-1441 SC-1442
#         SC-920 SC-921 SC-922 SC-923 SC-924 SC-926 (row S5)
#         SC-927 SC-928 SC-929 SC-930 SC-931 SC-932 SC-933 (row S6)

set -u

MAX_GROUPS=25   # detection runs after the command, so it can afford more than the pre-layer's 8
MAX_PATHS=100   # row S5 — the two basename-sensitive guards are asked per changed path. Generous
                # because a build or a branch switch can touch a lot, and both guards reject on a path
                # pattern before doing any work; what is not allowed is dropping the rest in silence.

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

ROOT=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}/.git" ]; then
  ROOT="$CLAUDE_PROJECT_DIR"
elif [ -n "$CWD" ]; then
  ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || ROOT=""
fi
[ -z "$ROOT" ] && exit 0

MARKER="$ROOT/.claude/.bash-write-marker"
BLOCKED="$ROOT/.claude/.bash-write-blocked"

# No before-time means nothing can be said about what this command changed, and inventing a finding is
# worse than missing one. (The pre-layer stamps the marker on every Bash call, so this is the
# first-command-of-a-session case, or a session where the pre-layer is not wired.)
[ -f "$MARKER" ] || exit 0

# Consume the marker whatever happens below, so the next command starts from its own before-time.
cleanup() { rm -f "$MARKER" 2>/dev/null || true; }

# Exemptions, checked before any work.
case "$CMD" in
  *"git checkout"*|*"git switch"*|*"git restore"*|*"git stash"*|*"git reset"*|*"git clean"*|\
  *"git pull"*|*"git merge"*|*"git rebase"*|*"template-autosync.sh"*|*"template-autosync-hook.sh"*)
    cleanup; exit 0 ;;
esac

# Everything that changed since the marker. Pruned to what a gate could ever care about: .git and build
# output are noise, .claude/worktrees holds stale whole copies of the repo, and graphify-out is generated.
# Measured at 23 ms over 802 .cs files on this tree — cheap enough to run after every shell command.
CHANGED=$(find "$ROOT" \
  -type d \( -name .git -o -name node_modules -o -name bin -o -name obj -o -name graphify-out \
             -o -name StrykerOutput -o -name TestResults -o -name worktrees -o -name .venv \) -prune -o \
  -type f -newer "$MARKER" -print 2>/dev/null)

if [ -z "$CHANGED" ]; then
  cleanup; exit 0
fi

# GENERATED OUTPUT IS NOT A SOURCE EDIT — ASK GIT, DO NOT GROW THE LIST ABOVE (row S6)
# ------------------------------------------------------------------------------------
# The prune list is a traversal cost saving, not a correctness mechanism, and as a correctness
# mechanism it was incomplete: `dist` is absent from it, so `npm run build` — which CLAUDE.md names
# in the verification floor before anything may be called done — was reported here as "source files
# the pipeline guard denies". Measured: pipeline-state-guard answers `deny` on
# src/AgentCrm.Web/dist/assets/index-<hash>.js exactly as it does on a real .tsx, and Vite writes a
# fresh content hash every build, so the escape hatch below never engages either. A gate that fires
# on required routine work with no way to settle it is one the reader learns to wave through.
#
# Adding `dist` would fix one command. In that project alone .gitignore also carries .vite/,
# playwright-report/, test-results/, blob-report/ and .playwright/, and the next tool adds a
# directory nobody enumerated. So the question is asked once, generally, of the thing that knows.
#
# `--no-index` IS NEVER PASSED, AND THAT IS THE WHOLE SAFETY ARGUMENT.
#   git check-ignore --stdin --no-index   → reports tracked files that match a pattern (5 on the
#                                           tree this was measured on, incl. two committed .tla files)
#   git check-ignore --stdin              → never reports a tracked file
# Tracked content matching a pattern is content somebody committed PAST the pattern: it is source,
# not output. So the question asked is "untracked AND ignored", which is what generated means.
#
# FAILS OPEN (FR-4): no git, an errored check-ignore, or a repo where the question cannot be asked
# all leave $CHANGED alone. A detection layer that goes quiet because a subprocess failed is worse
# than a noisy one — and here "fails open" means noisy, which is the safe direction.
#
# Line-based like every other list in this hook (find -print), so a path containing a newline breaks
# it the same way it already breaks the grouping. Not a regression; not fixed here.
IGNORE_RULES_MOVED=0
printf '%s\n' "$CHANGED" | grep -q '/\.gitignore$' && IGNORE_RULES_MOVED=1
# .git is pruned above, and a global excludes file lives outside $ROOT, so both are asked directly.
for _ex in "$ROOT/.git/info/exclude" \
           "$(git -C "$ROOT" config --get core.excludesFile 2>/dev/null | sed "s#^~#$HOME#")"; do
  [ -n "$_ex" ] && [ -f "$_ex" ] && [ "$_ex" -nt "$MARKER" ] && IGNORE_RULES_MOVED=1
done

# WHY THAT CHECK EXISTS: a quieter layer is where a bypass lives. After this filter, a line appended
# to .gitignore hides a path from detection. .gitignore is tracked, so the line itself is visible in
# `git status` and read by the PRE-layer when written through the shell — but that is visibility, not
# a gate. This is the gate: if the ignore rules themselves moved since the marker, they are not
# trusted for this command and the layer reports exactly as it did before row S6.
if [ "$IGNORE_RULES_MOVED" -eq 0 ]; then
  IGNORED=$(printf '%s\n' "$CHANGED" | git -C "$ROOT" check-ignore --stdin 2>/dev/null)
  if [ -n "$IGNORED" ]; then
    CHANGED=$(printf '%s\n' "$CHANGED" | grep -Fxv -f <(printf '%s\n' "$IGNORED"))
    if [ -z "$CHANGED" ]; then
      cleanup; exit 0
    fi
  fi
fi

# One representative per (directory, extension) for the three guards that decide from the path alone —
# for those, files sharing both get identical verdicts, so this is exact and not a sample.
#
# It is NOT exact for the two guards row S5 added, and that was a live bypass rather than a nicety:
# core-machinery decides from the BASENAME, so scripts/template-autosync.sh and scripts/other.sh share
# a group and have opposite verdicts, and whichever the grouping picked answered for both. Those two
# are asked about every changed path instead. Same defect, same fix, both layers.
REPS=$(printf '%s\n' "$CHANGED" | python3 "$HOOK_DIR/bash_write_targets.py" --group 2>/dev/null)
[ -z "$REPS" ] && { cleanup; exit 0; }
ALLP="$CHANGED"

GROUP_COUNT=$(printf '%s\n' "$REPS" | grep -c '')
PATH_COUNT=$(printf '%s\n' "$ALLP" | grep -c '')
TRUNCATED=""
if [ "$GROUP_COUNT" -gt "$MAX_GROUPS" ]; then
  # No silent caps (scripts/run-gates.sh's rule): say what was dropped, or the report reads as coverage it
  # does not have.
  TRUNCATED="
NOTE: ${GROUP_COUNT} directory/extension groups changed; only the first ${MAX_GROUPS} were checked. The rest are UNCHECKED, not cleared."
  REPS=$(printf '%s\n' "$REPS" | sed -n "1,${MAX_GROUPS}p")
fi
if [ "$PATH_COUNT" -gt "$MAX_PATHS" ]; then
  TRUNCATED="${TRUNCATED}
NOTE: ${PATH_COUNT} distinct paths changed; only the first ${MAX_PATHS} were checked for template ownership and register ticks. The rest are UNCHECKED, not cleared."
  ALLP=$(printf '%s\n' "$ALLP" | sed -n "1,${MAX_PATHS}p")
fi

# The bytes a guard needs to answer narrowly (row S5, FR-7).
#
# WHY THIS LAYER SUPPLIES THEM AND THE PRE-LAYER CANNOT
# ------------------------------------------------------
# The pre-layer derives a PATH from a command string and has no content to give, so
# core-owed-tick-guard-hook.sh answers about the file and says so. This layer runs after the write:
# the bytes are on disk, so it can hand over exactly what the Edit route hands over — the lines
# ADDED since HEAD — and get the same narrow verdict. Without them, every `- [/]` mark made
# legitimately with the Edit tool would be reported as a tick, and a report that fires on correct
# routine work is a report that stops being read.
#
# Falls back to path-only for an untracked file, a tree with no git, a read failure, or a diff past
# the cap. The report says which of the two it used rather than leaving the reader to assume.
ADDED_LINES=""   # set by added_lines(); empty means "ask on the path alone"
MAX_DIFF_BYTES=65536
added_lines() {
  ADDED_LINES=""
  [ -n "$ROOT" ] || return 0
  local d n
  # `grep '^+'` then drop the `+++ b/path` header, then strip the one marker column. Doing it in
  # that order matters: a content line that itself begins with `+` survives, and the header does not.
  d=$(git -C "$ROOT" diff -U0 --no-color -- "$1" 2>/dev/null \
        | grep '^+' | grep -v '^+++ ' | cut -c2-) || return 0
  [ -z "$d" ] && return 0
  n=$(printf '%s' "$d" | wc -c)
  [ "$n" -gt "$MAX_DIFF_BYTES" ] && return 0
  ADDED_LINES="$d"
}

FINDINGS=""
FIRST_REASON=""

# One scan function, two path lists and two guard lists — the same split the pre-layer makes, for the
# same reason. Findings accumulate here rather than exiting at the first: this layer reports, and a
# report that names one of four changed files is a report the reader has to redo by hand.
scan() {            # $1 = newline-separated paths, $2... = guard filenames
  local paths="$1"; shift
  [ -z "$paths" ] && return 0
  local target guard OUT INNER
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    case "$FINDINGS" in *"$target   ["*) continue ;; esac   # already reported by the other list
    added_lines "$target"
    for guard in "$@"; do
      [ -f "$HOOK_DIR/$guard" ] || continue
      OUT=$(jq -n --arg p "$target" --arg n "$ADDED_LINES" \
              'if $n == "" then {tool_input:{file_path:$p}} else {tool_input:{file_path:$p, new_string:$n}} end' \
              | bash "$HOOK_DIR/$guard" 2>/dev/null)
      [ -z "$OUT" ] && continue
      INNER=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
      [ -z "$INNER" ] && continue
      if [ -n "$ADDED_LINES" ]; then
        FINDINGS="${FINDINGS}${target}   [${guard%-hook.sh}]
"
      else
        FINDINGS="${FINDINGS}${target}   [${guard%-hook.sh}; asked on the path alone — no readable diff, so this is the wider verdict]
"
      fi
      [ -z "$FIRST_REASON" ] && FIRST_REASON="$INNER"
      break
    done
  done <<INNER_EOF
$paths
INNER_EOF
}

scan "$ALLP" core-machinery-guard-hook.sh core-owed-tick-guard-hook.sh
scan "$REPS" spec-register-guard-hook.sh pipeline-state-guard-hook.sh spec-interview-guard-hook.sh

if [ -z "$FINDINGS" ]; then
  cleanup; exit 0
fi

# The escape hatch: same finding as last time → stay quiet.
FINGERPRINT=$(printf '%s' "$FINDINGS" | sort | tr -d '\n')
if [ -f "$BLOCKED" ]; then
  PREV=$(cat "$BLOCKED" 2>/dev/null || true)
  if [ "$PREV" = "$FINGERPRINT" ]; then
    cleanup; exit 0
  fi
fi
printf '%s' "$FINGERPRINT" > "$BLOCKED" 2>/dev/null || true
cleanup

# The headline names no particular guard, because five can speak here and they answer different
# questions: three ask "has this spec's pipeline run?" about a source file, core-machinery asks
# "whose file is this?", core-owed-tick asks "may this register be ticked yet?". Saying "source
# files the pipeline guard denies" over a CORE finding would be false in both halves and would send
# the reader to the wrong repair — the mistake row H7t records for the pre-layer's provenance line.
# The per-file bracket says which guard spoke; the headline stays true for all of them.
REASON="A shell command changed files a guard refuses.

Files changed (and which guard refused each):
${FINDINGS}${TRUNCATED}
This was detected AFTER the fact, on the filesystem — the write had already happened. Before row H7b it
would not have been detected at all: the guards are wired to Edit/Write/MultiEdit, so a write made
through the shell met no gate, and 56 register rows shipped that way. Before row S5 only three of the
five were asked here, so a change under scripts/ or specs/ was detected by neither layer.

Either finish what the guard asks for, or revert these files. The guard's reason follows.

────────────────────────────────────────────────────────────
${FIRST_REASON}

(This blocks once for this set of files. Changing something else arms it again.)"

# Row S5: this line used to open with a hard-coded foreign project name. It is a CORE script, so
# that name shipped to every project the template serves and named none of them correctly.
SUMMARY="Pipeline guard: a shell command wrote to $(printf '%s' "$FINDINGS" | grep -c '') file(s) a guard denies. See the block reason for the file list and the guard's own explanation."

jq -n --arg r "$REASON" --arg s "$SUMMARY" \
  '{decision: "block", reason: $r, systemMessage: $s}'
exit 0
