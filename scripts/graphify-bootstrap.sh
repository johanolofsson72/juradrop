#!/usr/bin/env bash
# Cross-platform Graphify bootstrap. Idempotent — safe to run on a fresh
# machine OR on a project that already has Graphify installed. Designed
# to be called from sync-prompt.md and project-wizard so David's Linux
# box ends up in the same state as Johan's macOS box.
#
# What this does:
#   1. Ensures `pipx` is available (self-installs via the platform's
#      package manager when missing — apt/dnf/pacman/brew supported).
#   2. Ensures `graphify` CLI is installed via pipx.
#   3. Runs `graphify install --project` in the current directory so the
#      Graphify skill + PreToolUse nudge hook land in .claude/.
#   4. Runs `graphify update .` to build the initial graph (AST-only, no
#      LLM API key required).
#   5. Runs `graphify hook install` so future commits auto-rebuild.
#   6. Ensures graphify-out/ is in .gitignore.
#   7. Wires the savings-logging hook (scripts/graphify-fire-hook.sh) in
#      .claude/settings.json — done by the caller via sync-local-llm-hooks
#      machinery; this script just verifies the script file is on disk.
#
# Exit codes:
#   0 — everything in place (whether we changed anything or not)
#   1 — bootstrap failure (no package manager / pipx install failed /
#       graphify install failed). Bootstrap is best-effort but loud — a
#       failure prints the missing step so the caller can decide whether
#       to abort the wider sync.
#
# Heuristic for "should this project have graphify installed?": projects
# with <30 source files in supported languages waste setup overhead. The
# caller passes --eligibility-check first; this script also runs it
# internally and skips the install when the project is too small. Pass
# --force to override.

set -uo pipefail

FORCE=0
ELIGIBILITY_ONLY=0
for ARG in "$@"; do
  case "$ARG" in
    --force) FORCE=1 ;;
    --eligibility-check) ELIGIBILITY_ONLY=1 ;;
    *) printf 'unknown arg: %s\n' "$ARG" >&2; exit 2 ;;
  esac
done

# ---------- eligibility ----------
# Languages graphify can extract via tree-sitter. Mirrors .claude/docs/graphify.md.
SUPPORTED_EXTS='cs ts tsx js jsx mjs py go rs java c cpp h hpp rb kt scala php swift lua zig ps1 ex exs m mm jl vue svelte astro groovy gradle dart sql sh bash'

count_eligible_files() {
  # Single-pass find. Earlier versions ran 36 separate finds (one per
  # extension) and hit a 15+ minute wall on monorepos like iskvalp
  # (101k source files). The OR-name predicate keeps it to one tree
  # walk regardless of how long the extension list grows.
  #
  # set -f disables filename globbing for the duration of the function
  # so bash doesn't expand `*.cs` against the current directory before
  # find sees it. Without this, a project with `debug.cs` at the root
  # turns `-name *.cs` into `-name debug.cs` and find then breaks with
  # "unknown primary or operator" on the next token. set +f restores
  # globbing before return.
  local name_clause='' first=1 ext
  set -f
  for ext in $SUPPORTED_EXTS; do
    if [ "$first" = 1 ]; then
      name_clause="-name *.$ext"
      first=0
    else
      name_clause="$name_clause -o -name *.$ext"
    fi
  done
  # shellcheck disable=SC2086  # word-splitting on $name_clause is intentional and safe under `set -f`
  local count
  count=$(find . \
    \( -path './node_modules' -o -path './.git' -o -path './bin' -o -path './obj' \
       -o -path './dist' -o -path './build' -o -path './graphify-out' \
       -o -path './artifacts' -o -path './.specify' -o -path './target' \
       -o -path '*/wwwroot/dist*' -o -path '*/wwwroot/build*' \
    \) -prune -o \
    -type f \( $name_clause \) -print 2>/dev/null | wc -l | tr -d ' ')
  set +f
  printf '%s' "$count"
}

ELIGIBLE_COUNT=$(count_eligible_files)
THRESHOLD=30

if [ "$ELIGIBILITY_ONLY" -eq 1 ]; then
  if [ "$ELIGIBLE_COUNT" -ge "$THRESHOLD" ]; then
    printf 'eligible: %d source files (>=%d)\n' "$ELIGIBLE_COUNT" "$THRESHOLD"
    exit 0
  else
    printf 'skip: %d source files (<%d) — not worth the install overhead\n' "$ELIGIBLE_COUNT" "$THRESHOLD"
    exit 10
  fi
fi

if [ "$FORCE" -ne 1 ] && [ "$ELIGIBLE_COUNT" -lt "$THRESHOLD" ]; then
  printf '[graphify-bootstrap] skip — only %d eligible source files (<%d). Pass --force to override.\n' \
    "$ELIGIBLE_COUNT" "$THRESHOLD"
  exit 0
fi

# ---------- pipx ----------
# Cross-platform pipx installer. Order matters: brew on macOS, native
# Linux package managers next, Windows package managers (Git Bash detects
# scoop/winget/choco when they're on PATH), and finally a pip --user
# fallback for any environment where none of the above are available.
# `sudo` is only invoked when the package manager actually requires it
# (apt/dnf/pacman/zypper) — scoop and winget run unprivileged on Windows.
ensure_pipx() {
  if command -v pipx >/dev/null 2>&1; then
    return 0
  fi
  printf '[graphify-bootstrap] pipx not found — attempting install\n'

  # Detect "is this Windows Git Bash / MSYS / Cygwin" for diagnostic
  # messaging. The package-manager probes work regardless.
  IS_WINDOWS=0
  case "${OSTYPE:-}${MSYSTEM:-}" in
    *msys*|*cygwin*|*MINGW*) IS_WINDOWS=1 ;;
  esac
  [ -n "${MSYSTEM:-}" ] && IS_WINDOWS=1

  if command -v brew >/dev/null 2>&1; then
    brew install pipx >/dev/null 2>&1 && pipx ensurepath >/dev/null 2>&1
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -yq pipx && pipx ensurepath >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -yq pipx && pipx ensurepath >/dev/null 2>&1
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm python-pipx && pipx ensurepath >/dev/null 2>&1
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y python3-pipx && pipx ensurepath >/dev/null 2>&1
  elif command -v scoop >/dev/null 2>&1; then
    # Windows Git Bash: scoop is the friendliest path — unprivileged,
    # per-user, no UAC prompt. Preferred over winget/choco for the
    # Claude Code use case.
    scoop install pipx >/dev/null 2>&1 && pipx ensurepath >/dev/null 2>&1
  elif command -v winget >/dev/null 2>&1; then
    # winget runs unprivileged for per-user installs.
    winget install --silent --accept-package-agreements --accept-source-agreements pipx >/dev/null 2>&1 \
      && pipx ensurepath >/dev/null 2>&1
  elif command -v choco >/dev/null 2>&1; then
    # Chocolatey typically needs admin; this will surface a UAC prompt
    # on Windows or fail explicitly if the shell is unprivileged.
    choco install -y pipx >/dev/null 2>&1 && pipx ensurepath >/dev/null 2>&1
  else
    # Universal fallback: pip install --user pipx. Works on every
    # platform that has python3 + pip — including Windows Git Bash
    # when none of the package managers are present.
    if command -v python3 >/dev/null 2>&1; then
      python3 -m pip install --user pipx >/dev/null 2>&1 && python3 -m pipx ensurepath >/dev/null 2>&1
    elif command -v python >/dev/null 2>&1; then
      # Windows often only ships `python` (no `python3` alias).
      python -m pip install --user pipx >/dev/null 2>&1 && python -m pipx ensurepath >/dev/null 2>&1
    fi
  fi

  # pipx ensurepath modifies the shell rc files; re-export PATH for this
  # process so the next command can find pipx without a restart. Both
  # $HOME/.local/bin (POSIX) and the Windows %APPDATA%\Python\Scripts
  # locations are covered.
  export PATH="$HOME/.local/bin:$PATH"
  if [ "$IS_WINDOWS" = "1" ]; then
    # Windows Git Bash: pipx defaults to ~/AppData/Local/pipx OR
    # ~/.local/bin depending on the install path. Cover both.
    [ -d "$HOME/AppData/Local/pipx/scripts" ] && export PATH="$HOME/AppData/Local/pipx/scripts:$PATH"
    [ -d "$APPDATA/Python/Scripts" ] && export PATH="$APPDATA/Python/Scripts:$PATH"
  fi

  command -v pipx >/dev/null 2>&1
}

ensure_pipx || {
  printf '[graphify-bootstrap] ERROR: could not install pipx — install manually and re-run.\n' >&2
  printf '  macOS:           brew install pipx && pipx ensurepath\n' >&2
  printf '  Debian/Ubuntu:   sudo apt install pipx && pipx ensurepath\n' >&2
  printf '  Fedora/RHEL:     sudo dnf install pipx && pipx ensurepath\n' >&2
  printf '  Arch:            sudo pacman -S python-pipx && pipx ensurepath\n' >&2
  printf '  openSUSE:        sudo zypper install python3-pipx && pipx ensurepath\n' >&2
  printf '  Windows Git Bash: scoop install pipx  (or: winget install pipx)\n' >&2
  printf '  Any platform:    python3 -m pip install --user pipx && python3 -m pipx ensurepath\n' >&2
  exit 1
}

# ---------- graphifyy ----------
if command -v graphify >/dev/null 2>&1; then
  printf '[graphify-bootstrap] graphify already installed (%s)\n' "$(graphify --version 2>&1 | head -1)"
else
  printf '[graphify-bootstrap] installing graphifyy via pipx\n'
  pipx install graphifyy >/dev/null 2>&1 || {
    printf '[graphify-bootstrap] ERROR: pipx install graphifyy failed\n' >&2
    exit 1
  }
  export PATH="$HOME/.local/bin:$PATH"
  command -v graphify >/dev/null 2>&1 || {
    printf '[graphify-bootstrap] ERROR: graphify still not on PATH after install\n' >&2
    exit 1
  }
fi

# ---------- project install ----------
if [ -f .claude/skills/graphify/SKILL.md ]; then
  printf '[graphify-bootstrap] project install already present (%s)\n' '.claude/skills/graphify/SKILL.md'
else
  printf '[graphify-bootstrap] running: graphify install --project\n'
  graphify install --project >/dev/null 2>&1 || {
    printf '[graphify-bootstrap] WARN: graphify install --project exited non-zero — investigate manually\n' >&2
  }
fi

# ---------- initial extraction (AST only — no LLM key needed) ----------
if [ -f graphify-out/graph.json ]; then
  printf '[graphify-bootstrap] graph.json exists — skipping initial extraction\n'
else
  printf '[graphify-bootstrap] running: graphify update . (AST-only, this may take a minute)\n'
  graphify update . >/dev/null 2>&1 || {
    printf '[graphify-bootstrap] WARN: graphify update . exited non-zero — investigate manually\n' >&2
  }
fi

# ---------- git hooks ----------
if [ -f .git/hooks/post-commit ] && grep -q graphify .git/hooks/post-commit 2>/dev/null; then
  printf '[graphify-bootstrap] git post-commit hook already references graphify\n'
else
  printf '[graphify-bootstrap] running: graphify hook install\n'
  graphify hook install >/dev/null 2>&1 || {
    printf '[graphify-bootstrap] WARN: graphify hook install exited non-zero — investigate manually\n' >&2
  }
fi

# ---------- .gitignore ----------
GITIGNORE=".gitignore"
if [ ! -f "$GITIGNORE" ]; then
  touch "$GITIGNORE"
fi
if ! grep -qxF 'graphify-out/' "$GITIGNORE" 2>/dev/null; then
  printf '\n# Graphify knowledge-graph artifacts (derived; rebuilt on commit)\ngraphify-out/\n' >> "$GITIGNORE"
  printf '[graphify-bootstrap] added graphify-out/ to .gitignore\n'
fi
if ! grep -qxF '.claude/graphify-fire.log' "$GITIGNORE" 2>/dev/null \
   && ! grep -qxF '.claude/graphify-*.log' "$GITIGNORE" 2>/dev/null; then
  if ! grep -qE '^\.claude/.*\.log$' "$GITIGNORE" 2>/dev/null; then
    printf '.claude/graphify-*.log\n' >> "$GITIGNORE"
    printf '[graphify-bootstrap] added .claude/graphify-*.log to .gitignore\n'
  fi
fi

# ---------- verify telemetry hook script is on disk ----------
# The settings.json wiring is the caller's job (sync-prompt.md does this
# via sync-local-llm-hooks.py's mirror semantics). Here we only confirm
# the script file exists so the wiring won't reference a ghost.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/graphify-fire-hook.sh" ]; then
  printf '[graphify-bootstrap] WARN: graphify-fire-hook.sh missing from %s\n' "$SCRIPT_DIR" >&2
  printf '  Run the template sync (project-update) so the script is copied.\n' >&2
fi

printf '[graphify-bootstrap] done\n'
exit 0
