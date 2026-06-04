#!/usr/bin/env bash
# Spec 037 — native window smoke runner (contract A).
#
# One command: build-if-stale → mock → launch app with the hermetic seam →
# XCUITest (attach mode) → report → clean up. LOCAL-ONLY by register
# amendment: this script is deliberately absent from every default gate
# and from CI (github-actions budget rule).
#
# EMPIRICAL NOTE (probe phase): XCUITest's launchEnvironment does not
# propagate through XCUIApplication(bundleIdentifier:).launch(), so THIS
# SCRIPT launches the app binary directly with JURADROP_OLLAMA_URL set
# (verified working) and the suite attaches (JURADROP_SMOKE_ATTACH=1).
#
# Exit codes: 0 green · 1 suite red · 2 preflight failure (actionable).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/src-tauri/target/aarch64-apple-darwin/debug/bundle/macos/JuraDrop.app"
APP_BIN="$APP_BUNDLE/Contents/MacOS/juradrop"
PROJECT="$REPO_ROOT/ui-tests/JuraDropUITests.xcodeproj"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

FORCE_BUILD=0
ONLY_TESTING=""
for arg in "$@"; do
  case "$arg" in
    --build) FORCE_BUILD=1 ;;
    --probe-only) ONLY_TESTING="-only-testing:JuraDropUITests/NativeWindowSmokeTests/test00_probeAccessibilityExposure" ;;
    *) echo "usage: $0 [--build] [--probe-only]" >&2; exit 2 ;;
  esac
done

MOCK_PID=""
APP_PID=""
WORKDIR=""

SEAM_SET=""

cleanup() {
  # H-8 / TerminalIsCleaned — runs on EVERY exit path.
  [ -n "$SEAM_SET" ] && rm -f /tmp/juradrop-ollama-url-override 2>/dev/null || true
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
  pkill -x juradrop 2>/dev/null || true
  [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true
  pkill -f "mock-ollama.py" 2>/dev/null || true
  [ -n "$WORKDIR" ] && rm -rf "$WORKDIR" || true
}
trap cleanup EXIT

fail2() { echo "PREFLIGHT: $*" >&2; exit 2; }

# ── Preflight (FR-006/FR-007) ────────────────────────────────────────────
command -v xcodebuild >/dev/null || fail2 "xcodebuild not found — install Xcode."
command -v node >/dev/null || fail2 "node not found — needed to export the canonical zone titles."
command -v python3 >/dev/null || fail2 "python3 not found — needed for the mock endpoint."

# R7 — automation/accessibility permission probe. Words, not timeouts.
if ! osascript -e 'tell application "System Events" to count processes' >/dev/null 2>&1; then
  fail2 "macOS automation permission missing. Open System Settings → Privacy & Security → Accessibility (and Automation) and enable your terminal app + Xcode Helper, then rerun. The first xcodebuild run may also show an Allow dialog — click Allow."
fi

# Stray instances from interrupted runs poison attach mode — clear them.
pkill -x juradrop 2>/dev/null || true
pkill -f "mock-ollama.py" 2>/dev/null || true

# ── Build-if-stale (R8) ──────────────────────────────────────────────────
needs_build=$FORCE_BUILD
if [ ! -x "$APP_BIN" ]; then
  needs_build=1
elif [ -n "$(find "$REPO_ROOT/src" "$REPO_ROOT/src-tauri/src" "$REPO_ROOT/src-tauri/tauri.conf.json" -newer "$APP_BIN" -print -quit 2>/dev/null)" ]; then
  needs_build=1
fi
if [ "$needs_build" = "1" ]; then
  echo "▸ building debug .app (this takes a while)…"
  # tauri.conf.json enables createUpdaterArtifacts, so the build ALWAYS
  # ends with an updater-signing step that fails locally (no private
  # key) AFTER the .app is fully bundled. Judge by the artifact, not the
  # exit code: build, then verify the bundle exists and is fresh.
  (cd "$REPO_ROOT" && npm run tauri build -- --debug --target aarch64-apple-darwin --bundles app) || true
  [ -x "$APP_BIN" ] || fail2 "tauri debug build produced no app binary — see output above."
  if [ -n "$(find "$REPO_ROOT/src" "$REPO_ROOT/src-tauri/src" "$REPO_ROOT/src-tauri/tauri.conf.json" -newer "$APP_BIN" -print -quit 2>/dev/null)" ]; then
    fail2 "build finished but $APP_BIN is still older than the sources — the compile itself failed; see output above."
  fi
fi

# Sanity: the harness REQUIRES the debug seam (Hermetic invariant).
# (grep reads process substitution, not a pipe — grep -q's early exit
# would otherwise SIGPIPE strings and trip pipefail on a MATCH.)
grep -q "JURADROP_OLLAMA_URL" <(strings "$APP_BIN") \
  || fail2 "the built binary lacks the debug seam — was it built with --debug?"

# ── Canonical titles export (R6 / FR-012) ────────────────────────────────
WORKDIR="$(mktemp -d)"
TITLES_JSON="$WORKDIR/zone-titles.json"
(cd "$REPO_ROOT" && node --experimental-strip-types --input-type=module -e \
  "import('./src/components/DropZone.identity.ts').then(m => process.stdout.write(JSON.stringify(m.ZONE_ORDER.map(id => m.ZONE_IDENTITIES[id].title))))" \
  2>/dev/null) > "$TITLES_JSON"
[ -s "$TITLES_JSON" ] || fail2 "zone title export produced nothing — node --experimental-strip-types failed?"

# ── Fixture workspace ────────────────────────────────────────────────────
FIXTURE_DIR="$WORKDIR/fixtures"
mkdir -p "$FIXTURE_DIR"
printf 'Avtalet förlängs med tolv månader om ingen part säger upp det senast tre månader i förväg.\n' \
  > "$FIXTURE_DIR/dokument.txt"

# ── Mock endpoint (FR-004) ───────────────────────────────────────────────
python3 "$REPO_ROOT/scripts/mock-ollama.py" > "$WORKDIR/mock.out" 2> "$WORKDIR/mock.log" &
MOCK_PID=$!
disown "$MOCK_PID"   # silence job-control noise when the trap kills it
for _ in $(seq 1 20); do
  [ -s "$WORKDIR/mock.out" ] && break
  sleep 0.2
done
MOCK_PORT="$(awk '/^PORT/ {print $2}' "$WORKDIR/mock.out")"
[ -n "$MOCK_PORT" ] || fail2 "mock endpoint failed to start — see $WORKDIR/mock.log"
echo "▸ mock endpoint on 127.0.0.1:$MOCK_PORT"

# ── Seam injection (the empirical fix, final round) ──────────────────────
# Env-based injection fails on EVERY macOS launch path available here:
# (1) launchEnvironment does not survive XCUITest's bundle-id launch;
# (2) externally-started instances are invisible to testmanagerd binding;
# (3) launchctl setenv is ignored by testmanagerd's spawn (cached env).
# The seam therefore gained a debug-only FILE channel (client.rs, spec
# 037): the runner writes the mock URL here; cleanup removes it. Release
# builds never read the file (seam_privacy_invariant.rs pins the gate).
"$LSREGISTER" -f "$APP_BUNDLE" || true
SEAM_FILE="/tmp/juradrop-ollama-url-override"
printf 'http://127.0.0.1:%s\n' "$MOCK_PORT" > "$SEAM_FILE"
SEAM_SET=1
echo "▸ seam written to $SEAM_FILE"

# ── The suite ────────────────────────────────────────────────────────────
echo "▸ running XCUITest suite…"
set +e
# shellcheck disable=SC2086
TEST_RUNNER_JURADROP_OLLAMA_URL="http://127.0.0.1:$MOCK_PORT" \
TEST_RUNNER_JURADROP_APP_BUNDLE="$APP_BUNDLE" \
TEST_RUNNER_ZONE_TITLES_JSON="$TITLES_JSON" \
TEST_RUNNER_JURADROP_SMOKE_FIXTURE_DIR="$FIXTURE_DIR" \
xcodebuild test \
  -project "$PROJECT" \
  -scheme JuraDropUITests \
  -destination 'platform=macOS' \
  $ONLY_TESTING 2>&1 | tee "$WORKDIR/xcodebuild.log" \
  | grep -E "Test Case .* (started|passed|failed)|TEST .* (FAILED|SUCCEEDED)|error:"
RESULT=${PIPESTATUS[0]}
set -e

if [ "$RESULT" -eq 0 ]; then
  # Hermeticity tripwire (FR-004, learned the hard way): a green suite
  # whose mock never served a generation means a REAL Ollama answered —
  # the seam silently failed. Refuse to report green.
  if [ -z "$ONLY_TESTING" ] && ! grep -q "POST /api/generate" "$WORKDIR/mock.log"; then
    echo "▸ HERMETICITY VIOLATION: suite green but the mock served no generation — a real Ollama likely answered. Failing." >&2
    exit 1
  fi
  echo "▸ native smoke GREEN (hermetic: mock served the generation)"
else
  echo "▸ native smoke RED (xcodebuild exit $RESULT) — full log was at $WORKDIR/xcodebuild.log (removed on exit; rerun with tee elsewhere to keep)"
fi
exit "$RESULT"
