#!/bin/bash
# Deterministic template → project sync. No LLM, no judgment calls.
#
# Copies the mechanical half of what /project-update does — scripts/, rules/,
# docs/, agents/, and core-hook wiring — from the template repo into THIS
# project, then commits. The half that needs judgment (CLAUDE.md prose merges,
# settings.json project-specific hooks, tech-stack decisions) is never touched;
# it is reported so a human can run /project-update deliberately.
#
# Safety model — the manifest:
#   Every sync records `<sha256>  <relpath>` for each file it wrote into
#   .claude/.template-sync. On the next run a project file is only overwritten
#   when its current hash still matches the manifest (i.e. nobody edited it
#   locally since the last sync). A locally-modified file is SKIPPED and
#   reported, never clobbered. Files in the CORE set (enforcement machinery,
#   not prose) are overwritten even without a manifest entry — that is the
#   spine that must not drift.
#
# Intentional differences — the record (.claude/.sync-local, spec 007af):
#   Some project files are SUPPOSED to differ from the template forever, and
#   reporting those on every run is a permanent false alarm — the one line in
#   this output a reader learns to skip, on which the next genuinely-stale file
#   will be reported. `.claude/.sync-local` holds one line per accepted
#   difference:
#
#       <project-sha256>  <template-sha256>  <relpath>
#
#   Both hashes, not one. A record keyed on the project's bytes alone goes
#   silent and then STAYS silent when the template rewrites that file, which is
#   the same defect pointed upstream. So: neither side moved → silent; either
#   side moved → reported, naming which one. That is what stops the record from
#   becoming a blindfold.
#
#   Only `--accept-local` ever writes it. A sync that recorded its own skips
#   would be a rubber stamp, and the failure that causes — a genuinely stale
#   file going quiet — is invisible.
#
# Usage:
#   template-autosync.sh [--check] [--dry-run] [--force] [--no-commit] [--quiet]
#   template-autosync.sh --accept-local <path>...
#     --check         report drift and exit 0 without writing anything
#     --dry-run       same as --check but also prints the file list it would write
#     --force         sync even when the template SHA matches the stamp
#     --no-commit     write files but leave them unstaged
#     --quiet         only print the one-line summary
#     --accept-local  record <path> as an intentional local difference and exit.
#                     Writes nothing else: no sync, no commit, no push. Refuses a
#                     path that is missing, is not shipped by the template, is
#                     identical to it, or is in the CORE set (which this sync
#                     overwrites unconditionally, so silence there is a promise
#                     it would break on its very next run).
#
# Exit codes: 0 = up to date / synced / not applicable, 1 = hard error.
# Fails open by design: this runs from a SessionStart hook and must never
# block a session from starting.

set -u

TEMPLATE_REPO_URL="https://github.com/johanolofsson72/Claude.git"
TEMPLATE_TARBALL="https://codeload.github.com/johanolofsson72/Claude/tar.gz/refs/heads/main"

MODE_CHECK=0; MODE_DRYRUN=0; FORCE=0; DO_COMMIT=1; QUIET=0; MODE_ACCEPT=0; ACCEPT_PATHS=""
ORIG_ARGS="$*"   # kept for the self-update re-exec below (flags contain no spaces)
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE_CHECK=1 ;;
    --dry-run)   MODE_CHECK=1; MODE_DRYRUN=1 ;;
    --force)     FORCE=1 ;;
    --no-commit) DO_COMMIT=0 ;;
    --quiet)     QUIET=1 ;;
    --accept-local)
      MODE_ACCEPT=1
      # Everything after the flag is a path, so a caller can accept several at once. The loop stops
      # at the next flag rather than swallowing it, which keeps `--accept-local x --quiet` honest.
      while [ $# -gt 1 ]; do
        case "$2" in --*) break ;; esac
        ACCEPT_PATHS="$ACCEPT_PATHS $2"
        shift
      done
      ;;
    -h|--help)   grep -E '^#( |$)' "$0" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

# Recording a difference needs the template's actual bytes, so "already at this SHA"
# must not short-circuit the resolution. Nothing is synced either way — the accept
# path exits before the copy loop.
[ "$MODE_ACCEPT" -eq 1 ] && FORCE=1

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
# The final summary is the machine-readable result — the SessionStart wrapper
# greps it for "[synced]". --quiet suppresses chatter, never this.
tell() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# ---------------------------------------------------------------- project root
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || { say "[skip] not inside a git repository"; exit 0; }
[ -d "$PROJECT_ROOT/.claude" ] || { say "[skip] no .claude/ — not a Claude Code project"; exit 0; }

# Never sync the template onto itself. Identify it by remote URL — file markers
# are useless here because the sync copies scripts/sync-prompt.md and friends
# into every project, so every synced project looks like the template.
ORIGIN=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)
case "$ORIGIN" in
  *johanolofsson72/Claude.git|*johanolofsson72/Claude|*:johanolofsson72/Claude*)
    say "[skip] this IS the template repo"; exit 0 ;;
esac

# ------------------------------------------------------------- template source
# Preference: explicit env var → local clone → GitHub tarball (David's path).
TEMPLATE_DIR=""
TEMPLATE_SHA=""
TEMPLATE_TMP=""

# A local clone is preferred over the tarball, and until this existed it was also
# never refreshed: resolve_local_template took `rev-parse HEAD` as the template's
# SHA and copied whatever bytes happened to be checked out. sync-prompt.md Step -1
# tells every developer to clone the template to ~/repos/Claude, so the moment they
# follow that instruction their autosync pins itself to the commit they cloned --
# silently, forever. The stamp then matches the frozen SHA on every run, so the
# hook reports a clean sync and nothing ever says the source is months stale.
#
# So: fetch, then decide by relationship to origin/main. Four states, and only one
# of them is the bug:
#
#   equal     nothing to do.
#   behind    the stale-clone bug. Fast-forward it (clean trees only) and say so.
#   ahead     the template author's own machine, mid-work. Leave it alone -- those
#             unpushed commits are exactly what their other projects should receive.
#   diverged  local commits AND upstream commits. Ambiguous, so touch nothing and
#             warn; rewriting someone's clone and ignoring their commits are both
#             wrong, and a human can tell which one they meant.
#
# Fails open in every direction: no network, no git, not a clone, a clone of some
# other repo living at that path -- all of them fall back to "use it as-is", which
# is precisely the behaviour that existed before.
refresh_local_template() {
  _c="$1"
  git -C "$_c" rev-parse --git-dir >/dev/null 2>&1 || return 0
  case "$(git -C "$_c" remote get-url origin 2>/dev/null)" in
    *johanolofsson72/Claude.git|*johanolofsson72/Claude|*:johanolofsson72/Claude*) ;;
    *) return 0 ;;   # a different repo parked at that path: not ours to fetch
  esac

  # Bounded, because this runs from SessionStart. A fetch that hangs on a dead
  # network must not become the session's startup cost.
  _to=""
  if command -v timeout  >/dev/null 2>&1; then _to="timeout 20"
  elif command -v gtimeout >/dev/null 2>&1; then _to="gtimeout 20"; fi
  $_to git -C "$_c" fetch --quiet origin main >/dev/null 2>&1 || {
    warn "[note] template clone at $_c could not be fetched (offline?) -- using it as-is"
    return 0
  }

  _head=$(git -C "$_c" rev-parse HEAD 2>/dev/null)          || return 0
  _up=$(git -C "$_c" rev-parse origin/main 2>/dev/null)     || return 0
  [ "$_head" = "$_up" ] && return 0

  _behind=0; _ahead=0
  git -C "$_c" merge-base --is-ancestor "$_head" "$_up" 2>/dev/null && _behind=1
  git -C "$_c" merge-base --is-ancestor "$_up" "$_head" 2>/dev/null && _ahead=1

  if [ "$_behind" -eq 1 ]; then
    if [ -n "$(git -C "$_c" status --porcelain 2>/dev/null | head -1)" ]; then
      # Dirty AND behind: the uncommitted work is deliberate (the -dirty- SHA below
      # exists for exactly that case), so it wins -- but say the source is stale,
      # because that is the part nobody would otherwise notice.
      warn "[warn] template clone at $_c is behind origin/main and has uncommitted changes."
      warn "       Syncing from the working tree as-is. Commit or stash, then re-run to fast-forward."
      return 0
    fi
    if git -C "$_c" merge --ff-only --quiet origin/main >/dev/null 2>&1; then
      warn "[ok] template clone fast-forwarded to origin/main -- the files below come from the newer template"
    else
      warn "[warn] template clone at $_c is behind origin/main but would not fast-forward."
      warn "       Syncing from the stale checkout. Fix the clone with: git -C $_c pull --ff-only"
    fi
    return 0
  fi

  [ "$_ahead" -eq 1 ] && return 0   # author's machine, mid-work: their commits are the point

  warn "[warn] template clone at $_c has diverged from origin/main (local commits AND upstream commits)."
  warn "       Nothing was changed. Syncing from the local checkout; reconcile it by hand."
}

resolve_local_template() {
  for cand in "${CLAUDE_TEMPLATE_DIR:-}" "$HOME/repos/Claude" "$HOME/repos/claude"; do
    [ -n "$cand" ] || continue
    if [ -f "$cand/scripts/sync-prompt.md" ] && [ -d "$cand/.claude/rules" ]; then
      refresh_local_template "$cand"
      TEMPLATE_DIR="$cand"
      TEMPLATE_SHA=$(git -C "$cand" rev-parse --short=12 HEAD 2>/dev/null || echo "local-unknown")
      # A dirty working tree means the files being copied are NOT what the SHA
      # describes. Stamping the clean SHA would make the next run think it is
      # up to date and skip the (still uncommitted) changes forever.
      if [ -n "$(git -C "$cand" status --porcelain 2>/dev/null | head -1)" ]; then
        TEMPLATE_SHA="$TEMPLATE_SHA-dirty-$(date -u '+%Y%m%d%H%M%S')"
      fi
      return 0
    fi
  done
  return 1
}

resolve_remote_template() {
  command -v curl >/dev/null 2>&1 || return 1
  TEMPLATE_SHA=$(git ls-remote "$TEMPLATE_REPO_URL" main 2>/dev/null | cut -c1-12)
  [ -n "$TEMPLATE_SHA" ] || return 1
  # Only pay for the download when the SHA actually moved.
  STAMP_SHA=$(sed -n 's/^sha=//p' "$PROJECT_ROOT/.claude/.template-sync" 2>/dev/null | head -1)
  if [ "$TEMPLATE_SHA" = "$STAMP_SHA" ] && [ "$FORCE" -eq 0 ]; then
    return 2   # up to date, no download needed
  fi
  TEMPLATE_TMP=$(mktemp -d 2>/dev/null || mktemp -d -t claude-template)
  curl -fsSL --max-time 60 "$TEMPLATE_TARBALL" 2>/dev/null | tar -xz -C "$TEMPLATE_TMP" 2>/dev/null || return 1
  TEMPLATE_DIR=$(find "$TEMPLATE_TMP" -maxdepth 1 -type d -name 'Claude-*' | head -1)
  [ -n "$TEMPLATE_DIR" ] && [ -d "$TEMPLATE_DIR/.claude/rules" ]
}

cleanup() { [ -n "$TEMPLATE_TMP" ] && rm -rf "$TEMPLATE_TMP"; }
trap cleanup EXIT

if ! resolve_local_template; then
  resolve_remote_template
  RC=$?
  if [ "$RC" -eq 2 ]; then say "[ok] already at template $TEMPLATE_SHA"; exit 0; fi
  if [ "$RC" -ne 0 ]; then
    # A sync that cannot reach the template does nothing and says so quietly; it runs
    # from a SessionStart hook and must never make offline look like breakage. An
    # --accept-local that cannot reach it has to fail loudly instead: the template's
    # hash is half the record, and inventing it would silence a file forever against
    # a value nobody ever computed.
    if [ "$MODE_ACCEPT" -eq 1 ]; then
      warn "[accept-local] refused: the template could not be resolved (no local clone, and no network)."
      warn "               Recording a difference needs the template's bytes. Set CLAUDE_TEMPLATE_DIR"
      warn "               to a local clone, or retry with a connection."
      exit 1
    fi
    say "[skip] template unreachable (offline?) — nothing changed"; exit 0
  fi
fi

STAMP="$PROJECT_ROOT/.claude/.template-sync"
STAMP_SHA=$(sed -n 's/^sha=//p' "$STAMP" 2>/dev/null | head -1)
if [ "$TEMPLATE_SHA" = "$STAMP_SHA" ] && [ "$FORCE" -eq 0 ]; then
  say "[ok] already at template $TEMPLATE_SHA"
  exit 0
fi

# --------------------------------------------------------------------- hashing
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}
sha_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum 2>/dev/null | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 2>/dev/null | cut -d' ' -f1
  else cksum 2>/dev/null | cut -d' ' -f1; fi
}
manifest_hash() { grep -F "  $1" "$STAMP" 2>/dev/null | head -1 | cut -d' ' -f1; }

# ------------------------------------------------- the intentional-difference record
# `<project-sha256>  <template-sha256>  <relpath>`, one line per accepted difference.
#
# Field-exact on $3, deliberately NOT the substring match manifest_hash uses: this
# lookup decides whether a file goes SILENT, and a record borrowed by a path that
# merely starts the same (`git.md` answering for `git.md.orig`) is a file nobody is
# ever told about. Comment lines are skipped so the file can explain itself.
LOCAL_RECORD="$PROJECT_ROOT/.claude/.sync-local"
local_record() {
  [ -f "$LOCAL_RECORD" ] || return 1
  awk -v p="$1" '$1 !~ /^#/ && NF == 3 && $3 == p { print $1 " " $2; found = 1; exit }
                 END { exit !found }' "$LOCAL_RECORD" 2>/dev/null
}

# Bootstrap discrimination: on the very first sync there is no manifest, so a
# file that differs from the template is ambiguous — it could be an older
# template version (safe to update) or a deliberate project customization
# (must not be touched). Resolve it against the template's own git history: if
# the project's exact bytes ever WERE a template version, nobody customized it.
# Only possible with a local clone; the tarball path has no history, so it
# falls back to the conservative "skip and report".
HISTORY_DEPTH="${TEMPLATE_HISTORY_DEPTH:-60}"
matches_template_history() {
  SRCREL="$1"; CUR="$2"
  [ -n "$TEMPLATE_TMP" ] && return 1
  git -C "$TEMPLATE_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  for h in $(git -C "$TEMPLATE_DIR" log --format=%H -n "$HISTORY_DEPTH" -- "$SRCREL" 2>/dev/null); do
    OLD=$(git -C "$TEMPLATE_DIR" show "$h:$SRCREL" 2>/dev/null | sha_stdin)
    [ "$OLD" = "$CUR" ] && return 0
  done
  return 1
}

# ------------------------------------------------------------------- CORE sets
# Enforcement machinery: always overwritten, manifest or not. These are the
# files whose drift silently disables a gate — exactly what bit cv.
CORE_SCRIPTS="pipeline-trigger-match.sh pipeline-trigger-match.py emit-pipeline-reminder.sh
emit-clarify-reminder.sh emit-analyze-reminder.sh feature-pipeline-detect.sh
spec_active.py resolve-active-spec.sh test-active-spec-resolution.sh
spec-register-guard-hook.sh spec-register-orientation-hook.sh pipeline-state-guard-hook.sh
spec-interview-guard-hook.sh spec-md-coverage-reminder-hook.sh scenario-map-reminder-hook.sh
sync-feature-json-hook.sh
scenario-map-orientation-hook.sh continuous-execution-hook.sh stop-validation-hook.sh
repeat-failure-guard-hook.sh spec-run-log-hook.sh stack-marker-canary-hook.sh
detect-stack.sh prune-dangling-hooks.py prune-agent-worktrees.sh
speckit-extension-policy.sh
archive-spec-history.sh test-archive-spec-history.sh skill-audit.sh test-pipeline-hooks.sh tlc-cleanup.sh
test-template-clone-refresh.sh
project-maintenance.sh project-freshness.sh
sync-core-hooks.py sync-local-llm-hooks.py sync-graphify-wiring.py fix-hook-paths.py
template-autosync.sh template-autosync-hook.sh"

CORE_RULES="feature-pipeline.md continuous-execution.md validation-followup.md
spec-register.md spec-interview.md spec-hardening.md scenarios.md specs.md tests.md
security.md project-workflow.md github-actions.md allium.md"

is_core() {
  case "$2" in
    scripts) printf '%s\n' $CORE_SCRIPTS | grep -qx "$1" ;;
    rules)   printf '%s\n' $CORE_RULES   | grep -qx "$1" ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------------ stack gate
# testing=mobile means .claude/docs/testing.md holds the MOBILE content under
# the canonical name. Stamping the web doc over it is the documented failure
# that left a Flutter app reading "browser back mid-flow" instructions.
STACK=$(sed -n 's/^testing=//p' "$PROJECT_ROOT/.claude/.sync-stack" 2>/dev/null | head -1)
[ -n "$STACK" ] || STACK="unknown"

# ------------------------------------------------------- --accept-local (spec 007af)
# The ONLY writer of .claude/.sync-local, and it writes nothing else: no copy loop,
# no manifest, no commit, no push. That asymmetry — many readers, one deliberate
# writer — is the safety argument for keeping the record out of the manifest, which
# is regenerated wholesale on every run.
if [ "$MODE_ACCEPT" -eq 1 ]; then
  [ -n "$ACCEPT_PATHS" ] || { warn "[accept-local] refused: no path given."; exit 1; }

  # Which template file feeds this project path. They differ under the mobile stack
  # gate, where testing-mobile.md is written to the canonical testing.md — so the
  # record has to hash whichever file this project is actually fed from.
  accept_source_rel() {
    if [ "$STACK" = "mobile" ]; then
      case "$1" in
        .claude/docs/testing.md)                 printf '%s' ".claude/docs/testing-mobile.md"; return ;;
        .claude/docs/spec-testing-checklist.md)  printf '%s' ".claude/docs/spec-testing-checklist-mobile.md"; return ;;
      esac
    fi
    printf '%s' "$1"
  }

  # Both passes over the same list: validate every path, and only then write any of
  # them. A refusal that had already written the paths before it would make "writes
  # nothing on a refusal" true per-path and false per-invocation.
  for REL in $ACCEPT_PATHS; do
    REL=${REL#./}
    SRCREL=$(accept_source_rel "$REL")
    DEST="$PROJECT_ROOT/$REL"
    SRC="$TEMPLATE_DIR/$SRCREL"

    case "$REL" in
      scripts/*)        CLS=scripts ;;
      .claude/rules/*)  CLS=rules ;;
      *)                CLS=other ;;
    esac

    if [ ! -f "$DEST" ]; then
      warn "[accept-local] refused: '$REL' is not in this project."
      exit 1
    fi
    if [ ! -f "$SRC" ]; then
      warn "[accept-local] refused: the template does not ship '$SRCREL', so there is nothing to"
      warn "               differ from — this sync never looks at that path."
      exit 1
    fi
    if is_core "$(basename "$REL")" "$CLS"; then
      warn "[accept-local] refused: '$REL' is CORE machinery, which this sync overwrites"
      warn "               unconditionally. Recording it would promise silence AND let the file be"
      warn "               clobbered on the next run. Land the change in the template instead."
      exit 1
    fi
    if [ "$(sha_of "$DEST")" = "$(sha_of "$SRC")" ]; then
      warn "[accept-local] refused: '$REL' is identical to the template — there is no difference to"
      warn "               accept, and the record would be stale the moment it was written."
      exit 1
    fi
  done

  for REL in $ACCEPT_PATHS; do
    REL=${REL#./}
    SRCREL=$(accept_source_rel "$REL")
    P_HASH=$(sha_of "$PROJECT_ROOT/$REL")
    T_HASH=$(sha_of "$TEMPLATE_DIR/$SRCREL")

    # Rebuilt whole and sorted rather than appended: this is a committed file two
    # people may touch, and an append-ordered record turns a one-line change into a
    # diff nobody reads. Rebuilding is also what makes a re-accept a replacement —
    # two lines for one path would make the answer depend on read order.
    RECORD_TMP=$(mktemp 2>/dev/null || mktemp -t syncrecord)
    {
      [ -f "$LOCAL_RECORD" ] && awk -v p="$REL" '$1 !~ /^#/ && NF == 3 && $3 != p { print }' "$LOCAL_RECORD"
      printf '%s  %s  %s\n' "$P_HASH" "$T_HASH" "$REL"
    } | sort -k3 > "$RECORD_TMP"
    {
      printf '# Intentional local differences from the template (spec 007af).\n'
      printf '# <project-sha256>  <template-sha256>  <path> — the two hashes the difference was\n'
      printf '# accepted at. Neither side moved: silent. Either side moved: reported again, saying\n'
      printf '# which. Written only by `scripts/template-autosync.sh --accept-local <path>`.\n'
      cat "$RECORD_TMP"
    } > "$LOCAL_RECORD"
    rm -f "$RECORD_TMP"

    tell "[accept-local] recorded $REL"
    tell "               project  $P_HASH"
    tell "               template $T_HASH  ($SRCREL @ $TEMPLATE_SHA)"
  done

  tell "[accept-local] nothing else was written — commit .claude/.sync-local with the change that made"
  tell "               the difference intentional."
  exit 0
fi

WROTE=""; SKIPPED=""; ADDED=""; ADOPTED=""
# Spec 007af. INTENTIONAL is the only bucket that is never reported; the other two
# are the two ways a recorded difference comes back, and STALE is a record whose
# subject has gone away.
INTENTIONAL=""; LOCAL_MOVED=""; TMPL_MOVED=""; STALE=""; SEEN_RECORDS=""
NEW_MANIFEST=$(mktemp 2>/dev/null || mktemp -t manifest)

# Write via temp + rename, never `cp` onto a live path.
#
# This sync overwrites scripts/template-autosync.sh — itself — while bash is
# still reading it. bash reads a script incrementally by byte offset, so a plain
# `cp` truncates and rewrites the SAME inode under the running interpreter, which
# then resumes at its old offset inside different content and dies with a syntax
# error somewhere in the middle of the file. `mv` swaps the directory entry
# instead: the running process keeps its original inode open and finishes
# cleanly, while the next exec picks up the new file. Same reasoning protects any
# hook script that happens to be executing during a sync.
atomic_copy() {
  _dst="$2"
  cp "$1" "$_dst.autosync-tmp.$$" 2>/dev/null && mv -f "$_dst.autosync-tmp.$$" "$_dst" 2>/dev/null && return 0
  rm -f "$_dst.autosync-tmp.$$" 2>/dev/null
  cp "$1" "$_dst"   # last-resort fallback (e.g. a filesystem without rename)
}

# copy_file <template-abs> <project-rel> <class> [<template-rel>]
copy_file() {
  SRC="$1"; REL="$2"; CLASS="$3"; SRCREL="${4:-$2}"
  DEST="$PROJECT_ROOT/$REL"
  BASE=$(basename "$REL")
  SRC_HASH=$(sha_of "$SRC")

  if [ -f "$DEST" ]; then
    CUR_HASH=$(sha_of "$DEST")
    if [ "$CUR_HASH" = "$SRC_HASH" ]; then
      # A record for a file that no longer differs is rot: harmless, but it is the
      # one way this file accumulates lies. Reported so a human can delete it —
      # never deleted here, because the sync does not get to un-decide things.
      if local_record "$REL" >/dev/null; then
        STALE="$STALE $REL"
        SEEN_RECORDS="$SEEN_RECORDS $REL"
      fi
      printf '%s  %s\n' "$SRC_HASH" "$REL" >> "$NEW_MANIFEST"
      return 0                                  # identical, nothing to do
    fi
    OLD_HASH=$(manifest_hash "$REL")
    if [ "$CUR_HASH" != "$OLD_HASH" ] && ! is_core "$BASE" "$CLASS"; then
      # Has this difference been accepted? Asked BEFORE the history lookup for two
      # reasons. A settled record is the answer that lookup is searching for, so
      # running it anyway costs ~0.2 s of every sync to reach the same negative
      # forever. And bytes that ARE an older template version would be "adopted" —
      # overwritten — which would make recording a divergence the thing that
      # deletes it.
      REC=$(local_record "$REL")
      if [ -n "$REC" ]; then
        SEEN_RECORDS="$SEEN_RECORDS $REL"
        REC_PROJECT=${REC%% *}; REC_TEMPLATE=${REC##* }
        if [ "$REC_PROJECT" != "$CUR_HASH" ]; then
          # Project side first: if both moved, the local edit is the one the
          # developer made and the one they can explain.
          LOCAL_MOVED="$LOCAL_MOVED $REL"
        elif [ "$REC_TEMPLATE" != "$SRC_HASH" ]; then
          TMPL_MOVED="$TMPL_MOVED $REL"
        else
          INTENTIONAL="$INTENTIONAL $REL"
        fi
        # No manifest line either way. The manifest records bytes this sync WROTE;
        # it wrote none of these, and .sync-local is where their record lives.
        return 0
      fi
      # No manifest entry (first sync) → ask the template's history whether
      # these bytes are just an older template version.
      if [ -z "$OLD_HASH" ] && matches_template_history "$SRCREL" "$CUR_HASH"; then
        ADOPTED="$ADOPTED $REL"                 # stale template copy → update it
      else
        SKIPPED="$SKIPPED $REL"                 # differs, unrecorded → hands off
        [ -n "$OLD_HASH" ] && printf '%s  %s\n' "$OLD_HASH" "$REL" >> "$NEW_MANIFEST"
        return 0
      fi
    fi
    [ "$MODE_CHECK" -eq 1 ] || atomic_copy "$SRC" "$DEST"
    WROTE="$WROTE $REL"
  else
    # New file: only add CORE machinery, plus template-owned SKILLS. A doc/rule
    # the project deliberately removed (wordpress.md on a .NET project) must stay
    # removed — but a missing skill is never a decision, it is just a project that
    # predates the skill. Skills are add-if-missing yet manifest-protected on
    # update (they are not in the CORE set), so a customized skill is still safe.
    is_core "$BASE" "$CLASS" || [ "$CLASS" = "skills" ] || return 0
    [ "$MODE_CHECK" -eq 1 ] || { mkdir -p "$(dirname "$DEST")"; atomic_copy "$SRC" "$DEST"; }
    ADDED="$ADDED $REL"
  fi
  printf '%s  %s\n' "$SRC_HASH" "$REL" >> "$NEW_MANIFEST"
}

for f in "$TEMPLATE_DIR"/scripts/*.sh "$TEMPLATE_DIR"/scripts/*.py; do
  [ -f "$f" ] || continue
  copy_file "$f" "scripts/$(basename "$f")" scripts
done

for f in "$TEMPLATE_DIR"/.claude/rules/*.md; do
  [ -f "$f" ] || continue
  copy_file "$f" ".claude/rules/$(basename "$f")" rules
done

for f in "$TEMPLATE_DIR"/.claude/agents/*.md; do
  [ -f "$f" ] || continue
  copy_file "$f" ".claude/agents/$(basename "$f")" agents
done

# Template-owned skills. Until this existed the sync shipped rules, docs, scripts
# and agents but never skills — so a fix to /project-wizard or /project-update sat
# in the template while 35 projects kept running the old copy. Since those two
# skills are what bootstrap and update a project, a stale copy reproduces bugs
# that were fixed months earlier. `find`, not a glob: skills carry nested files
# (ui-ux-pro-max/data/*.csv, project-wizard/install.sh).
if [ -d "$TEMPLATE_DIR/.claude/skills" ]; then
  for rel in $(cd "$TEMPLATE_DIR/.claude/skills" && find . -type f 2>/dev/null | sed 's#^\./##'); do
    copy_file "$TEMPLATE_DIR/.claude/skills/$rel" ".claude/skills/$rel" skills
  done
fi

for f in "$TEMPLATE_DIR"/.claude/docs/*.md; do
  [ -f "$f" ] || continue
  B=$(basename "$f")
  case "$STACK:$B" in
    # Mobile/hybrid: the canonical names carry mobile content — never overwrite
    # them with the browser versions.
    mobile:testing.md|mobile:spec-testing-checklist.md) continue ;;
    mobile:testing-mobile.md)                copy_file "$f" ".claude/docs/testing.md" docs ".claude/docs/testing-mobile.md"; continue ;;
    mobile:spec-testing-checklist-mobile.md) copy_file "$f" ".claude/docs/spec-testing-checklist.md" docs ".claude/docs/spec-testing-checklist-mobile.md"; continue ;;
    # Web: no mobile docs.
    web:testing-mobile.md|web:spec-testing-checklist-mobile.md|web:deployment-mobile.md) continue ;;
  esac
  copy_file "$f" ".claude/docs/$B" docs
done

# A record whose path the copy loop never reached — the template stopped shipping it,
# or the project deleted it. Nothing is skipped on its behalf any more, so the record
# is doing nothing except waiting to be believed about a file that is not there.
if [ -f "$LOCAL_RECORD" ]; then
  for _r in $(awk '$1 !~ /^#/ && NF == 3 { print $3 }' "$LOCAL_RECORD" 2>/dev/null); do
    case " $SEEN_RECORDS " in *" $_r "*) ;; *) STALE="$STALE $_r" ;; esac
  done
fi

# Reported = the three buckets a reader can act on. INTENTIONAL is deliberately not
# among them: the whole point of the record is that a settled difference stops
# costing anybody a line.
REPORTED="$SKIPPED$LOCAL_MOVED$TMPL_MOVED"

if [ "$MODE_CHECK" -eq 1 ]; then
  rm -f "$NEW_MANIFEST"
  N_INTENTIONAL=$(echo "$INTENTIONAL" | tr ' ' '\n' | grep -c .)
  N_STALE=$(echo "$STALE" | tr ' ' '\n' | grep -c .)
  say "[check] template $TEMPLATE_SHA vs project $([ -n "$STAMP_SHA" ] && echo "$STAMP_SHA" || echo "never synced")"
  # `skip (locally edited):N` keeps its exact spelling — it is the string a reader's
  # eye is trained on, and silently redefining a counter is the same class of
  # mistake as the undirected wording this record replaced. It now counts
  # UNRECORDED differences; the recorded ones get counters of their own, printed
  # only when they have something to say.
  COUNTS="[check] would update:$(echo "$WROTE" | tr ' ' '\n' | grep -c .) · add:$(echo "$ADDED" | tr ' ' '\n' | grep -c .) · skip (locally edited):$(echo "$REPORTED" | tr ' ' '\n' | grep -c .)"
  [ "$N_INTENTIONAL" -gt 0 ] && COUNTS="$COUNTS · intentional:$N_INTENTIONAL"
  [ "$N_STALE" -gt 0 ] && COUNTS="$COUNTS · stale:$N_STALE"
  say "$COUNTS"
  if [ "$MODE_DRYRUN" -eq 1 ]; then
    for x in $WROTE;       do say "  update $x"; done
    for x in $ADDED;       do say "  add    $x"; done
    for x in $ADOPTED;     do say "  adopt  $x (older template copy, not a local edit)"; done
    for x in $INTENTIONAL; do say "  local  $x (intentional, unchanged since it was accepted)"; done
    for x in $LOCAL_MOVED; do say "  CHECK  $x (the local copy changed since it was accepted — merge, or re-run --accept-local)"; done
    for x in $TMPL_MOVED;  do say "  CHECK  $x (the template changed under an accepted local difference — merge, then --accept-local)"; done
    for x in $STALE;       do say "  stale  $x (recorded as an intentional difference, but no longer differs — drop the line)"; done
    # No direction asserted: the sync knows these bytes differ and nothing else.
    # Claiming the project is behind is what 007w measured backwards.
    for x in $SKIPPED;     do say "  SKIP   $x (differs from the template — merge it with /project-update, or record it with --accept-local)"; done
  fi
  exit 0
fi

# chmod ONLY what this sync wrote. A blanket `chmod +x scripts/*.sh` also flips
# the mode bit on the project's own scripts, producing mode-change diffs in files
# the sync does not own — unexplained churn in someone else's repo.
for _f in $WROTE $ADDED; do
  case "$_f" in
    scripts/*.sh|scripts/*.py) chmod +x "$PROJECT_ROOT/$_f" 2>/dev/null ;;
  esac
done

# ------------------------------------------------------------- self-update
# A project runs its OWN copy of this script, so the CORE_SCRIPTS list in memory
# is the one from the PREVIOUS template version. When the template adds a new
# enforcement script, this run copies the updated template-autosync.sh but has
# already decided (using the stale list) not to add the new script — so the
# project needs a second run to converge. Re-exec once with the freshly-written
# version instead. AUTOSYNC_REEXEC bounds it to exactly one hop: no matter what
# the new version does, it cannot re-exec again.
if [ "${AUTOSYNC_REEXEC:-0}" -eq 0 ]; then
  case " $WROTE " in
    *" scripts/template-autosync.sh "*)
      say "[self-update] template-autosync.sh changed — re-running once with the new version"
      # Carry this pass's file LISTS, not just counts. `git add -- $WROTE $ADDED`
      # in the second pass stages only what that pass touched, so carrying counts
      # alone leaves pass-1's files updated on disk but absent from the commit.
      AUTOSYNC_REEXEC=1
      AUTOSYNC_CARRY_WROTE="$WROTE"
      AUTOSYNC_CARRY_ADDED="$ADDED"
      export AUTOSYNC_REEXEC AUTOSYNC_CARRY_WROTE AUTOSYNC_CARRY_ADDED
      rm -f "$NEW_MANIFEST"
      exec bash "$PROJECT_ROOT/scripts/template-autosync.sh" $ORIG_ARGS --force
      ;;
  esac
fi

# ------------------------------------------------------- core-hook re-wiring
HOOKS_NOTE=""

# A project with .claude/ but no settings.json has the rules and the scripts and
# runs NONE of it — every hook lives in settings.json, so the whole deterministic
# layer is simply absent. The wiring helpers then fail with "project settings not
# found", which the block below used to report as a rollback, implying damage
# where there was nothing to roll back. Seed it from the template instead; this is
# what /project-update's settings.json merge prescribes for a file that does not
# exist yet ("File does NOT exist in this project → copy from template").
if [ ! -f "$PROJECT_ROOT/.claude/settings.json" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ]; then
  atomic_copy "$TEMPLATE_DIR/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json"
  ADDED="$ADDED .claude/settings.json"
  HOOKS_NOTE="settings.json seeded from template (project had none)"
  warn "[note] $PROJECT_ROOT had no .claude/settings.json — seeded from the template."
  warn "       Enforcement hooks are now ACTIVE here. If this project has source code"
  warn "       but no specs/INDEX.md, spec-register-guard will block source edits until"
  warn "       you create the register (the deny message explains how)."
fi
# -------------------------------------------------- outputStyle (add-if-absent)
# The hook helpers below rewire `hooks` and nothing else, so a settings key the
# template adopts reaches a project only through /project-update's prose merge --
# which most projects never run, because autosync exists precisely so they do not
# have to. outputStyle is the first such key, and it is worth carrying: a built-in
# output style modifies the SYSTEM PROMPT, where CLAUDE.md only adds a user message
# after it, so "Proactive" states the autonomy contract in .claude/rules/
# continuous-execution.md one layer above everything else that argues for it.
#
# Add-if-absent, never overwrite: a project that already names an outputStyle made
# a choice, and silently replacing someone's chosen voice is not a sync, it is a
# hijack. Idempotent, and a parse failure leaves the file untouched.
if [ -f "$PROJECT_ROOT/.claude/settings.json" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ] \
   && [ "$MODE_CHECK" -eq 0 ] && command -v python3 >/dev/null 2>&1; then
  if python3 - "$PROJECT_ROOT/.claude/settings.json" "$TEMPLATE_DIR/.claude/settings.json" <<'PYEOF'
import json, sys
proj, tmpl = sys.argv[1], sys.argv[2]
try:
    p = json.load(open(proj, encoding="utf-8"))
    t = json.load(open(tmpl, encoding="utf-8"))
except Exception:
    sys.exit(1)                      # unreadable: leave it alone
want = t.get("outputStyle")
if not want or p.get("outputStyle"):
    sys.exit(1)                      # nothing to add, or the project already chose
p["outputStyle"] = want
tmp = proj + ".outputstyle-tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(p, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
json.load(open(tmp, encoding="utf-8"))   # must still parse before it replaces anything
import os; os.replace(tmp, proj)
PYEOF
  then
    STYLE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["outputStyle"])' "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null)
    warn "[note] settings.json had no outputStyle — set to \"$STYLE\" from the template."
    case " $WROTE $ADDED " in *" .claude/settings.json "*) ;; *) WROTE="$WROTE .claude/settings.json" ;; esac
  fi
fi

if [ -f "$PROJECT_ROOT/scripts/sync-core-hooks.py" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ] \
   && command -v python3 >/dev/null 2>&1; then
  cp "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.autosync-bak" 2>/dev/null
  if (cd "$PROJECT_ROOT" && python3 scripts/sync-core-hooks.py "$TEMPLATE_DIR/.claude/settings.json" >/dev/null 2>&1) \
     && python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    if cmp -s "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.autosync-bak"; then
      HOOKS_NOTE="hooks unchanged"
    else
      HOOKS_NOTE="hooks rewired"
      WROTE="$WROTE .claude/settings.json"
    fi
    rm -f "$PROJECT_ROOT/.claude/settings.json.autosync-bak"
  else
    mv "$PROJECT_ROOT/.claude/settings.json.autosync-bak" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
    HOOKS_NOTE="hook rewiring FAILED (settings.json restored)"
    warn "[warn] sync-core-hooks.py failed — settings.json rolled back"
  fi
fi

# The local-LLM hook family is owned by its own helper (core-hooks deliberately
# ignores it), so wiring changes there — e.g. adding `if` filters — do not
# propagate without this. The helper treats the template as source of truth and
# DELETES project local-llm scripts the template does not ship; unattended
# deletion is not something this sync promises, so run it only when the delete
# set is provably empty and report otherwise.
if [ -f "$PROJECT_ROOT/scripts/sync-local-llm-hooks.py" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ] \
   && command -v python3 >/dev/null 2>&1; then
  EXTRA=""
  for pf in "$PROJECT_ROOT"/scripts/local-llm-*-hook.sh; do
    [ -f "$pf" ] || continue
    [ -f "$TEMPLATE_DIR/scripts/$(basename "$pf")" ] || EXTRA="$EXTRA $(basename "$pf")"
  done
  if [ -n "$EXTRA" ]; then
    HOOKS_NOTE="$HOOKS_NOTE · local-LLM wiring skipped (project-only scripts would be deleted:$EXTRA)"
  else
    cp "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.autosync-bak" 2>/dev/null
    if (cd "$PROJECT_ROOT" && python3 scripts/sync-local-llm-hooks.py "$TEMPLATE_DIR/.claude/settings.json" >/dev/null 2>&1) \
       && python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
      if ! cmp -s "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.autosync-bak"; then
        HOOKS_NOTE="$HOOKS_NOTE + local-LLM rewired"
        case " $WROTE " in *" .claude/settings.json "*) ;; *) WROTE="$WROTE .claude/settings.json" ;; esac
      fi
      rm -f "$PROJECT_ROOT/.claude/settings.json.autosync-bak"
    else
      mv "$PROJECT_ROOT/.claude/settings.json.autosync-bak" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
      HOOKS_NOTE="$HOOKS_NOTE · local-LLM rewiring FAILED (rolled back)"
    fi
  fi
fi

# ------------------------------------- pick up the helper-owned script mirrors
# sync-local-llm-hooks.py and sync-graphify-wiring.py mirror their own script
# families as a side effect of wiring, outside the copy loop above — so those
# writes never entered $WROTE and silently escaped the commit, leaving the repo
# permanently dirty with files identical to the template. Same class of bug as
# the re-exec dropping its file list; fold them in before staging.
for _f in $(git -C "$PROJECT_ROOT" status --porcelain -- scripts 2>/dev/null | awk '{print $2}'); do
  case "$_f" in
    scripts/local-llm-*|scripts/graphify-*|scripts/sync-local-llm-hooks.py|scripts/sync-graphify-wiring.py)
      case " $WROTE $ADDED " in *" $_f "*) ;; *) WROTE="$WROTE $_f" ;; esac ;;
  esac
done

# --------------------------------------------------- prune dangling hook refs
# settings.json can reference scripts the project never received — the graphify
# and local-LLM families are owned by other helpers and are stack/opt-in gated,
# and a wholesale seed brings their wiring along regardless. A hook pointing at a
# missing script never errors; it silently does nothing while every "is it wired?"
# audit reports green. Unwire what is not there.
if [ -f "$PROJECT_ROOT/scripts/prune-dangling-hooks.py" ] && command -v python3 >/dev/null 2>&1; then
  PRUNED=$( (cd "$PROJECT_ROOT" && python3 scripts/prune-dangling-hooks.py 2>/dev/null) | tail -1)
  case "$PRUNED" in
    *"removed"*)
      HOOKS_NOTE="${HOOKS_NOTE:+$HOOKS_NOTE · }$PRUNED"
      case " $WROTE " in *" .claude/settings.json "*) ;; *) WROTE="$WROTE .claude/settings.json" ;; esac
      ;;
  esac
fi

# ------------------------------------------- spec-kit extension policy
# `specify init --force` re-enables the git extension every time it runs, and it
# runs outside this sync (via /project-update or by hand). Re-assert the policy
# here so a project cannot silently regain feature-branch + auto-commit skills
# that contradict spec-register.md. Idempotent and silent when already correct.
if [ -f "$PROJECT_ROOT/scripts/speckit-extension-policy.sh" ]; then
  POL=$(bash "$PROJECT_ROOT/scripts/speckit-extension-policy.sh" --repo "$PROJECT_ROOT" 2>/dev/null | head -1)
  if [ -n "$POL" ]; then
    say "[speckit] $POL"
    case " $WROTE " in *" .specify/extensions/.registry "*) ;; *) WROTE="$WROTE .specify/extensions/.registry" ;; esac
  fi
fi

# ------------------------------------------------- stack marker (derive if absent)
# `.claude/.sync-stack` gates which testing docs this project receives. When it is
# missing the doc gate has nothing to go on and stamps BOTH the web and the mobile
# set, so the project carries instructions for a platform it does not ship. Derive
# it once, from the same detector the canary uses, and only when the answer is
# unambiguous (detect-stack.sh prints nothing when it cannot tell).
if [ ! -f "$PROJECT_ROOT/.claude/.sync-stack" ] && [ -f "$PROJECT_ROOT/scripts/detect-stack.sh" ]; then
  DETECTED=$(bash "$PROJECT_ROOT/scripts/detect-stack.sh" "$PROJECT_ROOT" 2>/dev/null | sed -n '1p')
  if [ -n "$DETECTED" ]; then
    printf 'testing=%s\n' "$DETECTED" > "$PROJECT_ROOT/.claude/.sync-stack"
    ADDED="$ADDED .claude/.sync-stack"
    say "[stack] no .sync-stack marker — derived testing=$DETECTED from the project's manifests"
  fi
fi

# ------------------------------------------------------------------ the stamp
{
  printf 'sha=%s\n' "$TEMPLATE_SHA"
  printf 'synced=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'source=%s\n' "$([ -n "$TEMPLATE_TMP" ] && echo github || echo "$TEMPLATE_DIR")"
  printf '# manifest: sha256 of each file as written by the sync — a project file\n'
  printf '# whose hash no longer matches was edited locally and is never overwritten.\n'
  sort -k2 "$NEW_MANIFEST"
} > "$STAMP"
rm -f "$NEW_MANIFEST"

# Merge in whatever the pre-re-exec pass wrote, de-duplicated, so both the
# commit and the summary cover the entire sync and not just the second pass.
for _c in ${AUTOSYNC_CARRY_WROTE:-}; do
  case " $WROTE " in *" $_c "*) ;; *) WROTE="$WROTE $_c" ;; esac
done
for _c in ${AUTOSYNC_CARRY_ADDED:-}; do
  case " $ADDED " in *" $_c "*) ;; *) ADDED="$ADDED $_c" ;; esac
done

N_WROTE=$(echo "$WROTE" | tr ' ' '\n' | grep -c .)
N_ADDED=$(echo "$ADDED" | tr ' ' '\n' | grep -c .)
N_SKIP=$(echo "$REPORTED" | tr ' ' '\n' | grep -c .)

# ---------------------------------------------------------------- commit/push
COMMIT_NOTE="not committed"
if [ "$DO_COMMIT" -eq 1 ] && [ $((N_WROTE + N_ADDED)) -gt 0 ]; then
  if [ -d "$PROJECT_ROOT/.git/rebase-merge" ] || [ -d "$PROJECT_ROOT/.git/rebase-apply" ] \
     || [ -f "$PROJECT_ROOT/.git/MERGE_HEAD" ] || [ -f "$PROJECT_ROOT/.git/CHERRY_PICK_HEAD" ]; then
    COMMIT_NOTE="commit skipped (rebase/merge in progress) — files staged for you"
    git -C "$PROJECT_ROOT" add -- $WROTE $ADDED .claude/.template-sync 2>/dev/null
  else
    git -C "$PROJECT_ROOT" add -- $WROTE $ADDED .claude/.template-sync 2>/dev/null
    MSG="chore(sync): template $TEMPLATE_SHA — $N_WROTE updated, $N_ADDED added"
    if git -C "$PROJECT_ROOT" commit -q -m "$MSG" -m "Deterministic template sync (scripts/rules/docs/agents + core-hook wiring).
Locally-modified files skipped: $N_SKIP. CLAUDE.md and project-specific settings untouched — run /project-update for those." 2>/dev/null; then
      SHORT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)
      COMMIT_NOTE="committed $SHORT"
      BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
      if git -C "$PROJECT_ROOT" rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
        if git -C "$PROJECT_ROOT" push -q origin "$BRANCH" 2>/dev/null; then
          COMMIT_NOTE="$COMMIT_NOTE, pushed to $BRANCH"
        else
          COMMIT_NOTE="$COMMIT_NOTE, push FAILED (offline or rejected)"
        fi
      else
        COMMIT_NOTE="$COMMIT_NOTE (no upstream — not pushed)"
      fi
    else
      COMMIT_NOTE="commit failed — files left staged"
    fi
  fi
fi

SUMMARY="template $TEMPLATE_SHA → $N_WROTE updated, $N_ADDED added, $N_SKIP skipped (locally modified)"
[ -n "$HOOKS_NOTE" ] && SUMMARY="$SUMMARY · $HOOKS_NOTE"
SUMMARY="$SUMMARY · $COMMIT_NOTE"
tell "[synced] $SUMMARY"
# Everything here is forwarded verbatim into a session by template-autosync-hook.sh,
# which is why a file that is SUPPOSED to differ must not appear: the false line
# would arrive bundled with the real news, on the one occasion somebody is reading.
if [ "$N_SKIP" -gt 0 ]; then
  tell "[manual] files that differ from the template and are left alone:"
  for x in $SKIPPED;     do tell "         $x — merge with /project-update, or record it with --accept-local"; done
  for x in $LOCAL_MOVED; do tell "         $x — the local copy changed since it was accepted as intentional"; done
  for x in $TMPL_MOVED;  do tell "         $x — the template changed under an accepted local difference"; done
fi
exit 0
