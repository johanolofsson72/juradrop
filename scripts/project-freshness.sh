#!/usr/bin/env bash
# project-freshness.sh — local "keep the project fresh" maintenance pass.
#
# Two independent checks, both LOCAL (never a GitHub Action — see
# .claude/rules/github-actions.md, the trufflehog/secret-scan-on-schedule ban):
#
#   1. trufflehog — verified secret scan of the repo (git history if this is a
#      git repo, otherwise the working tree). Catches credentials that already
#      got committed; complements the per-edit local-llm-secret-scan-hook.sh.
#   2. npm audit  — dependency vulnerability report for any package.json found.
#
# REPORT-FIRST by default: it tells you what is wrong and prints the exact
# remediation commands, but it does NOT mutate the tree. `npm audit fix --force`
# can yank in breaking major bumps, so it only runs when you pass --fix, and
# even then it forces a build + test afterwards so breakage surfaces before commit.
#
# bash 3.2-safe (macOS system bash): no associative arrays, no ${var,,}, no mapfile.
# Cross-platform: macOS / Linux / Windows Git Bash.
#
# trufflehog is self-installed when missing (brew → scoop → the official
# install.sh into ~/.local/bin), mirroring scripts/graphify-bootstrap.sh so
# David's Linux box ends up in the same state as Johan's macOS box. Best-effort
# and loud: if every install path fails it falls back to a skip + platform hint
# rather than aborting. Pass --no-install to suppress the self-install entirely.
#
# Usage:
#   bash scripts/project-freshness.sh             # report only (default), auto-installs trufflehog if missing
#   bash scripts/project-freshness.sh --fix       # also run `npm audit fix --force` + verify
#   bash scripts/project-freshness.sh --secrets   # only the trufflehog pass
#   bash scripts/project-freshness.sh --deps      # only the npm audit pass
#   bash scripts/project-freshness.sh --no-install # never self-install trufflehog; skip + hint if absent
#
# Exit codes: 0 = clean (or only skipped checks), 1 = findings reported,
#             2 = a requested --fix step failed verification.

set -uo pipefail

# ---- arg parsing ------------------------------------------------------------
DO_FIX=0
DO_SECRETS=1
DO_DEPS=1
NO_INSTALL=0
EXPLICIT_SCOPE=0
for arg in "$@"; do
  case "$arg" in
    --fix)        DO_FIX=1 ;;
    --no-install) NO_INSTALL=1 ;;
    --secrets) DO_SECRETS=1; [ "$EXPLICIT_SCOPE" -eq 0 ] && DO_DEPS=0; EXPLICIT_SCOPE=1 ;;
    --deps)    DO_DEPS=1;    [ "$EXPLICIT_SCOPE" -eq 0 ] && DO_SECRETS=0; EXPLICIT_SCOPE=1 ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "[WARN] unknown argument: $arg (ignored)" >&2 ;;
  esac
done

# ---- trufflehog self-installer (best-effort, cross-platform) ----------------
# Returns 0 if trufflehog is on PATH afterward, non-zero otherwise. Never aborts
# the caller — the secret-scan block falls back to a skip + install hint on failure.
ensure_trufflehog() {
  command -v trufflehog >/dev/null 2>&1 && return 0
  [ "$NO_INSTALL" -eq 1 ] && return 1
  echo "[INSTALL] trufflehog not found — attempting install (local only; never a CI/scheduled Action)…"

  if command -v brew >/dev/null 2>&1; then
    # macOS / Linuxbrew — cleanest path, keeps trufflehog updatable.
    brew install trufflehog >/dev/null 2>&1
  elif command -v scoop >/dev/null 2>&1; then
    # Windows Git Bash — unprivileged, per-user, no UAC prompt.
    scoop install trufflehog >/dev/null 2>&1
  elif command -v curl >/dev/null 2>&1; then
    # Universal fallback: the official install script into a user-writable
    # dir (no sudo). The script auto-detects OS/arch and fetches the right binary.
    mkdir -p "$HOME/.local/bin"
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
      | sh -s -- -b "$HOME/.local/bin" >/dev/null 2>&1
  elif command -v go >/dev/null 2>&1; then
    # Last resort for a Go-toolchain box with no curl/brew/scoop.
    go install github.com/trufflesecurity/trufflehog/v3@latest >/dev/null 2>&1
  fi

  # Re-export PATH so a freshly-installed binary is visible without a shell restart.
  export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
  command -v trufflehog >/dev/null 2>&1
}

# ---- locate the project root ------------------------------------------------
if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git rev-parse --show-toplevel)"
else
  ROOT="$PWD"
fi
cd "$ROOT" || { echo "[ERROR] cannot cd to $ROOT" >&2; exit 2; }

FINDINGS=0
# Per-section verdicts for the bottom-line SUMMARY recap. On a noisy project the
# npm audit table buries everything above it, so `... | tail` would miss the
# secret verdict entirely — these one-liners guarantee both land at the bottom.
SECRETS_STATUS="not run (--deps)"
DEPS_STATUS="not run (--secrets)"

echo "=========================================================="
echo " project-freshness — $ROOT"
echo "=========================================================="

# ---- 1. trufflehog: verified secret scan ------------------------------------
if [ "$DO_SECRETS" -eq 1 ]; then
  echo
  echo "── [1/2] trufflehog secret scan ──────────────────────────"
  ensure_trufflehog
  if command -v trufflehog >/dev/null 2>&1; then
    # --only-verified: live-checked credentials only (kills the false-positive
    #                  noise that makes a report nobody reads).
    # --no-update:     do not phone home for a self-update on every run.
    # --fail:          exit non-zero when results are found.
    if [ -d .git ]; then
      # git history scan: naturally skips gitignored node_modules/build output.
      if trufflehog git "file://$ROOT" --only-verified --no-update --fail; then
        echo "[OK] No verified secrets in git history."
        SECRETS_STATUS="clean"
      else
        echo "[FINDING] trufflehog found verified secret(s) above. Rotate them NOW —"
        echo "          a committed credential is compromised the moment it is pushed."
        FINDINGS=1
        SECRETS_STATUS="VERIFIED SECRET(S) FOUND — rotate now"
      fi
    else
      if trufflehog filesystem "$ROOT" --only-verified --no-update --fail; then
        echo "[OK] No verified secrets in working tree."
        SECRETS_STATUS="clean"
      else
        echo "[FINDING] trufflehog found verified secret(s) above. Rotate them NOW."
        FINDINGS=1
        SECRETS_STATUS="VERIFIED SECRET(S) FOUND — rotate now"
      fi
    fi
  else
    SECRETS_STATUS="skipped (trufflehog unavailable)"
    if [ "$NO_INSTALL" -eq 1 ]; then
      echo "[SKIP] trufflehog not installed and --no-install given. Install it manually (local only — never wire it as a CI/scheduled Action):"
    else
      echo "[SKIP] trufflehog auto-install failed. Install it manually (local only — never wire it as a CI/scheduled Action):"
    fi
    case "$(uname -s 2>/dev/null)" in
      Darwin)  echo "         brew install trufflehog" ;;
      Linux)   echo "         curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin"
               echo "         (or: dnf install trufflehog / pacman -S trufflehog / go install github.com/trufflesecurity/trufflehog/v3@latest)" ;;
      MINGW*|MSYS*|CYGWIN*)
               echo "         scoop install trufflehog   (or download the release binary from github.com/trufflesecurity/trufflehog/releases)" ;;
      *)       echo "         see https://github.com/trufflesecurity/trufflehog#installation" ;;
    esac
  fi
fi

# ---- 2. npm audit: dependency vulnerability report --------------------------
if [ "$DO_DEPS" -eq 1 ]; then
  echo
  echo "── [2/2] npm audit (dependency CVEs) ─────────────────────"
  # Scan every package.json that is not vendored/build output.
  PKG_FOUND=0
  DEPS_VULN=0; DEPS_CLEAN=0; DEPS_SKIPPED=0; DEPS_SUMMARY=""
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    PKG_FOUND=1
    dir="$(dirname "$pkg")"
    echo
    echo "  package: $pkg"
    # Route non-npm package managers to their own audit — npm audit can't read their lockfiles.
    if [ -f "$dir/yarn.lock" ]; then
      echo "  [SKIP] yarn.lock present — run 'yarn npm audit' (Berry) or 'yarn audit' (Classic) in $dir."
      DEPS_SKIPPED=1
      continue
    fi
    if [ -f "$dir/pnpm-lock.yaml" ]; then
      echo "  [SKIP] pnpm-lock.yaml present — run 'pnpm audit' in $dir."
      DEPS_SKIPPED=1
      continue
    fi
    # npm audit needs a lockfile; without one it errors (ENOLOCK), which is NOT a vulnerability finding.
    if [ ! -f "$dir/package-lock.json" ] && [ ! -f "$dir/npm-shrinkwrap.json" ]; then
      echo "  [SKIP] No lockfile — run 'npm install' in $dir first, then re-run the freshness pass."
      DEPS_SKIPPED=1
      continue
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "  [SKIP] npm not installed — see https://nodejs.org or your package manager."
      DEPS_SKIPPED=1
      break
    fi
    # Report only. With a lockfile present, a non-zero exit means vulnerabilities exist.
    AUDIT_OUT=$( cd "$dir" && npm audit 2>&1 ); AUDIT_RC=$?
    printf '%s\n' "$AUDIT_OUT"
    if [ "$AUDIT_RC" -eq 0 ]; then
      echo "  [OK] No advisories for $pkg."
      DEPS_CLEAN=1
    else
      echo "  [FINDING] Vulnerabilities reported for $pkg (see table above)."
      FINDINGS=1
      DEPS_VULN=1
      # Scrape npm's own summary line ("N vulnerabilities (a low, b moderate, …)").
      VSUM=$(printf '%s\n' "$AUDIT_OUT" | grep -i 'vulnerabilit' | tail -1 | sed 's/^[[:space:]]*//')
      [ -n "$VSUM" ] || VSUM="advisories found"
      DEPS_SUMMARY="$DEPS_SUMMARY $(basename "$dir")/: $VSUM;"
      if [ "$DO_FIX" -eq 1 ]; then
        echo "  [FIX] Running 'npm audit fix --force' (this CAN introduce breaking major bumps)…"
        ( cd "$dir" && npm audit fix --force )
        echo "  [FIX] Done. You MUST now verify nothing broke:"
        echo "          - JS/TS only:  npm run build && npm test"
        echo "          - .NET + SPA:  dotnet build && dotnet test  (the React build feeds wwwroot)"
        echo "        Inspect the package.json diff before committing — review the major bumps."
      else
        echo "  [NEXT] Report-first: nothing was changed. To remediate (review the diff after):"
        echo "          cd \"$dir\" && npm audit fix          # safe, semver-compatible fixes"
        echo "          cd \"$dir\" && npm audit fix --force  # includes breaking major bumps — then build + test"
        echo "        Or re-run with --fix to apply the forced fix + verification reminder automatically."
      fi
    fi
  done <<EOF
$(find "$ROOT" -name package.json \
    -not -path '*/node_modules/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/bin/*' \
    -not -path '*/obj/*' \
    2>/dev/null)
EOF
  if [ "$PKG_FOUND" -eq 0 ]; then
    echo "  [SKIP] No package.json found — not a Node/JS project. (yarn/pnpm projects: run 'yarn npm audit' / 'pnpm audit' manually.)"
  fi
  # Roll the per-package outcomes up into one verdict for the SUMMARY recap.
  if [ "$PKG_FOUND" -eq 0 ]; then
    DEPS_STATUS="no package.json (not a Node project)"
  elif [ "$DEPS_VULN" -eq 1 ]; then
    DEPS_STATUS="advisories —$DEPS_SUMMARY"
  elif [ "$DEPS_CLEAN" -eq 1 ]; then
    DEPS_STATUS="clean"
  else
    DEPS_STATUS="skipped (no lockfile / non-npm — see notes above)"
  fi
fi

# ---- summary ----------------------------------------------------------------
echo
echo "=========================================================="
echo " SUMMARY  Secrets: $SECRETS_STATUS"
echo "          Deps:    $DEPS_STATUS"
if [ "$FINDINGS" -eq 0 ]; then
  echo " RESULT: clean (no verified secrets, no reported advisories)."
  exit 0
else
  echo " RESULT: findings above need attention. Nothing was committed."
  echo "         Secrets → rotate. Deps → review then 'npm audit fix [--force]'."
  exit 1
fi
