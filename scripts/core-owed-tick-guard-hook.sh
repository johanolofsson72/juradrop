#!/bin/bash
# PreToolUse guard: refuses to tick a register row while this project still owes the template CORE
# work (spec 007ca).
#
# WHY THIS EXISTS
# ---------------
# scripts/template-autosync.sh overwrites CORE unconditionally — manifest or not, local edit or not.
# Three mechanisms already say so: core-machinery-guard-hook.sh before the edit, --accept-local when
# somebody tries to record the difference, and [owed] at every session start afterwards. All three
# are advice, and none of them is attached to the moment the project declares the work finished.
#
# Spec 007bl walked straight through all three. It edited eight CORE files and added nine scripts in
# one project, landed none of them in the template, and ticked its register row. [owed] named the
# eight files for three days and nothing acted on the report. Then a later sync reverted the split
# layout inside the very project that had authored it.
#
# The tick is the last moment where refusing is still free. After it the spec is closed, and a
# finding parked behind a closed spec is addressed to nobody — the failure mode CLAUDE.md already
# records for a diagnosis left in a run-log.md.
#
# WHAT COUNTS AS OWED
# -------------------
# Two families, and the second is the half [owed] cannot see:
#
#   --owed      CORE files whose bytes no longer match the manifest.
#   --unlisted  scripts the manifest has never named that a CORE file depends on. A file the
#               template has never shipped has no manifest line, so it cannot "differ" from
#               anything — 007bl's nine new scripts were not under-reported, they were absent from
#               the question.
#
# Both answers come from template-autosync.sh, asked rather than copied. A second list of CORE names
# here would drift from the first the moment either changed, and a stale list is authoritative-
# looking silence over exactly the new file nobody has habits about yet.
#
# FAILS OPEN — AND THAT IS NOT TIMIDITY
# -------------------------------------
# The opposite way round from pipeline-state-guard, which fails CLOSED. That guard protects a
# PROCESS this project committed to, so a resolution failure there must block. This one protects a
# FILE THE TEMPLATE OWNS — and if the sync machinery is missing or broken, no sync is coming and
# there is nothing to protect the file from. Beyond that, this guard sits in front of the register:
# a bug that failed closed would make every register in the fleet untickable at once, and a guard
# that bricks the register is deleted within the hour, taking the real protection with it.
#
# Silent (edit proceeds, nothing emitted) when:
#   - the target is not <something>/specs/INDEX.md
#   - the written bytes contain no `- [x]` (adding a row, marking `- [/]`, fixing prose, archiving
#     history — none of those is the event this gate is about, and blocking `- [/]` in particular
#     would block the repair path, since marking a row in progress is what you do ON THE WAY to
#     fixing what is owed)
#   - ALLOW_TICK_WITH_CORE_OWED=1 (deliberate override; says so rather than hiding)
#   - no git root, or the root has no .claude/
#   - the root IS the template repository (that is where the change belongs)
#   - the root has no scripts/template-autosync.sh (no sync, so nothing to owe)
#   - the sync cannot answer either question
#
# Exit: always 0. A deny is expressed as permissionDecision JSON on stdout, per the hook contract.

set -u

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# ------------------------------------------------------------------- cheap pre-filter
# First, because it rejects every edit in the repository but one file, and this hook must cost
# nothing on the other 99.9% of them. No tree walk, no subprocess, no hashing above this line.
case "$FILE" in
  */specs/INDEX.md) ;;
  *) exit 0 ;;
esac

# ------------------------------------------------------------------- is it a tick?
# Edit carries new_string, Write carries content, MultiEdit carries an edits array. A tick is
# textually `- [x]` at the start of a register row; the format is fixed by
# .claude/rules/spec-register.md and three existing guards already parse it.
#
# EMPTY IS NOT "NO". The Bash delegate (scripts/bash-write-guard-hook.sh) synthesises
# {"tool_input":{"file_path": ...}} and has no content to give — it extracts write TARGETS from a
# command string, not the bytes. Treating absent content as "not a tick" would make `sed -i` the
# silent route past this gate, which is the exact defect row H7b was opened to remove: 56 register
# rows shipped through the shell past three guards that denied every Edit. So no content means the
# guard answers about the FILE, and the reason says it is doing that.
NEW=$(printf '%s' "$INPUT" | jq -r '
  [ .tool_input.new_string?, .tool_input.content?, (.tool_input.edits[]?.new_string?) ]
  | map(select(. != null)) | join("\n")' 2>/dev/null)
CONTENT_SEEN=0
if [ -n "$NEW" ]; then
  CONTENT_SEEN=1
  # A here-string, not a pipeline into grep -q. The register can be tens of kilobytes and grep -q
  # exits at the first match; scripts/validate-no-sigpipe-assertions.sh exists because that shape
  # returns 141 under pipefail once the tail fills the pipe buffer. This hook sets no pipefail
  # today, which is exactly the kind of thing that changes underneath a file later.
  grep -qE '^[[:space:]]*- \[x\]' <<< "$NEW" || exit 0
fi

# ------------------------------------------------------------------- the override
# An environment variable rather than anything settable inside the edit, because the failure mode to
# design against is the reflex bypass. There is a real case for it — the tick that CLOSES the spec
# which lands the owed work is itself a tick made while the work is still owed — so the way through
# exists; it is just not quiet.
if [ "${ALLOW_TICK_WITH_CORE_OWED:-0}" = "1" ]; then
  jq -n '{hookSpecificOutput: {additionalContext: "core-owed-tick-guard: ALLOW_TICK_WITH_CORE_OWED=1 is set, so the register tick proceeds. If this project still owes the template CORE work, the next sync overwrites it — land it in the template, or it is gone."}}' 2>/dev/null
  exit 0
fi

# ------------------------------------------------------------------- project root
DIR=$(dirname "$FILE")
ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ] && [ "$DIR" != "." ]; do
  if [ -d "$DIR/.git" ]; then ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$ROOT" ] || exit 0
[ -d "$ROOT/.claude" ] || exit 0

# The template repository is where this guard is telling everyone to go, so denying a tick there
# would be perfectly circular. Identified by origin URL, the same three patterns
# template-autosync.sh uses — file markers are useless, because the sync copies
# scripts/sync-prompt.md and friends into every project it touches.
case "$(git -C "$ROOT" remote get-url origin 2>/dev/null)" in
  *johanolofsson72/Claude.git|*johanolofsson72/Claude|*:johanolofsson72/Claude*) exit 0 ;;
esac

SYNC="$ROOT/scripts/template-autosync.sh"
[ -f "$SYNC" ] || exit 0

# ------------------------------------------------------------------- the two questions
# Bounded, because this sits in front of an Edit. Both modes answer from the manifest and the
# working tree and exit before template resolution — no clone, no fetch — and measure at ~45 ms and
# ~165 ms on a project of this size. The timeout costs one line and removes a whole class of "why is
# my editor hanging".
TO=""
if command -v timeout  >/dev/null 2>&1; then TO="timeout 15"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout 15"; fi

# 0 = findings on stdout · 1 = none · 2 = cannot answer. Anything that is not 0 is treated as "no
# finding": 1 says so, and 2 (or a timeout, or a crash) has to be indistinguishable from it here —
# see the fail-open note at the top.
OWED=$(cd "$ROOT" && $TO bash "$SYNC" --owed 2>/dev/null)
[ $? -eq 0 ] || OWED=""
UNLISTED=$(cd "$ROOT" && $TO bash "$SYNC" --unlisted 2>/dev/null)
[ $? -eq 0 ] || UNLISTED=""

[ -n "$OWED" ] || [ -n "$UNLISTED" ] || exit 0

# ------------------------------------------------------------------- the refusal
# The two families are rendered under separate headings because they need different repairs: one is
# a file whose bytes moved, the other is a file the template has never had. A block that merged them
# would send half its readers to the wrong fix.
DETAIL=""
if [ -n "$OWED" ]; then
  DETAIL="CORE files whose bytes differ from what the template shipped:

$(printf '%s\n' "$OWED" | sed 's/^/  /')
"
fi
if [ -n "$UNLISTED" ]; then
  [ -n "$DETAIL" ] && DETAIL="$DETAIL
"
  DETAIL="${DETAIL}Scripts a CORE file depends on that the template has never shipped:

$(printf '%s\n' "$UNLISTED" | awk -F'\t' '{ printf "  %-44s (named by: %s)\n", $1, $2 }')

These have no manifest line, so [owed] cannot see them at all — a file the template has never
shipped cannot differ from anything. Add them to CORE_SCRIPTS in the template.
"
fi

if [ "$CONTENT_SEEN" -eq 1 ]; then
  SCOPE="This edit ticks a register row (\`- [x]\`)."
else
  SCOPE="This write targets specs/INDEX.md through the shell, where the guard sees the target path but
not the bytes — so it cannot tell a tick from any other register edit and answers about the file.
Use the Edit tool if you need the narrower verdict; it is checked line by line there."
fi

REASON="BLOCKED — this project still owes the template CORE work, so the register cannot be ticked yet.

$SCOPE

$DETAIL
Why the tick specifically: template-autosync.sh overwrites CORE unconditionally, so work that lives
only here is not at risk — it is already lost, and the only open question is how many hours until
the next session start collects it. Ticking closes the spec, and a finding behind a closed spec is
addressed to nobody. Spec 007bl did exactly this: eight CORE files, nine new scripts, none landed,
row ticked. [owed] reported the eight for three days, nothing acted, and a later sync reverted the
split layout in the project that had authored it.

What to do instead:

  1. Land the change in the template (\$CLAUDE_TEMPLATE_DIR, or ~/repos/Claude), commit and push it.
  2. Sync it back:   bash scripts/template-autosync.sh --force
  3. Confirm both questions are quiet:
       bash scripts/template-autosync.sh --owed       # 1 = nothing owed
       bash scripts/template-autosync.sh --unlisted   # 1 = nothing unlisted
  4. Then tick the row.

Marking the row \`- [/]\` or \`- [!]\`, adding a row, and every other register edit are NOT blocked —
only the tick. Marking a row in progress is what you do on the way to fixing this.

If the tick you are making IS the one that closes the spec which lands this work, set
ALLOW_TICK_WITH_CORE_OWED=1 for the session. It says so in the transcript rather than passing quietly."

jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
