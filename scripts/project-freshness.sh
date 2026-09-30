#!/usr/bin/env bash
# project-freshness.sh — local "keep the project fresh" maintenance pass.
#
# Six independent checks, all LOCAL (never a GitHub Action — see
# .claude/rules/github-actions.md, the trufflehog/secret-scan-on-schedule ban):
#
#   1. trufflehog — verified secret scan of the repo (git history if this is a
#      git repo, otherwise the working tree). Catches credentials that already
#      got committed; complements the per-edit local-llm-secret-scan-hook.sh.
#   2. key-shape scan — signing material trufflehog cannot verify: ASP.NET Data
#      Protection key rings, PEM / OpenSSH private keys, .pfx / .p12. Matched by name
#      and content over every blob in git history plus untracked-not-ignored files
#      (the working tree outside git). Needs only git, grep and awk. Prints paths
#      and metadata, never key bytes. Encrypted-at-rest keys are NOTEs; harmless
#      fixtures go in .secret-shapes-allow as "<path-glob>  # <reason>" (spec 023).
#   3. npm audit  — dependency vulnerability report for every package.json this
#      project actually owns. A manifest is skipped when its path is vendored/
#      build output (node_modules, dist, build, bin, obj, .claude/worktrees) or
#      when `git check-ignore` says the repo ignores it — a dead agent worktree,
#      a Stryker sandbox and a .next/ directory are all full copies of the app
#      whose CVEs are not this project's. Skips are printed, never silent, and
#      every package is labelled by its path relative to the project root so two
#      manifests sharing a basename stay distinguishable. Outside a git repo the
#      ignore filter is inert and only the path exclusions apply.
#   4. osv-scanner — one pass over the lockfiles npm audit cannot read: NuGet
#      packages.lock.json, Dart pubspec.lock, pnpm/yarn lockfiles. Never self-
#      installed (it is optional); when absent the pass prints one [skip] line
#      with the install command for this OS and the SUMMARY repeats it.
#   5. dotnet list package --vulnerable --include-transitive — when the project
#      has a .sln/.slnx/.csproj and dotnet is on PATH. NuGetAudit already warns
#      at restore; this is the explicit report, per solution.
#   6. dependency coverage — every Maven/Gradle/Cargo/Go/Python/Ruby/PHP/Elixir/Dart
#      manifest the project owns, one line each: [OK] when osv-scanner gave a verdict
#      and reads a file for it (the manifest or its lockfile), else [SKIP] … no auditor:
#      <why>. An unchecked manifest is NOT SCANNED in the RESULT, never clean (spec 070).
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
#   bash scripts/project-freshness.sh --secrets   # only the secret passes (trufflehog + key-shape scan)
#   bash scripts/project-freshness.sh --deps      # only the dependency passes (npm audit, osv-scanner, dotnet, coverage)
#   bash scripts/project-freshness.sh --no-install # never self-install trufflehog; skip + hint if absent
#
# Test seams: FRESHNESS_TRUFFLEHOG, FRESHNESS_OSV_SCANNER and FRESHNESS_DOTNET name the
# binaries to run (default: trufflehog / osv-scanner / dotnet on PATH; a seam-named
# trufflehog is never self-installed). The self-test points them at stubs so it
# neither touches the network nor depends on what this machine has installed.
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

TRUFFLEHOG_BIN="${FRESHNESS_TRUFFLEHOG:-trufflehog}"

# ---- trufflehog self-installer (best-effort, cross-platform) ----------------
# Returns 0 if trufflehog is on PATH afterward, non-zero otherwise. Never aborts
# the caller — the secret-scan block falls back to a skip + install hint on failure.
ensure_trufflehog() {
  command -v "$TRUFFLEHOG_BIN" >/dev/null 2>&1 && return 0
  [ "$NO_INSTALL" -eq 1 ] && return 1
  # A seam-named binary that is missing stays missing: never install over a test stub.
  [ -n "${FRESHNESS_TRUFFLEHOG:-}" ] && return 1
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
  command -v "$TRUFFLEHOG_BIN" >/dev/null 2>&1
}

# ---- locate the project root ------------------------------------------------
if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git rev-parse --show-toplevel)"
  IS_GIT_REPO=1
else
  ROOT="$PWD"
  IS_GIT_REPO=0
fi
cd "$ROOT" || { echo "[ERROR] cannot cd to $ROOT" >&2; exit 2; }

FINDINGS=0
# Per-section verdicts for the bottom-line SUMMARY recap. On a noisy project the
# npm audit table buries everything above it, so `... | tail` would miss the
# secret verdict entirely — these one-liners guarantee both land at the bottom.
SECRETS_STATUS="not run (--deps)"
DEPS_STATUS="not run (--secrets)"
OSV_STATUS="not run (--secrets)"
DOTNET_STATUS="not run (--secrets)"
KEYS_STATUS="not run (--deps)"
OTHER_STATUS="not run (--secrets)"
# Did osv-scanner give a verdict (exit 0/1)? Pass 6 counts a manifest as covered only then.
OSV_VERDICT="no"
OSV_WHY="osv-scanner not run"
NOT_SCANNED=""   # secret passes that did not run to completion; the RESULT line must not call them clean
OSV_BIN="${FRESHNESS_OSV_SCANNER:-osv-scanner}"
DOTNET_BIN="${FRESHNESS_DOTNET:-dotnet}"

echo "=========================================================="
echo " project-freshness — $ROOT"
echo "=========================================================="

# ---- 1. trufflehog: verified secret scan ------------------------------------
if [ "$DO_SECRETS" -eq 1 ]; then
  echo
  echo "── [1/6] trufflehog secret scan ──────────────────────────"
  ensure_trufflehog
  if command -v "$TRUFFLEHOG_BIN" >/dev/null 2>&1; then
    # --only-verified:        live-checked credentials only (kills the false-positive
    #                         noise that makes a report nobody reads).
    # --no-update:            do not phone home for a self-update on every run.
    # --fail:                 exit 183 when results are found.
    # --fail-on-scan-errors:  exit non-zero when the scan errors part-way; without it an
    #                         error exits 0 and would read as clean.
    # Only 183 is a finding. trufflehog exits 1 when it cannot scan at all (a repo with no
    # commits: "failed to read index file"), and any code we do not recognise is the same
    # third state: not clean, not a finding (spec 038).
    TH_ERR=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/freshness-th.$$")
    if [ -d .git ]; then
      # git history scan: naturally skips gitignored node_modules/build output.
      TH_WHERE="git history"
      "$TRUFFLEHOG_BIN" git "file://$ROOT" --only-verified --no-update --fail --fail-on-scan-errors 2>"$TH_ERR"
    else
      TH_WHERE="working tree"
      "$TRUFFLEHOG_BIN" filesystem "$ROOT" --only-verified --no-update --fail --fail-on-scan-errors 2>"$TH_ERR"
    fi
    TH_RC=$?
    cat "$TH_ERR" >&2
    case "$TH_RC" in
      0)
        # Verified means provider-checkable: an API token a provider will answer for. A key
        # ring, a .pfx or a private key answers to no provider, so this line vouches for none
        # of them — the key-shape pass below does.
        echo "[OK] No verified credentials in $TH_WHERE (provider-checkable tokens only; key files: next pass)."
        SECRETS_STATUS="no verified credentials"
        ;;
      183)
        echo "[FINDING] trufflehog found verified secret(s) above. Rotate them NOW —"
        echo "          a committed credential is compromised the moment it is pushed."
        FINDINGS=1
        SECRETS_STATUS="VERIFIED SECRET(S) FOUND — rotate now"
        ;;
      *)
        # trufflehog logs `<time>\terror\ttrufflehog\t<msg>\t{"error": "<why>"}`; the why is
        # the reason. Anything else (an old version's "unknown flag") is shown as it came.
        TH_REASON=$(grep -i 'error' "$TH_ERR" | head -1)
        [ -n "$TH_REASON" ] || TH_REASON=$(grep -v '^[[:space:]]*$' "$TH_ERR" | tail -1)
        TH_WHY=$(printf '%s' "$TH_REASON" | sed -n 's/.*"errors*": *\[*"\([^"]*\)".*/\1/p')
        [ -n "$TH_WHY" ] && TH_REASON=$TH_WHY
        TH_REASON=$(printf '%s' "$TH_REASON" | tr -d '\r' | cut -c1-200)
        echo "[WARN] trufflehog could not scan (exit $TH_RC) — $TH_WHERE was NOT scanned. This is not a finding and not clean."
        [ -n "$TH_REASON" ] && echo "       trufflehog said: $TH_REASON"
        if [ "$TH_WHERE" = "git history" ] && ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
          echo "       This repo has no commits yet, so there is no history to scan. Re-run after the first commit."
        fi
        SECRETS_STATUS="scan failed (exit $TH_RC)${TH_REASON:+ — $TH_REASON}"
        NOT_SCANNED="$NOT_SCANNED trufflehog"
        ;;
    esac
    rm -f "$TH_ERR"
  else
    SECRETS_STATUS="skipped (trufflehog unavailable)"
    NOT_SCANNED="$NOT_SCANNED trufflehog"
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

# ---- 2. key-shape scan: signing material trufflehog cannot verify ------------
# trufflehog --only-verified keeps what a provider will answer for. An ASP.NET Data
# Protection key ring, a .pfx and a private key answer to no provider, so a clean
# trufflehog run says nothing about them — and two projects shipped a cookie-signing
# key in history under exactly that clean run (spec 023). This pass matches key
# material by SHAPE: a key-shaped name, or a key body in the content. It needs only
# git, grep, tr and awk, so it runs whether or not trufflehog is installed.
#
# It never prints a byte of a key: path, label, where it lives, commit and date only.
# A report gets pasted into chats and PR comments; it must not become the leak.
#
# Verdicts: FINDING (usable key material, exit 1), NOTE (encrypted at rest, or not
# inspectable), ALLOWED (matched by a reasoned line in .secret-shapes-allow).
#
# Cost is flat in the number of candidates: every candidate blob goes through ONE
# `git cat-file --batch` into ONE awk. Forking per candidate took 158 s on 2000
# certificates. There is no size gate: the classifier streams and buffers only the
# lines around a marker, so padding a key past a limit cannot turn it into a NOTE.

# A key-shaped name. Name candidates are still classified by content — a .pem that
# holds only a certificate is public and yields nothing.
KEY_BASENAME_RE='(key-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.xml|[^/]*\.(pem|key|pfx|p12|ppk)|id_(rsa|dsa|ecdsa|ed25519))$'
KEY_NAME_RE="(^|/)$KEY_BASENAME_RE"
# Content markers. LS0tLS1CRUdJTi is base64 of "-----BEGIN" (a Kubernetes Secret, a CI
# variable); the classifier decides which of those are private keys and which are certs.
KEY_CONTENT_RE='BEGIN [A-Z0-9 ]*PRIVATE KEY|<masterKey|PuTTY-User-Key-File-|LS0tLS1CRUdJTi'

# The classifier reads `git cat-file --batch` format — "<id> <type> <size>\n<content>\n"
# per object, with NUL bytes turned into \001 upstream so byte counting survives BWK awk —
# and prints "<VERDICT>\t<label>\t<id>". VERDICT is FINDING or NOTE; BIN marks a non-empty
# binary object with no key text, NOTBLOB and MISSING say what the object was. POSIX awk
# only (BWK on macOS, gawk on Git Bash, mawk on Debian): no interval expressions, no
# gensub, no IGNORECASE, no ENDFILE. A key body is counted in tokens of 40+ base64
# characters, so a marker in a test or in prose never adds up to a key.
KEY_CLASSIFIER_AWK='
function verdict(v, l) {
  if (V == "FINDING") return
  if (v == "FINDING" || V == "") { V = v; L = l }
}
function tokens(s, min,    n, i, t, total) {
  n = split(s, t, /[^A-Za-z0-9+\/=]+/)
  total = 0
  for (i = 1; i <= n; i++) if (length(t[i]) >= min) total += length(t[i])
  return total
}
# JSON, C# and PHP string escapes: \n, \r, \/, + (+), / (/), = (=).
function norm(s) {
  gsub(/\\u002[Bb]/, "+", s); gsub(/\\u002[Ff]/, "/", s); gsub(/\\u003[Dd]/, "=", s)
  gsub(/\\\//, "/", s); gsub(/\\r/, "", s); gsub(/\\n/, "\n", s); gsub(/\r/, "", s)
  return s
}
# The text after a BEGIN marker: up to its END marker, or else the contiguous base64 run.
function segment(rest,    seg, e) {
  seg = substr(rest, 1, 16384)
  e = index(seg, "-----END")
  if (e > 0) return substr(seg, 1, e - 1)
  match(seg, /^[A-Za-z0-9+\/= \t\n]*/)
  return substr(seg, 1, RLENGTH)
}
function pem_type(t) {
  if (t == "RSA" || t == "EC" || t == "DSA") return t
  return (t == "") ? "PKCS#8" : "other"
}
function classify(    i, rest, type, pgp, seg, enc, b, nm, tok) {
  buf = norm(buf)
  i = index(buf, "<masterKey")
  if (i > 0) {
    rest = substr(buf, i)
    # The encrypted form carries no key bytes to measure, so it must look like a key ring
    # (<key id=…>), or prose that mentions both element names would read as one.
    if (index(rest, "<encryptedSecret") > 0 && index(buf, "<key id=") > 0)
      verdict("NOTE", "ASP.NET Data Protection key (encrypted at rest)")
    else if (match(rest, /<value>[^<]*<\/value>/) && tokens(substr(rest, RSTART + 7, RLENGTH - 15), 40) >= 40)
      verdict("FINDING", "ASP.NET Data Protection key (plaintext master key)")
  }
  rest = buf; nm = 0
  while (V != "FINDING" && nm < 64 && match(rest, /-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----/)) {
    nm++
    type = substr(rest, RSTART + 11, RLENGTH - 11)
    rest = substr(rest, RSTART + RLENGTH)
    pgp = (type ~ /^PGP PRIVATE KEY BLOCK/)
    sub(/ ?PRIVATE KEY( BLOCK)?-----$/, "", type)
    seg = segment(rest)
    # 60: an Ed25519 PKCS#8 body is 64 characters, the smallest real key there is.
    if (tokens(seg, 40) < 60) continue
    enc = (type == "ENCRYPTED") || seg ~ /(^|\n)[ \t]*Proc-Type:[ \t]*4,ENCRYPTED/ || index(seg, "DEK-Info:") > 0
    if (pgp) verdict("FINDING", "PGP private key block")
    else if (enc) verdict("NOTE", "PEM private key (passphrase-encrypted)")
    else if (type == "OPENSSH") {
      b = seg; gsub(/[^A-Za-z0-9+\/=]/, "", b)
      # base64 of "openssh-key-v1\0" + cipher "none": the unencrypted form.
      if (substr(b, 1, 31) == "b3BlbnNzaC1rZXktdjEAAAAABG5vbmU")
        verdict("FINDING", "OpenSSH private key (no passphrase)")
      else
        verdict("NOTE", "OpenSSH private key (passphrase-encrypted)")
    }
    else verdict("FINDING", "PEM private key (" pem_type(type) ")")
  }
  i = index(buf, "PuTTY-User-Key-File-")
  if (i > 0) {
    rest = substr(buf, i, 16384)
    if (rest ~ /Private-Lines:[ \t]*[0-9]/) {
      if (rest ~ /Encryption:[ \t]*none/) verdict("FINDING", "PuTTY private key (no passphrase)")
      else verdict("NOTE", "PuTTY private key (passphrase-encrypted)")
    }
  }
  # Base64 of a whole PEM file. The prefixes are base64 of "-----BEGIN <T> PRIVATE KEY-----"
  # cut to whole 3-byte groups, so they hold wherever the PEM starts the encoded string.
  rest = buf; nm = 0
  while (V != "FINDING" && nm < 64 && match(rest, /LS0tLS1CRUdJTi[A-Za-z0-9+\/=]+/)) {
    nm++
    tok = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    if (length(tok) < 150) continue
    if (index(tok, "LS0tLS1CRUdJTiBFTkNSWVBURUQgUFJJVkFURSBLRVktLS0t") == 1)
      verdict("NOTE", "base64-encoded PEM private key (passphrase-encrypted)")
    else if (index(tok, "LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0t") == 1 \
          || index(tok, "LS0tLS1CRUdJTiBFQyBQUklWQVRFIEtFWS0tLS0t") == 1 \
          || index(tok, "LS0tLS1CRUdJTiBEU0EgUFJJVkFURSBLRVktLS0t") == 1 \
          || index(tok, "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0t") == 1 \
          || index(tok, "LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0t") == 1)
      verdict("FINDING", "base64-encoded PEM private key")
  }
}
function finish() {
  if (skip) print "NOTBLOB\t\t" id
  else {
    if (nbuf > 0) classify()
    if (V != "") print V "\t" L "\t" id
    else if (bin) print "BIN\t\t" id
  }
  buf = ""; nbuf = 0; V = ""; L = ""; bin = 0; cap = 0
}
rem <= 0 {
  n = split($0, h, " ")
  id = h[1]
  if (n < 3) { print "MISSING\t\t" id; next }
  skip = (h[2] != "blob"); rem = h[3] + 1
  if (rem == 1) { getline; rem = 0; finish() }
  next
}
{
  rem -= length($0) + 1
  if (!skip) {
    if (index($0, "\001") > 0) bin = 1
    # Buffer only the neighbourhood of a marker, and at most 64 KiB of it per object:
    # memory and time stay bounded whatever the object size.
    if (index($0, "PRIVATE KEY") || index($0, "<masterKey") || index($0, "<key id=") \
        || index($0, "PuTTY-User-Key-File-") || index($0, "LS0tLS1CRUdJTi")) cap = 200
    if (cap > 0 && length(buf) < 65536) { buf = buf $0 "\n"; nbuf++; cap-- }
  }
  if (rem <= 0) finish()
}'

# .secret-shapes-allow → "$KS_TMP/allow" as "<glob>\t<reason>". A line with no reason is
# ignored and named: an exemption that does not say why is not one.
load_key_allow() {
  : > "$KS_TMP/allow"
  [ -f "$ROOT/.secret-shapes-allow" ] || return 0
  ka_n=0
  while IFS= read -r ka_line || [ -n "$ka_line" ]; do
    ka_n=$((ka_n + 1))
    ka_trim=$(printf '%s' "$ka_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$ka_trim" in ''|'#'*) continue ;; esac
    ka_glob=""; ka_reason=""
    case "$ka_trim" in
      *'#'*) ka_glob=$(printf '%s' "${ka_trim%%#*}" | sed 's/[[:space:]]*$//')
             ka_reason=$(printf '%s' "${ka_trim#*#}" | sed 's/^[[:space:]]*//') ;;
    esac
    if [ -z "$ka_glob" ] || [ -z "$ka_reason" ]; then
      echo "  [WARN] .secret-shapes-allow:$ka_n has no '# reason' — ignored. An exemption says why."
      continue
    fi
    printf '%s\t%s\n' "$ka_glob" "$ka_reason" >> "$KS_TMP/allow"
  done < "$ROOT/.secret-shapes-allow"
}

# $1 path · stdout: the reason of the first matching allow line, or nothing.
key_allow_reason() {
  while IFS="	" read -r kr_glob kr_reason; do
    # The glob is the project's own pattern, deliberately unquoted: case matching, never eval.
    # shellcheck disable=SC2254
    case "$1" in $kr_glob) printf '%s\n' "$kr_reason"; return ;; esac
  done < "$KS_TMP/allow"
}

# Paths and reasons come from the scanned repo. A control character in one (CR, ESC[2K)
# could rewrite the [FINDING] line on the reader's terminal, so it prints as '?'.
ks_clean() { printf '%s' "$1" | LC_ALL=C tr '\001-\037\177' '?'; }

# $1 label · $2 command…: run it, and record a failure in KS_ERR instead of reading it as clean.
ks_git() {
  ks_label="$1"; shift
  if ! "$@" 2>"$KS_TMP/err"; then
    KS_ERR="${KS_ERR:+$KS_ERR; }$ks_label failed: $(head -1 "$KS_TMP/err" | LC_ALL=C tr -d '\000-\037')"
  fi
}

key_shape_scan() {
  KS_TMP=$(mktemp -d 2>/dev/null) || { KS_TMP="${TMPDIR:-/tmp}/freshness-keys.$$"; mkdir -m 700 "$KS_TMP" 2>/dev/null; } || {
    echo "[WARN] key-shape scan not run — no private temp directory."
    KEYS_STATUS="NOT RUN — no temp dir"; NOT_SCANNED="$NOT_SCANNED key-shape"; return; }
  trap 'rm -rf "$KS_TMP"' EXIT
  trap 'rm -rf "$KS_TMP"; exit 130' INT TERM
  KS_ERR=""
  # Internal files are "<field>\t…\t<path>": the path is always LAST, so a tab inside a
  # path cannot shift a verdict into the wrong column. A path holding a newline is not
  # supported (git's -z output is turned into lines).
  : > "$KS_TMP/cand"; : > "$KS_TMP/staged"; : > "$KS_TMP/tracked"; : > "$KS_TMP/untracked"
  : > "$KS_TMP/head"; : > "$KS_TMP/objs"
  if [ "$IS_GIT_REPO" -eq 1 ]; then
    if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
      KS_ERR="shallow clone: history before the graft is not scanned (git fetch --unshallow)"
    fi
    # Every blob reachable from any ref, as "sha path" (split on the FIRST space: paths
    # hold spaces). rev-list names each blob ONCE, under the first path it met; the raw log
    # adds every path a blob ever had.
    ks_git "git rev-list" git rev-list --all --objects > "$KS_TMP/objs"
    ks_git "git log --raw" git log --all --raw -z --no-abbrev --no-renames --format= > "$KS_TMP/raw"
    tr '\000' '\n' < "$KS_TMP/raw" | LC_ALL=C awk '
      /^:/ { split($0, m, " "); sha = m[4]; if (sha ~ /^0+$/) sha = m[3]; next }
      sha != "" && $0 != "" { print sha " " $0; sha = "" }' >> "$KS_TMP/objs"
    sort -u "$KS_TMP/objs" -o "$KS_TMP/objs"
    grep -iE "^[0-9a-f]+ (.*/)?$KEY_BASENAME_RE" "$KS_TMP/objs" \
      | LC_ALL=C awk '{ i = index($0, " "); print substr($0, 1, i - 1) "\t" substr($0, i + 1) }' >> "$KS_TMP/cand"
    # Content candidates: every path whose history ever added or removed a marker. A repo
    # whose .gitattributes switches diffs off (-diff, binary, a textconv driver) would hide
    # its files from -G, so there the pickaxe diffs as text — slower, and only where needed.
    ks_text=""
    if git grep -qE '(^|[[:space:]])(-diff|binary|diff=)' HEAD -- .gitattributes '*/.gitattributes' 2>/dev/null; then
      ks_text="--text"
    fi
    ks_git "git log -G" git log --all -z -E $ks_text --no-textconv -G "$KEY_CONTENT_RE" --format= --name-only > "$KS_TMP/pick"
    tr '\000' '\n' < "$KS_TMP/pick" | grep -v '^$' | sort -u > "$KS_TMP/pickpaths"
    LC_ALL=C awk 'NR == FNR { want[$0] = 1; next }
                  { i = index($0, " "); if (i && (substr($0, i + 1) in want)) print substr($0, 1, i - 1) "\t" substr($0, i + 1) }' \
      "$KS_TMP/pickpaths" "$KS_TMP/objs" >> "$KS_TMP/cand"
    # Staged, not committed: reachable from no ref and not "untracked" — the moment just
    # before the leak. Every staged blob is a candidate; the classifier decides.
    ks_git "git diff --cached" git diff --cached --raw -z --no-abbrev --no-renames --diff-filter=AM > "$KS_TMP/idx"
    tr '\000' '\n' < "$KS_TMP/idx" | LC_ALL=C awk '
      /^:/ { split($0, m, " "); sha = m[4]; next }
      sha != "" && $0 != "" { print sha "\t" $0; sha = "" }' > "$KS_TMP/staged"
    cat "$KS_TMP/staged" >> "$KS_TMP/cand"
    # A flagged blob is flagged at EVERY path it ever had: a key renamed or copied is found
    # at its new name too, even though the pickaxe listed only the old one.
    LC_ALL=C awk -F '\t' 'NR == FNR { want[$1] = 1; next }
                  { i = index($0, " "); s = substr($0, 1, i - 1); if (s in want) print s "\t" substr($0, i + 1) }' \
      "$KS_TMP/cand" "$KS_TMP/objs" >> "$KS_TMP/cand"
    if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
      ks_git "git ls-tree" git ls-tree -r -z --full-tree HEAD > "$KS_TMP/tree"
      tr '\000' '\n' < "$KS_TMP/tree" | LC_ALL=C awk '{ i = index($0, "\t"); split(substr($0, 1, i - 1), m, " "); print m[3] "\t" substr($0, i + 1) }' > "$KS_TMP/head"
    fi
    ks_git "git ls-files" git ls-files -z > "$KS_TMP/lsf"
    tr '\000' '\n' < "$KS_TMP/lsf" > "$KS_TMP/tracked"
    ks_git "git ls-files --others" git ls-files -z --others --exclude-standard > "$KS_TMP/lso"
    tr '\000' '\n' < "$KS_TMP/lso" > "$KS_TMP/untracked"
  else
    # Relative to ROOT, so a project that itself lives under a build/ or bin/ directory
    # is not excluded wholesale by the structural filters.
    ( cd "$ROOT" && find . -type f -not -path './.git/*' -not -path '*/node_modules/*' \
        -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/dist/*' -not -path '*/build/*' \
        -not -path '*/.claude/worktrees/*' 2>/dev/null ) | sed 's|^\./||' > "$KS_TMP/untracked"
  fi
  # Working-tree files (untracked-not-ignored, or everything outside git): name OR content.
  # One grep over the list, not one per file; "--" keeps a file named "-q" a file.
  { grep -iE "$KEY_NAME_RE" "$KS_TMP/untracked"
    tr '\n' '\000' < "$KS_TMP/untracked" | LC_ALL=C xargs -0 grep -lIE "$KEY_CONTENT_RE" -- 2>/dev/null
  } | sort -u | while IFS= read -r f; do
    [ -f "./$f" ] && printf -- '-\t%s\n' "$f"
  done >> "$KS_TMP/cand"
  sort -u "$KS_TMP/cand" -o "$KS_TMP/cand"

  # One classifier pass. Blobs: one `git cat-file --batch`. Working-tree files: the same
  # format, synthesised with id "f<N>" (each copied first, so its size cannot change under
  # us). NUL → \001 keeps byte counts intact through awk.
  cut -f1 "$KS_TMP/cand" | grep -v '^-$' | sort -u > "$KS_TMP/shas"
  : > "$KS_TMP/fmap"
  {
    if [ -s "$KS_TMP/shas" ]; then
      ks_git "git cat-file --batch" git cat-file --batch < "$KS_TMP/shas"
    fi
    ks_n=0
    grep '^-	' "$KS_TMP/cand" | cut -f2- | while IFS= read -r f; do
      ks_n=$((ks_n + 1))
      printf 'f%s\t%s\n' "$ks_n" "$f" >> "$KS_TMP/fmap"
      if cat "./$f" > "$KS_TMP/cur" 2>/dev/null; then
        printf 'f%s blob %s\n' "$ks_n" "$(wc -c < "$KS_TMP/cur" | tr -d ' ')"
        cat "$KS_TMP/cur"; printf '\n'
      else
        printf 'f%s missing\n' "$ks_n"
      fi
    done
  } | LC_ALL=C tr '\000' '\001' | LC_ALL=C awk "$KEY_CLASSIFIER_AWK" > "$KS_TMP/verdicts"

  # Join per candidate → "<verdict>\t<label>\t<sha or ->\t<path>". A .pfx/.p12 is decided
  # by name, but only for a blob (a DIRECTORY named x.pfx is not a key); a key-named file
  # that is not text is a NOTE (DER cannot be read as PEM).
  LC_ALL=C awk -F '\t' '
    FILENAME == ARGV[1] { v[$3] = $1; l[$3] = $2; next }
    FILENAME == ARGV[2] { i = index($0, "\t"); fid[substr($0, i + 1)] = substr($0, 1, i - 1); next }
    {
      i = index($0, "\t"); s = substr($0, 1, i - 1); path = substr($0, i + 1)
      k = (s == "-") ? fid[path] : s
      p = tolower(path)
      if (v[k] == "NOTBLOB") next
      if (v[k] == "MISSING") print "NOTE\tnot inspected (object missing — shallow or partial clone?)\t" s "\t" path
      else if (p ~ /\.(pfx|p12)$/) print "FINDING\tPKCS#12 bundle (certificate + private key)\t" s "\t" path
      else if (v[k] == "FINDING" || v[k] == "NOTE") print v[k] "\t" l[k] "\t" s "\t" path
      else if (v[k] == "BIN" && p ~ /(\.(key|pem|ppk)|(^|\/)id_(rsa|dsa|ecdsa|ed25519))$/)
        print "NOTE\tbinary key-named file, not PEM (DER?) — inspect by hand\t" s "\t" path
    }' "$KS_TMP/verdicts" "$KS_TMP/fmap" "$KS_TMP/cand" > "$KS_TMP/hits"

  # Where each hit lives, decided per BLOB: a key pasted into appsettings.json and later
  # scrubbed is not "at HEAD" just because appsettings.json is. Rank 0 = a live copy.
  # The "added" lookup walks history, so it is done for the first 20 history hits only.
  : > "$KS_TMP/located"   # verdict \t rank \t label \t where \t path
  ks_lookups=0
  while IFS= read -r line; do
    v=${line%%	*}; line=${line#*	}
    label=${line%%	*}; line=${line#*	}
    sha=${line%%	*}; path=${line#*	}
    if [ "$sha" = "-" ]; then
      if [ "$IS_GIT_REPO" -eq 1 ]; then where="untracked (not ignored)"; else where="working tree"; fi; rank=0
    elif grep -qxF -- "$sha	$path" "$KS_TMP/staged"; then where="staged, not committed"; rank=0
    elif grep -qxF -- "$sha	$path" "$KS_TMP/head"; then where="at HEAD"; rank=0
    else
      added=""
      if [ "$ks_lookups" -lt 20 ]; then
        ks_lookups=$((ks_lookups + 1))
        added=$(git log --all --find-object="$sha" --format='%h %ad' --date=short 2>/dev/null | tail -1)
      fi
      if grep -qxF -- "$path" "$KS_TMP/tracked"; then
        where="history only (the path is tracked; this content is not at HEAD${added:+; added $added})"
      else
        where="history only (untracked at HEAD${added:+; added $added})"
      fi
      rank=1
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$v" "$rank" "$label" "$where" "$path" >> "$KS_TMP/located"
  done < "$KS_TMP/hits"
  # One line per path: FINDING sorts before NOTE, a live copy before history.
  LC_ALL=C sort -t "	" -k5 -k1,1 -k2,2n "$KS_TMP/located" \
    | LC_ALL=C awk '{ r = $0; for (n = 0; n < 4; n++) r = substr(r, index(r, "\t") + 1)
                      if (r != last) print; last = r }' > "$KS_TMP/worst"

  load_key_allow
  KF=0; KN=0; KA=0; KDP=0
  while IFS= read -r line; do
    v=${line%%	*}; line=${line#*	}
    line=${line#*	}                      # rank
    label=${line%%	*}; line=${line#*	}
    where=${line%%	*}; path=${line#*	}
    reason=$(key_allow_reason "$path")
    shown=$(ks_clean "$path")
    if [ -n "$reason" ]; then
      echo "  [ALLOWED] $shown — $label — $where — $(ks_clean "$reason")"; KA=$((KA + 1))
    elif [ "$v" = "FINDING" ]; then
      echo "  [FINDING] $shown — $label — $where"; KF=$((KF + 1))
      case "$label" in *"Data Protection"*) KDP=1 ;; esac
    else
      echo "  [NOTE] $shown — $label — $where"; KN=$((KN + 1))
    fi
  done < "$KS_TMP/worst"
  rm -rf "$KS_TMP"
  trap - EXIT INT TERM

  ks_tail=""
  [ "$KN" -gt 0 ] && ks_tail="$ks_tail, $KN note(s)"
  [ "$KA" -gt 0 ] && ks_tail="$ks_tail, $KA allowed"
  if [ "$KF" -gt 0 ]; then
    FINDINGS=1
    echo "[FINDING] $KF file(s) of key material above. Rotate each key NOW: whoever has read"
    echo "          access to this history can sign as you. Untracking does not un-leak a key,"
    echo "          and a history purge (git filter-repo) is optional and only after rotation."
    if [ "$KDP" -eq 1 ]; then
      echo "          Data Protection: delete the key ring, let the app mint a new one, and keep the"
      echo "          ring outside the repo (gitignored dir or mounted volume). Every cookie it signed dies."
    fi
    echo "          A harmless fixture? Add '<path-glob>  # <why>' to .secret-shapes-allow."
    KEYS_STATUS="$KF KEY FILE(S) FOUND — rotate now$ks_tail"
  elif [ -z "$KS_ERR" ]; then
    if [ "$IS_GIT_REPO" -eq 1 ]; then
      echo "[OK] No key material in git history, the index or the untracked working tree$ks_tail."
    else
      echo "[OK] No key material in the working tree$ks_tail."
    fi
    KEYS_STATUS="clean$ks_tail"
  fi
  if [ -n "$KS_ERR" ]; then
    # Not scanned is not clean: the SUMMARY and the RESULT line both say so.
    echo "[WARN] key-shape scan incomplete — $KS_ERR."
    NOT_SCANNED="$NOT_SCANNED key-shape"
    if [ "$KF" -gt 0 ]; then KEYS_STATUS="$KEYS_STATUS (scan INCOMPLETE)"
    else KEYS_STATUS="INCOMPLETE — $KS_ERR$ks_tail"; fi
  fi
}

if [ "$DO_SECRETS" -eq 1 ]; then
  echo
  echo "── [2/6] key-shape scan (signing material) ───────────────"
  key_shape_scan
fi

# ---- 3. npm audit: dependency vulnerability report --------------------------
if [ "$DO_DEPS" -eq 1 ]; then
  echo
  echo "── [3/6] npm audit (dependency CVEs) ─────────────────────"
  # Scan every package.json that is not vendored/build output.
  PKG_FOUND=0
  DEPS_VULN=0; DEPS_CLEAN=0; DEPS_SKIPPED=0; DEPS_IGNORED=0; DEPS_SUMMARY=""
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    dir="$(dirname "$pkg")"
    # Label every line by the path relative to $ROOT, never by basename. Two manifests
    # can share a basename — `apps/web` and `packages/web`, or the live app and a copy
    # of it — and a summary that calls both "web/" tells the reader which one is on fire
    # exactly never. The banner at the top already establishes $ROOT, so the absolute
    # prefix bought nothing. A manifest at the root itself relativises to "." → "./".
    rel="${pkg#$ROOT/}"
    rel_dir="$(dirname "$rel")"
    # A gitignored manifest is not part of this project's dependency surface: it is a dead
    # agent worktree, a Stryker sandbox, a Next.js build output, a nested unrelated checkout.
    # Auditing it reports another repository's CVEs under this one's name. The secrets half of
    # this script already gets this right for free — it scans git history, and its own comment
    # says so — so the two halves of this script disagreed about what the repository is. This
    # is the deps half asking the same authority.
    #
    # It fails open by construction: `check-ignore` exits non-zero for an untracked-but-not-
    # ignored file (so a project with nothing committed yet is still audited) and for a
    # non-git ROOT (so the filter is simply inert there). Non-zero means "keep", which is the
    # safe direction for a security-adjacent scan. The stderr is discarded because outside a
    # repo git prints a fatal that has no business in this report.
    #
    # The path exclusions in the `find` below stay: they need no git at all, which is what
    # covers the non-git case that this filter cannot.
    if [ "$IS_GIT_REPO" -eq 1 ] && git check-ignore -q "$pkg" 2>/dev/null; then
      echo
      echo "  [SKIP] $rel — gitignored, so not this project's dependency surface"
      echo "         (agent worktree? Stryker sandbox? build output? nested checkout?)."
      echo "         Audit it by hand if you disagree: cd \"$dir\" && npm audit"
      DEPS_IGNORED=$((DEPS_IGNORED + 1))
      continue
    fi
    PKG_FOUND=1
    echo
    echo "  package: $rel"
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
      # A workspaces MEMBER has no lockfile of its own BY DESIGN. The root holds one
      # lockfile and one node_modules for the whole tree, and `npm audit` at that root
      # already covers every member — so this is not an unscanned package, it is the
      # same package counted twice.
      #
      # The advice this used to print was not merely noise, it was harmful: `npm install`
      # inside a member creates a nested lockfile and breaks the hoisting the workspace
      # depends on. Measured on fundit, whose src/web is a correct npm-workspaces root
      # with eight members — the pass reported eight SKIPs and a RESULT of "findings need
      # attention" on a tree it had fully audited.
      ws_root=""
      ws_dir="$dir"
      while [ "$ws_dir" != "/" ] && [ "$ws_dir" != "." ] && [ -n "$ws_dir" ]; do
        ws_dir="$(dirname "$ws_dir")"
        case "$ws_dir" in "$ROOT"|"$ROOT"/*) ;; *) break ;; esac
        if [ -f "$ws_dir/package.json" ] \
           && { [ -f "$ws_dir/package-lock.json" ] || [ -f "$ws_dir/npm-shrinkwrap.json" ]; } \
           && grep -qE '"workspaces"[[:space:]]*:' "$ws_dir/package.json" 2>/dev/null; then
          ws_root="$ws_dir"
          break
        fi
      done

      if [ -n "$ws_root" ]; then
        echo "  [OK] npm workspaces member — covered by the audit of ${ws_root#"$ROOT"/}."
        continue
      fi

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
      echo "  [OK] No advisories for $rel."
      DEPS_CLEAN=1
    else
      echo "  [FINDING] Vulnerabilities reported for $rel (see table above)."
      FINDINGS=1
      DEPS_VULN=1
      # Scrape npm's own summary line ("N vulnerabilities (a low, b moderate, …)").
      VSUM=$(printf '%s\n' "$AUDIT_OUT" | grep -i 'vulnerabilit' | tail -1 | sed 's/^[[:space:]]*//')
      [ -n "$VSUM" ] || VSUM="advisories found"
      DEPS_SUMMARY="$DEPS_SUMMARY $rel_dir/: $VSUM;"
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
    -not -path '*/.claude/worktrees/*' \
    2>/dev/null)
EOF
  if [ "$PKG_FOUND" -eq 0 ] && [ "$DEPS_IGNORED" -eq 0 ]; then
    echo "  [SKIP] No package.json found — not a Node/JS project. (yarn/pnpm projects: run 'yarn npm audit' / 'pnpm audit' manually.)"
  fi
  # Roll the per-package outcomes up into one verdict for the SUMMARY recap.
  #
  # "No package.json" and "every package.json was gitignored" are different facts and must
  # not share a sentence: the first says this is not a Node project, the second says the walk
  # found manifests and deliberately declined all of them. A reader who sees the first when
  # the second is true concludes the scan covered everything it could. It didn't.
  #
  # And when some were audited and some skipped, the bottom line still accounts for the
  # skipped ones — the SUMMARY is the only line a busy developer reads, so a filter that is
  # loud in the body and silent here is silent.
  DEPS_IGNORED_NOTE=""
  [ "$DEPS_IGNORED" -gt 0 ] && DEPS_IGNORED_NOTE=" (+$DEPS_IGNORED gitignored, skipped)"
  if [ "$PKG_FOUND" -eq 0 ] && [ "$DEPS_IGNORED" -gt 0 ]; then
    DEPS_STATUS="no auditable package.json — all $DEPS_IGNORED found were gitignored (see skips above)"
  elif [ "$PKG_FOUND" -eq 0 ]; then
    DEPS_STATUS="no package.json (not a Node project)"
  elif [ "$DEPS_VULN" -eq 1 ]; then
    DEPS_STATUS="advisories —$DEPS_SUMMARY$DEPS_IGNORED_NOTE"
  elif [ "$DEPS_CLEAN" -eq 1 ]; then
    DEPS_STATUS="clean$DEPS_IGNORED_NOTE"
  else
    DEPS_STATUS="skipped (no lockfile / non-npm — see notes above)$DEPS_IGNORED_NOTE"
  fi
fi

# ---- 4. osv-scanner: every lockfile npm audit cannot read ------------------
if [ "$DO_DEPS" -eq 1 ]; then
  echo
  echo "── [4/6] osv-scanner (NuGet / pub / npm lockfiles) ───────"
  if command -v "$OSV_BIN" >/dev/null 2>&1; then
    # `scan source -r` walks the tree and honours .gitignore, so the dead worktrees
    # and Stryker sandboxes the npm walk declines are declined here too.
    "$OSV_BIN" scan source -r "$ROOT"; OSV_RC=$?
    case "$OSV_RC" in
      0)   echo "[OK] osv-scanner: no known vulnerabilities in any lockfile."
           OSV_VERDICT="yes"; OSV_STATUS="clean" ;;
      1)   echo "[FINDING] osv-scanner reported vulnerabilities (table above)."
           FINDINGS=1; OSV_VERDICT="yes"
           OSV_STATUS="vulnerabilities found — see table above" ;;
      128) # Documented as "no packages found": nothing to scan is not a clean scan.
           echo "[SKIP] osv-scanner found no lockfiles to scan."
           OSV_STATUS="no lockfiles found" ;;
      *)   # A scanner that errored has vouched for nothing. Say so, but do not turn
           # a tool failure into a vulnerability finding.
           echo "[WARN] osv-scanner exited $OSV_RC (an error, not a finding) — nothing was verified."
           OSV_STATUS="ERROR (exit $OSV_RC) — lockfiles unscanned" ;;
    esac
    [ "$OSV_VERDICT" = "yes" ] || OSV_WHY="osv-scanner gave no verdict (exit $OSV_RC)"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin) OSV_HINT="brew install osv-scanner" ;;
      Linux)  OSV_HINT="brew install osv-scanner | pacman -S osv-scanner | go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest | binary: github.com/google/osv-scanner/releases" ;;
      MINGW*|MSYS*|CYGWIN*) OSV_HINT="scoop install osv-scanner | winget install Google.OSVScanner" ;;
      *)      OSV_HINT="see https://google.github.io/osv-scanner/installation/" ;;
    esac
    # Fail open, but loud: optional tooling must not block the pass, and "not scanned"
    # must never read like "no findings". The SUMMARY repeats it for the same reason.
    echo "[skip] osv-scanner not installed — NuGet/pub/Maven/Gradle/Cargo/Go/pip lockfiles unscanned; install: $OSV_HINT"
    OSV_STATUS="SKIPPED — osv-scanner not installed (lockfiles unscanned; per-manifest list in pass 6)"
    OSV_WHY="osv-scanner not installed (install: $OSV_HINT)"
  fi
fi

# ---- 5. dotnet list package --vulnerable ------------------------------------
if [ "$DO_DEPS" -eq 1 ]; then
  echo
  echo "── [5/6] dotnet vulnerable packages (incl. transitive) ───"
  # Target solutions first: one `dotnet list` over a solution covers all its projects,
  # and listing each .csproj as well would report every package twice. Loose project
  # files become targets only when there is no solution at all. Same path exclusions
  # and gitignore oracle as the npm walk above.
  DOTNET_TARGETS=""
  for pattern in '*.sln' '*.slnx' '*.csproj'; do
    [ "$pattern" = '*.csproj' ] && [ -n "$DOTNET_TARGETS" ] && break
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$IS_GIT_REPO" -eq 1 ] && git check-ignore -q "$f" 2>/dev/null; then continue; fi
      DOTNET_TARGETS="$DOTNET_TARGETS
$f"
    done <<LIST
$(find "$ROOT" -name "$pattern" \
    -not -path '*/node_modules/*' -not -path '*/bin/*' -not -path '*/obj/*' \
    -not -path '*/.claude/worktrees/*' 2>/dev/null)
LIST
  done

  if [ -z "$DOTNET_TARGETS" ]; then
    echo "  [SKIP] No .sln/.slnx/.csproj found — not a .NET project."
    DOTNET_STATUS="no .NET project"
  elif ! command -v "$DOTNET_BIN" >/dev/null 2>&1; then
    echo "  [SKIP] .NET project found but dotnet is not installed — NuGet packages unscanned here."
    DOTNET_STATUS="SKIPPED — dotnet not installed"
  else
    DN_VULN=0; DN_CLEAN=0; DN_UNSCANNED=0; DN_SUMMARY=""
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      rel="${t#$ROOT/}"
      echo
      echo "  target: $rel"
      DN_OUT=$("$DOTNET_BIN" list "$t" package --vulnerable --include-transitive 2>&1); DN_RC=$?
      printf '%s\n' "$DN_OUT"
      # dotnet exits 0 whether or not it found anything, so the verdict comes from the
      # text. An unrestored project (non-zero exit, or "No assets file") was not
      # scanned, and must not be counted as clean.
      if [ "$DN_RC" -ne 0 ] || grep -qi 'no assets file' <<< "$DN_OUT"; then
        echo "  [SKIP] could not list packages for $rel — run 'dotnet restore' first."
        DN_UNSCANNED=$((DN_UNSCANNED + 1))
      elif grep -qi 'has the following vulnerable packages' <<< "$DN_OUT"; then
        echo "  [FINDING] vulnerable NuGet packages in $rel (see above)."
        echo "  [NEXT] dotnet package update --vulnerable   (.NET 10 SDK) — review the diff, then build + test."
        FINDINGS=1; DN_VULN=1; DN_SUMMARY="$DN_SUMMARY $rel;"
      else
        echo "  [OK] no vulnerable packages in $rel."
        DN_CLEAN=1
      fi
    done <<LIST
$DOTNET_TARGETS
LIST
    DN_NOTE=""
    [ "$DN_UNSCANNED" -gt 0 ] && DN_NOTE=" (+$DN_UNSCANNED unscanned — restore first)"
    if [ "$DN_VULN" -eq 1 ]; then
      DOTNET_STATUS="vulnerable packages —$DN_SUMMARY$DN_NOTE"
    elif [ "$DN_CLEAN" -eq 1 ]; then
      DOTNET_STATUS="clean$DN_NOTE"
    else
      DOTNET_STATUS="unscanned — restore first$DN_NOTE"
    fi
  fi
fi

# ---- 6. dependency coverage: no manifest is silently unchecked --------------
# Passes 3 and 5 print a line per package.json / .NET target. Every other ecosystem is
# left to osv-scanner, which reports one exit code for the whole tree and cannot say which
# manifests it read. ekofak's Maven backend was never audited and the report read as
# complete (spec 070). This pass lists each such manifest and says whether anything
# checked it. Covered means osv-scanner gave a verdict AND reads a file for it: the
# manifest itself, or its lockfile in the manifest's directory or an ancestor up to $ROOT
# (Cargo / uv / Gradle workspaces keep one lock at the root). The file names follow
# osv-scanner's documented supported-files list.
if [ "$DO_DEPS" -eq 1 ]; then
  echo
  echo "── [6/6] dependency coverage (non-npm, non-.NET manifests) ─"
  # First file in $2… found in $1 or an ancestor up to $ROOT, relative to $ROOT; empty if none.
  lock_for() {
    lf_dir=$1; shift
    while :; do
      for lf_name in "$@"; do
        [ -f "$lf_dir/$lf_name" ] && { lf_path="$lf_dir/$lf_name"; printf '%s' "${lf_path#"$ROOT"/}"; return 0; }
      done
      [ "$lf_dir" = "$ROOT" ] && return 1
      case "$lf_dir" in "$ROOT"/*) lf_dir=$(dirname "$lf_dir") ;; *) return 1 ;; esac
    done
  }
  COV_TOTAL=0; COV_OK=0; COV_UNCHECKED=""
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    if [ "$IS_GIT_REPO" -eq 1 ] && git check-ignore -q "$m" 2>/dev/null; then continue; fi
    mdir=$(dirname "$m")
    rel="${m#"$ROOT"/}"
    [ "$mdir" = "$ROOT" ] && rel="./$rel"
    COV_TOTAL=$((COV_TOTAL + 1))
    lock=""
    # sabotage:lockfile-rule:start
    case "$(basename "$m")" in
      pom.xml|go.mod|requirements.txt)
        lock="${m#"$ROOT"/}"; lock_hint="" ;;
      build.gradle|build.gradle.kts)
        lock=$(lock_for "$mdir" gradle.lockfile gradle/verification-metadata.xml)
        lock_hint="enable dependency locking, then ./gradlew dependencies --write-locks" ;;
      Cargo.toml)   lock=$(lock_for "$mdir" Cargo.lock);    lock_hint="cargo generate-lockfile" ;;
      pyproject.toml)
        lock=$(lock_for "$mdir" poetry.lock uv.lock pdm.lock pylock.toml)
        lock_hint="poetry lock | uv lock | pdm lock" ;;
      Pipfile)      lock=$(lock_for "$mdir" Pipfile.lock);  lock_hint="pipenv lock" ;;
      Gemfile)      lock=$(lock_for "$mdir" Gemfile.lock gems.locked); lock_hint="bundle lock" ;;
      composer.json) lock=$(lock_for "$mdir" composer.lock); lock_hint="composer update --lock" ;;
      mix.exs)      lock=$(lock_for "$mdir" mix.lock);      lock_hint="mix deps.get" ;;
      pubspec.yaml) lock=$(lock_for "$mdir" pubspec.lock);  lock_hint="dart pub get" ;;
    esac
    # sabotage:lockfile-rule:end
    if [ "$OSV_VERDICT" != "yes" ]; then
      echo "  [SKIP] $rel — no auditor: $OSV_WHY"
    elif [ -z "$lock" ]; then
      echo "  [SKIP] $rel — no auditor: no lockfile osv-scanner reads (run: $lock_hint)"
    else
      echo "  [OK] $rel — osv-scanner ($lock)"
      COV_OK=$((COV_OK + 1))
      continue
    fi
    COV_UNCHECKED="$COV_UNCHECKED${COV_UNCHECKED:+; }$rel"
  done <<LIST
$(find "$ROOT" \( -name pom.xml -o -name build.gradle -o -name build.gradle.kts -o -name Cargo.toml \
      -o -name go.mod -o -name pyproject.toml -o -name requirements.txt -o -name Pipfile \
      -o -name Gemfile -o -name composer.json -o -name mix.exs -o -name pubspec.yaml \) \
    -not -path '*/node_modules/*' -not -path '*/bin/*' -not -path '*/obj/*' \
    -not -path '*/.claude/worktrees/*' -not -path '*/target/*' -not -path '*/build/*' \
    -not -path '*/.gradle/*' -not -path '*/vendor/*' -not -path '*/.venv/*' -not -path '*/venv/*' \
    -not -path '*/_build/*' -not -path '*/deps/*' -not -path '*/.dart_tool/*' -not -path '*/.git/*' \
    2>/dev/null | sort)
LIST
  if [ "$COV_TOTAL" -eq 0 ]; then
    echo "  [OK] no Maven/Gradle/Cargo/Go/Python/Ruby/PHP/Elixir/Dart manifests found."
    OTHER_STATUS="none found"
  elif [ -z "$COV_UNCHECKED" ]; then
    OTHER_STATUS="all $COV_TOTAL covered by osv-scanner"
  else
    OTHER_STATUS="$((COV_TOTAL - COV_OK)) of $COV_TOTAL UNCHECKED — $COV_UNCHECKED"
    # sabotage:not-scanned-join:start
    NOT_SCANNED="$NOT_SCANNED deps($COV_UNCHECKED)"
    # sabotage:not-scanned-join:end
  fi
fi

# ---- summary ----------------------------------------------------------------
echo
echo "=========================================================="
echo " SUMMARY  Secrets: $SECRETS_STATUS"
echo "          Keys:    $KEYS_STATUS"
echo "          npm:     $DEPS_STATUS"
echo "          OSV:     $OSV_STATUS"
echo "          .NET:    $DOTNET_STATUS"
echo "          Other:   $OTHER_STATUS"
if [ "$FINDINGS" -eq 0 ] && [ -n "$NOT_SCANNED" ]; then
  echo " RESULT: no findings, but NOT SCANNED:$NOT_SCANNED — see above. That is not clean."
  exit 0
elif [ "$FINDINGS" -eq 0 ]; then
  echo " RESULT: clean (no verified credentials, no committed key material, no reported advisories)."
  exit 0
else
  echo " RESULT: findings above need attention. Nothing was committed."
  [ -n "$NOT_SCANNED" ] && echo "         Also NOT SCANNED:$NOT_SCANNED — findings there are unknown, not absent."
  echo "         Secrets / keys → rotate. npm → review then 'npm audit fix [--force]'."
  echo "         NuGet → 'dotnet package update --vulnerable'. OSV → upgrade per its table."
  exit 1
fi
