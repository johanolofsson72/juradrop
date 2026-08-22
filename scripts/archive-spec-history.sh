#!/bin/bash
# archive-spec-history.sh — one-shot (repeatable) context-cost cleanup.
#
# WHY: specs/INDEX.md and specs/SCENARIOS.md each carry a "## ... history"
# section that grows one entry per spec and gets RE-READ in full on every
# subsequent spec. On a 60+ spec project that history balloons to tens of
# thousands of tokens that buy nothing — the live rows/ledger are what the
# pipeline actually needs. This script moves the OLD history entries out to a
# sibling ".history.md" archive (never read per-spec) and keeps only the N
# NEWEST entries inline (ordering auto-detected: works whether the register
# appends newest-at-bottom or prepends newest-at-top). The live spec rows /
# SC-id ledger are never touched.
#
# Safe by construction:
#   - The history region is everything BELOW the last "## ... history" heading,
#     and it admits ONLY two things: "- YYYY-MM-DD ..." entries (one line each,
#     per .claude/rules/spec-register.md and .claude/rules/scenarios.md) and
#     blank lines. Anything else is a ledger block that was appended in the wrong
#     place, and the script REFUSES the file rather than moving it (exit 3).
#     This guard is why the section header no longer claims the script "operates
#     only on the history section" — it used to say that, and it was false: the
#     split is positional, so four scenario ledger blocks appended below the
#     heading were swept as if they were history. Measured before the fix: 155
#     lines and 76 live "✓ validated" SC-ids relocated into the archive, with
#     validate-scenario-traceability.sh reporting 100% and exit 0 throughout,
#     because it reads both files. That silence is the K5 violation; row H5j.
#   - Reversible — the repo is git-tracked; `git diff` shows exactly what moved,
#     `git checkout -- <file>` undoes it.
#   - Idempotent — re-running with the same KEEP just re-confirms; nothing is
#     lost or duplicated (archived entries are prepended once, newest-first).
#
# Exit codes:
#   0  success (or nothing to do)
#   1  no specs/ directory found
#   2  usage error (unknown arg, non-numeric --keep)
#   3  REFUSED — a history region contained something that is not a history
#      entry. Nothing was written. Distinct from 1/2 so a test asserting the
#      refusal cannot pass because the script died of an unrelated fault.
#
# Usage:
#   scripts/archive-spec-history.sh                 # cleans ./specs/*, KEEP=5
#   scripts/archive-spec-history.sh --keep 8        # keep the 8 newest inline
#   scripts/archive-spec-history.sh --dir path/to/specs
#   scripts/archive-spec-history.sh --dry-run       # report only, write nothing
#
# Cross-platform: POSIX awk + bash. Runs under macOS, Linux, and Git Bash/WSL.

set -eu

KEEP=5
SPECS_DIR=""
DRY_RUN=0
# Set to 1 by archive_history() when a file is refused. The function itself
# always returns 0 — `set -e` is live, so returning non-zero would kill the
# script at that call and a refused INDEX.md would stop SCENARIOS.md from ever
# being examined (silently breaking the "a clean sibling is still processed"
# guarantee). The refusal is reported per file and settled once, at the end.
REFUSED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP="${2:?--keep needs a number}"; shift 2 ;;
    --dir) SPECS_DIR="${2:?--dir needs a path}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$KEEP" in ''|*[!0-9]*) echo "--keep must be a non-negative integer" >&2; exit 2 ;; esac

# Locate the specs dir: explicit --dir, else ./specs, else walk up to a repo root.
if [ -z "$SPECS_DIR" ]; then
  if [ -d "./specs" ]; then
    SPECS_DIR="./specs"
  else
    d="$PWD"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
      if [ -d "$d/specs" ]; then SPECS_DIR="$d/specs"; break; fi
      [ -d "$d/.git" ] && break
      d=$(dirname "$d")
    done
  fi
fi
[ -n "$SPECS_DIR" ] && [ -d "$SPECS_DIR" ] || { echo "no specs/ dir found (use --dir)" >&2; exit 1; }

# archive_history <live-file> <archive-file> <history-heading-regex>
# <history-heading-regex> MUST be anchored to a markdown heading (^#+ ...) so a
# history ENTRY that merely mentions the words "register history" in its prose is
# not mistaken for the section heading (that would split the file at the wrong
# line). Splits the file at the LAST heading matching the regex.
# Keeps the KEEP newest top-level "- " bullets (with their continuation lines)
# inline — detecting whether newest is at the top or bottom from the first vs
# last entry's ISO date — and moves the older bullets to the archive.
archive_history() {
  live="$1"; archive="$2"; heading_re="$3"
  [ -f "$live" ] || { echo "  skip: $live (not found)"; return 0; }

  # Line number of the last heading that matches (history is the final section).
  hdr_line=$(awk -v re="$heading_re" 'tolower($0) ~ re {n=NR} END{print n+0}' "$live")
  if [ "$hdr_line" -eq 0 ]; then
    echo "  skip: $(basename "$live") — no history section (nothing to archive)"
    return 0
  fi

  # ---- GUARD -------------------------------------------------------------
  # The region below the heading admits ONLY dated history entries and blank
  # lines. Anything else (a heading, a table row, a mermaid fence, a horizontal
  # rule, an undated bullet) is ledger content sitting in the wrong place;
  # moving it would make proven scenarios invisible to the next spec.
  #
  # Checked over the WHOLE region and BEFORE the keep/move partition below, so
  # the verdict never depends on --keep. A guard evaluated after partitioning
  # would pass at --keep 20 and fail at --keep 5 on the same file, which teaches
  # people the fault is spurious.
  #
  # Anchored at line start, so a history entry whose prose quotes '#', '|' or a
  # date is admitted normally — the real entries do all three.
  foreign=$(awk -v h="$hdr_line" '
    NR<=h                                            { next }
    /^[[:space:]]*$/                                 { next }
    /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/  { next }
                                                     { printf "%d:%.120s", NR, $0; exit }
  ' "$live") || true

  if [ -n "$foreign" ]; then
    fl=${foreign%%:*}; ft=${foreign#*:}
    echo "  FAULT: $(basename "$live") — line $fl below '$(awk -v h="$hdr_line" 'NR==h' "$live")' is not a history entry:"
    echo "           $ft"
    echo "         That region admits ONLY '- YYYY-MM-DD ...' entries (one line each) and blank lines."
    echo "         Scenario/ledger blocks belong ABOVE the heading — everything below it is treated as"
    echo "         archivable history, and archived history is never read during the pipeline."
    echo "         Nothing was moved; $(basename "$live") is unchanged."
    REFUSED=1
    return 0
  fi
  # ---- end GUARD ---------------------------------------------------------

  tmp_body=$(mktemp); tmp_keep=$(mktemp); tmp_move=$(mktemp)
  trap 'rm -f "$tmp_body" "$tmp_keep" "$tmp_move"' RETURN

  # Body = everything up to and including the history heading line.
  awk -v h="$hdr_line" 'NR<=h' "$live" > "$tmp_body"

  # History region = everything after the heading. Group into entries: an entry
  # starts at a top-level "- " bullet and includes following non-bullet lines.
  # Keep the KEEP NEWEST entries inline; archive the rest. Registers differ in
  # convention: some append newest-at-bottom (the template example), some prepend
  # newest-at-top (every real project checked). So detect ordering from the first
  # vs last entry's ISO date and keep whichever END holds the newest entries —
  # never blindly keep-last, or a newest-first register archives its RECENT
  # history and keeps ancient entries inline.
  awk -v h="$hdr_line" -v keep="$KEEP" -v fkeep="$tmp_keep" -v fmove="$tmp_move" '
    function dateof(s){ if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return substr(s, RSTART, RLENGTH); return "" }
    NR<=h { next }
    { region[++n]=$0 }
    END{
      e=0
      for(i=1;i<=n;i++) if (region[i] ~ /^- /) starts[++e]=i
      if (e<=keep) { for(i=1;i<=n;i++) print region[i] > fkeep; exit }   # nothing to move
      fd = dateof(region[starts[1]]); ld = dateof(region[starts[e]])
      newestFirst = (fd != "" && ld != "" && fd > ld) ? 1 : 0
      if (newestFirst) {
        # newest at top → keep entries 1..keep, archive keep+1..e
        keepEnd = starts[keep+1] - 1
        for(i=1;i<=n;i++){ if (i<=keepEnd) print region[i] > fkeep; else print region[i] > fmove }
      } else {
        # newest at bottom (or undated) → keep the last KEEP, archive 1..(e-keep)
        moveEnd = starts[e-keep+1] - 1
        for(i=1;i<=n;i++){ if (i<=moveEnd) print region[i] > fmove; else print region[i] > fkeep }
      }
    }
  ' "$live"

  # grep -c prints "0" AND exits non-zero on no match; use `|| true` so we keep
  # that "0" without appending a second line (which would break the -eq test).
  moved=$(grep -cE '^- ' "$tmp_move" 2>/dev/null || true)
  moved=${moved:-0}
  if [ "$moved" -eq 0 ]; then
    echo "  ok:   $(basename "$live") — history ≤ keep=$KEEP, nothing to move"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  DRY:  $(basename "$live") — would archive $moved entr$([ "$moved" -eq 1 ] && echo y || echo ies) → $(basename "$archive"), keep newest $KEEP inline"
    return 0
  fi

  # Prepend moved entries (older) to the archive, newest archived batch on top of
  # the older archive but below the archive header. Build fresh archive content.
  arch_tmp=$(mktemp)
  {
    echo "# $(basename "${live%.md}") — archived history"
    echo
    echo "Old history entries moved out of $(basename "$live") to keep per-spec context cheap."
    echo "This file is NOT read during the pipeline. Newest archived batch first."
    echo
    cat "$tmp_move"
    if [ -f "$archive" ]; then
      # Append the previous archive body (strip its header block: first 5 lines).
      echo
      awk 'NR>5' "$archive"
    fi
  } > "$arch_tmp"
  mv "$arch_tmp" "$archive"

  # Rebuild the live file: body (through heading) + kept entries.
  { cat "$tmp_body"; cat "$tmp_keep"; } > "$live.tmp" && mv "$live.tmp" "$live"
  echo "  ok:   $(basename "$live") — archived $moved entr$([ "$moved" -eq 1 ] && echo y || echo ies) → $(basename "$archive"), kept newest $KEEP inline"
}

echo "Archiving spec history in: $SPECS_DIR (keep newest $KEEP inline)$([ "$DRY_RUN" -eq 1 ] && echo '  [DRY RUN]')"
archive_history "$SPECS_DIR/INDEX.md"     "$SPECS_DIR/INDEX.history.md"     '^#+ .*register history'
archive_history "$SPECS_DIR/SCENARIOS.md" "$SPECS_DIR/SCENARIOS.history.md" '^#+ .*scenario history'

if [ "$REFUSED" -ne 0 ]; then
  echo "REFUSED: at least one history region held content that is not a history entry. Nothing was"
  echo "moved for that file. Move the offending block ABOVE its history heading and re-run."
  exit 3
fi

echo "Done. Review with 'git diff', undo with 'git checkout -- $SPECS_DIR'."
