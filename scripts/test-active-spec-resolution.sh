#!/usr/bin/env bash
# Harness for spec 007m — proves which spec the enforcement guards think is active.
#
# WHY THIS EXISTS
# ---------------
# Both PreToolUse guards extracted the spec id from a register row with a
# numeric-only regex:
#
#     id_re = re.compile(r"^\**\s*([0-9]+)\b")
#
# `\b` is a word boundary and there is no boundary between "7" and "m", so
# "007m" did not match AT ALL. Rows with a letter-suffixed id — 004a, and 007a
# through 007o, i.e. the last twelve consecutive specs — were silently skipped
# exactly like an "H1" checkpoint row, and the guards settled on the first
# *numeric* row they could parse instead.
#
# That is not merely a wrong citation. If the later numeric spec's artifacts
# happen to exist, the guards approve a source edit for a spec that has NO
# artifacts and NO interview. The FAILOPEN fixture below reproduces precisely
# that, and against the pre-fix scripts BOTH GUARDS ALLOW IT.
#
# The fix was applied once before (spec 004a, commit 9e32986) and reverted ten
# days later by a template autosync (e17fd50), because both guards are in
# CORE_SCRIPTS — overwritten unconditionally. So this harness is not a one-off
# diagnostic: it is the thing that notices if it happens a third time.
#
# BOTH ARMS
# ---------
# Point GUARD_DIR at a directory holding pre-fix copies of the two guards to
# watch the failing arm. A guard whose failing arm has never been observed is
# not known to work — that is spec 007f's lesson, and this harness is built to
# honour it:
#
#     GUARD_DIR=/tmp/prefix-guards bash scripts/test-active-spec-resolution.sh
#
# Usage:
#   bash scripts/test-active-spec-resolution.sh            # all fixtures
#   bash scripts/test-active-spec-resolution.sh failopen   # one fixture
#   GUARD_DIR=<dir> bash scripts/test-active-spec-resolution.sh --expect-prefix
#
# Exit: 0 all expectations met · 1 an expectation failed · 2 harness broke.
# The three-state exit is deliberate (spec 007l): "the suite is red" and "the
# harness fell over" are different facts and must not share an exit code.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${GUARD_DIR:=$SCRIPT_DIR}"

GUARD_STATE="$GUARD_DIR/pipeline-state-guard-hook.sh"
GUARD_INTERVIEW="$GUARD_DIR/spec-interview-guard-hook.sh"

for g in "$GUARD_STATE" "$GUARD_INTERVIEW"; do
  [ -f "$g" ] || { echo "HARNESS ERROR: guard not found: $g" >&2; exit 2; }
done

# --expect-prefix inverts the expectations for the two fixtures whose whole
# point is that the pre-fix scripts get them wrong. Everything else is expected
# to behave identically at both arms.
EXPECT_PREFIX=0
FILTER=""
for arg in "$@"; do
  case "$arg" in
    --expect-prefix) EXPECT_PREFIX=1 ;;
    -*) echo "HARNESS ERROR: unknown option '$arg'" >&2; exit 2 ;;
    *) FILTER="$arg" ;;
  esac
done

WORK=$(mktemp -d 2>/dev/null) || { echo "HARNESS ERROR: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
CHECKS=0

# Write a complete artifact set for a spec dir, so the guards would be satisfied
# IF they were looking at this spec.
seed_complete_spec() {
  _d="$1"
  mkdir -p "$_d"
  printf '# Spec\n\n## Clarifications\n\n- Q: seeded → A: yes\n' > "$_d/spec.md"
  : > "$_d/plan.md"
  : > "$_d/tasks.md"
  : > "$_d/spec.allium"
  printf 'Mode: AUTO\n\n' > "$_d/interview.md"
  _i=1
  while [ "$_i" -le 20 ]; do
    printf '## Q%s — seeded\n**Q:** q%s\n**A (auto):** a%s\n\n' "$_i" "$_i" "$_i" >> "$_d/interview.md"
    _i=$((_i + 1))
  done
}

# Build a fixture project: a git boundary, a language marker, a register, and
# whatever spec dirs the caller seeds afterwards.
make_fixture() {
  _name="$1"; _register="$2"
  _root="$WORK/$_name"
  mkdir -p "$_root/.git" "$_root/src"
  : > "$_root/package.json"
  mkdir -p "$_root/specs"
  printf '%s\n' "$_register" > "$_root/specs/INDEX.md"
  printf '%s' "$_root"
}

# Run one guard, print "ALLOW" or "DENY <first line of reason>".
run_guard() {
  _guard="$1"; _root="$2"
  _out=$(printf '{"tool_input":{"file_path":"%s/src/App.cs"}}' "$_root" | bash "$_guard" 2>/dev/null)
  if [ -z "$_out" ]; then
    printf 'ALLOW'
    return 0
  fi
  printf '%s' "$_out" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
    h = d.get("hookSpecificOutput", {})
    reason = h.get("permissionDecisionReason", "").splitlines()
    print(h.get("permissionDecision", "?").upper() + " " + (reason[0] if reason else ""))
except Exception:
    print("UNPARSEABLE")
' 2>/dev/null || printf 'UNPARSEABLE'
}

check() {
  _label="$1"; _actual="$2"; _expect_kind="$3"; _expect_needle="${4:-}"
  CHECKS=$((CHECKS + 1))
  case "$_expect_kind" in
    allow)
      if [ "$_actual" = "ALLOW" ]; then
        printf '  ✓ %s — ALLOW\n' "$_label"
      else
        printf '  ✗ %s — expected ALLOW, got: %s\n' "$_label" "$_actual"; FAILURES=$((FAILURES + 1))
      fi
      ;;
    deny)
      case "$_actual" in
        DENY*)
          if [ -z "$_expect_needle" ] || case "$_actual" in *"$_expect_needle"*) true ;; *) false ;; esac; then
            printf '  ✓ %s — DENY (names %s)\n' "$_label" "${_expect_needle:-<any>}"
          else
            printf '  ✗ %s — denied, but did not name "%s": %s\n' "$_label" "$_expect_needle" "$_actual"
            FAILURES=$((FAILURES + 1))
          fi
          ;;
        *)
          printf '  ✗ %s — expected DENY naming "%s", got: %s\n' "$_label" "$_expect_needle" "$_actual"
          FAILURES=$((FAILURES + 1))
          ;;
      esac
      ;;
  esac
}

want() { [ -z "$FILTER" ] || [ "$FILTER" = "$1" ]; }

# ---------------------------------------------------------------- FAILOPEN
# The active row is a letter-suffixed spec with NOTHING on disk. A later
# numeric row has a complete artifact set. A correct guard denies and names
# 007z; the pre-fix guards skip 007z entirely, land on 008, find 008's homework
# in order, and allow the edit.
if want failopen; then
  echo "FIXTURE failopen — active letter-suffixed spec has zero artifacts; a later numeric spec is complete"
  ROOT=$(make_fixture failopen '# Spec register

## Specs

- [x] 007 — preview — full track — done
- [/] 007z — active-spec — full track — IN PROGRESS, no artifacts at all
- [ ] 008 — future — full track — a later spec whose artifacts happen to exist')
  mkdir -p "$ROOT/specs/007z-active-spec"        # deliberately empty
  seed_complete_spec "$ROOT/specs/008-future"
  S=$(run_guard "$GUARD_STATE" "$ROOT")
  I=$(run_guard "$GUARD_INTERVIEW" "$ROOT")
  if [ "$EXPECT_PREFIX" -eq 1 ]; then
    echo "  (pre-fix arm: the bypass is the expected result)"
    check "state-guard"     "$S" allow
    check "interview-guard" "$I" allow
  else
    check "state-guard"     "$S" deny "007z-active-spec"
    check "interview-guard" "$I" deny "007z-active-spec"
  fi
fi

# ---------------------------------------------------------------- CHECKPOINT
# H1 is not a spec. It has no spec.md and must never be asked for one. This is
# the one thing the numeric-only regex got right, and the fix must not lose it
# while teaching the parser about letter suffixes.
if want checkpoint; then
  echo "FIXTURE checkpoint — an H-row is a checkpoint, not a spec, and needs no artifacts"
  ROOT=$(make_fixture checkpoint '# Spec register

## Specs

- [x] 007 — preview — full track — done
- [/] H1 — integration-hardening — checkpoint — full-system regression
- [ ] 008 — future — full track — later')
  S=$(run_guard "$GUARD_STATE" "$ROOT")
  I=$(run_guard "$GUARD_INTERVIEW" "$ROOT")
  if [ "$EXPECT_PREFIX" -eq 1 ]; then
    # Pre-fix, the exemption in the code's own comment ("H1 … no pipeline
    # artifacts required") was never what the code did. `continue` does not mean
    # "allow" — it means "keep looking for a spec row", and the loop lands on the
    # next pending NUMERIC row and demands ITS artifacts. So an H1 checkpoint
    # blocked every source edit while citing a spec nobody was working on.
    # H1 is the row immediately after 007o in this project's register, so this
    # was queued to fire on the very next checkpoint.
    echo "  (pre-fix arm: the documented checkpoint exemption never worked — denies citing 008)"
    check "state-guard"     "$S" deny "008"
    check "interview-guard" "$I" deny "008"
  else
    check "state-guard"     "$S" allow
    check "interview-guard" "$I" allow
  fi
fi

# ---------------------------------------------------------------- COMPLETE
# Every row ticked. "No active row" is an ANSWER, not a resolution failure, so
# the guards must allow. Denying here would block all work on a finished
# project — the failure mode of over-correcting fail-open into fail-closed.
if want complete; then
  echo "FIXTURE complete — every row ticked; no active spec is an answer, not a failure"
  ROOT=$(make_fixture complete '# Spec register

## Specs

- [x] 007 — preview — full track — done
- [x] 007m — prereq-spec-resolution — spec-only track — done')
  S=$(run_guard "$GUARD_STATE" "$ROOT")
  I=$(run_guard "$GUARD_INTERVIEW" "$ROOT")
  check "state-guard"     "$S" allow
  check "interview-guard" "$I" allow
fi

# ---------------------------------------------------------------- SATISFIED
# The positive control. A letter-suffixed spec that HAS done its homework must
# be allowed — otherwise the fix would simply block everything and the failopen
# fixture would pass for the wrong reason.
if want satisfied; then
  echo "FIXTURE satisfied — a letter-suffixed spec with complete artifacts is allowed"
  ROOT=$(make_fixture satisfied '# Spec register

## Specs

- [/] 007m — prereq-spec-resolution — full track — complete artifacts
- [ ] 008 — future — full track — later')
  seed_complete_spec "$ROOT/specs/007m-prereq-spec-resolution"
  S=$(run_guard "$GUARD_STATE" "$ROOT")
  I=$(run_guard "$GUARD_INTERVIEW" "$ROOT")
  if [ "$EXPECT_PREFIX" -eq 1 ]; then
    # Pre-fix, this passes for the WRONG reason: it skips 007m and finds no
    # specs/008-* dir, so it denies. Recorded so the arm is honest.
    echo "  (pre-fix arm: expect DENY naming 008 — right verdict for 'satisfied'? no: wrong spec entirely)"
    check "state-guard"     "$S" deny "008"
    check "interview-guard" "$I" deny "008"
  else
    check "state-guard"     "$S" allow
    check "interview-guard" "$I" allow
  fi
fi

# ---------------------------------------------------------------- MISSINGDIR
# The active spec is named but its directory does not exist. Deny, by name.
# This is today's behaviour and must not regress into an allow.
if want missingdir; then
  echo "FIXTURE missingdir — active spec has no directory at all"
  ROOT=$(make_fixture missingdir '# Spec register

## Specs

- [/] 007q — never-created — full track — no directory on disk
- [ ] 009 — later — full track — later')
  S=$(run_guard "$GUARD_STATE" "$ROOT")
  I=$(run_guard "$GUARD_INTERVIEW" "$ROOT")
  if [ "$EXPECT_PREFIX" -eq 1 ]; then
    check "state-guard"     "$S" deny "009"
    check "interview-guard" "$I" deny "009"
  else
    check "state-guard"     "$S" deny "007q"
    check "interview-guard" "$I" deny "007q"
  fi
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "PASS — $CHECKS/$CHECKS expectations met (guards: $GUARD_DIR)"
  exit 0
fi
echo "FAIL — $FAILURES of $CHECKS expectations missed (guards: $GUARD_DIR)"
exit 1
