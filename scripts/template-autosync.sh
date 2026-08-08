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
# Usage:
#   template-autosync.sh [--check] [--dry-run] [--force] [--no-commit] [--quiet]
#     --check      report drift and exit 0 without writing anything
#     --dry-run    same as --check but also prints the file list it would write
#     --force      sync even when the template SHA matches the stamp
#     --no-commit  write files but leave them unstaged
#     --quiet      only print the one-line summary
#
# Exit codes: 0 = up to date / synced / not applicable, 1 = hard error.
# Fails open by design: this runs from a SessionStart hook and must never
# block a session from starting.

set -u

TEMPLATE_REPO_URL="https://github.com/johanolofsson72/Claude.git"
TEMPLATE_TARBALL="https://codeload.github.com/johanolofsson72/Claude/tar.gz/refs/heads/main"

MODE_CHECK=0; MODE_DRYRUN=0; FORCE=0; DO_COMMIT=1; QUIET=0
ORIG_ARGS="$*"   # kept for the self-update re-exec below (flags contain no spaces)
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE_CHECK=1 ;;
    --dry-run)   MODE_CHECK=1; MODE_DRYRUN=1 ;;
    --force)     FORCE=1 ;;
    --no-commit) DO_COMMIT=0 ;;
    --quiet)     QUIET=1 ;;
    -h|--help)   grep -E '^#( |$)' "$0" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

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

resolve_local_template() {
  for cand in "${CLAUDE_TEMPLATE_DIR:-}" "$HOME/repos/Claude" "$HOME/repos/claude"; do
    [ -n "$cand" ] || continue
    if [ -f "$cand/scripts/sync-prompt.md" ] && [ -d "$cand/.claude/rules" ]; then
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
  if [ "$RC" -ne 0 ]; then say "[skip] template unreachable (offline?) — nothing changed"; exit 0; fi
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
spec-register-guard-hook.sh spec-register-orientation-hook.sh pipeline-state-guard-hook.sh
spec-interview-guard-hook.sh spec-md-coverage-reminder-hook.sh scenario-map-reminder-hook.sh
scenario-map-orientation-hook.sh continuous-execution-hook.sh stop-validation-hook.sh
repeat-failure-guard-hook.sh spec-run-log-hook.sh stack-marker-canary-hook.sh
archive-spec-history.sh skill-audit.sh test-pipeline-hooks.sh tlc-cleanup.sh
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

WROTE=""; SKIPPED=""; ADDED=""; ADOPTED=""
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
      printf '%s  %s\n' "$SRC_HASH" "$REL" >> "$NEW_MANIFEST"
      return 0                                  # identical, nothing to do
    fi
    OLD_HASH=$(manifest_hash "$REL")
    if [ "$CUR_HASH" != "$OLD_HASH" ] && ! is_core "$BASE" "$CLASS"; then
      # No manifest entry (first sync) → ask the template's history whether
      # these bytes are just an older template version.
      if [ -z "$OLD_HASH" ] && matches_template_history "$SRCREL" "$CUR_HASH"; then
        ADOPTED="$ADOPTED $REL"                 # stale template copy → update it
      else
        SKIPPED="$SKIPPED $REL"                 # locally edited → hands off
        [ -n "$OLD_HASH" ] && printf '%s  %s\n' "$OLD_HASH" "$REL" >> "$NEW_MANIFEST"
        return 0
      fi
    fi
    [ "$MODE_CHECK" -eq 1 ] || atomic_copy "$SRC" "$DEST"
    WROTE="$WROTE $REL"
  else
    # New file: only add CORE machinery. A doc/rule the project deliberately
    # removed (wordpress.md on a .NET project) must stay removed.
    is_core "$BASE" "$CLASS" || return 0
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

if [ "$MODE_CHECK" -eq 1 ]; then
  rm -f "$NEW_MANIFEST"
  say "[check] template $TEMPLATE_SHA vs project $([ -n "$STAMP_SHA" ] && echo "$STAMP_SHA" || echo "never synced")"
  say "[check] would update:$(echo "$WROTE" | tr ' ' '\n' | grep -c .) · add:$(echo "$ADDED" | tr ' ' '\n' | grep -c .) · skip (locally edited):$(echo "$SKIPPED" | tr ' ' '\n' | grep -c .)"
  if [ "$MODE_DRYRUN" -eq 1 ]; then
    for x in $WROTE;   do say "  update $x"; done
    for x in $ADDED;   do say "  add    $x"; done
    for x in $ADOPTED; do say "  adopt  $x (older template copy, not a local edit)"; done
    for x in $SKIPPED; do say "  SKIP   $x (locally modified — needs /project-update)"; done
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
N_SKIP=$(echo "$SKIPPED" | tr ' ' '\n' | grep -c .)

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
if [ "$N_SKIP" -gt 0 ]; then
  tell "[manual] locally-modified files left alone — run /project-update to merge them:"
  for x in $SKIPPED; do tell "         $x"; done
fi
exit 0
