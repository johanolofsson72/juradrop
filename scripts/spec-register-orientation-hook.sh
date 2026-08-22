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

# H6s2 finding 1 — the resolver is a sibling of THIS FILE, not of the project
# being oriented. Looked up under "$PROJECT_ROOT/scripts/" it went missing in any
# project whose scripts/ does not carry it (a truncated autosync: the .py pass
# runs after every .sh), and both consequences were silent — the run-log tail,
# which is the whole point of a run log for a freshly-cleared session, simply did
# not appear, and --sync-feature-json did not run, leaving spec-kit's
# feature.json naming the PREVIOUS spec. That last one is the defect 007m exists
# to prevent, re-entering through the lookup path rather than the parser.
_ORIENT_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

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

  # Lane ownership. Two developers share one register, so "next" is per-lane: a row
  # carries a trailing "@name" tag and SPEC_OWNER (per machine, .claude/settings.local.json)
  # says which lane this session is in. Same rule as the two PreToolUse guards, and it has
  # to stay the same — an orientation line pointing at a row the guards will refuse to
  # unlock is worse than no orientation line. Unset SPEC_OWNER = every row, as before.
  # Untagged rows belong to nobody and stay visible in both lanes.
  LANE=$(printf '%s' "${SPEC_OWNER:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

  # Pick this lane's row, in priority order: my in-progress row → my next row → an unowned
  # in-progress row → the next unowned row. A row assigned to me beats an unowned one that
  # sits higher in the register: the order is dependency-driven, so the top of the shared
  # tail is usually blocked behind the OTHER lane's current row. Same resolution as the two
  # PreToolUse guards — an orientation line pointing at a row the guards will refuse to
  # unlock is worse than no orientation line at all.
  # $1 = "prog" to consider only in-progress rows. Empty LANE → nothing is "mine", which
  # collapses to first-[/]-else-first-[ ]: the old single-lane behaviour, unchanged.
  pick_row() {
    awk -v lane="$LANE" -v only_prog="${1:-}" '
      # "- [!]" is deliberately NOT here. A held row is one somebody stopped for a reason the
      # register cannot express as a dependency, and pointing a fresh session at it is how the
      # decision gets quietly overruled by a banner. pipeline-state-guard and
      # spec-interview-guard already match only "- [/]" and "- [ ]", so this is the line that
      # was out of step with them rather than a new rule.
      /^- \[[ \/]\]/ {
        inprog = ($0 ~ /^- \[\/\]/)
        if (only_prog != "" && !inprog) next
        owner = ""
        if (match($0, /—[[:space:]]*@[A-Za-z0-9._-]+[[:space:]]*$/)) {
          owner = substr($0, RSTART, RLENGTH)
          sub(/^—[[:space:]]*@/, "", owner); gsub(/[[:space:]]/, "", owner)
          owner = tolower(owner)
        }
        if (lane != "" && owner != "" && owner != lane) next
        mine = (lane != "" && owner == lane)
        if (mine) { if (inprog) { if (oa == "") oa = $0 } else { if (op == "") op = $0 } }
        else      { if (inprog) { if (fa == "") fa = $0 } else { if (fp == "") fp = $0 } }
      }
      END {
        if (oa != "") print oa; else if (op != "") print op
        else if (fa != "") print fa; else if (fp != "") print fp
      }' "$FOUND_REG" 2>/dev/null
  }

  NEXT_LINE=$(pick_row | sed -E 's/^- \[[ /!]\] //' || true)
  # Bound it. A register row is SUPPOSED to be "NNN — slug — track — short one-line
  # goal", but rows grow: on one real project the next row was 9096 characters and
  # this banner came to 13 KB — about 3 200 tokens, charged at every session start,
  # first thing in context. The same banner carries a canary telling the reader that
  # INDEX.md is too big to read whole; pasting the biggest row into it made this hook
  # the single largest contributor to the cost it was warning about. The row's head
  # is what orients you; the rest is in the file, which the banner names.
  #
  # Truncate by CHARACTERS, not bytes. `cut -c` is character-aware only in a UTF-8
  # locale; under LC_ALL=C — which a hook can easily inherit — it counts bytes and
  # will split a multibyte character in half. These registers are written in Swedish
  # and full of em-dashes, so that boundary is hit routinely. jq --arg does not fail
  # on the dangling bytes (it substitutes U+FFFD and still emits valid JSON), so the
  # damage is only a stray replacement character in the banner — but python3 is
  # already required by resolve-active-spec.sh two lines below, so there is no reason
  # to accept even that. cut stays as the fallback for a box without python3.
  # 800, not 240. The first cut at 240 was sized against a pathological row (9096
  # chars) and it punished the ordinary case: on msroute the NEXT row is 1632 chars
  # of actual brief and the banner cut it at "…what **changed in the rep", so the
  # thing that announces the spec no longer said what the spec was. A row is meant
  # to be a one-line goal; when it is not, the reader still needs the brief. 800
  # carries a real brief and still cuts a 9096-char essay by 91%.
  ORIENT_ROW_MAX="${ORIENT_ROW_MAX:-800}"
  if [ "${#NEXT_LINE}" -gt "$ORIENT_ROW_MAX" ]; then
    _ORIENT_FULL_LEN="${#NEXT_LINE}"
    if command -v python3 >/dev/null 2>&1; then
      _ORIENT_HEAD=$(ORIENT_ROW_MAX="$ORIENT_ROW_MAX" NEXT_LINE="$NEXT_LINE" python3 -c \
        'import os,sys; sys.stdout.write(os.environ["NEXT_LINE"][:int(os.environ["ORIENT_ROW_MAX"])])' 2>/dev/null)
    fi
    [ -n "${_ORIENT_HEAD:-}" ] || _ORIENT_HEAD=$(printf '%s' "$NEXT_LINE" | cut -c1-"$ORIENT_ROW_MAX")
    NEXT_LINE="${_ORIENT_HEAD}… [row truncated — ${_ORIENT_FULL_LEN} chars; read it in the register]"
  fi
  if [ -z "$NEXT_LINE" ]; then
    if [ -n "$LANE" ]; then
      NEXT_LINE="(no unfinished row owned by @${LANE} — the other lane has the rest; pick one up or tag one)"
    else
      NEXT_LINE="(register complete — all ${TOTAL} specs done)"
    fi
  fi
  LANE_NOTE=""
  [ -n "$LANE" ] && LANE_NOTE="
Lane: @${LANE} (SPEC_OWNER). Rows tagged for the other developer are hidden from this
  session's guards. Two developers, one register — see 'Två spår' in specs/INDEX.md."

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
  # Spec 007m — resolve the in-progress spec's directory through the ONE
  # canonical resolver, and refresh .specify/feature.json from it while here.
  #
  # The refresh is the fix for the fourth resolver. spec-kit's
  # check-prerequisites.sh reads .specify/feature.json, which is written once by
  # /speckit-specify and never updated — so for the whole of every spec it named
  # the PREVIOUS spec, and /speckit-analyze would have analysed that spec's
  # spec.md/plan.md/tasks.md while reporting clean. We deliberately do NOT patch
  # check-prerequisites.sh or common.sh: `specify init --force` regenerates them,
  # which is the same clobber trap that reverted spec 004a's fix. Instead we keep
  # spec-kit's own documented input correct, demoting feature.json from a rival
  # source of truth to a cache of the register's answer.
  RUNLOG_TAIL=""
  if [ "$PROG" -gt 0 ]; then
    # Spec 007q — the --sync-feature-json flag USED to be on this call, and that
    # was the defect: this block only runs when PROG>0 (an in-progress "- [/]"
    # row exists), because it exists to print the run-log tail. At the start of
    # every spec the row is still "- [ ]", so the refresh never ran and the cache
    # went on naming the PREVIOUS spec — the very thing H6s2's note above says it
    # costs, reached by gating instead of by lookup. The refresh now lives in
    # scripts/sync-feature-json-hook.sh, wired to SessionStart unconditionally.
    # Do not re-add the flag here; this call is only for the run-log tail.
    IP_JSON=$(bash "${_ORIENT_SCRIPT_DIR}/resolve-active-spec.sh" --root "$PROJECT_ROOT" 2>/dev/null)
    IP_DIR=$(printf '%s' "$IP_JSON" | sed -n 's/.*"dir": *"\([^"]*\)".*/\1/p')
    for cand in "${PROJECT_ROOT}/${IP_DIR}/run-log.md"; do
      if [ -n "$IP_DIR" ] && [ -f "$cand" ]; then
        # Same bound, same reason: run-log entries are specified as one line each
        # but are written by hand, and a paragraph-long one is charged every session.
        TAIL_LINES=$(grep -E '^- ' "$cand" 2>/dev/null | tail -5 | cut -c1-200)
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
  # .claude/rules/spec-register.md: "- [/] — in progress (only one spec carries
  # this at a time)". spec_active.py already computes duplicate_active and nothing
  # ever surfaced it, so a register with 33 in-progress rows looked normal in the
  # totals while "the active spec" — which all three PreToolUse guards key off —
  # was whichever one happened to sort first.
  DUP_WARN=""
  if [ "$PROG" -gt 1 ]; then
    DUP_WARN="
⚠ ${PROG} rows are marked in-progress \`- [/]\`, but the register allows ONE at a time.
  All three pipeline guards resolve \"the active spec\" from the first of them, so the
  rest are invisible to the gates. Tick the finished ones \`- [x]\`, return the
  not-actually-started ones to \`- [ ]\`, and leave exactly one \`- [/]\`."
  fi

  ACTIONABLE="${CHECKPOINT_DUE}${CLEAR_BANNER}${SIZE_WARN}${RUNLOG_TAIL}${DUP_WARN}"
  if [ -z "$ACTIONABLE" ] && [ "$BLOCK" -eq 0 ] && [ "$PROG" -eq 0 ]; then
    MSG="Register: ${DONE}/${TOTAL} done${LANE:+ · lane @${LANE}} · next: ${NEXT_LINE} · (.claude/rules/spec-register.md — one spec end-to-end, then stop)"
    jq -n --arg m "$MSG" '{systemMessage: $m}'
    exit 0
  fi

  MSG="Spec register: ${FOUND_REG}
Totals — Total: ${TOTAL} | Done: ${DONE} | In-progress: ${PROG} | Blocked: ${BLOCK} | Todo: ${TODO}
Next: ${NEXT_LINE}${LANE_NOTE}${DUP_WARN}${CHECKPOINT_DUE}${CLEAR_BANNER}${SIZE_WARN}${RUNLOG_TAIL}

Per .claude/rules/spec-register.md: work this row end-to-end through the pipeline, commit and push to the working branch directly (that rule and .claude/rules/project-workflow.md are solo/direct-push — no feature branch, no PR, no merge step, unless this project's own workflow memory says otherwise), tick the register, then stop with the status summary. No mid-spec stops except real ambiguity, hard blocker, Allium/TLA+ findings, or a register-rewrite proposal."
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
