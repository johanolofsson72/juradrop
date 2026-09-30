#!/bin/bash
# The one way a script reaches template-autosync.sh (spec 011, landed from consultpilot H7bo).
# SOURCE this file; do not run it.
#
# WHY THIS EXISTS
#
# Spec 010 (consultpilot H7bm) made the sandbox interlock mandatory, but OPT-IN PER CALL SITE. Two
# halves are required of every driver —
#
#   CLAUDE_PROJECT_DIR=…            names the target. Without it, `cd` is decoration: the sync
#                                   resolves ${CLAUDE_PROJECT_DIR:-$PWD}, and under a Claude Code
#                                   hook the harness has already exported it, pointing at the real
#                                   repository.
#   CLAUDE_TEMPLATE_SYNC_SANDBOX=…  declares the only directory the run may write inside.
#
# — and they were spelled by hand at 19 places across 6 files, under three wrapper names plus
# inline, with three different sandbox variable names. With no single invocation form, the GATE
# that makes callers declare had to reverse-engineer the convention: handle derivation, two match
# arms, a two-line lookback, a `/` branch, and seven exclusions of which two existed only to absorb
# its own false positives. Every new call shape was a regex amendment to the matcher.
#
# One invocation form removes the need to infer one. That is the whole idea.
#
# WHAT THIS GUARANTEES, AND WHAT IT DOES NOT
#
#   It guarantees WHERE a run may write.       Both halves are set from the two positional
#                                              arguments, so omitting one is an arity error rather
#                                              than a forgotten habit.
#   It does NOT guarantee WHAT runs.           DRIVE_SYNC_SCRIPT is checked for existence and
#                                              readability, never content. "Is this really the
#                                              sync" is undecidable and would be theatre:
#                                              test-template-autosync-unlisted.sh's era and
#                                              sabotaged copies exist precisely BECAUSE they are
#                                              not the current sync.
#
# WHY template-autosync.sh DOES NOT SOURCE THIS FILE
#
# A CORE file that sources a project-local script makes that script an [unlisted] dependency by the
# sync's own detector, and core-owed-tick-guard-hook.sh then refuses the register tick. So this
# helper serves the CALLERS and never the sync — which is also why the interlock itself still lives
# in template-autosync.sh and is not moved here.
#
# USAGE
#
#   . "$(dirname "$0")/drive-sync.sh"
#
#   drive_sync           <project> <sandbox> [args…]   # the ordinary entry point
#   drive_sync_readonly  <project>           [args…]   # query modes only; refuses otherwise
#
#   CLAUDE_TEMPLATE_DIR="$T" drive_sync "$P" "$TMP" --force      # extra env: prefix the call.
#                                                               # Measured: bash exports it to the
#                                                               # child and leaves nothing behind
#                                                               # in the caller (outside POSIX
#                                                               # mode). Exactly the semantics the
#                                                               # 19 hand-spelled sites had.
#
#   DRIVE_SYNC_SCRIPT=…    which sync to run   (REQUIRED, absolute; there is no default)
#   DRIVE_SYNC_CWD=…       where to run it     (default: <project>)
#   DRIVE_SYNC_TIMEOUT=…   seconds             (default: none. `timeout` has to sit between the
#                                              environment and `bash`, which is why it cannot be a
#                                              prefix assignment and is a variable instead.)
#
# EXIT CODES
#
#   Whatever the sync returned                 — on the ordinary path, verbatim.
#   64 (DRIVE_SYNC_EBADARG)                    — the ARGUMENTS were refused; nothing was started.
#
# 64 is deliberate and load-bearing. template-autosync.sh answers 0 (yes/clean), 1 (no/findings)
# and 2 (cannot answer); if a refusal shared any of those, a broken fixture would read as a real
# verdict and the assertion below it would pass having never run. A status shaped like success for
# a run that did not happen is exactly what a gate must never report.
#
# Scenario ids deliberately absent: this file is CORE and ships into projects whose SC numbering is
# their own (row 012).

DRIVE_SYNC_EBADARG=64

# The repository this helper is part of, resolved physically and once, at source time: a caller is
# free to cd afterwards, and a relative `. scripts/drive-sync.sh` would resolve differently later. A
# sandbox that CONTAINS it is the 2026-08-30 incident wearing a declaration. `CDPATH=''` and `--` are
# template-autosync.sh's own _phys idiom, hardened by spec 010's review: an ambient CDPATH must not
# steer the answer to another tree.
_drive_sync_own_repo=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P) || _drive_sync_own_repo=""

_drive_sync_phys() { ( CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P ); }

# The refusal code is a LITERAL 64 wherever it is returned. DRIVE_SYNC_EBADARG is set for
# callers to compare against, never read back here: a caller that set it to 0 after sourcing turned
# every refusal into a pass and the run went ahead (adversarial review, 011).
_drive_sync_bad() {  # <message>
  printf 'drive_sync: %s\n' "$1" >&2
  return 64
}

# Every check below runs BEFORE anything starts. The old design could only ask whether an
# assignment was PRESENT, and presence was satisfied by CLAUDE_TEMPLATE_SYNC_SANDBOX=/ — a
# declaration naming the filesystem root, which constrains nothing and was the whole 2026-08-30
# incident reopened by one line. Here the same question is asked once, of a value.
_drive_sync_check_project() {  # <project>
  [ -n "$1" ]  || { _drive_sync_bad "project is empty"; return $?; }
  [ -e "$1" ]  || { _drive_sync_bad "project does not exist: $1"; return $?; }
  [ -d "$1" ]  || { _drive_sync_bad "project is not a directory: $1"; return $?; }
}

_drive_sync_check_sandbox() {  # <sandbox>
  [ -n "$1" ]     || { _drive_sync_bad "sandbox is empty — that is no declaration at all, and an empty prefix matches every path"; return $?; }
  case "$1" in
    /) _drive_sync_bad "sandbox is the filesystem root, which constrains nothing"; return $? ;;
    /*) : ;;
    *) _drive_sync_bad "sandbox is relative: $1 — a sandbox that depends on cwd is not a sandbox"; return $? ;;
  esac
  [ -e "$1" ] || { _drive_sync_bad "sandbox does not exist: $1 — a caller naming a sandbox that is not there has already lost track of it"; return $?; }
  [ -d "$1" ] || { _drive_sync_bad "sandbox is not a directory: $1"; return $?; }

  # A declaration that CONTAINS this repository permits writing to this repository, which is the
  # whole of the 2026-08-30 incident with a declaration attached. `/` was already refused above as
  # the extreme case; this is the same argument carried to every other ancestor — $HOME, /Users,
  # the repo's own parent — each of which satisfies "absolute, exists, is a directory" while
  # constraining nothing that matters. Compared physically, so a symlinked temp dir is judged by
  # where it actually is.
  #
  # Fail closed. If this file's own repository cannot be resolved (or resolves to `/`), the check
  # below would compare against nothing and pass every sandbox — so no writing run starts at all.
  case "$_drive_sync_own_repo" in
    ""|/) _drive_sync_bad "cannot resolve the repository this helper belongs to, so it cannot tell whether $1 contains it — refusing"; return $? ;;
  esac
  _ds_sp=$(_drive_sync_phys "$1")
  case "$_drive_sync_own_repo/" in
    "$_ds_sp"/*) _drive_sync_bad "sandbox $1 contains this repository ($_drive_sync_own_repo) — a declaration that permits writing here is the incident this helper exists to prevent, not a sandbox"; return $? ;;
  esac
}

# DRIVE_SYNC_SCRIPT is REQUIRED, not defaulted. Measured across the six converted suites: all 19 call
# sites set it, so a default did no work — while giving the one parameter every caller supplies the
# property this helper exists to remove from the other two. Forget it and the call would quietly run
# the REPO's sync where the caller meant a fixture copy, an era copy or a sabotaged copy; the sandbox
# still holds, so nothing is damaged and the test measures the wrong binary, which is the quiet
# direction. An arity error is the loud one.
_drive_sync_check_script() {  # <script>
  [ -n "$1" ] || { _drive_sync_bad "DRIVE_SYNC_SCRIPT is not set. Name the sync this call should run — the repo's own, a fixture's copy, or an era/sabotaged copy. There is deliberately no default."; return $?; }
  # Absolute, because it is checked here in the caller's cwd and run later from DRIVE_SYNC_CWD: a
  # relative path could pass this check against one copy and execute another (review, 011).
  case "$1" in /*) : ;; *) _drive_sync_bad "sync script is relative: $1 — it is checked here and run from another directory"; return $? ;; esac
  [ -f "$1" ] || { _drive_sync_bad "sync script not found: $1"; return $?; }
  [ -r "$1" ] || { _drive_sync_bad "sync script not readable: $1"; return $?; }
  # Deliberately nothing about CONTENT. See the header.
}

# A bound is whole seconds greater than zero, or nothing. `--version` made timeout print and exit 0
# without running the sync, `0` meant unbounded, and `abc` exited 125 — none of them a refusal.
_drive_sync_check_timeout() {
  case "${DRIVE_SYNC_TIMEOUT:-}" in
    "") : ;;
    *[!0-9]*|0*) _drive_sync_bad "DRIVE_SYNC_TIMEOUT=$DRIVE_SYNC_TIMEOUT is not a whole number of seconds greater than zero"; return $? ;;
  esac
}

# The subshell is not tidiness. A helper that leaked either half would poison the NEXT assertion in
# the same file rather than fail — quieter than a crash, and the one new failure mode centralising
# 19 separate prefixes could introduce. So: `( … )`, always, on every path including refusal.
_drive_sync_run() {  # <project> <sandbox-or-empty> <script> [args…]
  _ds_p="$1"; _ds_s="$2"; _ds_x="$3"; shift 3
  (
    cd "${DRIVE_SYNC_CWD:-$_ds_p}" 2>/dev/null || {
      printf 'drive_sync: cannot cd to %s (DRIVE_SYNC_CWD)\n' "${DRIVE_SYNC_CWD:-$_ds_p}" >&2
      exit 64
    }
    CLAUDE_PROJECT_DIR="$_ds_p"
    export CLAUDE_PROJECT_DIR
    if [ -n "$_ds_s" ]; then
      CLAUDE_TEMPLATE_SYNC_SANDBOX="$_ds_s"
      export CLAUDE_TEMPLATE_SYNC_SANDBOX
    else
      unset CLAUDE_TEMPLATE_SYNC_SANDBOX
    fi
    if [ -n "${DRIVE_SYNC_TIMEOUT:-}" ]; then
      # A caller who asked for a bound and silently did not get one is the "no silent misses" rule
      # broken by convenience: the run would look bounded in the source and be unbounded in fact.
      # Callers that cannot rely on the binary guard with `command -v timeout` themselves.
      _ds_t=$(command -v timeout 2>/dev/null) || _ds_t=$(command -v gtimeout 2>/dev/null) || _ds_t=""
      [ -n "$_ds_t" ] || {
        printf 'drive_sync: DRIVE_SYNC_TIMEOUT=%s was asked for and neither timeout nor gtimeout exists — refusing rather than running unbounded\n' \
          "$DRIVE_SYNC_TIMEOUT" >&2
        exit 64
      }
      exec "$_ds_t" "$DRIVE_SYNC_TIMEOUT" bash "$_ds_x" "$@"
    fi
    exec bash "$_ds_x" "$@"
  )
}

# What both entry points do once their own arguments have passed.
_drive_sync_launch() {  # <project> <sandbox-or-empty> [args…]
  _drive_sync_check_script "${DRIVE_SYNC_SCRIPT:-}" || return $?
  _drive_sync_check_timeout || return $?
  _ds_l_p="$1"; _ds_l_s="$2"; shift 2
  _drive_sync_run "$_ds_l_p" "$_ds_l_s" "$DRIVE_SYNC_SCRIPT" "$@"
}

# The ordinary entry point. Both halves come from the two positional arguments.
drive_sync() {  # drive_sync <project> <sandbox> [args…]
  [ $# -ge 2 ] || { _drive_sync_bad "usage: drive_sync <project> <sandbox> [args…]"; return $?; }
  _ds_project="$1"; _ds_sandbox="$2"; shift 2
  _drive_sync_check_project "$_ds_project" || return $?
  _drive_sync_check_sandbox "$_ds_sandbox" || return $?
  _drive_sync_launch "$_ds_project" "$_ds_sandbox" "$@"
}

# The write-free entry point. Four modes return above the project-root resolution inside
# template-autosync.sh — --is-core, --list-core-scripts, --list-core-rules and --template-dir — so
# such a run never resolves a root, cannot write, and has nothing for a declaration to constrain.
# test-validate-sync-sandbox-declarations.sh AC-12/AC-12b assert that property for each of the
# four; move one below the resolution and the assertion reddens. consultpilot's copy knew only
# --is-core, because consultpilot's sync had only that one.
#
# It is a SEPARATE FUNCTION and not an empty sandbox argument, and it CHECKS argv rather than
# trusting the caller. An empty-string sentinel on drive_sync would have been the smaller change
# and the larger hole: a value any caller could pass on any call, including a writing one. Here
# "no sandbox" is reachable only on a path that provably cannot write, and the proof is read off
# the arguments.
drive_sync_readonly() {  # drive_sync_readonly <project> [args…]
  [ $# -ge 1 ] || { _drive_sync_bad "usage: drive_sync_readonly <project> [args…]"; return $?; }
  _ds_project="$1"; shift
  _drive_sync_check_project "$_ds_project" || return $?
  _ds_ok=0
  for _ds_a in "$@"; do
    case "$_ds_a" in --is-core|--list-core-scripts|--list-core-rules|--template-dir) _ds_ok=1 ;; esac
  done
  [ "$_ds_ok" -eq 1 ] || {
    _drive_sync_bad "drive_sync_readonly is for the query modes only (--is-core, --list-core-scripts, --list-core-rules, --template-dir), and none is in these arguments. Any other mode resolves a project root and can write; use drive_sync and declare a sandbox."
    return $?
  }
  _drive_sync_launch "$_ds_project" "" "$@"
}
