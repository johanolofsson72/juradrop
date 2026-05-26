# Feature Specification: Ollama Sidecar Proof of Concept

**Feature Branch**: `main` (direct-push per `.claude/rules/spec-register.md`)

**Spec ID**: 002-ollama-sidecar-poc

**Pipeline track**: full (per `specs/INDEX.md`)

**Created**: 2026-05-26

**Status**: Draft

**Input**: User description: "bundle Ollama binary, start/stop lifecycle from Rust, prove first-launch model pull + one inference round-trip works end-to-end"

## Clarifications

### Session 2026-05-26

- Q: Behavior when port 11434 is already bound by another process — fail-fast / auto-fallback / non-default port? → A: **Fail fast** with Swedish "Porten är upptagen". User closes the conflicting tool and re-launches. Matches Principle VIII (Honest Failure States). FR-010 / US4 #3 already cover this; no spec change beyond confirming intent.
- Q: First-outbound disclosure UX for the ollama.com model pull — one-time modal / passive banner / both? → A: **One-time modal** on first launch with explicit "Fortsätt" / "Avbryt" buttons. The user actively opts in to the only outbound exception to Principle I. Modal text: "JuraDrop hämtar nu en AI-modell (~3 GB) från ollama.com. Det är enda gången något skickas utanför din Mac. Fortsätt?" If the user clicks "Avbryt", the app shows a static "AI-modell saknas. Starta om JuraDrop för att försöka igen." in the welcome card and does not pull.
- Q: Interrupted-download recovery — re-call `/api/pull` / delete partial then restart / explicit user prompt? → A: **Always re-call `/api/pull`** on next launch if the model is incomplete. Ollama's `/api/pull` is internally idempotent (resumes by layer). No need to manage partial-file state ourselves. Simpler code, no corruption risk.
- Q: Streaming inference infrastructure at this spec — blocking now / streaming now / hybrid? → A: **Blocking `/api/generate`** at this spec. Streaming arrives in spec 003 when drop zones need user-visible progress. YAGNI applies; no streaming plumbing in the round-trip code.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Sidecar lifecycle (Priority: P1)

A user launches JuraDrop. While the app window is open, the bundled Ollama process is running locally. When the user closes the window (or quits the app), the Ollama process stops cleanly. No orphan Ollama process remains in the background. No user action is required to manage the AI engine — Ollama is invisible plumbing.

**Why this priority**: Every other AI capability depends on Ollama being available while the app runs. Zombie processes after quit would be a privacy/resource leak.

**Independent Test**: Launch the app, open Activity Monitor, observe a process named `ollama` running. Quit the app. Confirm the `ollama` process disappears from Activity Monitor within 5 seconds. No second instance of Ollama should appear if the user re-launches the app.

**Acceptance Scenarios**:

1. **Given** the app is not running, **When** the user launches JuraDrop, **Then** an `ollama` child process starts within 5 seconds and stays running for the duration of the window.
2. **Given** the app is running with the Ollama sidecar active, **When** the user closes the window (red traffic-light button), **Then** both the JuraDrop process and the Ollama child process exit within 5 seconds.
3. **Given** the app was previously quit, **When** the user re-launches it, **Then** exactly one Ollama process runs (no duplicates from a stale instance).
4. **Given** an Ollama process was already running on the system before JuraDrop launches (e.g., the user installed Ollama themselves), **When** JuraDrop launches, **Then** JuraDrop binds to its own bundled Ollama instance on its own port and does NOT interfere with the system one (or, alternatively, refuses to start with a clear Swedish error if the port is held by another process).

---

### User Story 2 — First-launch model download (Priority: P1)

On the very first time the app launches on a particular Mac, the default AI model is not yet on disk. JuraDrop initiates a model download from the Ollama registry. The user is informed (in Swedish) that the model is downloading. Subsequent launches reuse the cached model and start nearly instantly.

**Why this priority**: Without the model, no AI feature can work. The user cannot be expected to run `ollama pull` themselves (Principle II — zero-CLI install). This MUST be invisible plumbing.

**Independent Test**: On a Mac that has never run JuraDrop and where Ollama has never been used, launch the app. Observe the model download progress (in the UI as a Swedish status string, or in a console log). Wait for the download to complete. Close the app, re-launch — the model is already present, no download is triggered.

**Acceptance Scenarios**:

1. **Given** the default model is NOT present in the user's Ollama model storage, **When** the app launches, **Then** the app initiates a model download via the Ollama API and surfaces a Swedish status ("Laddar ner AI-modell …") in the welcome card.
2. **Given** the model download is in progress, **When** the network drops mid-download, **Then** the app shows a Swedish error ("Modellnedladdningen avbröts. Försök igen.") and offers retry, without crashing.
3. **Given** the default model IS already present locally, **When** the app launches, **Then** no download is triggered and the welcome card shows "AI redo" within 5 seconds.
4. **Given** the user quits the app mid-download, **When** the user re-launches, **Then** the download resumes from where it left off (or restarts cleanly) without corrupting the existing partial model file.

---

### User Story 3 — One inference round-trip (Priority: P2)

To prove the sidecar is fully wired and not just a process that started, the app sends one test prompt to the local Ollama instance and receives a non-empty response. At this spec the test is invoked from a developer-only surface (a Tauri command exposed in dev builds only, or a Rust integration test), not from the user-facing UI. The user does NOT see this round-trip; it exists to give the developer confidence the pipeline works before spec 003 wires real drop zones.

**Why this priority**: This is the literal "proof of concept" half of the spec title. Without it, spec 002 is just "Ollama is a running process", not "Ollama is usable".

**Independent Test**: With the app running and the default model present, run the Rust integration test `cargo test --test sidecar_roundtrip -- --ignored` (the ignored flag protects normal `cargo test` from a multi-minute model load). The test asserts a non-empty response was returned for a hardcoded prompt within 30 seconds.

**Acceptance Scenarios**:

1. **Given** the app is running and the default model is loaded, **When** the developer invokes the round-trip test, **Then** the test sends a prompt (e.g., "Säg hej.") to the Ollama API and receives a non-empty Swedish response within 30 seconds.
2. **Given** the model is not yet loaded into memory (cold start), **When** the round-trip test is invoked, **Then** the first call may take up to 60 seconds (model load + inference); subsequent calls are faster.
3. **Given** the round-trip test fails (Ollama returns an error or times out), **When** the test runs, **Then** the test fails with a descriptive error message that does NOT leak prompt or response content to logs.

---

### User Story 4 — Honest failure states (Priority: P2)

When something goes wrong — sidecar fails to start, model download fails, Ollama crashes mid-inference — the app surfaces a plain-Swedish error in the welcome card. No stack traces, no English error codes, no silent failures. The user sees what's wrong and what to do.

**Why this priority**: Constitution Principle VIII (Honest Failure States) is non-negotiable. A broken AI engine with no visible state is worse than no AI engine.

**Independent Test**: Forcibly break the sidecar by renaming the bundled Ollama binary to something unreachable. Launch the app. The welcome card MUST show a Swedish error ("AI-motorn kunde inte starta. Starta om JuraDrop.") within 10 seconds. Restore the binary, re-launch — the welcome card returns to "AI redo".

**Acceptance Scenarios**:

1. **Given** the bundled Ollama binary is missing or non-executable, **When** the app launches, **Then** the welcome card shows the Swedish error "AI-motorn kunde inte starta. Starta om JuraDrop." within 10 seconds — no stack trace, no English text.
2. **Given** the Ollama sidecar started but crashed during model load, **When** the failure is detected, **Then** the welcome card shows "Något gick fel med AI-motorn. Starta om JuraDrop." and the app attempts one automatic restart of the sidecar before surfacing the error.
3. **Given** port 11434 (or the chosen port) is already bound by an unrelated process, **When** the app tries to start the sidecar, **Then** the welcome card shows "Porten är upptagen. Stäng andra AI-program och starta om." in Swedish.

---

### Edge Cases

- **App quit while model is mid-download**: the in-progress `.gguf` file MUST either resume cleanly on next launch or be deleted so the next launch starts fresh — never a corrupted half-file that Ollama refuses to load.
- **System sleeps mid-inference**: Ollama API call MUST time out gracefully (no indefinite hang); the welcome card resets to "AI redo" when the system wakes.
- **Disk full during model download**: the download MUST fail with a Swedish "Inte tillräckligt med diskutrymme. Frigör minst 4 GB." error rather than corrupting the model file.
- **Multiple JuraDrop instances launched simultaneously**: the second instance MUST detect the port is bound by the first and either focus the existing window or refuse to start with a clear message.
- **The user removes the model file manually between launches**: the app MUST detect this on next launch and re-trigger the download flow from US2.
- **Ollama version mismatch (bundled binary is older than the model's required Ollama version)**: the app MUST detect the version mismatch at sidecar startup and surface a Swedish error rather than failing cryptically later.
- **macOS denies execution of the bundled binary (Gatekeeper / quarantine attribute)**: caught by the "binary missing / non-executable" path; same Swedish error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST bundle an Ollama binary inside the application bundle so that no separate installation step is required (Principle II — zero-CLI install).
- **FR-002**: On app launch the app MUST start the bundled Ollama process as a child of the JuraDrop process. The Ollama HTTP API MUST become reachable at the configured loopback address within 10 seconds (cold start, no model preload).
- **FR-003**: On app quit (window close) the app MUST send a graceful shutdown signal to the Ollama child process and wait up to 5 seconds for it to terminate cleanly. If it does not exit within 5 seconds the app MUST force-terminate it.
- **FR-004**: At no point MUST a JuraDrop-spawned Ollama process outlive the JuraDrop process. After app quit, no Ollama instance owned by JuraDrop may remain visible in `ps`/`Activity Monitor`.
- **FR-005**: The Ollama HTTP API MUST be reachable only on loopback (`127.0.0.1` or `::1`). No remote-host configuration MUST be accepted (Principle III — local-only inference).
- **FR-006**: The default model identifier MUST be configurable in code but the default value at this spec is `gemma3:4b`. The model identifier MUST NOT be exposed in user-facing UI (Principle VII — Ollama is internal plumbing; users see "AI", not model tags).
- **FR-007**: On launch the app MUST query the Ollama API to determine whether the default model is present locally. If absent, the app MUST initiate a model pull from the configured Ollama registry (default `https://ollama.com`).
- **FR-008**: While the model is downloading, the welcome card MUST display a Swedish status message containing the word "Laddar" and (where possible) a progress percentage or downloaded-bytes indicator. Plain Swedish only — no English, no model tags, no URLs.
- **FR-009**: When the model is ready and the sidecar is reachable, the welcome card MUST display the Swedish status "AI redo".
- **FR-010**: When sidecar startup fails (binary missing, non-executable, port bound, crash on start), the welcome card MUST display a plain-Swedish error matching the scenarios under US4. No stack traces, no English, no exception names.
- **FR-011**: The app MUST expose a developer-only round-trip test (Tauri command in dev profile only, OR a Rust integration test marked `#[ignore]` so it does not run on every `cargo test`) that sends a hardcoded prompt to the local Ollama API and asserts a non-empty response within 30 seconds.
- **FR-012**: The round-trip test MUST NOT log the prompt or response content (Principle I — no telemetry that captures user content; even test content stays out of logs to avoid accidental telemetry pipelines later).
- **FR-013**: All outbound network traffic introduced by this spec MUST be limited to: (a) the initial model pull from the Ollama registry domain (default `ollama.com`), (b) loopback traffic to the local Ollama sidecar. No telemetry, no analytics, no other outbound calls. Constitution Principle I allows the model pull as the only added exception.
- **FR-014**: *(superseded by FR-020 — the idempotent re-call of `/api/pull` is the canonical recovery; no partial-file management at this layer.)*
- **FR-015**: If the bundled Ollama binary is missing, non-executable, or denied by macOS Gatekeeper, the app MUST surface the US4 Swedish error within 10 seconds rather than hanging or crashing the WebView.
- **FR-016**: The Tauri capability allowlist MUST gain only the permissions strictly required by this spec: ability to spawn the bundled sidecar, ability to make HTTP requests to `127.0.0.1`, and ability to make HTTP requests to the Ollama registry domain only. No filesystem-write capability beyond Ollama's own data directory (managed by Ollama).
- **FR-017**: All user-facing Swedish strings introduced by this spec MUST be passed through the `humanizer` skill before merge (per CLAUDE.md BLOCKING REQUIREMENT).
- **FR-018**: The sidecar binary MUST be signed with the same Developer ID as the outer `.app` (deferred to spec 006 for actual signing infrastructure, but the file structure at this spec MUST be ready for it — i.e., the binary lives where the signing pipeline will find it).
- **FR-019**: Before any model pull from `ollama.com`, the app MUST display a one-time consent modal on first launch with the exact Swedish text: "JuraDrop hämtar nu en AI-modell (~3 GB) från ollama.com. Det är enda gången något skickas utanför din Mac. Fortsätt?" with two buttons: "Fortsätt" (initiates the pull) and "Avbryt" (does not initiate the pull). The modal MUST be shown exactly once per fresh install. After explicit "Fortsätt" consent, the pull starts and the welcome card switches to the FR-008 progress status.
- **FR-019b**: If the user clicks "Avbryt" on the FR-019 modal, the welcome card MUST display the static Swedish message "AI-modell saknas. Starta om JuraDrop för att försöka igen." The app MUST NOT silently retry the pull until the user re-launches.
- **FR-020**: When a model pull is interrupted (network drop, user quit, system sleep), the app MUST simply re-call `/api/pull` on the next launch. The app MUST NOT attempt to manage partial-file state, delete partial files, or detect resume vs restart — Ollama's `/api/pull` is idempotent at the layer level and handles resumption internally.
- **FR-021**: All inference calls at this spec MUST use Ollama's blocking `/api/generate` endpoint. Streaming response handling (chunked HTTP / SSE) is explicitly out of scope at this spec and arrives in spec 003 when drop zones need user-visible progress.

### Key Entities

- **OllamaSidecar**: the child process running the Ollama HTTP server. Has a lifecycle state (`not_started → starting → ready → crashed | stopping → stopped`). Has a port binding (default `11434`). Has a PID once started. Owns a reference to the bundled binary path.
- **ModelArtifact**: the on-disk model file managed by Ollama (location is Ollama's choice; the app does not directly read or write the file). Has a lifecycle state (`not_present → downloading → ready | download_failed`). Identified by a model tag (default `gemma3:4b`).
- **SidecarStatus**: the user-visible summary derived from OllamaSidecar + ModelArtifact states. One of `klar` ("AI redo"), `laddar_ner_modell` ("Laddar ner AI-modell ..."), `startar` ("Startar AI..."), `fel_kunde_inte_starta`, `fel_porten_upptagen`, `fel_disk_full`, `fel_modellnedladdning_avbröts`, `fel_oväntat`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a cold launch on a Mac where the default model is already present, the welcome card transitions from "Startar AI..." to "AI redo" within 10 seconds on a baseline M-series Mac.
- **SC-002**: From a cold launch on a Mac where the default model is NOT yet present, the model download completes within 5 minutes on a 100 Mbit/s broadband connection, and the welcome card subsequently shows "AI redo".
- **SC-003**: Quitting the app while the sidecar is running results in a zombie-free state within 5 seconds: `ps aux | grep ollama` (excluding the grep itself) returns zero JuraDrop-owned Ollama processes.
- **SC-004**: The developer round-trip test returns a non-empty Swedish response within 30 seconds for a hardcoded prompt, on a baseline M-series Mac with the model warm.
- **SC-005**: Forcibly breaking the sidecar (binary rename) surfaces the Swedish error in the welcome card within 10 seconds — never a stack trace, never English.
- **SC-006**: Zero non-loopback / non-`ollama.com` outbound network connections originate from the JuraDrop process during normal operation, as verified by a `lsof -i -n -P` or `nettop` snapshot during the round-trip test.

## Assumptions

- The default model is `gemma3:4b` (decided pre-MVP; ~3.3 GB) and can be pulled from the public Ollama registry without authentication.
- The user's Mac has at least 8 GB of RAM (Ollama's `gemma3:4b` works on 8 GB but is more comfortable on 16 GB). System-RAM detection / model selection by size is deferred to spec 010 (settings panel).
- The bundled Ollama binary is the `aarch64-apple-darwin` build (matches FR-020 of spec 001). Universal2 / x86_64 is deferred to spec 006.
- The user has a working internet connection at first launch (the only launch that requires it). Subsequent launches work fully offline.
- The Ollama HTTP API surface (`/api/tags`, `/api/pull`, `/api/generate`, `/api/chat`) is stable enough between Ollama versions that pinning to a specific bundled version is sufficient. Ollama version migrations are out of scope for this spec.
- macOS Gatekeeper accepts the bundled Ollama binary either because the developer signs it (spec 006) or because the user has previously bypassed Gatekeeper for the parent `.app`. At this spec the binary is unsigned and may require a right-click → Open or a `xattr -d com.apple.quarantine` step on a fresh `.app`. This is documented in README + spec 006 inherits responsibility for production signing.
- Ollama's own data directory (`~/.ollama/models/` by default) is acceptable for storing the model. JuraDrop does NOT relocate it. Quota / disk-space management is delegated to Ollama; the app surfaces "disk full" errors that bubble up.
- The model download URL goes to `ollama.com` (the default registry). A self-hosted registry override is out of scope for this spec — adding configurability would re-open the privacy hole this app is built to close (Principle III).

## Functional Coverage Tests *(MANDATORY)*

| ID | Function | Test type | What it asserts |
|----|----------|-----------|-----------------|
| FC-001 | Sidecar starts on launch | Rust integration test + manual Activity Monitor | A `ollama` child process is reachable on the loopback port within 10 s |
| FC-002 | Sidecar stops on quit | Rust integration test (spawn + kill) + manual Activity Monitor | No JuraDrop-owned Ollama process after app exit |
| FC-003 | Model presence check | Rust unit test against mocked Ollama API | If `/api/tags` lists the default model, no download is triggered |
| FC-004 | Model download triggered when absent | Rust integration test (test registry) | If `/api/tags` returns no match, `/api/pull` is invoked |
| FC-005 | Welcome card shows "AI redo" | Vitest DOM | When the sidecar status command returns `klar`, the card displays "AI redo" |
| FC-006 | Welcome card shows download progress | Vitest DOM | When the status command returns `laddar_ner_modell` with progress N%, the card displays "Laddar ner AI-modell ... N%" |
| FC-007 | Welcome card shows Swedish error on sidecar failure | Vitest DOM | When the status command returns `fel_kunde_inte_starta`, the card displays the Swedish message (no English, no stack trace) |
| FC-008 | Round-trip prompt → response | Rust integration test (`#[ignore]`, run via `cargo test -- --ignored`) | Hardcoded prompt yields non-empty response within 30 s |
| FC-009 | Round-trip never logs content | Rust unit test on the logging layer | The logger MUST NOT emit prompt or response strings even at TRACE level |
| FC-010 | Loopback-only binding | Manual `lsof -i -n -P` check + Rust unit test | The Ollama child binds only `127.0.0.1` / `::1`; no `0.0.0.0` |
| FC-011 | First-outbound disclosure modal | Vitest DOM | First-launch flow shows the FR-019 consent modal exactly once. "Fortsätt" initiates pull; "Avbryt" sets the welcome card to the FR-019b static error and prevents auto-retry within the session. |
| FC-013 | Interrupted-download recovery | Rust integration test with mocked partial pull | After a mid-pull abort, the next launch re-calls `/api/pull` without inspecting partial-file state. Ollama's idempotent behavior is the test target. |
| FC-014 | Blocking-only inference at this spec | Rust unit test on the inference module | The module exposes only a blocking `generate(prompt) -> String` API surface; no streaming function is exported. |
| FC-012 | Capability allowlist scope | Static JSON inspection of `capabilities/*.json` | Only the sidecar + loopback + `ollama.com` permissions are granted; no filesystem-write or shell capabilities |

## Destructive Tests *(per `.claude/docs/spec-testing-checklist.md`)*

| ID | Category | Scenario | Expected behavior |
|----|----------|----------|-------------------|
| DT-001 | Invalid input | The Ollama HTTP API returns malformed JSON for `/api/tags` | App treats the response as "unknown" and shows the generic Swedish error rather than panicking |
| DT-002 | Invalid input | A prompt containing XSS payload, control characters, and emoji is sent through the round-trip test | The response renders safely; no script execution from the response is possible (response is text, not HTML) |
| DT-003 | Wrong order | The user closes the window before the sidecar finishes starting | The app cancels the sidecar startup cleanly; no orphan process; no error on next launch |
| DT-004 | Wrong order | Model download is interrupted, then app is quit, then re-launched immediately | The download either resumes cleanly or restarts cleanly — never a corrupted half-file |
| DT-005 | Skip steps | The user calls the dev-only round-trip command before the model is loaded | The command waits or fails with a clear "Model not loaded" Swedish error; does NOT corrupt state |
| DT-006 | Boundary | The bundled Ollama binary is renamed to a missing path | Sidecar startup fails fast with the FR-015 Swedish error within 10 s |
| DT-007 | Boundary | Port 11434 is held by an unrelated process when JuraDrop launches | Sidecar startup either uses a fallback port or fails with the Swedish "port busy" error — never silently binds to a different one |
| DT-008 | Timing/race | Two model-download triggers fire in quick succession (e.g., double-click of a dev button) | Only one download runs; the second call observes the in-progress state and does not re-trigger |
| DT-009 | Timing/race | The system sleeps for 30 s during an active inference call | The call times out gracefully on wake; no indefinite hang; the welcome card resets to "AI redo" |
| DT-010 | Accessibility | The download progress message is announced via aria-live region when it changes | Screen readers receive the status update without polling the DOM |

## Out of Scope (explicit non-goals)

- **Drop zones (any of them)** — those start with spec 003 (`first-zone-sammanfatta`).
- **Settings panel for model selection** — spec 010 (`settings-panel`).
- **Automatic sidecar crash recovery beyond one retry** — spec 011 (`error-recovery`) handles the full retry / circuit-breaker logic.
- **Updater for the bundled Ollama binary** — spec 007 (`auto-updater`) is for the app, not for Ollama. Ollama versions are pinned at build time in this spec.
- **First-run wizard / progress UI polish** — spec 008 (`first-run-wizard`). At this spec the download progress is a single string in the welcome card; the proper wizard layout comes later.
- **Universal2 / Intel Mac build of the sidecar** — spec 006 (`signing-and-ci`) introduces multi-arch builds together with notarization.
- **Reading or writing document content** — no `.docx`/`.pdf` parsing at this spec. The round-trip test uses a hardcoded prompt; real documents wait for spec 003.
- **Streaming responses to the UI** — the round-trip test takes the simple `/api/generate` blocking response. Streaming response handling for drop zones arrives with spec 003.
