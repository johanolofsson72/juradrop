#!/bin/bash
# PreToolUse guard: refuses an Edit/Write/MultiEdit against CORE machinery — the 54
# files scripts/template-autosync.sh overwrites unconditionally, manifest or not.
#
# Why this exists (spec 007ao). A project's copy of a CORE file IS the template's
# copy. Measured over every commit this template's flagship project ever made to one
# outside a sync: the lines that survive today are exactly the lines the template also
# has, in all twelve cases, with no exceptions. So an edit made only in a project is
# not risky, it is already lost — the only open question is how many hours until the
# next SessionStart collects it. Spec 007ak spent an entire spec shipping 59 lines
# into scripts/template-autosync.sh; a sync deleted them the next morning, a later
# spec restored them by hand, and a second sync deleted them again nineteen hours
# after that. Nothing said a word on any of those days.
#
# The words already existed. `template-autosync.sh --accept-local` has refused this
# since spec 007af — but only when somebody tries to RECORD the difference, which is
# after the edit, after the spec, after the commit. This hook asks the same script the
# same question at the one moment the answer is still free, through --is-core.
#
# The three BLOCKING guards cannot do this job: spec-register-guard,
# pipeline-state-guard and spec-interview-guard all exit early on */scripts/* and
# */.claude/* by design, because every one of them IS a script under scripts/ and a
# guard that blocks its own repair path cannot be fixed. That exemption is correct and
# stays. This guard asks a different question — not "has the pipeline run?" but "who
# owns this file?" — over exactly the set they exempt, so no path is judged by both.
#
# Silent (edit proceeds, nothing emitted) when:
#   - the tool call carries no file path
#   - ALLOW_CORE_MACHINERY_EDIT=1 (deliberate override; says so rather than hiding)
#   - the path is not under <root>/scripts/ or <root>/.claude/rules/
#   - no git root, or the root has no .claude/
#   - the root IS the template repository (that is where the change belongs)
#   - the root has no scripts/template-autosync.sh (no sync, so no owner to defer to)
#   - the classifier says not CORE, or cannot answer at all
#   - the write leaves the file byte-identical to the template clone's copy (spec 039)
#
# Fails OPEN, deliberately, and the other way round from pipeline-state-guard. That
# guard protects a process this project committed to, so a resolution failure there
# must block. This one protects a file the TEMPLATE owns — and if the sync machinery
# is missing or broken, no sync is coming and there is nothing to protect the file
# from. A guard that blocked all script editing because it could not parse something
# would be deleted within the hour, taking the real protection with it.

set -u

INPUT=$(cat)

# Cheapest exit first (spec 073, R9): both branches below act only on a path under scripts/ or
# .claude/rules/, and such a path appears in the raw JSON verbatim — JSON escaping leaves letters,
# dots and slashes alone. Without either substring there is nothing to decide, and no reason to start
# jq to find that out. A match only means "look properly"; the case statements below still decide.
# Bounded to small payloads: bash's matchers are slow on long strings (a 200 KB Write took longer to
# scan than jq takes to start), so a large payload skips this and pays exactly what it paid before.
if [ "${#INPUT}" -le 4096 ]; then
  case "$INPUT" in
    */scripts/*|*/.claude/rules/*) ;;
    *) exit 0 ;;
  esac
fi
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# ------------------------------------------------------------------- the override
# Named in the deny text below, and deliberately an environment variable rather than
# anything settable inside the edit: the failure mode to design against is the reflex
# bypass. There is a real case for it — spec 007al restoring somebody else's deleted
# work mid-spec was the right call and this guard would have stopped it — so the way
# through exists, it is just not quiet.
if [ "${ALLOW_CORE_MACHINERY_EDIT:-0}" = "1" ]; then
  case "$FILE" in
    */scripts/*|*/.claude/rules/*)
      jq -n --arg f "$FILE" '{hookSpecificOutput: {additionalContext: ("core-machinery-guard: ALLOW_CORE_MACHINERY_EDIT=1 is set, so the edit to " + $f + " proceeds. If this file turns out to be CORE machinery, the next template sync overwrites it — land the change in the template as well, or it is gone.")}}' 2>/dev/null
      ;;
  esac
  exit 0
fi

# A cheap pre-filter before anything walks a directory tree or forks a shell. The CORE
# sets are defined over exactly two directories, so everything else is somebody's own
# code and this guard has no opinion about it — which is the overwhelming majority of
# edits, and the reason this hook costs nothing on almost all of them.
case "$FILE" in
  */scripts/*|*/.claude/rules/*) ;;
  *) exit 0 ;;
esac

# ------------------------------------------------------------------- project root
DIR=$(dirname "$FILE")
ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ] && [ "$DIR" != "." ]; do
  if [ -d "$DIR/.git" ]; then ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$ROOT" ] || exit 0
[ -d "$ROOT/.claude" ] || exit 0

# The template repository is where this guard is telling everyone to go, so denying an
# edit here would be perfectly circular. Identified by origin URL, the same three
# patterns template-autosync.sh uses — file markers are useless, because the sync
# copies scripts/sync-prompt.md and friends into every project it touches. Asked
# directly rather than by shelling out to the sync, because a guard that consults the
# sync to decide whether to consult the sync is a loop with no floor.
case "$(git -C "$ROOT" remote get-url origin 2>/dev/null)" in
  *johanolofsson72/Claude.git|*johanolofsson72/Claude|*:johanolofsson72/Claude*) exit 0 ;;
esac

SYNC="$ROOT/scripts/template-autosync.sh"
[ -f "$SYNC" ] || exit 0

REL=${FILE#"$ROOT"/}
case "$REL" in /*) exit 0 ;; esac      # not under this root after all

# ------------------------------------------------------------------- the question
# One source of truth, asked rather than copied. A second list of CORE names living
# here would drift the first time an enforcement script is added, and a stale list is
# worse than none: it is authoritative-looking silence over precisely the new file
# nobody has habits about yet.
#
# Bounded, because this sits in front of an Edit. --is-core exits before template
# resolution and answers in ~7 ms, but a timeout costs one line and removes a whole
# class of "why is my editor hanging".
TO=""
if command -v timeout  >/dev/null 2>&1; then TO="timeout 5"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout 5"; fi

REASON_BODY=$($TO bash "$SYNC" --is-core "$REL" 2>/dev/null)
RC=$?
# 0 = CORE. 1 = not CORE. Anything else is the classifier failing to answer, and it
# has to be indistinguishable from "not CORE" here — see the fail-open note above.
[ "$RC" -eq 0 ] || exit 0
[ -n "$REASON_BODY" ] || exit 0

# ------------------------------------------------------------- where it belongs
# The same candidates resolve_local_template() prefers, minus the tarball fallback and
# minus the fetch: a deny message is worth a stat, not a network round trip. A deny
# that cannot name the concrete file to open instead is an obstacle rather than an
# instruction, so when no clone is found the message says where to put one.
TEMPLATE_DIR=""
for cand in "${CLAUDE_TEMPLATE_DIR:-}" "$HOME/repos/Claude" "$HOME/repos/claude"; do
  [ -n "$cand" ] || continue
  if [ -f "$cand/scripts/sync-prompt.md" ] && [ -d "$cand/.claude/rules" ]; then
    TEMPLATE_DIR="$cand"; break
  fi
done

# ------------------------------------------------- the write that changes nothing (spec 039)
# The path alone said CORE, and that used to be the whole verdict. So the first sync on a fresh
# project, placing every CORE file with the template's own bytes, was refused by the guard that
# exists to keep those files equal to the template (hetznerradar, 2026-09-07, scripts/tlc-cleanup.sh).
# The only way through was ALLOW_CORE_MACHINERY_EDIT=1, and an override spent on routine bootstrap
# stops meaning anything by the time a real local repair needs it.
#
# A write that leaves the file byte-identical to <template>/<rel> diverges from nothing. So compute
# the bytes the tool call would leave on disk and compare them. Write carries them; Edit and
# MultiEdit are applied to the current file here, first occurrence or replace_all, with split/join
# so no offset is ever computed and non-ASCII content cannot shift one.
#
# Every doubt denies. No template clone, no template copy of the file, a payload with no bytes
# (the Bash route hands this guard a path only), an Edit on a file that does not exist, an
# old_string that is not there, a jq that fails, a CRLF translation on some platform's jq: each one
# falls through to the deny below, which is what this guard did before. The allow has to be proven.
if [ -n "$TEMPLATE_DIR" ] && [ -f "$TEMPLATE_DIR/$REL" ]; then
  if [ -f "$FILE" ] && [ -r "$FILE" ]; then CUR="$FILE"; EXISTS=true
  else CUR=/dev/null; EXISTS=false; fi
  RESULT_TMP=$(mktemp 2>/dev/null || mktemp -t coreguard 2>/dev/null) || RESULT_TMP=""
  if [ -n "$RESULT_TMP" ]; then
    if printf '%s' "$INPUT" | jq -j --rawfile cur "$CUR" --argjson exists "$EXISTS" '
        def apply($e):
          ($e.old_string // "") as $o | ($e.new_string // "") as $n |
          if ($o | type) != "string" or $o == "" or ($n | type) != "string" then error("unusable edit")
          elif ($e.replace_all // false) == true then split($o) | join($n)
          else split($o) as $p
            | if ($p | length) < 2 then error("old_string not found")
              else $p[0] + $n + ($p[1:] | join($o)) end
          end;
        .tool_input as $t
        | if ($t | has("content")) then
            (if ($t.content | type) == "string" then $t.content else error("content is not a string") end)
          elif ($t | has("edits")) then
            (if $exists then reduce $t.edits[] as $e ($cur; apply($e)) else error("no current file") end)
          elif ($t | has("old_string")) then
            (if $exists then $cur | apply($t) else error("no current file") end)
          else error("no bytes in this payload") end
      ' > "$RESULT_TMP" 2>/dev/null \
       && cmp -s "$RESULT_TMP" "$TEMPLATE_DIR/$REL"; then
      rm -f "$RESULT_TMP"
      exit 0
    fi
    rm -f "$RESULT_TMP"
  fi
fi

if [ -n "$TEMPLATE_DIR" ]; then
  WHERE="  $TEMPLATE_DIR/$REL

Edit it there, commit and push the template, then bring it here the way every other project gets it:

  bash $ROOT/scripts/template-autosync.sh --force"
else
  WHERE="No local template clone was found at \$CLAUDE_TEMPLATE_DIR, ~/repos/Claude or ~/repos/claude.
Clone it first — scripts/sync-prompt.md Step -1 has the command — then edit $REL there and re-sync."
fi

REASON="BLOCKED — $REL is not this project's file to edit.

$REASON_BODY

Where the change goes instead:

$WHERE

Why this is a hard stop and not a warning: a warning is what the last two attempts had. Spec 007ak shipped 59 lines into scripts/template-autosync.sh and a sync deleted them the next morning; spec 007al restored them by hand knowing exactly why they had vanished, and a second sync deleted them again nineteen hours later. Across every commit this project has made to a CORE file outside a sync, the lines that survive today are exactly the lines the template also has — twelve cases, no exceptions. An edit that lives only here is already lost.

Ask the classifier yourself about any path:

  bash scripts/template-autosync.sh --is-core <project-relative-path>
  # 0 = CORE (the template owns it) · 1 = yours · 2 = cannot answer

A write whose bytes are byte-identical to the template's copy passes this guard on its own, so a sync placing the template's file is never what gets refused here. This write would leave the file different from the template — or there was no template clone to compare it with, and then nothing proves it harmless.

If you are knowingly making a temporary local repair — restoring work a sync deleted, say — set ALLOW_CORE_MACHINERY_EDIT=1 for the session. It still has to land in the template afterwards, or the next sync takes it back.

This guard is scoped to the CORE set only. Every other file under scripts/ and .claude/rules/ is yours, and the three pipeline guards deliberately leave all of scripts/** open so the tooling can always be repaired."

jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
