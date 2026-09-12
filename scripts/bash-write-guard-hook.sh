#!/usr/bin/env bash
# PreToolUse guard on Bash: applies the SAME pipeline gate to writes made through the shell that
# Edit/Write/MultiEdit have had all along (row H7b).
#
# WHY THIS EXISTS
# ---------------
# The three pipeline guards (spec-register, pipeline-state, spec-interview) are wired to the matcher
# "Edit|Write|MultiEdit". Nothing was wired to Bash. So the enforcement answer depended on which tool the
# agent happened to pick: `Edit src/App.cs` was denied, `sed -i '' 's/x/y/' src/App.cs` was not. Measured at
# H7b: 56 register rows shipped in a tree where all three guards denied every Edit — through the shell.
#
# A guard whose enforcement depends on the tool is not a guard.
#
# IT DELEGATES — IT DOES NOT DECIDE
# ---------------------------------
# This hook extracts candidate write targets and then feeds each one to the four EXISTING guards as a
# synthetic {"tool_input":{"file_path": ...}}. The path allowlist, the extension list, the .git walk, the
# language-marker check and the register resolution are all inherited, not copied. Spec 007m's regression
# survived ten days precisely because each guard carried its own copy of the register parser; a fourth copy
# of the policy here would rebuild that trap. If a verdict is wrong, it is wrong identically in both paths,
# which is the property that makes it findable.
#
# DECLARED COVERAGE BOUND (FR-010) — read this before trusting it
# ---------------------------------------------------------------
# Six shell forms are detected: redirection `>` / `>>` (which is also how a heredoc writes), `sed -i`,
# `tee`, `cp`, `mv`. Row S5 adds a seventh shape — see THE OPAQUE PASS below. What remains outside:
#
#   * any path assembled at runtime, in the shell or inside an interpreter's program. Nothing here
#     evaluates anything, and guessing what $DIR expands to would invent a finding
#   * `xargs sed -i`, `find -exec`, a Makefile target, a script that writes files — these carry a
#     COMMAND rather than a program, which is a different shape from the one the opaque pass names
#   * `install`, `dd of=`, `truncate`, `patch` — deliberately NOT claimed here, because a form named in a
#     requirement with no fixture behind it is a coverage number with no coverage
#
# Every one of those is caught by the OTHER layer, scripts/bash-write-detect-hook.sh, which watches the
# filesystem instead of the command string and therefore does not care how the write was spelled. This hook
# is prevention for the common shapes; that one is detection for everything. Neither alone is honest.
#
# THAT LAST SENTENCE WAS UNTRUE FOR TWO GUARDS, AND IT MATTERED (row S5)
# ----------------------------------------------------------------------
# The detect layer asked three of the five delegates, and all three exit early on scripts/**, .claude/**
# and specs/** by design. So the two guards that own precisely those paths — core-machinery and
# core-owed-tick — were asked HERE and nowhere else, and a form this parser could not see reached
# neither layer. A register tick written as a python heredoc went through that gap. Both lists are now
# the same five, in the same order.
#
# THE OPAQUE PASS — an interpreter with no script path (row S5)
# -------------------------------------------------------------
# `python3 - <<'PY'`, `python3 -c`, `perl -e`, `node -e`, `eval`: the program is IN the command, and this
# parser cannot read it. It does not try. It recognises the shape, scans that region for path-shaped
# tokens, and asks the same five guards about each — so it answers about the PATH, not about what the
# program does with it. A read-only one-liner naming a gated file is therefore denied too; the refusal
# names both ways out. The alternative was leaving three interpreters as the quiet way past a gate that
# denies `sed -i`, which is the defect row H7b was opened to remove, one interpreter down.
#
# THE FOURTH DELEGATE — CORE OWNERSHIP (row H7t)
# ---------------------------------------------
# scripts/core-machinery-guard-hook.sh answers a different question from the three above: not "has this
# spec's pipeline run?" but "whose file is this?" — over the CORE set that scripts/template-autosync.sh
# overwrites unconditionally. It was wired to Edit|Write|MultiEdit only, so the same defect this hook was
# built to remove existed one floor up: `Edit scripts/template-autosync.sh` was denied and
# `sed -i '' s/x/y/ scripts/template-autosync.sh` was silent. Measured 2026-08-25, and not hypothetically —
# a session told to prefer Bash for file edits takes the silent route by default.
#
# It is asked FIRST and it cannot collide with the other three: they all exit early on */scripts/* and
# */.claude/* by design (a guard that blocks its own repair path cannot be repaired), and core-machinery is
# silent everywhere EXCEPT <root>/scripts/ and <root>/.claude/rules/. Disjoint sets, so the order changes
# which text arrives first only in a case that cannot occur — first is chosen so the reading order matches
# the Edit path.
#
# Its fail-open, its ALLOW_CORE_MACHINERY_EDIT=1 override and its template-repo self-exemption are all
# inherited unmodified. With the override set it answers with additionalContext rather than a deny, so INNER
# comes back empty and the loop simply continues — the override works on this route without a line of code
# here, and there is a fixture pinning that rather than a comment claiming it.
#
# SECRETS (FR-015)
# ----------------
# The command string is NEVER echoed — not in the deny reason, not in a log, not in an error. A shell
# command can carry a credential (`op read`, `--password`, a heredoc holding a key) and CLAUDE.md §Secrets
# forbids values reaching logs or error output. Only DERIVED file paths appear in output.
#
# Exit: always 0. A deny is expressed as permissionDecision JSON on stdout, per the hook contract.
#
# Covers: SC-1437 SC-1439 SC-1442 SC-1678 SC-1679 SC-1680 SC-1681
#         SC-913 SC-914 SC-915 SC-916 SC-917 SC-918 SC-919 SC-925 SC-926 (row S5)

set -u

MAX_GROUPS=8   # FR-006a — see the cap note below
MAX_PATHS=32   # row S5 — the basename-sensitive guards are asked per path, so that count needs its own
               # ceiling. Higher than MAX_GROUPS because these two guards are cheap: both reject on a
               # path pattern before doing any work, and only specs/INDEX.md and CORE names go further.

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# ---------------------------------------------------------------------------
# 1) Stamp the "before" marker for the PostToolUse layer.
#
# Unconditional and first: the detect layer needs a before-time for EVERY Bash call, including the ones
# this layer skips in a millisecond — those are exactly the calls whose writes it cannot see.
# ---------------------------------------------------------------------------
ROOT=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}/.git" ]; then
  ROOT="$CLAUDE_PROJECT_DIR"
elif [ -n "$CWD" ]; then
  ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || ROOT=""
fi
if [ -n "$ROOT" ] && [ -d "$ROOT/.claude" ]; then
  : > "$ROOT/.claude/.bash-write-marker" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2) Fast reject. This hook is on the Bash hot path, so a command that cannot contain any of the six forms
#    must not pay for a python start (~50 ms on this machine). Deliberately over-inclusive: it costs a
#    wasted extraction, never a missed one.
# ---------------------------------------------------------------------------
# The heredoc/inline-flag/eval tokens are row S5's addition. Without them a pure
# `python3 - <<'PY' … PY` exits HERE, before the parser is ever asked — which is half of why that
# shape passed all five guards silently. The other half was the parser dropping heredoc bodies.
case "$CMD" in
  *">"*|*sed*|*tee*|*cp*|*mv*|*"<<"*|*" -c"*|*" -e"*|*" -E"*|*" -r"*|*"--eval"*|*eval*) ;;
  *) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# 3) Extract candidate write targets and make them absolute.
# ---------------------------------------------------------------------------
TARGETS=$(CMD_TEXT="$CMD" CWD_PATH="${CWD:-$PWD}" python3 "$HOOK_DIR/bash_write_targets.py" 2>/dev/null) || exit 0

# Row S5: no extracted target is no longer the end of the story — the opaque pass at the bottom
# still runs, because the shapes it recognises produce zero targets by construction.
TOTAL=$(printf '%s\n' "$TARGETS" | sed -n '1p')
REPS=$(printf '%s\n' "$TARGETS" | sed '1d' | sed '/^$/d')

ALLP=$(CMD_TEXT="$CMD" CWD_PATH="${CWD:-$PWD}" python3 "$HOOK_DIR/bash_write_targets.py" --all 2>/dev/null | sed '1d' | sed '/^$/d')

GROUP_COUNT=0
[ -n "$REPS" ] && GROUP_COUNT=$(printf '%s\n' "$REPS" | grep -c '')
PATH_COUNT=0
[ -n "$ALLP" ] && PATH_COUNT=$(printf '%s\n' "$ALLP" | grep -c '')

# FR-006a — bounded. Each representative costs three guard processes with a python start apiece, and an
# unbounded layer on the Bash hot path is a layer that gets deleted. Past the cap this DENIES rather than
# waves through: an unmeasured allow is the failure this whole row is about.
if [ "$GROUP_COUNT" -gt "$MAX_GROUPS" ] || [ "$PATH_COUNT" -gt "$MAX_PATHS" ]; then
  REASON="BLOCKED — this shell command writes to more distinct places than the pipeline guard will check unverified (${GROUP_COUNT} directory/extension groups, cap ${MAX_GROUPS}; ${PATH_COUNT} distinct paths, cap ${MAX_PATHS}; ${TOTAL} target paths in all).

Two caps because there are two questions. The three pipeline guards decide from the path alone, so one representative per (directory, extension) group answers for the whole group — an identity, not a sample. The other two decide from the file's NAME (is it CORE machinery? is it the register?), so they are asked about every distinct path; before row S5 they were asked about the representative, and the order of operands decided the verdict.

Past either cap it stops rather than guessing: waving a write through unmeasured is the exact failure this guard exists to remove.

Split the command into smaller writes, or make the edits with the Edit tool, which is gated the same way one file at a time."
  jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
fi

# ---------------------------------------------------------------------------
# 4) Delegate. First deny wins; its reason is passed through verbatim with one line of provenance.
#
#    TWO GRANULARITIES, AND WHY (row S5)
#    -----------------------------------
#    The three pipeline guards decide from the path alone, so one representative per
#    (directory, extension) group answers for the whole group — that is an identity, and it is what
#    keeps MAX_GROUPS honest. The other two do not: core-machinery decides from the BASENAME and
#    core-owed-tick from the exact filename. Asking them about a representative let the ORDER OF
#    OPERANDS decide the verdict:
#
#      sed -i 's/a/b/' scripts/other.sh scripts/template-autosync.sh   -> ALLOW   (measured)
#      sed -i 's/a/b/' scripts/template-autosync.sh scripts/other.sh   -> deny
#
#    So those two are asked about EVERY distinct path and the other three about one per group.
# ---------------------------------------------------------------------------
ARM="normal"

emit_and_exit() {   # $1 = guard, $2 = target, $3 = the guard's own reason
  local guard="$1" target="$2" INNER="$3" REASON
  if [ "$ARM" = "opaque" ]; then
    REASON="BLOCKED — this path is named inside a program an interpreter would run, and a guard refuses it.

Target: ${target}
Guard:  scripts/${guard}

The path was found inside an interpreter invoked with no script path — a heredoc body, a -c/-e/--eval
argument, or eval. Nothing here reads that program, so this guard cannot tell a READ from a WRITE in
it and answers about the path instead. That is deliberate: before row S5 the same write spelled
\`sed -i\` was denied while three interpreters made it silently, and one register tick did.

Two ways on, and neither is a bypass:

  * If you are WRITING this file — use the Edit tool. It is gated the same way, one file at a time,
    and it can see the bytes, so its verdict is the narrow one.
  * If you are only READING it — use cat, sed -n, grep or the Read tool. None of those is an
    interpreter carrying a program, so none of them reaches this arm.

The guard's own reason follows.

────────────────────────────────────────────────────────────
${INNER}"
    jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
    # The provenance line has to be true, and there are two different truths here. The pipeline guards
    # answer "has this spec's pipeline run?" about a SOURCE file; core-machinery answers "whose file is
    # this?" about a file under scripts/ or .claude/rules/ that the template owns. Calling the second one
    # "a source file the pipeline guard denies" would be false in both halves, and a header that lies
    # about which gate spoke sends the reader to the wrong repair (row H7t). The delegate's own reason is
    # passed through verbatim in both arms — only the one line above it changes.
    case "$guard" in
      core-owed-tick-guard-hook.sh)
        REASON="BLOCKED — a shell command was about to tick a register row while this project owes the template CORE work.

Target: ${target}
Guard:  scripts/${guard}

Its own reason follows. Note the coverage bound it states: this route hands it a path and no bytes, so unlike the Edit route it cannot tell a tick from any other write to specs/INDEX.md. Answering about the file is the conservative half of that trade — the alternative is that \`sed -i\` is the silent way past a gate the Edit tool enforces, which is the defect row H7b exists to remove.

────────────────────────────────────────────────────────────
${INNER}"
        ;;
      core-machinery-guard-hook.sh)
        REASON="BLOCKED — a shell command was about to write to a file the TEMPLATE owns.

Target: ${target}
Guard:  scripts/${guard}

This is the same answer the Edit tool has given since spec 007ao. Until row H7t it was wired to Edit/Write/MultiEdit only, so \`sed -i\`, a redirect or a heredoc against CORE machinery met no gate at all — and a guard whose verdict depends on which tool you picked is not a guard. The guard's own reason follows.

────────────────────────────────────────────────────────────
${INNER}"
        ;;
      *)
        REASON="BLOCKED — a shell command was about to write to a source file the pipeline guard denies.

Target: ${target}
Guard:  scripts/${guard}

The gate is the same one Edit/Write/MultiEdit have always passed through; before row H7b it simply was not wired to Bash, so which tool you picked decided whether the rule applied. It no longer does. The guard's own reason follows.

────────────────────────────────────────────────────────────
${INNER}"
        ;;
    esac
  jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Ask one guard list about one list of paths. First deny wins and never returns.
ask_list() {        # $1 = newline-separated paths, $2... = guard filenames
  local paths="$1"; shift
  [ -z "$paths" ] && return 0
  local target guard OUT INNER
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    for guard in "$@"; do
      [ -f "$HOOK_DIR/$guard" ] || continue
      OUT=$(printf '{"tool_input":{"file_path":%s}}' "$(jq -Rn --arg p "$target" '$p')" \
              | bash "$HOOK_DIR/$guard" 2>/dev/null)
      [ -z "$OUT" ] && continue
      INNER=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
      [ -z "$INNER" ] && continue
      emit_and_exit "$guard" "$target" "$INNER"
    done
  done <<EOF
$paths
EOF
}

BASENAME_GUARDS="core-machinery-guard-hook.sh core-owed-tick-guard-hook.sh"
PATH_GUARDS="spec-register-guard-hook.sh pipeline-state-guard-hook.sh spec-interview-guard-hook.sh"

# shellcheck disable=SC2086
ask_list "$ALLP" $BASENAME_GUARDS
# shellcheck disable=SC2086
ask_list "$REPS" $PATH_GUARDS

# ---------------------------------------------------------------------------
# 5) The opaque pass (row S5). An interpreter invoked with NO SCRIPT PATH carries its program in
#    the command — a heredoc body, a -c/-e/-E/-r/--eval argument, or eval. The parser above cannot
#    see a write in there, and the declared answer used to be "the post-layer catches it". It did
#    not: that layer asked three of the five guards, and the two that own scripts/ and specs/ were
#    not among them. So a register tick written as `python3 - <<'PY' … PY` met NOTHING, and one did.
#
#    This does not read the program. It recognises the SHAPE, scans the region for path-shaped
#    tokens, and asks the same five guards about each. It cannot tell a read from a write in there,
#    so it answers about the PATH — the same trade core-owed-tick-guard-hook.sh already documents
#    for the shell route. The cost is a false deny on a one-liner that only reads a guarded path;
#    the reason names both ways out, and neither is more than a keystroke.
#
#    Silent when the region names nothing guarded, which is the overwhelming majority of one-liners.
# ---------------------------------------------------------------------------
OPAQUE=$(CMD_TEXT="$CMD" CWD_PATH="${CWD:-$PWD}" python3 "$HOOK_DIR/bash_write_targets.py" --opaque 2>/dev/null) || exit 0
OREPS=$(printf '%s\n' "$OPAQUE" | sed '1d' | sed '/^$/d')
[ -z "$OREPS" ] && exit 0
OALLP=$(CMD_TEXT="$CMD" CWD_PATH="${CWD:-$PWD}" python3 "$HOOK_DIR/bash_write_targets.py" --opaque --all 2>/dev/null | sed '1d' | sed '/^$/d')

# The caps truncate here rather than deny. A deny past the cap is right in section 4, where every path
# in the list is a write the command really makes; here the list is candidates from a program nobody
# read, so refusing a long one-liner outright would punish the case with the weakest evidence. What is
# not allowed is a SILENT cap: the count that was dropped rides along in the refusal (run-gates.sh's
# rule), and nothing is reported as cleared that was never checked.
OVER=""
OGROUPS=$(printf '%s\n' "$OREPS" | grep -c '')
if [ "$OGROUPS" -gt "$MAX_GROUPS" ]; then
  OREPS=$(printf '%s\n' "$OREPS" | sed -n "1,${MAX_GROUPS}p")
  OVER="${OVER} (${OGROUPS} candidate groups found; the first ${MAX_GROUPS} were checked and the rest are UNCHECKED, not cleared)"
fi
OPATHS=0
[ -n "$OALLP" ] && OPATHS=$(printf '%s\n' "$OALLP" | grep -c '')
if [ "$OPATHS" -gt "$MAX_PATHS" ]; then
  OALLP=$(printf '%s\n' "$OALLP" | sed -n "1,${MAX_PATHS}p")
  OVER="${OVER} (${OPATHS} candidate paths found; the first ${MAX_PATHS} were checked and the rest are UNCHECKED, not cleared)"
fi

ARM="opaque"
# shellcheck disable=SC2086
ask_list "$OALLP" $BASENAME_GUARDS
# shellcheck disable=SC2086
ask_list "$OREPS" $PATH_GUARDS

exit 0
