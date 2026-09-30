#!/bin/bash
# SessionStart hook: orients to specs/INDEX.md.
#
# Case 1: register exists → tell Claude the counts and the next unchecked spec,
#         so it knows which row is on deck.
# Case 2: register missing AND project has language markers → bootstrap reminder.
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

# SPEC 046 — this brief is written FOR Claude: which row is next, what is due,
# what the run log said last time. It went out as `systemMessage`, which the CLI
# defines as "Warning shown to user in UI", and the UI renders one notification
# per line — so a 26-line orientation became 26 red warnings at every /clear.
# additionalContext puts it where it was always addressed.
. "$_ORIENT_SCRIPT_DIR/hook-notice.sh"

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
        # A STANDING row is a pointer, not work — the same reason "- [!]" is
        # excluded above. .claude/rules/carve-budget.md gives every register one
        # "T0 — harness-defects — standing" row pointing at the template register;
        # it owes no artifacts and is never carved from. Without this, the two
        # projects whose other rows were all ticked greeted every session with
        # "next: T0 — harness-defects" as the spec to build.
        #
        # Both spellings, because agentcrm, consultpilot and msroute write their
        # registers in Swedish.
        if ($0 ~ /—[[:space:]]*(standing|st\303\245ende)[[:space:]]*—/) next
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
  # print a loud reminder per .claude/rules/spec-hardening.md.
  #
  # MATCHED ON THE TRACK FIELD, NOT THE ROW'S TEXT (test-pipeline-hooks.sh). This used to lower-case
  # the WHOLE row and glob it, so the word "checkpoint" anywhere — in a slug, in the
  # one-line goal — did two wrong things at once: it fired this banner on a row that is
  # not full-track, and it silenced the every-5 integration-checkpoint alarm below,
  # whose `case` reads the same variable. A downstream project's own slug contained the
  # word, which is how it was found; the fix has now been lost to a sync TWICE, which is
  # why it lives upstream rather than only in the project that needed it.
  #
  # A slug must not be able to switch off a gate. The register row format is
  # `id — slug — track — goal`, so field 3 is the track and is the only field either
  # decision may read.
  NEXT_LC=$(printf '%s' "$NEXT_LINE" | tr '[:upper:]' '[:lower:]')

  # Field 3, em-dash separated. When the row does not parse into >= 3 fields the
  # fallback is the WHOLE line — deliberately the old behaviour, because the two
  # decisions downstream fail in opposite directions and both are safe that way: an
  # unnecessary /clear reminder costs a sentence, and a checkpoint-due alarm that fires
  # when it need not is noise, while missing either is the hygiene loss the banner and
  # the cadence exist to prevent. Failing toward the reminder, never away from it.
  NEXT_TRACK=$(printf '%s' "$NEXT_LC" | awk -F' — ' 'NF >= 3 { print $3; found = 1 } END { if (!found) print "" }')
  [ -z "$NEXT_TRACK" ] && NEXT_TRACK="$NEXT_LC"
  CLEAR_BANNER=""
  case "$NEXT_TRACK" in
    *hardened*|*checkpoint*|*"full track"*|*"full-track"*)
      CLEAR_BANNER="
▶ START THIS SPEC IN A FRESH SESSION — run /clear now.
  This is a full-track / hardened / checkpoint row (per .claude/rules/spec-hardening.md).
  A hook cannot clear context for you. If this session already carries unrelated
  work, stop, run /clear, and resume the spec fresh. (Already fresh → just proceed.)"
      ;;
  esac

  # What this project OWES, and what made it owe it. The checkpoint cadence below has worked this
  # way since spec-hardening.md was written -- see checkpoint-cadence.sh -- and it was the only recurring job with a
  # due state. maintenance-due.sh generalises it to the other four, so a stale mutation gate or an
  # unrun suite is surfaced here rather than depending on a nightly cron firing on a sleeping
  # laptop. Delegated, never recomputed: three readers, one engine.
  MAINT_DUE=""
  if [ -x "${_ORIENT_SCRIPT_DIR}/maintenance-due.sh" ] || [ -f "${_ORIENT_SCRIPT_DIR}/maintenance-due.sh" ]; then
    MAINT_DUE=$(cd "$PROJECT_ROOT" 2>/dev/null && bash "${_ORIENT_SCRIPT_DIR}/maintenance-due.sh" --brief 2>/dev/null)
    [ -n "$MAINT_DUE" ] && MAINT_DUE="
$MAINT_DUE"
  fi

  # Cross-spec integration-hardening checkpoint cadence (.claude/rules/spec-hardening.md).
  # Delegated to checkpoint-cadence.sh, never recomputed here. This used to be `DONE % 5` over every
  # ticked row, which counted H rows and carved rows as feature specs (fundit F211: "due" with four
  # feature specs since H2) and went silent at 6 on a checkpoint that was never worked (spec 068).
  # Nothing to flag when the next row already is the checkpoint.
  CHECKPOINT_DUE=""
  case "$NEXT_TRACK" in
    *checkpoint*) : ;;
    *)
      if [ -f "${_ORIENT_SCRIPT_DIR}/checkpoint-cadence.sh" ]; then
        _CADENCE=$(bash "${_ORIENT_SCRIPT_DIR}/checkpoint-cadence.sh" --dir "$PROJECT_ROOT" 2>/dev/null)
        case "$_CADENCE" in
          *due=1)
            _CP_COUNT=$(printf '%s' "$_CADENCE" | sed -n 's/.*count=\([0-9]*\).*/\1/p')
            _CP_SINCE=$(printf '%s' "$_CADENCE" | sed -n 's/^since=\([^ ]*\).*/\1/p')
            if [ "$_CP_SINCE" = "none" ]; then _CP_SINCE="the start of the register"; fi
            CHECKPOINT_DUE="
⚠ INTEGRATION-HARDENING CHECKPOINT DUE — ${_CP_COUNT} feature specs since ${_CP_SINCE}.
  Per .claude/rules/spec-hardening.md, insert + work an integration-hardening
  checkpoint row (full-system regression + security sweep + scenario reconciliation
  + mutation spot-check) BEFORE the next feature spec. Do not skip it silently."
            ;;
        esac
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
  # Row 017: the 300-byte row budget and this canary do not compose. msroute kept every row inside
  # budget and still sat at 29 KB (ticked rows, nothing left to archive); agentcrm's 59 KB was
  # prose inside ## Specs. Both were told to run the row archiver, which had nothing to do. So the
  # register is measured by part, and the advice is whatever register-bytes.sh says moves the
  # bytes. A register with no move is not "actionable": one info line, no attention mode.
  # Helper missing or failing (a partial sync) -> IDX_MOVES stays empty and IDX_PARTS unset, and
  # the old wording below is used. The canary must never go silent because a helper is absent.
  IDX_PARTS=""; IDX_MOVES=""; SIZE_NOTE=""
  if [ "$IDX_BYTES" -gt "$WARN_THRESH" ]; then
    if IDX_RB=$(bash "${_ORIENT_SCRIPT_DIR}/register-bytes.sh" "$FOUND_REG" 2>/dev/null) && [ -n "$IDX_RB" ]; then
      _rb() { printf '%s\n' "$IDX_RB" | sed -n "s/^$1=\([0-9]*\) share=\([0-9]*\).*/\\$2/p"; }
      IDX_PARTS="rows $(( $(_rb rows 1) / 1024 )) KB ($(_rb rows 2)%), prose $(( $(_rb prose 1) / 1024 )) KB ($(_rb prose 2)%), history $(( $(_rb history 1) / 1024 )) KB ($(_rb history 2)%)"
      IDX_MOVES=$(printf '%s\n' "$IDX_RB" | sed -n 's/^move=\([a-z]*\) \(.*\)/  · \1: \2/p')
    fi
    if [ -n "$IDX_PARTS" ] && [ -z "$IDX_MOVES" ]; then
      SIZE_NOTE="
· INDEX.md $((IDX_BYTES/1024)) KB (${IDX_PARTS}) — every part complies; nothing archives it further. Read it targeted."
    else
      BLOATED="INDEX.md ($((IDX_BYTES/1024)) KB)"
    fi
  fi
  if [ "$SCEN_BYTES" -gt "$WARN_THRESH" ]; then
    [ -n "$BLOATED" ] && BLOATED="$BLOATED, SCENARIOS.md ($((SCEN_BYTES/1024)) KB)" || BLOATED="SCENARIOS.md ($((SCEN_BYTES/1024)) KB)"
  fi

  # Spec 007bl: on a project whose map outgrew one file, SCENARIOS.md keeps only the use-case
  # diagram and a per-feature index, and the rows live in specs/scenarios/<slug>.md. Measuring
  # the index alone there reports a healthy 9 KB while the file a spec actually opens is its
  # feature file — the canary would go blind at exactly the moment it started mattering, which
  # is how the map reached 85 KB in the first place: no single edit ever looked large.
  #
  # Each feature file is measured SEPARATELY and never summed. Nothing reads all of them in one
  # spec, so a sum would fire permanently on a map behaving exactly as designed — recreating the
  # un-actionable warning 007bl exists to remove. Every file over the threshold is named, not
  # just the largest: "your biggest file is too big" sends the reader back for the next one.
  if [ -d "${PROJECT_ROOT}/specs/scenarios" ]; then
    for _scen in "${PROJECT_ROOT}"/specs/scenarios/*.md; do
      [ -f "$_scen" ] || continue
      _sb=$(wc -c < "$_scen" 2>/dev/null | tr -d ' ') || _sb=0
      _sb=${_sb:-0}
      if [ "$_sb" -gt "$WARN_THRESH" ]; then
        _sn="scenarios/$(basename "$_scen") ($((_sb/1024)) KB)"
        [ -n "$BLOATED" ] && BLOATED="$BLOATED, $_sn" || BLOATED="$_sn"
      fi
    done
  fi
  if [ -n "$BLOATED" ]; then
    # Row 008: the archivers below shrink INDEX.md and history sections, never an SC row. Sent at
    # a 121 KB map they return a few hundred bytes and the same warning, which is how 17 maps sat
    # over this line unheeded. A map gets its own remedy, and the maintenance pass records it.
    MAP_REMEDY=""
    case "$BLOATED" in
      *SCENARIOS.md*|*scenarios/*) MAP_REMEDY="
  Scenario map: the archivers do not shrink it — split the map (or the feature
  file) per 'Keep the map lean' in .claude/rules/scenarios.md.
  scripts/project-maintenance.sh records each one in specs/FINDINGS.md." ;;
    esac
    # Row 017: when the register was measured, name its parts and only the moves that exist.
    IDX_REMEDY=""
    case "$BLOATED" in
      *INDEX.md*)
        if [ -n "$IDX_MOVES" ]; then
          IDX_REMEDY="
  INDEX.md is ${IDX_PARTS}. What shrinks it, largest part first:
${IDX_MOVES}"
        else
          IDX_REMEDY="
  INDEX.md: run scripts/archive-completed-rows.sh (archives completed rows to
  *.completed.md, reports rows over the 300-byte budget) or
  scripts/archive-spec-history.sh (moves old history to *.history.md)."
        fi ;;
    esac
    SIZE_WARN="
⚠ CONTEXT-COST CANARY — large per-spec files: ${BLOATED}.
  These are read every spec. Trim before continuing, and read these files
  TARGETED (only the next row / the current feature's SC rows), never whole.
  See 'Keep the register lean' / 'Keep the map lean' in .claude/rules/.${IDX_REMEDY}${MAP_REMEDY}"
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

  # Is the register closing faster than it grows? (.claude/rules/carve-budget.md)
  # This is the only banner that describes the project's direction rather than its
  # state, and it belongs at SessionStart because the decision it informs -- carve
  # another row, or fold the findings -- is made at the start of a spec, not after.
  # The check is lazy: a handful of `git show` calls, ~1-2 s on a 359 KB register.
  CONVERGE_WARN=""
  if [ -x "$PROJECT_ROOT/scripts/register-convergence.sh" ]; then
    # Capture the exit code from the SCRIPT, not from the `head` that trims it --
    # piping first makes $? the trimmer's, which is always 0, and the banner then
    # never fires however badly the register diverges.
    CONV_RAW=$(cd "$PROJECT_ROOT" && bash scripts/register-convergence.sh --quiet 2>/dev/null)
    CONV_RC=$?
    CONV_LINE=$(printf '%s\n' "$CONV_RAW" | head -1)
    # A developer who already answered the stop with a freeze (row 077) should not be asked again
    # every session. The freeze line replaces the three-ways-out banner and says what it permits.
    FREEZE_LINE=$(cd "$PROJECT_ROOT" && bash scripts/register-convergence.sh --freeze 2>/dev/null)
    FREEZE_RC=$?
    FREEZE_LINE=$(printf '%s\n' "$FREEZE_LINE" | head -1)
    # Only 0/2/3 are a freeze. 4 (malformed line) is surfaced on its own and does NOT silence the
    # convergence stop; 5/127 (cannot evaluate: partial sync, no python3) fall through to it.
    FREEZE_BAD=""
    [ "$FREEZE_RC" = "4" ] && FREEZE_BAD="
⚠ ${FREEZE_LINE} — fix the line; until then the freeze is not in force."
    if [ "$FREEZE_RC" = "0" ] || [ "$FREEZE_RC" = "2" ] || [ "$FREEZE_RC" = "3" ]; then
      CONVERGE_WARN="
${CONV_LINE:+· ${CONV_LINE}
}⚠ ${FREEZE_LINE}
  FREEZE (carve-budget.md §6): no new rows. A finding goes to scripts/finding.sh --add; a row
  someone needs is a proposal (--propose-row --need \"<evidence>\"), presented for approve/decline
  at this spec's stop (finding.sh --review --proposals). An approved row carries \"approved F<nnn>\"."
      [ "$FREEZE_RC" = "2" ] && CONVERGE_WARN="${CONVERGE_WARN}
  Rows above were added without an approved proposal: surface them to the developer (approve or cut)."
    elif [ "$CONV_RC" = "2" ] && [ -n "$CONV_LINE" ]; then
      CONVERGE_WARN="
⚠ ${CONV_LINE}
  Per .claude/rules/carve-budget.md this is a CONVERGENCE STOP. Work the current row,
  then stop and put the three ways out to the developer (freeze carving · batch the open
  spec-only rows into one · cut what no longer matters). Do not carve further rows in the
  meantime: a finding gets fixed in place, or declined in the run log with a reason."
    elif [ "$CONV_RC" = "1" ] && [ -n "$CONV_LINE" ]; then
      CONVERGE_WARN="
· ${CONV_LINE}"
    fi
  fi

  ACTIONABLE="${CHECKPOINT_DUE}${CLEAR_BANNER}${SIZE_WARN}${RUNLOG_TAIL}${DUP_WARN}${CONVERGE_WARN}${FREEZE_BAD:-}${MAINT_DUE}"
  if [ -z "$ACTIONABLE" ] && [ "$BLOCK" -eq 0 ] && [ "$PROG" -eq 0 ]; then
    MSG="Register: ${DONE}/${TOTAL} done${LANE:+ · lane @${LANE}} · next: ${NEXT_LINE} · (.claude/rules/spec-register.md — one spec end-to-end, then stop)${SIZE_NOTE}"
    notice_model SessionStart "$MSG"
    exit 0
  fi

  MSG="Spec register: ${FOUND_REG}
Totals — Total: ${TOTAL} | Done: ${DONE} | In-progress: ${PROG} | Blocked: ${BLOCK} | Todo: ${TODO}
Next: ${NEXT_LINE}${LANE_NOTE}${DUP_WARN}${CONVERGE_WARN}${FREEZE_BAD:-}${CHECKPOINT_DUE}${MAINT_DUE}${CLEAR_BANNER}${SIZE_WARN}${SIZE_NOTE}${RUNLOG_TAIL}

Per .claude/rules/spec-register.md: work this row end-to-end through the pipeline, commit and push to the working branch directly (that rule and .claude/rules/project-workflow.md are solo/direct-push — no feature branch, no PR, no merge step, unless this project's own workflow memory says otherwise), tick the register, then stop with the status summary. No mid-spec stops except real ambiguity, hard blocker, Allium/TLA+ findings, or a register-rewrite proposal."
  notice_model SessionStart "$MSG"
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
  notice_model SessionStart "$MSG"
  exit 0
fi

# Case 3: template/scratch → silent
exit 0
