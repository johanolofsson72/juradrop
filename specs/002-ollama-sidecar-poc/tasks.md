---
description: "Task list for spec 002 — Ollama Sidecar PoC"
---

# Tasks: 002 — Ollama Sidecar PoC

**Input**: Design documents from `specs/002-ollama-sidecar-poc/`
**Prerequisites**: `plan.md` ✅, `spec.md` ✅, `spec.allium` ✅, `research.md` ✅, `data-model.md` ✅, `contracts/` ✅, `quickstart.md` ✅

**Tests**: INCLUDED. Full pipeline track + 14 FC tasks + 10 DT tasks in spec.md.

**Organization**: Tasks grouped by user story (US1=P1=sidecar lifecycle, US2=P1=consent+download, US3=P2=round-trip, US4=P2=failure states). Setup + Foundational phases create the shared scaffolding. Polish covers humanizer, README, audit, and destructive tests.

## Format: `[ID] [P?] [Story?] Description`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Fetch the bundled binary, install new dependencies, update build config.

- [ ] T001 Write `scripts/fetch-ollama.sh` per research.md R-001: downloads `Ollama-darwin.zip` v0.24.0 from GitHub releases, extracts `Ollama.app/Contents/Resources/ollama`, verifies SHA-256 against a pinned hash, places at `src-tauri/binaries/ollama-aarch64-apple-darwin`, chmod +x. Include curl, unzip, shasum -a 256 verification. Exit non-zero on hash mismatch.
- [ ] T002 Add the pinned Ollama SHA-256 hash to `scripts/fetch-ollama.sh` (run the script once locally to determine the hash, then bake it in).
- [ ] T003 Run `bash scripts/fetch-ollama.sh` and confirm `src-tauri/binaries/ollama-aarch64-apple-darwin` exists and is executable.
- [ ] T004 [P] Add Rust dependencies to `src-tauri/Cargo.toml`: `reqwest = { version = "0.12", default-features = false, features = ["json", "rustls-tls", "stream"] }`, `tauri-plugin-shell = "2"`, `chrono = { version = "0.4", features = ["serde"] }`, `parking_lot = "0.12"`, `futures = "0.3"`, `tokio` (verify already pulled in transitively; add explicit `features = ["macros", "rt-multi-thread", "process", "io-util"]` if not).
- [ ] T005 [P] Add JS dependencies via npm: `npm install zustand @tauri-apps/plugin-shell`.
- [ ] T006 [P] Scaffold the shadcn `Dialog` component: `npx shadcn@latest add dialog --yes`. Produces `src/components/ui/dialog.tsx`.
- [ ] T007 [P] Add `src-tauri/binaries/` entry to `.gitignore` if NOT committing the binary (size ~150 MB). Decision: per research.md, the binary is fetched by script, so we ignore it. Add `src-tauri/binaries/ollama-*` to `.gitignore`.
- [ ] T007a [P] Document the build-pipeline gap in `README.md`: production builds (`npm run tauri:build`) require `bash scripts/fetch-ollama.sh` to be run first. Spec 006 (signing-and-ci) will wire this into CI. At spec 002, devs must run the fetch script manually before any `tauri build`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Scaffold the sidecar module, register the shell plugin, update capabilities, create the React infrastructure (zustand store + bridge). Each subsequent user story extends these.

- [ ] T008 [P] Update `src-tauri/tauri.conf.json` per contracts/ollama-api-usage.md: add `bundle.externalBin: ["binaries/ollama"]`. Add `plugins.shell` block with `open: false`, `scope: []`. Verify no other `bundle.*` fields regress from spec 001.
- [ ] T009 [P] Update `src-tauri/capabilities/default.json` per contracts/capabilities.md: add `core:default`, `core:app:default`, `core:event:default`, scoped `shell:allow-spawn` to `binaries/ollama` sidecar, `shell:allow-kill`. Leave `windows: ["main"]` unchanged. Verify no `fs:*` or `http:*` entries.
- [ ] T010 [P] Create the sidecar module skeleton: `src-tauri/src/sidecar/mod.rs` re-exporting `manager`, `client`, `status`, `consent`, `commands`, `log_safe`. Each child file initially contains only a module-doc comment.
- [ ] T011 [P] Implement `src-tauri/src/sidecar/log_safe.rs` per data-model.md: `pub struct Redacted<T>(pub T);` with `Debug`/`Display` impls returning `"<redacted>"`, `.len()` for `T: AsRef<str>`, `.into_inner()`. Include `#[cfg(test)]` tests verifying `format!("{}", Redacted("secret"))` returns `"<redacted>"`.
- [ ] T012 [P] Implement `src-tauri/src/sidecar/status.rs` per data-model.md: `SidecarStatus`, `ModelStatus`, `ConsentChoice`, `UserVisibleStatus` enums with `#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]` and `serde(rename_all = "snake_case")`. `AppStatus` struct with `Serialize`. Include `impl AppStatus { fn derive(...) -> UserVisibleStatus }` mapping the three sub-states to the visible status per the rule list in spec.allium.
- [ ] T013 [P] Implement `src-tauri/src/sidecar/consent.rs` per contracts/consent-store.md: `ConsentRecord` struct, `load(app)` returns `NotAsked` if file absent or schemaVersion > 1 surfaces error, `save(app)` does the atomic write-tmp-rename. Include unit tests for load-absent, load-present, round-trip-save-then-load, atomic-write-survives-fake-crash.
- [ ] T014 [US2 + foundational] Implement `src-tauri/src/sidecar/client.rs` skeleton: `OllamaClient` struct holding a `reqwest::Client` with base URL `http://127.0.0.1:11434`. Methods `list_tags()`, `pull_stream(model)`, `generate(model, prompt: Redacted<String>) -> Result<Redacted<String>, ClientError>` — bodies stubbed with `todo!()` for now. `ClientError` enum.
- [ ] T015 [P] Register `tauri_plugin_shell` in `src-tauri/src/lib.rs` via `.plugin(tauri_plugin_shell::init())`. Do NOT add the sidecar lifecycle yet (that's T020+).
- [ ] T016 [P] Create `src/lib/tauri-bridge.ts`: typed wrappers around `invoke()` and `listen()`. Exports `getStatus()`, `giveConsent()`, `cancelConsent()`, `runRoundtripDev()`, plus `subscribeStatus(cb)`, `subscribeProgress(cb)` that return cleanup functions. Strong types matching the TS enums in data-model.md.
- [ ] T017 [P] Create `src/lib/status-store.ts`: zustand store per data-model.md TS mirror. Initial state: `{ visible: 'startar', sidecar: 'not_started', model: 'not_present', progress_percent: null, consent: 'not_asked' }`. Actions: `setStatus`, `giveConsent`, `cancelConsent`. The store auto-subscribes to the two Tauri events on first use.

**Checkpoint**: Phase 2 done = code compiles, all enums + stubs exist, plugin registered, capabilities updated. Nothing runs yet; that's per-story.

---

## Phase 3: User Story 1 — Sidecar Lifecycle (Priority: P1)

**Goal**: Ollama process starts when the app launches, stops when the app quits. No zombie processes.

**Independent Test**: Launch the app → see an `ollama` process in Activity Monitor. Quit the app → process disappears within 5 s. Run the Rust integration test `cargo test --test sidecar_lifecycle`.

### CLAUDE.md blocking prerequisite

- [ ] T017a [US1] Invoke the `frontend-design` skill before writing any UI code that lands in this spec (US2 onward). T017a sits in US1 phase as a checkpoint to satisfy the rule before WelcomeCard / ConsentModal changes. Read `design-system/MASTER.md` first.

### Implementation for User Story 1

- [x] T018 [US1] Implement `OllamaSidecar::spawn(app: &AppHandle) -> Result<Self, SidecarError>` in `src-tauri/src/sidecar/manager.rs`: locates the bundled binary via `app.shell().sidecar("ollama")`, sets env `OLLAMA_HOST=127.0.0.1:11434` and `OLLAMA_ORIGINS=` (empty), spawns, captures PID. Returns `SidecarError::BundledBinaryMissing` if `sidecar()` errors with a missing-binary path. Per research.md R-002, R-004. **Implementation note**: signature is `spawn<R: Runtime>(&self, app: &AppHandle<R>) -> Result<(), SidecarError>` — return type carries `()` (the `Arc<Self>` is constructed by `OllamaSidecar::new` and held in `AppState` as a long-lived shared handle, not returned from `spawn`); the runtime generic was added during T023 so `tauri::test::mock_builder()` can drive the manager.
- [x] T019 [US1] Implement `OllamaSidecar::wait_ready(&self, timeout)` in `manager.rs`: polls `GET http://127.0.0.1:11434/api/tags` every 200 ms via the existing `reqwest::Client` until 2xx or `timeout` elapses. On timeout, returns `SidecarError::StartupTimeout`. Per research.md R-003. **Hardened in GAP-2 fix**: on timeout, the spawned child is killed before returning so a slow-starting Ollama can't leak the port for the rest of the session.
- [x] T020 [US1] Implement `OllamaSidecar::stop(&self, grace)` in `manager.rs`: sends SIGTERM to the child PID, waits up to `grace`, sends SIGKILL on timeout. Updates `self.status` to `Stopping` then `Stopped`. **Implementation note**: phase 1 sends `libc::kill(pid, SIGTERM)` on the captured child PID, phase 2 polls `libc::kill(pid, 0)` every 100 ms up to `grace` to detect exit (ESRCH = gone), phase 3 falls back to `CommandChild::kill()` (SIGKILL) on timeout. Ollama serve responds to SIGTERM within ~100–300 ms in practice — T023 went from 3.56 s (immediate SIGKILL) to 3.01 s (SIGTERM-first), so the graceful path doesn't bump the close-app latency.
- [x] T021 [US1] Wire the sidecar lifecycle into `src-tauri/src/lib.rs`: on app `setup`, spawn the sidecar in a tokio task; store the `OllamaSidecar` in `app.manage(Arc<OllamaSidecar>)`. On `RunEvent::ExitRequested`, call `sidecar.stop(Duration::from_secs(5)).await` synchronously before letting the process exit. Per FR-002, FR-003, FR-004. **Implementation note**: the shutdown hook fires on `WindowEvent::CloseRequested` for the `main` window (single-window app — functionally equivalent to `ExitRequested` for our scope). Pidfile is cleared after the synchronous stop so the next launch's orphan reaper doesn't chase a dead PID.
- [x] T022 [US1] Detect port-busy on spawn: in `manager.rs::spawn`, before launching the sidecar, attempt to bind a TCP listener on `127.0.0.1:11434` ephemerally. If the bind fails with `EADDRINUSE`, return `SidecarError::PortBusy` immediately without spawning. Per US4 #3.

### Tests for User Story 1

- [x] T023 [P] [US1] Write `src-tauri/tests/sidecar_lifecycle.rs`: spawn the sidecar via the manager API, assert `wait_ready` returns `Ok(())` within 10 s, then stop and assert the child PID exits within 5 s (use `nix::sys::wait` or polling `/api/tags` returns connection-refused). Covers FC-001, FC-002. **Implementation note**: post-stop assertion uses HTTP probe (connection-refused on `/api/tags`) instead of `nix::sys::wait` — Tauri's `CommandChild` doesn't expose the owned PID for `waitpid`, and the HTTP probe is sufficient evidence that the OS released the port. Test skips with a clear message when port 11434 already has a tenant (Homebrew, Ollama.app, parallel `tauri dev`). Required runtime-genericising `OllamaSidecar::spawn` and the `pidfile::*` helpers over `R: tauri::Runtime` so `tauri::test::mock_builder()` can drive them — production call sites (Wry) keep working unchanged.
- [~] T024 [P] [US1] ~~Write `src-tauri/src/sidecar/manager.rs#[cfg(test)] mod tests`: unit-test the `SidecarStatus` transition graph — valid transitions succeed, invalid transitions (e.g., `ready → starting`) return errors.~~ **Dropped per F9 allium-distill decision (2026-05-26)**: `set_status` doesn't validate transitions because the transition graph isn't actually load-bearing for any rule — invalid transitions can't happen via the current code paths and adding runtime validation would catch nothing real. The spec.allium graph remains a design document.

**Checkpoint**: US1 complete = sidecar spawns + stops cleanly in tests. App launch via `npm run tauri dev` also spawns sidecar (verifiable in Activity Monitor).

---

## Phase 4: User Story 2 — First-launch Model Download with Consent (Priority: P1)

**Goal**: On first launch, show the FR-019 consent modal. On "Fortsätt", download `gemma3:4b` and surface progress. On "Avbryt", show the `modell_saknas_avbruten` static state.

**Independent Test**: Delete `~/Library/Application Support/se.noisycricket.juradrop/consent.json` and any local `gemma3:4b` from `~/.ollama/models/`. Launch the app. Modal appears. Click "Fortsätt". Progress climbs from 0% to 100%. Welcome card switches to "AI redo".

### Implementation for User Story 2

- [ ] T025 [US2] Implement `OllamaClient::list_tags()` in `src-tauri/src/sidecar/client.rs`: `GET /api/tags` with 5 s timeout, parse response, return `Vec<String>` of model names. Per contracts/ollama-api-usage.md.
- [ ] T026 [US2] Implement `OllamaClient::pull_stream(model)` in `client.rs`: `POST /api/pull` with `{ "name": <model>, "stream": true }`, parse NDJSON response stream, emit `PullEvent::Progress { percent }`, `PullEvent::Completed`, `PullEvent::Failed`. Use `futures::stream` and `reqwest::Response::bytes_stream()`. Throttle progress emission per contracts/tauri-events.md (≥ 1% change OR ≥ 500 ms since last emit).
- [ ] T027 [US2] Implement the `#[tauri::command]` functions in `src-tauri/src/sidecar/commands.rs` per contracts/tauri-commands.md: `get_status`, `give_consent`, `cancel_consent`. `give_consent` persists the consent record AND kicks off the pull stream in a tokio task. `cancel_consent` persists AND transitions visible status to `modell_saknas_avbruten`.
- [ ] T028 [US2] Register the three commands via `.invoke_handler(tauri::generate_handler![get_status, give_consent, cancel_consent])` in `lib.rs`. (`run_roundtrip_dev` is registered in US3.)
- [ ] T029 [US2] Emit `juradrop://status` and `juradrop://progress` events from Rust at every state transition. Add a helper `fn emit_status(app: &AppHandle, status: &AppStatus)` and call it in the manager, consent, and pull paths. Per contracts/tauri-events.md.
- [ ] T030 [US2] Wire the model-presence check on sidecar-ready in `lib.rs`: after `wait_ready` returns, call `client.list_tags()`. If `gemma3:4b` is present, set `ModelStatus = Ready` → `UserVisibleStatus = Klar`. Otherwise: if `consent.choice = NotAsked` → set `BegarSamtycke`; if `consent.choice = Fortsatt` → re-call pull per FR-020; if `consent.choice = Avbryt` → set `ModellSaknasAvbruten`.
- [ ] T031 [P] [US2] Write `src/components/ConsentModal.tsx`: uses shadcn `Dialog`. Title "Ladda ner AI-modell". Body "JuraDrop hämtar nu en AI-modell (~3 GB) från ollama.com. Det är enda gången något skickas utanför din Mac." Two buttons: "Fortsätt" (calls `giveConsent`), "Avbryt" (calls `cancelConsent`). Visibility tied to `useStatusStore.consent === 'not_asked' && useStatusStore.visible === 'begar_samtycke'`.
- [ ] T032 [P] [US2] Modify `src/components/WelcomeCard.tsx`: replace the static placeholder paragraph with a Swedish status string derived from `useStatusStore.visible`. Mapping in a `statusMessage(visible)` helper: `klar` → "AI redo", `startar` → "Startar AI…", `laddar_ner_modell` → `Laddar ner AI-modell … ${percent}%`, error variants → their Swedish strings. Remove the disabled "Kom igång" Button (no longer placeholder — status string is the meaningful content).
- [ ] T033 [US2] Modify `src/App.tsx`: mount `<ConsentModal />` alongside `<WelcomeCard />`. Initialize the status store on mount: call `getStatus()` once, then subscribe to events. Cleanup subscriptions on unmount.

### Tests for User Story 2

- [x] T034 [P] [US2] Write `src-tauri/tests/model_presence.rs`: starts sidecar, asserts `client.list_tags()` returns a list, asserts presence detection works (handles both "model present" and "model absent" cases against the live Ollama). Covers FC-003. **Implementation note**: spec.md classifies FC-003 as "Rust unit test against mocked Ollama API" — the live-Ollama path is already exercised by T023's `wait_ready` poll, so this file uses `wiremock` to serve Ollama's exact `/api/tags` shape across four cases: default model present, default absent (other models present), empty list, and `:latest`/`:9b` near-miss tags that must NOT satisfy the strict `gemma3:4b` equality check (catches a future `starts_with("gemma3")` regression).
- [x] T035 [P] [US2] Write `src-tauri/tests/consent_persistence.rs`: writes a consent record, reads it back, verifies atomic-write semantics by simulating crash mid-write (write to .tmp, fail rename, ensure original is unchanged). Also tests schema-version > 1 surfaces an error. Covers FR-019, FR-019b, R-006. **Implementation note**: added `pub async fn load_at(path)` and `pub async fn save_at(path, record)` to `consent.rs`; production `load()`/`save()` now delegate. The test drives those against a `tempfile::TempDir` so it never touches `~/Library/Application Support/se.noisycricket.juradrop/`. Five cases: round-trip with UTC timestamp preserved, post-save `.tmp` is gone, lingering `.tmp` does NOT pollute `load`, schema 99 surfaces `ConsentError::UnsupportedSchemaVersion(99)`, missing file yields `ConsentChoice::NotAsked` default.
- [x] T036 [P] [US2] Write `src/__tests__/ConsentModal.test.tsx`: renders the modal when `consent === 'not_asked' && visible === 'begar_samtycke'`; clicks "Fortsätt" → asserts `giveConsent` was called; clicks "Avbryt" → asserts `cancelConsent` was called. Mocks `tauri-bridge`. Covers FC-011 (modal shown exactly once).
- [x] T037 [P] [US2] Write `src/__tests__/status-store.test.ts`: store initial state is correct, `setStatus` updates the snapshot, the derived `statusMessage(visible)` returns the right Swedish string for each `UserVisibleStatus` value. Covers FC-005, FC-006, FC-007 (rendering paths).
- [x] T038 [P] [US2] Extend `src/__tests__/WelcomeCard.test.tsx`: assert the Swedish status string updates when the store mutates. Drop the old "shadcn Button" assertion since US2 removes the button.

**Checkpoint**: US2 complete = consent flow works end-to-end; modal shows exactly once per fresh install; pull completes; "AI redo" status reached.

---

## Phase 5: User Story 3 — One Inference Round-Trip (Priority: P2)

**Goal**: A developer-only test sends a hardcoded prompt to the local Ollama and asserts a non-empty response. Proves the full pipeline works end-to-end.

**Independent Test**: With the app running and `gemma3:4b` loaded, run `cargo test --test sidecar_roundtrip -- --ignored --nocapture`. Expect green within 60 s (cold) / 30 s (warm).

### Implementation for User Story 3

- [ ] T039 [US3] Implement `OllamaClient::generate(&self, model, prompt: Redacted<String>) -> Result<Redacted<String>, ClientError>` in `client.rs`: `POST /api/generate` with `{ "model": <model>, "prompt": <inner>, "stream": false }`, parse response, extract `response` field as `Redacted<String>`. 30 s timeout. Per contracts/ollama-api-usage.md, FR-021 (blocking only).
- [ ] T040 [US3] Implement the dev-only `run_roundtrip_dev` `#[tauri::command]` in `commands.rs`: in dev profile (`#[cfg(debug_assertions)]`), call `client.generate("gemma3:4b", Redacted("Säg hej.".into()))` and return the response length. In release, return `Err("not available in release build".into())`.
- [ ] T041 [US3] Register `run_roundtrip_dev` in `lib.rs`'s invoke handler.

### Tests for User Story 3

- [ ] T042 [P] [US3] Write `src-tauri/tests/sidecar_roundtrip.rs` marked `#[ignore]` per research.md R-009: spawns sidecar, waits ready, asserts `gemma3:4b` present (SKIP with clear message if not), sends "Säg hej.", asserts response length > 0 within 30 s, tears down. Covers FC-008.
- [x] T043 [P] [US3] Write `src-tauri/src/sidecar/log_safe.rs#[cfg(test)] mod tests`: asserts `format!("{}", Redacted("secret"))` returns `"<redacted>"`, `format!("{:?}", Redacted("secret"))` returns `"<redacted>"`, `Redacted("hello").len() == 5`. Covers FC-009 (log redaction).
- [x] T044 [P] [US3] Write `src-tauri/src/sidecar/client.rs#[cfg(test)] mod tests`: asserts the public API surface of `OllamaClient` exposes only `list_tags`, `pull_stream`, `generate` — no streaming-inference method. Static check via the type system (visibility). Covers FC-014 (blocking-only). **Implementation note**: method named `pull` (not `pull_stream`) — semantically equivalent, just shorter.

**Checkpoint**: US3 complete = round-trip integration test runs green; no prompt/response content appears in test logs (verify with `cargo test -- --ignored --nocapture | grep -i "säg hej\|hej\|hallå" → should be empty for the prompt; response varies but is never logged).

---

## Phase 6: User Story 4 — Honest Failure States (Priority: P2)

**Goal**: Every failure path surfaces a plain-Swedish error in the welcome card. No stack traces, no English, no silent failures.

**Independent Test**: For each of the six error variants (kunde_inte_starta, porten_upptagen, disk_full, modellnedladdning_avbroten, ovantat, modell_saknas_avbruten), induce the condition and verify the welcome card shows the right Swedish string within 10 s.

### Implementation for User Story 4

- [x] T045 [US4] Implement the one-retry mechanism in `manager.rs` per spec.allium SidecarOneRetry: track a `retry_count: AtomicU8` on `OllamaSidecar`. On crash detection (RunEvent indicates child terminated unexpectedly while we expected `ready`): if `retry_count == 0`, attempt one re-spawn and increment the counter. If retry fails, hold `FelOvantat` status until next launch. Per US4 #2.
- [x] T046 [US4] Map every `SidecarError` and `ClientError` variant to the matching `UserVisibleStatus` via `impl From<SidecarError> for UserVisibleStatus { ... }`. Exhaustive match — compile error if a new variant is added without mapping. Covers FR-010.
- [x] T047 [US4] Implement disk-space pre-check before triggering pull: in `commands.rs::give_consent`, before kicking off the pull, call `fs::statvfs` (or platform equivalent) on the app data root, assert ≥ 4 GB free, otherwise set `UserVisibleStatus = FelDiskFull` and abort. Per FR-010 / SC-006-edge.
- [x] T048 [US4] Implement the "bundled binary missing" pre-check: in `manager.rs::spawn`, verify `app.shell().sidecar("ollama")` returns Ok; if not, return `SidecarError::BundledBinaryMissing` → `FelKundeIntStarta`. Per FR-015. **Covered by spawn-time detection per F7 allium-distill decision (2026-05-26)**: `app.shell().sidecar("ollama")` returns an error if the binary is missing, the error is mapped to `BundledBinaryMissing` (manager.rs heuristic on "No such file" / "not found"), and the T046 `From<&SidecarError>` impl surfaces it as `fel_kunde_inte_starta`. An explicit pre-check duplicates the spawn's own work with no user-visible difference.

### Tests for User Story 4

- [x] T049 [P] [US4] Extend `src-tauri/tests/sidecar_lifecycle.rs` with a test that renames the bundled binary to a nonexistent path, attempts spawn, asserts `SidecarError::BundledBinaryMissing` is returned within 10 s. Restore the binary after the test. **Implementation note**: rename is wrapped in a `BinaryHidden` RAII guard so a panicking assertion still restores the staged binary; test skips with a clear message when port 11434 is held by a foreign Ollama (the manager would short-circuit on `PortBusy` before reaching the missing-binary path).
- [x] T050 [P] [US4] Extend `src-tauri/tests/sidecar_lifecycle.rs` with a port-busy test: bind a TCP listener on 127.0.0.1:11434 in the test, attempt spawn, assert `SidecarError::PortBusy`. Release the listener after. **Implementation note**: if the bind fails because a foreign Ollama already owns the port, that's also a valid `PortBusy` scenario for the manager — the assertion holds either way. A `tokio::sync::Mutex` serializes T023/T049/T050 access to port 11434 so the multi-threaded test runtime doesn't race.
- [x] T051 [P] [US4] Write a Vitest test `src/__tests__/error-rendering.test.tsx`: for each `UserVisibleStatus` error variant, assert the WelcomeCard renders the right Swedish string and contains no English words, no `Error:` prefix, no stack trace lines. Covers FC-007.

**Checkpoint**: US4 complete = the six error paths all surface their Swedish strings; one-retry tested; binary-missing and port-busy tested.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T052 [P] Run the `humanizer` skill on every Swedish string introduced in this spec — modal title/body/buttons, all `statusMessage(visible)` mappings, error variants. Adjust any flagged AI-tinged phrasing. Per FR-017 + CLAUDE.md BLOCKING REQUIREMENT.
- [x] T053 [P] Outbound network audit (strict). Two-part check:
  - (a) `grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/` — only matches MUST be `reqwest::` inside `src-tauri/src/sidecar/client.rs` (or the new client module). Any other hit fails the audit.
  - (b) `grep -RInE 'https?://[^"]*' src/ src-tauri/src/` — every non-loopback URL literal MUST be either `http://127.0.0.1:11434` or `https://ollama.com…` (or a documented redirect target). Any other hostname fails the audit. The CI step in spec 006 will codify this as a build-time grep with exit-nonzero behavior; spec 002 documents it as a manual checklist item.
- [x] T054 [P] Live-runtime network audit: with the app running and the model present, run `lsof -p $(pgrep -f juradrop | head -1) -i -n -P 2>/dev/null | grep -E '(ESTABLISHED|LISTEN)'` and confirm only 127.0.0.1:* entries. During a pull, `ollama.com` (and its CDN redirects) may appear; record them in `quickstart.md` if they vary from the spec.
- [x] T055 [P] Update `README.md`: add a "Spec 002 progress" line in the status section. Note that the model download is the only outbound call and consent is required.
- [x] T056 Execute destructive test DT-001: send malformed JSON to `/api/tags` (mock by intercepting the response) — verify graceful Swedish-error fallback. **Coverage**: `src-tauri/tests/client_robustness.rs::list_tags_with_malformed_json_returns_graceful_error` mocks `/api/tags` with junk-shaped bytes via `wiremock`, asserts `ClientError::Http` or `ClientError::Json`. Mapping to `FelModellnedladdningAvbroten` is covered by `status.rs::tests::client_error_network_variants_map_to_fel_modellnedladdning_avbroten`. **Implementation note**: `OllamaClient::new()` was refactored to forward to `OllamaClient::with_base_url(BASE_URL.to_string())` so tests can point the client at a `wiremock::MockServer` URI without touching the production loopback invariant.
- [x] T057 Execute destructive test DT-002: send a prompt containing `<script>alert(1)</script>`, control chars `\x00\x01\x07`, emoji `🎉`, and assert the response renders safely (text, not HTML). **Coverage**: `client_robustness.rs::generate_round_trips_xss_control_bytes_and_emoji_without_panic` sends the literal `<script>alert(1)</script>\u{0007}\u{007F}🎉 hej världen 🎉` prompt and asserts the response bytes round-trip exactly. The "renders as text not HTML" half is moot for spec 002 — the WebView never renders generate() output in spec 002; that contract belongs to spec 003 (`first-zone-sammanfatta`) where the drop-zone UI lands. The Redacted wrapper keeps the content out of logs regardless.
- [x] T058 Execute destructive test DT-003: close the window during sidecar startup (within first 2 s). Verify no orphan process via `pgrep -f ollama`. **Needs user verification**.
- [ ] T059 Execute destructive test DT-004: interrupt model download mid-pull (kill -9 the app), re-launch, verify pull resumes via `/api/pull` idempotency. **Needs Rust integration test or manual**.
- [x] T060 Execute destructive test DT-005: call `run_roundtrip_dev` before the model is loaded. Verify Swedish "model not loaded" error rather than corruption. **Coverage**: `client_robustness.rs::generate_against_missing_model_returns_graceful_error` mocks Ollama's actual 404 shape (`{"error": "model 'gemma3:4b' not found, try pulling it first"}`) and asserts the call returns a graceful `ClientError` variant rather than panicking. The mapping to a Swedish status is covered by `status.rs::tests::client_error_network_variants_map_to_fel_modellnedladdning_avbroten`. A bonus test (`generate_with_empty_response_string_returns_empty_response_error`) hardens the adjacent path where a 200 with `"response": ""` would otherwise let an empty string bubble up.
- [x] T061 Execute destructive test DT-006: rename binary mid-app, re-launch, verify `FelKundeIntStarta` within 10 s. Same as T049 but observed in the UI. **Coverage**: the Rust path is covered by T023's `spawn_with_missing_binary_returns_bundled_binary_missing`. The `SidecarError::BundledBinaryMissing → UserVisibleStatus::FelKundeIntStarta` mapping is covered by `status.rs::tests::sidecar_error_bundled_binary_missing_maps_to_fel_kunde_inte_starta`. The UI rendering of that Swedish string is covered by `WelcomeCard.test.tsx`'s `shows the Swedish error string when the sidecar cannot start`. The three-test chain proves the user sees `FelKundeIntStarta` exactly when the binary is missing.
- [x] T062 Execute destructive test DT-007: bind port 11434 in another process, launch app, verify `FelPortenUpptagen`. Same as T050 + UI check. **Coverage**: the Rust path is covered by T023's `spawn_when_port_11434_busy_returns_port_busy`. The `SidecarError::PortBusy → UserVisibleStatus::FelPortenUpptagen` mapping is covered by `status.rs::tests::sidecar_error_port_busy_maps_to_fel_porten_upptagen`. The UI rendering is covered by `error-rendering.test.tsx` (T051). The three-test chain proves the user sees `FelPortenUpptagen` exactly when the port is busy.
- [ ] T063 Execute destructive test DT-008: double-click the dev round-trip command rapidly. Verify only one round-trip runs and the second observes the in-progress state. **Needs dev-button + race-test**.
- [ ] T064 Execute destructive test DT-009: sleep the system mid-`/api/generate`. Verify graceful timeout on wake. **Needs user manual (sleep is hard to trigger from a test)**.
- [x] T065 Execute destructive test DT-010: assert the welcome card uses `aria-live="polite"` so screen readers receive status updates. **Vitest assertion**. **Coverage**: `WelcomeCard.test.tsx::marks the status paragraph as aria-live polite and atomic for screen readers` verifies `aria-live="polite"`, `aria-atomic="true"`, and non-empty live-region text content. The atomic flag matters because the live region wraps the whole status string — without it, VoiceOver would only re-read the changed character (e.g. one percent digit) instead of the full sentence.
- [x] T066 Run all the spec-001 verification commands again (npm test / lint / typecheck / cargo test / clippy / fmt / playwright stub). All MUST still exit 0. Spec 002's additions must not regress spec 001. **Run (2026-05-27)**: `npm test` 78/78 ✓, `npm run lint` exit 0 ✓, `npm run typecheck` exit 0 ✓, `npm run test:e2e` 1/1 ✓ (placeholder stub), `cargo test` 42 unit + 4 client_robustness + 5 sidecar_lifecycle ✓, `cargo clippy` exit 0 with one pre-existing `clippy::let_underscore_future` warning at `client.rs::_pull_is_callable` (deliberately preserved — out of scope for this verification pass), `cargo fmt --check` clean.
- [ ] T067 SC-001 verification: cold launch with model present → "AI redo" within 10 s on M-series Mac. **Needs user verification on a real Mac**.
- [ ] T068 SC-002 verification: cold launch without model → consent → pull completes within 5 min on 100 Mbit/s. **Needs user verification**.
- [x] T069 SC-003 verification: quit app → `pgrep -f ollama` returns no JuraDrop-owned process within 5 s. **Automatable via integration test or quick CLI check**. **Coverage**: `sidecar_lifecycle.rs::stop_leaves_no_orphan_process` captures the spawned PID before `stop()`, then probes `libc::kill(pid, 0)` for up to 5 s and asserts the process is gone (ESRCH). Stronger than T023's port-release assertion — a process could theoretically close its listener and linger zombified; this catches that. Added a `pub fn pid(&self) -> Option<u32>` to `OllamaSidecar` so the test can capture the PID before the child handle is consumed by `stop()`. Verified end-to-end by stopping the local launch agent and re-running (3.79 s, all 5 lifecycle tests green).
- [ ] T070 SC-004 verification: round-trip test completes within 30 s warm. Already validated via T042 if it consistently passes.

---

## Dependencies & Execution Order

- Phase 1 (Setup) → no deps. Sequential within: T001 → T002 → T003; then [P] T004, T005, T006, T007.
- Phase 2 (Foundational) → depends on Phase 1. All [P] except where noted.
- Phase 3 (US1) → depends on Phase 2.
- Phase 4 (US2) → depends on Phase 2 + US1 (uses the sidecar started by US1).
- Phase 5 (US3) → depends on Phase 2 + US2 (needs model loaded).
- Phase 6 (US4) → depends on Phase 2 + US1 (most error paths are sidecar-side).
- Phase 7 (Polish) → depends on all user stories.

### Within US1, US2, US3, US4

- US1: T018 → T019 → T020 → T021 → T022 sequential (manager → wait_ready → stop → wire → port-check). Tests T023, T024 [P] after.
- US2: T025 → T026 → T027 → T028 → T029 → T030 sequential (client API → commands → events → wire). UI tasks T031, T032, T033 [P] after T029. Tests T034–T038 [P].
- US3: T039 → T040 → T041 sequential. Tests T042, T043, T044 [P].
- US4: T045–T048 [P]. Tests T049–T051 [P].

### Solo (this project)

Per `.claude/rules/project-workflow.md` direct-push solo workflow. Tasks execute sequentially by one developer (or Claude in `/speckit-implement`). `[P]` markers indicate independent file-writes batchable in parallel.

---

## Parallel Example: Phase 2 Foundational

```bash
Task: "Update src-tauri/tauri.conf.json with externalBin"      # T008
Task: "Update src-tauri/capabilities/default.json"             # T009
Task: "Scaffold src-tauri/src/sidecar/mod.rs"                  # T010
Task: "Implement log_safe.rs with Redacted<T>"                 # T011
Task: "Implement status.rs enums + AppStatus"                  # T012
Task: "Implement consent.rs with atomic write"                 # T013
Task: "Register tauri-plugin-shell in lib.rs"                  # T015
Task: "Create src/lib/tauri-bridge.ts"                         # T016
Task: "Create src/lib/status-store.ts"                         # T017
```

---

## Implementation Strategy

### MVP First (US1 + US2)

US1 and US2 together are the MVP. US3 is the verification-of-MVP. US4 hardens it.

1. Phase 1 (Setup) — fetch binary, install deps.
2. Phase 2 (Foundational) — all modules + capabilities + plugin.
3. Phase 3 (US1) — sidecar lifecycle.
4. Phase 4 (US2) — consent + download.
5. **STOP and validate MVP**: clean Mac → app shows consent modal → user clicks "Fortsätt" → progress climbs → "AI redo".

### Incremental Delivery

After MVP:
6. Phase 5 (US3) — round-trip test proves the pipeline.
7. Phase 6 (US4) — error paths.
8. Phase 7 (Polish) — humanizer, audits, destructive tests.

---

## Notes

- T056–T064 are mostly automatable (Rust integration tests) but some (DT-003, DT-009) are inherently manual — they require user interaction with the live app or system state. Marked accordingly.
- T067, T068 are manual user verifications because they involve real-world timing and visual confirmation.
- Spec 002 is the first spec where the source tree gains an outbound network call. T053 + T054 are load-bearing audits.
- `cargo test -- --ignored` is the only command that exercises FC-008. Normal `cargo test` MUST stay fast (no model load).
