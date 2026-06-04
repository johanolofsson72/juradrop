# Research: Native Window Smoke (spec 037)

## R1 — Launching an external app from XCUITest

**Decision**: `XCUIApplication(bundleIdentifier: "se.noisycricket.juradrop")` after the runner registers the freshly-built bundle with `lsregister -f <path>`; `launchEnvironment` carries the seam URL (it applies regardless of init method).

**Rationale**: a UI-testing bundle's default target-application mechanism wants an app built by the same project; bundle-id launch is the standard technique for driving a foreign app. Registration pins WHICH copy launches (stale registered copies are the classic foot-gun — `lsregister -f` on the exact path each run removes the ambiguity).

**Alternatives**: installing to /Applications each run — slower, pollutes the user's system; `XCUIApplication()` with a host-app trampoline — cannot target a foreign binary.

## R2 — Why a dummy host app target exists

**Decision**: `HarnessHost`, a do-nothing stub app target the UI-testing bundle nominally targets; tests ignore it and drive JuraDrop by bundle id.

**Rationale**: Xcode's ui-testing product type requires a runnable test host; a 10-line stub satisfies the toolchain without entangling JuraDrop's own build. Hand-written pbxproj stays minimal (two targets, one scheme).

## R3 — Hermeticity vs the hardcoded adoption probe

**Decision**: mock on an EPHEMERAL port + `JURADROP_OLLAMA_URL` seam; do NOT bind 11434.

**Rationale**: manager.rs's spec-026 adoption probe is hardcoded to `127.0.0.1:11434`. Binding the mock there would collide with a developer's real Ollama (this machine may run one) and would test an artificial adoption. With the seam: (a) real Ollama on 11434 → app adopts it, client still talks to the mock — hermetic; (b) port free → bundled sidecar spawns as in production, client talks to the mock — hermetic. Both branches are REAL app behavior; inference is canned in both.

**Alternatives**: mock on 11434 — port conflict + masks the spawn path; no mock + real model — slow, non-hermetic, violates FR-004.

## R4 — Mock server implementation

**Decision**: `scripts/mock-ollama.py`, Python 3 stdlib `http.server`, ephemeral port printed to stdout. Endpoints: `GET /api/tags` → `{"models":[{"name":"gemma3:4b"}]}`; `POST /api/generate` → `{"model":"gemma3:4b","response":"<canned>","done":true}` (client sends `stream:false`, parses one JSON object — same shape the wiremock tests use).

**Rationale**: zero dependencies, synchronous stdlib handler is plenty for ≤ a handful of requests, trivially auditable. Node would also work but python3's http.server is the smallest honest tool.

## R5 — Driving the native open panel

**Decision**: activate the zone's `Välj fil` button via its accessible label, wait for the open panel (sheet/dialog), use `Cmd+Shift+G` (Go to Folder), type the absolute temp path of the fixture, Return to accept the path, then Return/"Öppna" to confirm the selection.

**Rationale**: path-typing through Go-to-Folder is the robust, locale-tolerant way to drive NSOpenPanel under automation (element-by-element sidebar navigation is brittle). The panel may be an out-of-process remote view; XCUITest resolves it within the target app's element tree in the common non-sandboxed case (Tauri apps are not sandboxed by default) — if not, querying the `open and save panel service` process is the documented fallback (probe will tell).

## R6 — Canonical Swedish titles into Swift without retyping

**Decision**: the runner exports the twelve titles to a temp JSON via `node -e` from the canonical TS identity source (`ZONE_IDENTITIES`/`ZONE_ORDER`) and passes the file path in `launchEnvironment`-adjacent test env (`ZONE_TITLES_JSON`); the Swift test decodes and asserts. FR-012 satisfied with zero string duplication and zero new build steps.

**Alternatives**: hardcoding Swedish in Swift — drift the moment a title is humanizer-tweaked; generating a Swift file — build-step complexity for the same result.

## R7 — Permission preflight

**Decision**: `osascript -e 'tell application "System Events" to count processes'` as the preflight; non-zero exit → print the exact instruction ("System Settings → Privacy & Security → Accessibility/Automation: enable Terminal (or the invoking host) and Xcode Helper") and exit 2. First `xcodebuild test` run may still raise the one-time OS consent dialog — quickstart documents clicking Allow.

**Rationale**: the osascript probe fails in precisely the unauthorized case, cheap and deterministic; FR-007 wants words, not timeouts.

## R8 — Build staleness

**Decision**: rebuild when `JuraDrop.app` is missing OR any file under `src/` / `src-tauri/src` / `src-tauri/tauri.conf.json` is newer than the bundle binary; `--build` forces. Build command: `npm run tauri build -- --debug --target aarch64-apple-darwin`.

**Rationale**: tauri has no incremental "is the bundle current" query; mtime is the honest cheap proxy. Debug target keeps the seam (`#[cfg(debug_assertions)]`).

## R9 — App state on this machine

**Decision**: accept the existing app-support state (consent/settings persist across runs); the harness only requires "model present" (mock /api/tags) → ready-state zones regardless of stored consent (consent gates the PULL, which never happens). The runner does NOT touch `~/Library/Application Support/se.noisycricket.juradrop` — mutating a developer's real app state would be hostile.

**Risk accepted**: a pre-existing settings tier other than Smart changes the model id the client requests — the mock answers any model name identically, so assertions hold.

## R10 — The probe is the gate (FR-009)

**Decision**: test 00 (`test00_probeAccessibilityExposure`) launches, waits for the window, logs `app.debugDescription`, and asserts at minimum the window exists; the implementing agent inspects the dump for web-content elements (zone titles/buttons). Outcome `web_content_reachable` → proceed to full scope; `chrome_only_fallback` → stop, amend spec + register honestly (per the allium rule `ProbeWebContentExposure`), ship the reduced scope.
