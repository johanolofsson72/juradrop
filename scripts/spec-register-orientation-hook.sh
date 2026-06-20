#!/bin/bash
# SessionStart hook: orients to specs/INDEX.md.
#
# Case 1: register exists → emit a status systemMessage with counts and the
#         next unchecked spec. Tells Claude exactly which row is on deck.
# Case 2: register missing AND project has language markers → emit a bootstrap
#         reminder systemMessage.
# Case 3: register missing AND no language markers (template/scratch) → silent.
#
# Walk semantics match scripts/spec-register-guard-hook.sh: walk up from $PWD
# collecting markers, stop at the first .git boundary. Never walk past a repo
# root — protects template/scratch dirs from picking up unrelated parent-dir
# language markers.

set -u

DIR="$PWD"
FOUND_REG=""
LANG_MARKER=""
PROJECT_ROOT=""
REPO_FOUND=0

while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -z "$FOUND_REG" ] && [ -f "$DIR/specs/INDEX.md" ]; then
    FOUND_REG="$DIR/specs/INDEX.md"
    [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"
  fi
  if [ -z "$LANG_MARKER" ]; then
    for marker in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile build.gradle build.gradle.kts pom.xml pubspec.yaml; do
      if [ -f "$DIR/$marker" ]; then LANG_MARKER="$marker"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"; break; fi
    done
  fi
  if [ -z "$LANG_MARKER" ]; then
    if ls "$DIR"/*.csproj >/dev/null 2>&1; then LANG_MARKER="*.csproj"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"; fi
  fi
  if [ -z "$LANG_MARKER" ]; then
    if ls "$DIR"/*.sln >/dev/null 2>&1; then LANG_MARKER="*.sln"; [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"; fi
  fi
  if [ -d "$DIR/.git" ]; then
    REPO_FOUND=1
    [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done

# Case 1: register exists → status line
if [ -n "$FOUND_REG" ]; then
  DONE=$(grep -cE '^- \[x\]' "$FOUND_REG" 2>/dev/null) || DONE=0
  PROG=$(grep -cE '^- \[/\]' "$FOUND_REG" 2>/dev/null) || PROG=0
  BLOCK=$(grep -cE '^- \[!\]' "$FOUND_REG" 2>/dev/null) || BLOCK=0
  TODO=$(grep -cE '^- \[ \]' "$FOUND_REG" 2>/dev/null) || TODO=0
  DONE=${DONE:-0}; PROG=${PROG:-0}; BLOCK=${BLOCK:-0}; TODO=${TODO:-0}
  TOTAL=$((DONE + PROG + BLOCK + TODO))
  [ "$TOTAL" -eq 0 ] && exit 0

  NEXT_LINE=$(grep -m1 -E '^- \[[ /!]\]' "$FOUND_REG" 2>/dev/null | sed -E 's/^- \[[ /!]\] //' || true)
  [ -z "$NEXT_LINE" ] && NEXT_LINE="(register complete — all ${TOTAL} specs done)"

  # Big-spec context hygiene: full-track / hardened / checkpoint rows want a
  # fresh session. A hook cannot run /clear (it is a harness built-in), so we
  # print a loud reminder per .claude/rules/spec-hardening.md. Case-insensitive
  # match on the next row's text.
  NEXT_LC=$(printf '%s' "$NEXT_LINE" | tr '[:upper:]' '[:lower:]')
  CLEAR_BANNER=""
  case "$NEXT_LC" in
    *hardened*|*checkpoint*|*"full track"*|*"full-track"*)
      CLEAR_BANNER="
▶ START THIS SPEC IN A FRESH SESSION — run /clear now.
  This is a full-track / hardened / checkpoint row (per .claude/rules/spec-hardening.md).
  A hook cannot clear context for you. If this session already carries unrelated
  work, stop, run /clear, and resume the spec fresh. (Already fresh → just proceed.)"
      ;;
  esac

  # Cross-spec integration-hardening checkpoint cadence (every 5 completed specs).
  # If DONE is a nonzero multiple of 5 and the next row is NOT already a checkpoint,
  # flag that a checkpoint row is due before the next feature spec.
  CHECKPOINT_DUE=""
  case "$NEXT_LC" in
    *checkpoint*) : ;;  # already on a checkpoint row — nothing to flag
    *)
      if [ "$DONE" -gt 0 ] && [ $((DONE % 5)) -eq 0 ]; then
        CHECKPOINT_DUE="
⚠ INTEGRATION-HARDENING CHECKPOINT DUE — ${DONE} specs done (multiple of 5).
  Per .claude/rules/spec-hardening.md, insert + work an integration-hardening
  checkpoint row (full-system regression + security sweep + scenario reconciliation
  + mutation spot-check) BEFORE the next feature spec. Do not skip it silently."
      fi
      ;;
  esac

  MSG="Spec register: ${FOUND_REG}
Totals — Total: ${TOTAL} | Done: ${DONE} | In-progress: ${PROG} | Blocked: ${BLOCK} | Todo: ${TODO}
Next: ${NEXT_LINE}${CHECKPOINT_DUE}${CLEAR_BANNER}

Per .claude/rules/spec-register.md: work this row end-to-end through the pipeline, commit + push to main, tick the register, then stop with the status summary. No mid-spec stops except real ambiguity, hard blocker, Allium/TLA+ findings, or a register-rewrite proposal."
  jq -n --arg m "$MSG" '{systemMessage: $m}'
  exit 0
fi

# Case 2: no register, but project has language markers → bootstrap reminder
if [ -n "$LANG_MARKER" ]; then
  MSG="No spec register at ${PROJECT_ROOT}/specs/INDEX.md but project has code (${LANG_MARKER}). Per .claude/rules/spec-register.md, the register MUST exist BEFORE any development. The PreToolUse guard (scripts/spec-register-guard-hook.sh) will block source-code edits until you create it.

Bootstrap:
  1. AskUserQuestion → identify the initial set of specs and their order.
  2. Triage each per .claude/rules/specs.md (full / light / spec-only).
  3. Write specs/INDEX.md with the register + a dated Register history entry.
  4. git commit + git push origin main.
  5. Then start spec 001 with /specify."
  jq -n --arg m "$MSG" '{systemMessage: $m}'
  exit 0
fi

# Case 3: template/scratch → silent
exit 0
