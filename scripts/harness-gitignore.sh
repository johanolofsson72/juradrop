#!/bin/bash
# harness-gitignore.sh — the one list of paths the harness writes that no repository should track,
# and the managed .gitignore block that carries it into a project (spec 040).
#
# WHY THIS EXISTS
#
# .gitignore is deliberately outside the synced set: a project's ignore file is its own, and replacing
# it would trample build output, language conventions and local habits. The harness still writes
# files it KNOWS are machine-local — attempt counters, due-state, timestamps re-stamped on every Bash
# write, the per-machine lane config — and until this script the only thing carrying that knowledge
# into a project was prose (section 3a of the sync-template skill), applied by hand during
# /project-update. A project that only autosyncs learned none of it. hetznerradar, measured
# 2026-09-07: 109 `.claude/state/attempts/` files committed, and a `.bash-write-marker` deletion in
# `git status` at session start.
#
# The file cannot be REPLACED. It can be appended to. This script owns the lines between two marker
# lines and nothing else — the same shape sync-core-hooks.py uses for settings.json: strip the managed
# set, reinstall the current one, leave the project's own alone.
#
# USAGE
#
#   harness-gitignore.sh --list            the managed patterns, one per line
#   harness-gitignore.sh --apply  <root>   write the block into <root>/.gitignore
#   harness-gitignore.sh --check  <root>   say what --apply would do, write nothing
#   harness-gitignore.sh --tracked <root>  paths the index already holds under the managed patterns
#
# --apply and --check print `added` (no .gitignore existed), `updated` (the file changes) or nothing
# (the block is current). Exit 0 on all three. Exit 3 when the markers are malformed — a start with
# no end, an end with no start, or two blocks — and then NOTHING is written: guessing where a broken
# block ends is how a project's own lines get eaten. Exit 2 on a usage error.
#
# --tracked prints each tracked path collapsed to the directory a directory pattern matched
# (`.claude/state`, not 109 attempt files). Empty when nothing matches or <root> is not a git
# repository. Ignoring a tracked file changes nothing, so the sync reports these with the
# `git rm -r --cached` line to run. It never runs it: rewriting what the next commit records,
# unattended, at a session start, is not a sync's call.

set -u

BEGIN_MARK='# >>> claude-code harness (managed by scripts/harness-gitignore.sh) >>>'
END_MARK='# <<< claude-code harness <<<'

# pattern%reason. The reason is the contestable half: a line here is a claim that the path is churn
# in every repository that runs the harness, and test-runtime-markers-ignored.sh B fails if any of
# these swallows a record a project is meant to commit (.claude/.template-sync and its siblings).
#
# Directory patterns carry no glob. --tracked collapses on them literally, and a glob there would
# need a second matcher that could disagree with git's.
HARNESS_IGNORES='.claude/state/%repeat-failure guard attempt counters, TTL-pruned; one file per verification command
.claude/validation/%stop-validation hook timestamp
.claude/.maintenance-state%when each recurring job last ran ON THIS MACHINE; a committed stamp lets one lane mark the other clean
.claude/.template-sync-check%autosync rate-limit marker (mtime only; the manifest .claude/.template-sync IS tracked)
.claude/.bash-write-marker%bash-write guard timestamp, re-stamped on every Bash write
.claude/.bash-write-blocked%bash-write guard escape-hatch record, a second file on purpose (bash-write-detect-hook.sh)
.claude/.local-llm-*%local-LLM drafts, caches and scratch context, regenerated on demand
.claude/local-llm-*.log%local-LLM telemetry, per machine
.claude/local-llm-*.log.errors%local-LLM telemetry write errors
.claude/graphify-*.log%graphify telemetry, per machine
.claude/graphify-*.log.errors%graphify telemetry write errors
.claude/settings.local.json%per-machine settings: SPEC_OWNER and CLAUDE_TEMPLATE_AUTOSYNC live here, and two lanes cannot share one identity
.claude/projects/%per-user Claude memory
.claude/worktrees/%agent worktrees; tracked, each is a gitlink that shows modified whenever its HEAD moves
.specify/feature.json%spec-kit active-spec marker, rewritten at every session start by sync-feature-json-hook.sh
__pycache__/%python bytecode; the guards import scripts/spec_active.py on every run
CLAUDE.local.md%personal project instructions, never shared'

patterns() { printf '%s\n' "$HARNESS_IGNORES" | cut -d'%' -f1; }

# $1 = line ending to append to every line: "" or a carriage return.
render_block() {
  {
    printf '%s\n' "$BEGIN_MARK"
    printf '%s\n' '# Written by the template sync and replaced on every sync. Add your own ignores'
    printf '%s\n' '# outside these markers. Why each path is here: scripts/harness-gitignore.sh.'
    patterns
    printf '%s\n' "$END_MARK"
  } | awk -v eol="$1" '{ printf "%s%s\n", $0, eol }'
}

die_usage() { printf 'usage: %s --list | --apply <root> | --check <root> | --tracked <root>\n' "$0" >&2; exit 2; }

# ------------------------------------------------------------------------------ --apply / --check
apply_block() {  # $1 = apply|check  $2 = root
  _mode="$1"; _root="$2"
  [ -d "$_root" ] || { printf 'harness-gitignore: %s is not a directory\n' "$_root" >&2; return 2; }
  _f="$_root/.gitignore"

  if [ ! -e "$_f" ]; then
    if [ "$_mode" = apply ]; then
      _tmp="$_f.harness-tmp.$$"
      render_block "" > "$_tmp" && mv "$_tmp" "$_f" || { rm -f "$_tmp"; return 2; }
    fi
    printf 'added\n'
    return 0
  fi

  # CRLF is decided by the first line. A Windows checkout with a CRLF ignore file gets a CRLF block,
  # not a mixed file the next editor normalises into a diff.
  _eol=""
  if head -n 1 "$_f" | od -An -c | grep -q '\\r'; then _eol=$(printf '\r'); fi

  # Whole-line matches only, with an optional \r. A substring match would let a project comment that
  # quotes the marker ("see # >>> claude-code harness …") become the start of a block.
  _pos=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    { l = $0; sub(/\r$/, "", l) }
    l == b { nb++; bl = NR }
    l == e { ne++; el = NR }
    END { printf "%d %d %d %d\n", nb, ne, bl, el }' "$_f")
  set -- $_pos
  _nb=$1; _ne=$2; _bl=$3; _el=$4

  _new="$_f.harness-tmp.$$"
  if [ "$_nb" -eq 0 ] && [ "$_ne" -eq 0 ]; then
    # Appended LAST. Git applies the last matching rule, so no earlier project line can undo the
    # block; a project that really wants one of these tracked writes a negation after it.
    {
      cat "$_f"
      if [ -s "$_f" ]; then
        # `$( )` strips a trailing newline, so a non-empty result means the file has no final one.
        [ -n "$(tail -c 1 "$_f")" ] && printf '%s\n' "$_eol"
        printf '%s\n' "$_eol"
      fi
      render_block "$_eol"
    } > "$_new"
  elif [ "$_nb" -eq 1 ] && [ "$_ne" -eq 1 ] && [ "$_bl" -lt "$_el" ]; then
    # head/tail, not awk: they pass bytes through untouched, including a last line with no newline.
    {
      head -n $((_bl - 1)) "$_f"
      render_block "$_eol"
      tail -n +$((_el + 1)) "$_f"
    } > "$_new"
  else
    rm -f "$_new"
    if   [ "$_nb" -gt 1 ] || [ "$_ne" -gt 1 ]; then _why="$_nb start and $_ne end markers; expected one of each"
    elif [ "$_nb" -eq 0 ]; then _why="an end marker (line $_el) with no start marker"
    elif [ "$_ne" -eq 0 ]; then _why="a start marker (line $_bl) with no end marker"
    else _why="the end marker (line $_el) comes before the start marker (line $_bl)"
    fi
    printf 'harness-gitignore: %s has %s. Nothing was written; fix the markers by hand.\n' "$_f" "$_why" >&2
    return 3
  fi

  if cmp -s "$_new" "$_f"; then
    rm -f "$_new"
    return 0
  fi
  if [ "$_mode" = check ]; then
    rm -f "$_new"
  elif [ -L "$_f" ]; then
    # Write through a symlink rather than replacing it with a regular file.
    cat "$_new" > "$_f" && rm -f "$_new" || { rm -f "$_new"; return 2; }
  else
    mv "$_new" "$_f" || { rm -f "$_new"; return 2; }
  fi
  printf 'updated\n'
  return 0
}

# ------------------------------------------------------------------------------------ --tracked
tracked() {  # $1 = root
  _root="$1"
  git -C "$_root" rev-parse --git-dir >/dev/null 2>&1 || return 0
  _top=$(git -C "$_root" rev-parse --show-toplevel 2>/dev/null) || return 0
  _pat=$(mktemp 2>/dev/null || mktemp -t harness-gitignore) || return 0
  patterns > "$_pat"
  # The index is the oracle for WHICH files match; git applies the patterns exactly as .gitignore
  # would. -z so a path with an unusual character is not handed back C-quoted.
  # Collapsed to the topmost DIRECTORY a pattern matches, globs included: `.claude/.local-llm-*`
  # matches the directory `.claude/.local-llm-cache`, and without this a project that committed its
  # cache (ticket, measured: 114 files) got one line per cached response. A pattern with a slash is
  # anchored to the root and matched against the whole prefix; one without is matched against each
  # directory name, which is what git does with it.
  git -C "$_top" ls-files -z -c -i --exclude-from="$_pat" 2>/dev/null | tr '\0' '\n' \
    | awk -v pf="$_pat" '
        function glob_re(g,   r, i, ch) {
          r = ""
          for (i = 1; i <= length(g); i++) {
            ch = substr(g, i, 1)
            if (ch == "*")      r = r "[^/]*"
            else if (ch == "?") r = r "[^/]"
            else if (index(".[]()+{}^$|\\", ch)) r = r "\\" ch
            else                r = r ch
          }
          return "^" r "$"
        }
        BEGIN {
          while ((getline p < pf) > 0) {
            sub(/\/$/, "", p)
            if (p == "") continue
            np++; re[np] = glob_re(p); anch[np] = (index(p, "/") > 0)
          }
        }
        NF {
          n = split($0, c, "/"); pre = ""
          for (i = 1; i < n; i++) {
            pre = (i == 1) ? c[1] : pre "/" c[i]
            for (k = 1; k <= np; k++)
              if ((anch[k] && pre ~ re[k]) || (!anch[k] && c[i] ~ re[k])) { print pre; next }
          }
          print $0
        }' \
    | LC_ALL=C sort -u
  rm -f "$_pat"
}

case "${1:-}" in
  --list)    patterns ;;
  --apply)   [ $# -eq 2 ] || die_usage; apply_block apply "$2" ;;
  --check)   [ $# -eq 2 ] || die_usage; apply_block check "$2" ;;
  --tracked) [ $# -eq 2 ] || die_usage; tracked "$2" ;;
  *)         die_usage ;;
esac
