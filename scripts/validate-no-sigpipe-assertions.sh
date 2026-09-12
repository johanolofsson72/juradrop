#!/usr/bin/env bash
# validate-no-sigpipe-assertions.sh — rows H7x (the idiom) and H7ax (the scope predicate).
#
# WHY THIS GATE EXISTS. `set -o pipefail` is on in nine of this project's eleven self-tests, and every
# assertion in them was written `printf '%s' "$OUT" | grep -q PATTERN`. When `grep -q` finds its match it
# exits immediately; `printf` keeps writing into a reader-less pipe, takes SIGPIPE, and dies 141. Under
# `pipefail` the PIPELINE returns 141 — not grep's 0. So:
#
#   positive assertion   `if … | grep -q X`     -> a claim that HOLDS is read as one that does not (loud).
#   negated  assertion   `if ! … | grep -q X`   -> 141 inverted by `!` is TRUE, so a claim that must FAIL
#                                                  is reported PASS. A silent pass. 46 of the 215 sites
#                                                  this gate was written against were negated.
#
# MEASURED, not reasoned (Darwin 25.6, bash 3.2.57, 30 runs per point): the trigger is not the payload's
# total size, it is the number of bytes AFTER the matching line — everything before it grep has already
# read. At and above the 64 KiB pipe buffer it is certain (30/30 at 65 536, 30/30 at 262 144). BELOW the
# buffer it is a genuine race, not immunity — 1/30 still failed at 32 768, because whether printf finishes
# writing before grep leaves is a scheduling question. There is no safe size, only sizes where it happens
# rarely enough that nobody connects it to the code. And if the match and the whole tail sit on ONE line
# the pipeline is immune, because grep cannot report a match before the line ends — so exposure follows the
# text's shape as much as its length, and "our output is small enough" is not an argument that survives
# someone adding a newline.
#
# THE FIX this gate enforces: a here-string (`grep -q PAT <<< "$VAR"`), which bash materialises as a temp
# file — no pipe, no SIGPIPE, no pipefail interaction — or a direct `grep -q PAT FILE` when the source is
# a file. `PIPESTATUS` is deliberately NOT accepted: it preserves the defect behind an index.
#
# SCOPE — AND WHY IT IS NOT THE SAME QUESTION IN EVERY TREE (row H7ax).
# The exemption this gate grants is not "CORE files are fine". It is: a fix written into one would be
# eaten by the next `chore(sync)`, so nagging about it would be nagging about something unfixable — the
# H7t lesson. That is a claim about the SYNC, not about the filename, and it is only true DOWNSTREAM.
#
# In the template the same predicate inverts. There `CORE_SCRIPTS` names the files the template OWNS:
# every one of them is fixable, and the fix is durable, because it is what every project's copy comes
# from. Ported verbatim, this gate scanned 5 of the template's 22 `scripts/test-*.sh` and printed
# `clean` — exempting precisely the seventeen files the sweep it enforces was written for. A green gate
# blind to its own population is worse than no gate: it reads as an answer. So the scope is:
#
#   downstream of the template -> scripts/test-*.sh MINUS CORE_SCRIPTS  (a fix in CORE is eaten here;
#                                                                       those files are scanned upstream)
#   the template itself        -> scripts/test-*.sh, every one of them  (nothing is eaten; CORE = mine)
#
# The mode is REPORTED in every branch, with the count of files actually opened and the count exempted.
# A gate that silently changes its own population is this same defect one level up, and "how many did you
# look at" is the one number that would have caught it.
#
# WHICH TREE AM I? Asked the way the sync itself asks it (`template-autosync.sh`: *"Never sync the
# template onto itself. Identify it by remote URL — file markers are useless here because the sync copies
# scripts/sync-prompt.md and friends into every project, so every synced project looks like the
# template"*). The URL is READ from that file (`TEMPLATE_REPO_URL`), never copied — a copied slug drifts
# the day the template moves, and this gate's whole argument is that a copied boundary is a wrong one.
# A second signal answers when there is no origin remote: `.claude/.template-sync` is WRITTEN by the sync
# into every target and never exists in the template, so it escapes the file-marker objection above.
# When neither signal answers, the gate resolves toward the TEMPLATE mode: it scans everything and says
# why. Doubt resolves toward looking, never toward silence — a false nag is loud and self-correcting, a
# false silence is the defect this row exists to remove.
#
# Diagnostic pipes (inside `bad …`, inside a command substitution whose value is used) are NOT assertions:
# their exit status is never read, `bad` has already incremented FAIL, and the suite's exit code is
# computed from $FAIL. Rewriting them would be the scope creep the register forbids.
#
# Usage:  bash scripts/validate-no-sigpipe-assertions.sh [--list]
# Env:    SCAN_ROOT  tree to scan (default: this repo) · AUTOSYNC  where CORE_SCRIPTS and
#         TEMPLATE_REPO_URL are read from (default: scripts/template-autosync.sh). Both exist so the
#         self-test can drive the gate against a fixture tree; without them the gate could only ever be
#         run against whatever state the real repo happens to be in, which is how a gate ends up with no
#         red case (H5b).
# Exit:   0 clean, or NOT RUN when the exemption emptied the population — the two are worded apart and
#           never both called "clean" · 1 at least one assertion carries the idiom · 2 nothing to scan,
#           or a boundary the gate refuses to guess (a fault, not silence)
#
# Covers: SC-1728 SC-1731 SC-1732 SC-1733 SC-1734 SC-1735 SC-1746 SC-1747 SC-1748 SC-1749 SC-1750
#         SC-1751 SC-1752

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the self-test can point the gate at a fixture tree. Without this the gate could only ever
# be driven against the real repo, i.e. against whatever state it happens to be in — which is how a gate
# ends up with no red case (H5b).
SCAN_ROOT="${SCAN_ROOT:-$REPO_ROOT}"
AUTOSYNC="${AUTOSYNC:-$REPO_ROOT/scripts/template-autosync.sh}"

LIST=0
[ "${1:-}" = "--list" ] && LIST=1

# --- the CORE boundary --------------------------------------------------------------------------------
# Read from template-autosync.sh rather than copied here. A copy drifts the moment upstream adds a script,
# and a gate that is wrong about which files it owns is worse than no gate: it either nags about files it
# cannot fix, or goes quiet about files it can.
core_names() {
  [ -r "$AUTOSYNC" ] || return 0
  sed -n '/^CORE_SCRIPTS="/,/"$/p' "$AUTOSYNC" \
    | sed 's/^CORE_SCRIPTS="//; s/"$//' \
    | tr ' \t' '\n\n' \
    | grep -E '\.(sh|py)$' || true
}
CORE_LIST="$(core_names)"
if [ -z "$CORE_LIST" ]; then
  echo "ERROR: could not read CORE_SCRIPTS from $AUTOSYNC — refusing to guess which files the sync owns." >&2
  echo "       Without that boundary this gate cannot tell a durable fix from one the next sync eats." >&2
  exit 2
fi

is_core() { grep -qxF "$1" <<< "$CORE_LIST"; }

# --- which tree is this, and does the CORE exemption apply here at all? (row H7ax) ---------------------
# See the SCOPE block at the top. The answer is carried in two variables and both are printed: the mode,
# and the SIGNAL that decided it. A mode nobody can trace is a mode nobody can argue with, and this gate
# was blind upstream for exactly as long as nobody could see which population it had chosen.
template_slug() {
  [ -r "$AUTOSYNC" ] || return 0
  sed -n 's|^TEMPLATE_REPO_URL="[^"]*[/:]\([^/"]*/[^/"]*\)\.git".*|\1|p' "$AUTOSYNC" | head -1
}

# Only the toplevel counts. A sandbox created inside some other checkout would otherwise inherit THAT
# repo's origin and be classified by a repository it is not part of — which, in this gate's own self-test,
# would mean every fixture answering "downstream" because the test harness lives in a project.
scan_root_origin() {
  local top phys
  top="$(git -C "$SCAN_ROOT" rev-parse --show-toplevel 2>/dev/null)" || return 0
  phys="$(cd "$SCAN_ROOT" 2>/dev/null && pwd -P)" || return 0
  [ "$top" = "$phys" ] || return 0
  git -C "$SCAN_ROOT" remote get-url origin 2>/dev/null || true
}

SLUG="$(template_slug)"
ORIGIN="$(scan_root_origin)"
if [ -n "$SLUG" ] && [ -n "$ORIGIN" ]; then
  case "$ORIGIN" in
    *"$SLUG"|*"$SLUG".git|*"$SLUG"/|*"$SLUG".git/)
      EXEMPT_SYNC_OWNED=0; MODE_WHY="origin is $SLUG" ;;
    *)
      EXEMPT_SYNC_OWNED=1; MODE_WHY="origin is $ORIGIN, which is not $SLUG" ;;
  esac
elif [ -f "$SCAN_ROOT/.claude/.template-sync" ]; then
  EXEMPT_SYNC_OWNED=1; MODE_WHY=".claude/.template-sync is present — the sync writes it into every target"
else
  EXEMPT_SYNC_OWNED=0
  MODE_WHY="neither an origin remote nor a sync stamp answers — undecidable, so nothing is exempted"
fi
if [ "$EXEMPT_SYNC_OWNED" -eq 1 ]; then MODE_LABEL="downstream"; else MODE_LABEL="template"; fi

# --- heredoc bodies are fixture DATA, not code --------------------------------------------------------
# A self-test that drives this gate has to write the banned idiom into a fixture file, and it does that
# with `cat > … <<'EOF'`. Those lines are the test's input, not its assertions — flagging them would make
# the gate impossible to test, which is the same trap as flagging the comment that explains it.
# The exemption is narrow on purpose: only lines strictly between a heredoc opener and its terminator.
# `<<<` (a here-string, the replacement this gate recommends) is not a heredoc opener and does not match.
heredoc_lines() {
  awk '
    inhd {
      t = $0
      sub(/^[[:space:]]+/, "", t)          # <<- strips leading tabs from the terminator
      if (t == delim) { inhd = 0 } else { print NR }
      next
    }
    match($0, /<<-?[[:space:]]*'"'"'?"?[A-Za-z_][A-Za-z_0-9]*'"'"'?"?/) {
      s = substr($0, RSTART, RLENGTH)
      sub(/^<<-?[[:space:]]*/, "", s)
      gsub(/['"'"'"]/, "", s)
      delim = s; inhd = 1
    }
  ' "$1"
}

# --- what counts as an early-exit consumer ------------------------------------------------------------
# grep -q  : exits at the first match.
# grep -m N: exits after N matches.
# head     : exits after its line/byte budget.
# Consumers that must read all of stdin (grep -c, wc, sort, awk without exit) cannot orphan the writer and
# are deliberately absent.
CONSUMER='grep[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|-m[[:space:]]*[0-9]+)|head([[:space:]]|$)'

# --- a pipe inside a quoted string is TEXT, not a pipeline --------------------------------------------
# Every file that documents this defect has to spell the banned idiom out, and not all of those mentions
# are in comments — some are inside a failure message, which is exactly where the explanation belongs.
# `bad "… 'printf | grep -q' fail …"` is prose. Counting it would push the gate toward the one outcome it
# must never have: an author who reworded a diagnostic to appease a scanner.
# So the scan walks each line's quoting and reports the pipe only when it is really a pipe.
scan_lines() {
  awk -v consumer="$CONSUMER" '
    {
      line = $0
      n = length(line)
      q = ""
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (q != "") {
          if (c == q) q = ""
          else if (c == "\\" && q == "\"") i++
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        if (c == "|" && substr(line, i + 1, 1) != "|" && substr(line, i - 1, 1) != "|") {
          rest = substr(line, i + 1)
          sub(/^[ \t]+/, "", rest)
          if (rest ~ ("^(" consumer ")")) { print NR ":" line; next }
        }
      }
    }
  ' "$1"
}

# --- what counts as an ASSERTION ----------------------------------------------------------------------
# The distinction the whole gate turns on: is this pipeline's exit status READ? A line is an assertion when
# a conditional consumes it. A line is diagnostic when its status is discarded — printed inside a bad/ok
# arm, or captured for its stdout in a command substitution.
is_assertion() {
  local line="$1" stripped
  # Strip leading whitespace.
  stripped="${line#"${line%%[![:space:]]*}"}"
  # Diagnostic arms: the pipeline follows a reporter call on the same line, so the reporter has ALREADY
  # counted the failure and the pipeline that follows only prints context. `then`/`else`/`fi` may prefix
  # it — `else bad "…"; printf … | head -4` is the commonest shape in this tree and it is not an
  # assertion, so matching only a line-initial `bad ` would send it to UNDECIDED for no reason.
  case "$stripped" in
    bad\ *|ok\ *|echo\ *|:\ *) return 1 ;;
    else\ bad\ *|else\ ok\ *|then\ bad\ *|then\ ok\ *|else\ echo\ *|then\ echo\ *) return 1 ;;
    *\;\ bad\ *|*\;\ ok\ *) return 1 ;;
  esac
  # Command substitution whose value is assigned: the status is discarded, stdout is the point. Both the
  # bare and the quoted form (`X=$(…)` and `X="$(…)"`) occur here.
  if [[ "$stripped" =~ ^(local[[:space:]]+|declare[[:space:]]+|export[[:space:]]+)?[A-Za-z_][A-Za-z_0-9]*=\"?\$\( ]]; then
    return 1
  fi
  # Conditional context: the status is read.
  case "$stripped" in
    if\ *|elif\ *|while\ *|until\ *|\!\ *|\&\&*|\|\|*) return 0 ;;
  esac
  # A continuation line of a multi-line condition: `   && printf … | grep -q X \`
  case "$stripped" in
    *\&\&*|*\|\|*) return 0 ;;
  esac
  # Inside a `bad …` diagnostic block the pipeline usually stands alone on its own line, and so does a
  # bare assertion inside a helper function. Neither shape can be told apart from the line alone, so the
  # gate says so rather than guessing — a gate that resolves doubt toward "fine" never rejects anything.
  return 2
}

FILES=0
HITS=0
UNDECIDED=0
EXEMPT=0
BACKLOG=0   # findings in production scripts: reported, not fatal unless --strict

# `find … -print0`-free on purpose: the paths are ours and contain no spaces, and a while-read over a glob
# keeps the gate readable. If that ever stops being true this loop is the place to harden.
# Row 015. The default population is scripts/test-*.sh, and that is the gate's
# contract: an assertion returning 141 silently inverts a claim, which is the
# defect this exists to find. Its own meta-test, its K5 "nothing was scanned"
# refusal and its sync-owned exemption are all written against that population.
#
# But 104 of this repo's 139 shell scripts were never looked at, and
# template-autosync.sh:227 carried the same shape and broke a unit test under
# load. So the wider scan is available, and OPT-IN:
#
#   --all      scan every scripts/*.sh; production findings are a reported
#              backlog and do not change the exit code
#   --strict   with --all, fail on them too
#
# Making the wide scan the DEFAULT was tried and reverted: it reports 54
# production pipelines, nearly all legitimate diagnostics where a 141 costs
# nothing, and it broke three arms of the gate's own meta-test — including the
# one guaranteeing a tree with nothing to scan is refused rather than called
# clean. A gate bent to fit a wider net is worse than a narrow net plus a flag.
SCAN_ALL=0
STRICT=0
case " $* " in *" --all "*) SCAN_ALL=1 ;; esac
case " $* " in *" --strict "*) STRICT=1; SCAN_ALL=1 ;; esac
shopt -s nullglob
if [ "$SCAN_ALL" -eq 1 ]; then
  TESTS=("$SCAN_ROOT"/scripts/*.sh)
  POP_LABEL="scripts/*.sh"
else
  TESTS=("$SCAN_ROOT"/scripts/test-*.sh)
  POP_LABEL="scripts/test-*.sh"
fi
shopt -u nullglob
is_selftest() { case "$(basename "$1")" in test-*) return 0 ;; *) return 1 ;; esac; }

if [ "${#TESTS[@]}" -eq 0 ]; then
  echo "ERROR: no scripts/test-*.sh under $SCAN_ROOT — nothing was scanned." >&2
  echo "       Zero results are a fault until proven benign (K5); this gate will not report a clean tree" >&2
  echo "       it never looked at." >&2
  exit 2
fi

for f in "${TESTS[@]}"; do
  base="$(basename "$f")"
  # Downstream: a fix in a sync-owned file is eaten by the next `chore(sync)`, so it is exempt HERE and
  # scanned in the template instead. In the template that sentence is false about every file, so the
  # branch does not fire and the population is all 22 rather than 5. Row H7ax.
  if [ "$EXEMPT_SYNC_OWNED" -eq 1 ] && is_core "$base"; then
    EXEMPT=$((EXEMPT + 1)); continue
  fi
  FILES=$((FILES + 1))
  HD="$(heredoc_lines "$f")"
  while IFS= read -r entry; do
    lineno="${entry%%:*}"
    body="${entry#*:}"
    # Fixture content written into a sandbox file, not an assertion this file makes.
    if [ -n "$HD" ] && grep -qxF "$lineno" <<< "$HD"; then continue; fi
    # Skip comment lines — this file's own header quotes the banned idiom, and so will the next one that
    # explains it.
    case "${body#"${body%%[![:space:]]*}"}" in '#'*) continue ;; esac
    is_assertion "$body"; verdict=$?
    case $verdict in
      0)
        if is_selftest "$f"; then HITS=$((HITS + 1)); else BACKLOG=$((BACKLOG + 1)); fi
        printf '%s:%s\n' "${f#"$SCAN_ROOT"/}" "$lineno"
        printf '    %s\n' "${body#"${body%%[![:space:]]*}"}"
        printf '    -> use a here-string: grep -q PATTERN <<< "$VAR"   (or grep -q PATTERN FILE)\n'
        ;;
      2)
        if is_selftest "$f"; then UNDECIDED=$((UNDECIDED + 1)); else BACKLOG=$((BACKLOG + 1)); fi
        printf '%s:%s  UNDECIDED — cannot tell assertion from diagnostic on this line alone\n' \
          "${f#"$SCAN_ROOT"/}" "$lineno"
        printf '    %s\n' "${body#"${body%%[![:space:]]*}"}"
        ;;
    esac
  done < <(scan_lines "$f")
done

# --strict folds the production backlog into the verdict; by default it is
# reported and the exit code speaks only for the self-tests, where a 141 silently
# inverts an assertion.
if [ "$STRICT" -eq 1 ]; then TOTAL=$((HITS + UNDECIDED + BACKLOG)); else TOTAL=$((HITS + UNDECIDED)); fi
if [ "$BACKLOG" -gt 0 ]; then
  printf '\n[backlog] %s pipeline(s) in production scripts (not self-tests).\n' "$BACKLOG" >&2
  printf '          Usually a diagnostic, where 141 costs nothing. Re-run with --strict to fail on\n' >&2
  printf '          them, and fix them ONE AT A TIME: a bulk regex pass over 34 of these turned a\n' >&2
  printf '          real suite red on 2026-09-03 (msroute row M2).\n' >&2
fi

# Printed in EVERY branch, clean or not. The one fact that would have caught this gate going blind
# upstream is how many files it opened out of how many it found, and that fact must not be conditional
# on the verdict — a number you only see when something else already went wrong is a number nobody has.
mode_line() {
  printf 'mode: %s — %s\n' "$MODE_LABEL" "$MODE_WHY"
  printf 'population: %s of %s %s in scope, %s exempt as sync-owned\n' \
    "$FILES" "${#TESTS[@]}" "${POP_LABEL:-scripts/test-*.sh}" "$EXEMPT"
}

if [ "$LIST" -eq 1 ]; then
  printf '\n'
  mode_line
  printf 'scanned %s self-test(s): %s assertion(s), %s undecided\n' "$FILES" "$HITS" "$UNDECIDED"
  exit 0
fi

if [ "$TOTAL" -gt 0 ]; then
  printf '\nFAIL: %s pipeline(s) into an early-exit consumer in %s self-test(s)\n' "$TOTAL" "$FILES" >&2
  printf '      (%s read as assertions, %s undecided — an undecided line is a refusal, not a pass)\n' \
    "$HITS" "$UNDECIDED" >&2
  printf '      Under set -o pipefail these return 141 once the tail after the match reaches the pipe\n' >&2
  printf '      buffer (and intermittently well below it), which reads a true claim as false — and,\n' >&2
  printf '      when negated, reads a false claim as PASS. Row H7x.\n' >&2
  mode_line >&2
  exit 1
fi

# NOTHING WAS IN SCOPE. This is not "clean" — there is no verdict about files nobody opened, and calling
# it one is the exact shape row H7ax removed. It is also not a fault under K5 ("zero results are a fault
# until proven benign"): the zero is proven benign by construction, because every exempted file is
# scanned in the template itself. That proof is what H7ax bought; before it, this branch would have been
# a hole. A freshly synced project has precisely this shape, and a gate that refused there would be a
# gate switched off on day one.
if [ "$FILES" -eq 0 ]; then
  mode_line
  printf 'no-sigpipe-assertions: NOT RUN — this tree has no self-tests of its own. All %s are sync-owned\n' "$EXEMPT"
  printf '                       and are scanned in the template. No verdict is claimed about them here.\n'
  exit 0
fi

mode_line
printf 'no-sigpipe-assertions: clean — %s self-test(s), 0 early-exit assertion pipelines\n' "$FILES"
exit 0
