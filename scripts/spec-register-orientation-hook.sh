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

  # Context-cost canary: INDEX.md and SCENARIOS.md are read (sometimes re-read)
  # on every spec. When either balloons, every subsequent spec pays for it. Warn
  # once at session start so the bloat is visible and gets archived, rather than
  # silently re-billed. Threshold ~25 KB (~6k tokens). `wc -c` is portable.
  SIZE_WARN=""
  WARN_THRESH=25600
  SCEN_FILE="${PROJECT_ROOT}/specs/SCENARIOS.md"
  IDX_BYTES=$(wc -c < "$FOUND_REG" 2>/dev/null | tr -d ' ') || IDX_BYTES=0
  SCEN_BYTES=0
  [ -f "$SCEN_FILE" ] && { SCEN_BYTES=$(wc -c < "$SCEN_FILE" 2>/dev/null | tr -d ' ') || SCEN_BYTES=0; }
  IDX_BYTES=${IDX_BYTES:-0}; SCEN_BYTES=${SCEN_BYTES:-0}
  BLOATED=""
  [ "$IDX_BYTES" -gt "$WARN_THRESH" ] && BLOATED="INDEX.md ($((IDX_BYTES/1024)) KB)"
  if [ "$SCEN_BYTES" -gt "$WARN_THRESH" ]; then
    [ -n "$BLOATED" ] && BLOATED="$BLOATED, SCENARIOS.md ($((SCEN_BYTES/1024)) KB)" || BLOATED="SCENARIOS.md ($((SCEN_BYTES/1024)) KB)"
  fi
  if [ -n "$BLOATED" ]; then
    SIZE_WARN="
⚠ CONTEXT-COST CANARY — large per-spec files: ${BLOATED}.
  These are read every spec. Trim before continuing: run
  scripts/archive-spec-history.sh (moves old history to *.history.md), and read
  these files TARGETED (only the next row / the current feature's SC rows), never
  whole. See 'Keep the register lean' / 'Keep the map lean' in .claude/rules/."
  fi

  # Failure memory for a resumed spec: when a row is mid-flight ("- [/]"), show
  # the TAIL of its run log so a fresh session knows what already went wrong
  # (escalated interview answer, failed gate, deferred finding) instead of
  # rediscovering it. Tail only — the log is never pipeline input.
  RUNLOG_TAIL=""
  if [ "$PROG" -gt 0 ]; then
    IP_ROW=$(grep -m1 -E '^- \[/\]' "$FOUND_REG" 2>/dev/null | sed -E 's/^- \[.\] *//')
    IP_ID=$(printf '%s' "$IP_ROW" | awk '{print $1}')
    IP_SLUG=$(printf '%s' "$IP_ROW" | awk -F' — ' '{print $2}' | tr -d ' ')
    for cand in "${PROJECT_ROOT}/specs/${IP_ID}-${IP_SLUG}/run-log.md" "${PROJECT_ROOT}/.specify/specs/${IP_ID}-${IP_SLUG}/run-log.md"; do
      if [ -f "$cand" ]; then
        TAIL_LINES=$(grep -E '^- ' "$cand" 2>/dev/null | tail -5)
        [ -n "$TAIL_LINES" ] && RUNLOG_TAIL="
Run log (last 5, ${cand#$PROJECT_ROOT/}):
${TAIL_LINES}"
        break
      fi
    done
  fi

  # Quiet mode vs attention mode. A SessionStart advisory that prints the same
  # paragraph every session is a fixed context tax on EVERY session, forever, and
  # it trains the reader to skim past exactly the sessions where it matters. So:
  # the full block prints only when something is actually actionable (checkpoint
  # due / fresh-context banner / size canary / a blocked or in-flight row);
  # otherwise the register collapses to a single line.
  ACTIONABLE="${CHECKPOINT_DUE}${CLEAR_BANNER}${SIZE_WARN}${RUNLOG_TAIL}"
  if [ -z "$ACTIONABLE" ] && [ "$BLOCK" -eq 0 ] && [ "$PROG" -eq 0 ]; then
    MSG="Register: ${DONE}/${TOTAL} done · next: ${NEXT_LINE} · (.claude/rules/spec-register.md — one spec end-to-end, then stop)"
    jq -n --arg m "$MSG" '{systemMessage: $m}'
    exit 0
  fi

  MSG="Spec register: ${FOUND_REG}
Totals — Total: ${TOTAL} | Done: ${DONE} | In-progress: ${PROG} | Blocked: ${BLOCK} | Todo: ${TODO}
Next: ${NEXT_LINE}${CHECKPOINT_DUE}${CLEAR_BANNER}${SIZE_WARN}${RUNLOG_TAIL}

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
