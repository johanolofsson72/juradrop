#!/usr/bin/env bash
# skill-audit.sh — local "what skills am I actually loading?" audit pass.
#
# WHY THIS EXISTS
# Every installed skill costs baseline context at session start: its name +
# description load into the system prompt even on sessions where the skill never
# fires. The project-wizard / project-update sync is install-only — it clones
# external skill bundles (anthropics/skills, superpowers, dotnet/skills,
# vercel-labs/skills, playwright-skill, …) and never removes anything. Over time
# a machine accumulates dozens of globally-installed skills, many irrelevant to
# the project in front of you (a Flutter app does not need Playwright; a pure
# .NET API does not need React perf rules). This script makes that cost visible.
#
# REPORT-ONLY — IT NEVER DELETES ANYTHING.
# Global skills live under ~/.claude/skills and are SHARED across every project
# on the machine. Deleting one because THIS project's stack does not use it would
# break a sibling project that does. So this script only ever *reports* and
# prints commented-out removal suggestions you can copy if you decide to act. It
# is the deliberate complement to the install-only sync: visibility + discipline,
# not automated pruning.
#
# WHAT IT DOES
#   1. Finds every SKILL.md under ~/.claude/skills (global) and ./.claude/skills
#      (project), including nested ones (a single clone like anthropics/skills
#      contains many skills, each its own SKILL.md in a subdir).
#   2. Extracts name + description from each, estimates the per-session token
#      cost (chars / 4), and sums an honest baseline-context total.
#   3. Detects this project's stack (.claude/.sync-stack, else file markers) and
#      flags bundles that this stack plainly does not use — REVIEW, not delete.
#   4. Warns when the global skill count crosses a soft ceiling (default 15).
#
# bash 3.2-safe (macOS system bash): no associative arrays, no ${var,,}, no
# mapfile. Cross-platform: macOS / Linux / Windows Git Bash.
#
# Usage:
#   bash scripts/skill-audit.sh                 # audit global + project skills
#   bash scripts/skill-audit.sh --global-only   # only ~/.claude/skills
#   bash scripts/skill-audit.sh --project-only   # only ./.claude/skills
#   bash scripts/skill-audit.sh --stack=mobile   # override stack detection
#   bash scripts/skill-audit.sh --ceiling=20     # change the soft ceiling
#
# Exit codes: 0 = audit ran (always, even with flags), 2 = bad usage.

set -uo pipefail

# ---- arg parsing ------------------------------------------------------------
DO_GLOBAL=1
DO_PROJECT=1
STACK_OVERRIDE=""
CEILING=15
EXPLICIT_SCOPE=0
for arg in "$@"; do
  case "$arg" in
    --global-only)  DO_GLOBAL=1; [ "$EXPLICIT_SCOPE" -eq 0 ] && DO_PROJECT=0; EXPLICIT_SCOPE=1 ;;
    --project-only) DO_PROJECT=1; [ "$EXPLICIT_SCOPE" -eq 0 ] && DO_GLOBAL=0; EXPLICIT_SCOPE=1 ;;
    --stack=*)      STACK_OVERRIDE="${arg#--stack=}" ;;
    --ceiling=*)    CEILING="${arg#--ceiling=}" ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "[WARN] unknown argument: $arg (ignored)" >&2 ;;
  esac
done

case "$CEILING" in
  ''|*[!0-9]*) echo "[ERROR] --ceiling must be an integer" >&2; exit 2 ;;
esac

GLOBAL_ROOT="$HOME/.claude/skills"
PROJECT_ROOT=".claude/skills"

# ---- stack detection --------------------------------------------------------
# Emits a space-separated set of flags into STACK_FLAGS: web mobile dotnet flutter
detect_stack() {
  flags=""
  if [ -n "$STACK_OVERRIDE" ]; then
    case "$STACK_OVERRIDE" in
      web)    flags="web" ;;
      mobile) flags="mobile" ;;
      hybrid) flags="web mobile" ;;
      dotnet) flags="web dotnet" ;;
      *)      flags="$STACK_OVERRIDE" ;;
    esac
    echo "$flags"; return
  fi

  # .sync-stack records the testing track chosen during sync (web|mobile|hybrid)
  if [ -f .claude/.sync-stack ]; then
    track=$(grep -E '^testing=' .claude/.sync-stack 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    case "$track" in
      web)    flags="web" ;;
      mobile) flags="mobile" ;;
      hybrid) flags="web mobile" ;;
    esac
  fi

  # Augment with hard file markers (cheap, deterministic)
  if ls ./*.csproj ./*.sln >/dev/null 2>&1 || find . -maxdepth 3 -name '*.csproj' 2>/dev/null | head -1 | grep -q .; then
    case " $flags " in *" dotnet "*) :;; *) flags="$flags dotnet web" ;; esac
  fi
  if [ -f pubspec.yaml ] && grep -qE '^\s*(flutter:|sdk:\s*flutter)' pubspec.yaml 2>/dev/null; then
    case " $flags " in *" flutter "*) :;; *) flags="$flags flutter mobile" ;; esac
  fi
  if [ -f package.json ] && grep -qE '"(expo|react-native)"' package.json 2>/dev/null; then
    case " $flags " in *" mobile "*) :;; *) flags="$flags mobile" ;; esac
  fi

  # Normalize: split to words, drop duplicates preserving first-seen order, rejoin.
  echo "$flags" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ $//'
}

has_flag() { case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

# ---- relevance table --------------------------------------------------------
# Given a top-level skills-dir basename and the stack flags, echo a one-word
# verdict: "core" (universal, never flag), "ok" (relevant to this stack), or
# "review:<reason>" (this stack plainly does not use it — review, do not assume).
relevance() {
  bundle="$1"; flags="$2"
  case "$bundle" in
    anthropics-skills|superpowers|trailofbits-skills|ui-ux-pro-max|frontend-design)
      echo "core" ;;
    dotnet-skills)
      if has_flag "$flags" dotnet; then echo "ok"
      else echo "review:no .NET project detected (.csproj/.sln) — .NET-only patterns"; fi ;;
    vercel-skills)
      # React web performance rules. Relevant to web/react; not to Flutter-only
      # or a pure non-web stack.
      if has_flag "$flags" web && ! { has_flag "$flags" flutter && ! has_flag "$flags" web; }; then echo "ok"
      elif has_flag "$flags" flutter && ! has_flag "$flags" web; then echo "review:Flutter stack — React web-perf rules do not apply"
      elif has_flag "$flags" mobile && ! has_flag "$flags" web; then echo "review:mobile-only stack — React *web* perf rules rarely apply"
      else echo "ok"; fi ;;
    playwright-skill|qa-test)
      # Browser automation / destructive browser testing. Useless on a pure
      # native-mobile stack (those use Maestro/Patrol, no browser).
      if has_flag "$flags" web; then echo "ok"
      elif has_flag "$flags" mobile; then echo "review:mobile-only stack has no browser — use Maestro/Patrol instead"
      else echo "ok"; fi ;;
    *)
      echo "ok" ;;
  esac
}

# ---- per-root audit ---------------------------------------------------------
# Walks one skills root, prints a grouped report, and appends to the running
# global counters via a temp file (bash 3.2 has no nameref).
TALLY="${TMPDIR:-/tmp}/skill-audit.$$"
: > "$TALLY"        # lines: "<tokens>"
COUNT_FILE="${TMPDIR:-/tmp}/skill-audit-count.$$"
echo 0 > "$COUNT_FILE"
trap 'rm -f "$TALLY" "$COUNT_FILE" 2>/dev/null' EXIT

field() {
  # $1 = SKILL.md path, $2 = field name (name|description). Reads only the
  # frontmatter (between the first two '---' lines). Strips quotes.
  awk -v key="$2" '
    NR==1 && $0!~/^---/ {exit}
    /^---/ {d++; if (d==2) exit; next}
    d==1 {
      if ($0 ~ "^"key":[ \t]*") {
        sub("^"key":[ \t]*","",$0)
        gsub(/^"|"$|^'\''|'\''$/,"",$0)
        print; exit
      }
    }
  ' "$1" 2>/dev/null
}

audit_root() {
  root="$1"; label="$2"; flags="$3"
  [ -d "$root" ] || { echo "  ($label root not present: $root)"; return; }

  # Find every SKILL.md, skipping VCS dirs. Group by the first path component
  # under the root (the install bundle).
  prev_bundle=""
  # Use a sorted find so grouping is stable.
  find "$root" -type f -name 'SKILL.md' 2>/dev/null \
    | grep -v '/\.git/' \
    | sort \
    | while IFS= read -r skill; do
        rel="${skill#$root/}"
        bundle="${rel%%/*}"
        [ "$bundle" = "SKILL.md" ] && bundle="(top-level)"
        nm=$(field "$skill" name)
        desc=$(field "$skill" description)
        [ -z "$nm" ] && nm="$bundle"
        chars=$(printf '%s%s' "$nm" "$desc" | wc -c | tr -d ' ')
        toks=$(( (chars + 3) / 4 ))
        echo "$toks" >> "$TALLY"
        c=$(cat "$COUNT_FILE"); echo $((c+1)) > "$COUNT_FILE"

        if [ "$bundle" != "$prev_bundle" ]; then
          verdict=$(relevance "$bundle" "$flags")
          case "$verdict" in
            core)        tag="[core]    " ;;
            ok)          tag="[ok]      " ;;
            review:*)    tag="[REVIEW]   " ;;
          esac
          echo ""
          echo "  $tag $bundle"
          case "$verdict" in
            review:*) echo "             ↳ ${verdict#review:} — global/shared, review before removing" ;;
          esac
          prev_bundle="$bundle"
        fi
        printf '             - %-28s ~%s tok\n' "$nm" "$toks"
      done
}

# ---- run --------------------------------------------------------------------
STACK_FLAGS=$(detect_stack)
[ -z "$STACK_FLAGS" ] && STACK_FLAGS="(unknown — no .sync-stack or markers)"

echo "=== skill audit ============================================================"
echo "Stack detected: $STACK_FLAGS"
echo "Soft ceiling:   $CEILING global skills"
echo "Report-only: this script NEVER deletes. Global skills are shared across all"
echo "projects on this machine — a [REVIEW] flag means 'this project's stack does"
echo "not use it', not 'safe to delete'."

if [ "$DO_GLOBAL" -eq 1 ]; then
  echo ""
  echo "--- GLOBAL skills ($GLOBAL_ROOT) -------------------------------------------"
  audit_root "$GLOBAL_ROOT" "global" "$STACK_FLAGS"
fi

GLOBAL_COUNT=$(cat "$COUNT_FILE")

if [ "$DO_PROJECT" -eq 1 ]; then
  echo ""
  echo "--- PROJECT skills ($PROJECT_ROOT) -----------------------------------------"
  audit_root "$PROJECT_ROOT" "project" "$STACK_FLAGS"
fi

TOTAL_COUNT=$(cat "$COUNT_FILE")
TOTAL_TOK=$(awk '{s+=$1} END{print s+0}' "$TALLY")

echo ""
echo "--- summary ----------------------------------------------------------------"
echo "Skills discovered (SKILL.md files): $TOTAL_COUNT"
echo "Estimated baseline context per session: ~${TOTAL_TOK} tokens (name+description only)"
echo "  (full SKILL.md bodies load only when a skill actually fires — progressive disclosure)"

if [ "$DO_GLOBAL" -eq 1 ] && [ "$GLOBAL_COUNT" -gt "$CEILING" ]; then
  echo ""
  echo "[CEILING] $GLOBAL_COUNT global skills > soft ceiling of $CEILING."
  echo "          Review the [REVIEW]-tagged bundles above. The audit discipline:"
  echo "          monthly, remove what no project on this machine uses, re-baseline."
  echo "          Removal is a manual decision — e.g.  rm -rf \"$GLOBAL_ROOT/<bundle>\""
else
  echo ""
  echo "[OK] global skill count within the soft ceiling."
fi
echo "============================================================================"
exit 0
