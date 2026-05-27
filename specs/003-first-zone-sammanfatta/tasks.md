---
description: "Task list for spec 003 — First drop zone (Sammanfatta)"
---

# Tasks: 003 — First drop zone (Sammanfatta)

**Input**: Design documents from `specs/003-first-zone-sammanfatta/`

**Prerequisites**: `plan.md` ✅, `spec.md` ✅, `spec.allium` ✅, `research.md` ✅, `data-model.md` ✅, `contracts/` ✅, `quickstart.md` ✅

**Tests**: INCLUDED. Per CLAUDE.md, the full pipeline track requires functional + destructive browser tests + TLA+.

**Organization**: Tasks grouped by user story (US1=P1=happy path, US2=P1=state machine, US3=P2=not-ready gate, US4=P2=Swedish errors, US5=P2=cancellation). Setup + Foundational phases create shared scaffolding. Polish covers humanizer, audits, regression, and TLA+.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Independent file/edit — parallelizable
- **[Story]**: User story tag (US1, US2, US3, US4, US5)
- Setup/Foundational/Polish phases have no story tag

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add new dependencies, scaffold the design notes.

- [x] T001 Add Rust dependencies to `src-tauri/Cargo.toml` per plan.md: `docx-rs = "0.4"` (extract + write), `open = "5"` (OS default-handler invocation — or `tauri_plugin_opener` if preferred). Re-use spec 002's `tokio` (the `select!` for cancel) and `chrono` (the timestamp suffix). Verify `tokio-util = { version = "0.7", features = ["rt"] }` is added if `tokio::select!` ergonomics don't suffice on their own.
- [x] T002 [P] Add `sha2 = "0.10"` and `tempfile` (already a dev-dep from spec 002 — confirm) to `src-tauri/Cargo.toml` `[dev-dependencies]` for the SHA-256 source-immutability integration test (R-009).
- [x] T003 [P] Create the design notes file `design-system/pages/003-sammanfatta-zone.md` capturing the zone's visual treatment per `design-system/MASTER.md` — dashed border, dragover pulse, spinner placement, cancel-button styling, success/error flash colors. Reference the existing WelcomeCard treatment for color/typography reuse.
- [x] T003a Invoke the `frontend-design` skill via the Skill tool BEFORE any UI work below. Reference `design-system/MASTER.md` and the new T003 doc. This is a **BLOCKING REQUIREMENT** from CLAUDE.md and gates US1 / US2 / US3 / US4 / US5 UI tasks.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the `zones/` module skeleton, define the enums + structs, extend the React store/bridge, define the Swedish error copy map. Each user story extends these.

- [x] T004 [P] Create the `src-tauri/src/zones/` module skeleton: `mod.rs` re-exporting `sammanfatta`, `docx_extract`, `docx_write`, `sidecar_path`, `prompts`, `job`, `errors`, `snapshot`. Each child file starts with only the module doc-comment.
- [x] T005 [P] Implement `src-tauri/src/zones/errors.rs` per data-model.md: `pub enum ZoneFailure` with `#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]`, `serde(rename_all = "snake_case")`, and the nine `#[error("…")]` Swedish strings from FR-013..FR-020. Include `#[cfg(test)]` unit tests asserting each variant's `Display` output matches the spec.md Swedish string exactly and that no variant starts with `Error:` or exceeds 80 chars (Allium `SwedishCopy` invariants).
- [x] T006 [P] Implement `src-tauri/src/zones/snapshot.rs` per data-model.md: `pub enum ZoneState` (Idle/Dragover/Processing/Success/Error), `pub enum JobOutcome` (InFlight/Success/Failure/Cancelled), and `pub struct ZoneSnapshot` (`state`, `disabled`, `failure: Option<ZoneFailure>`, `job_id: Option<uuid::Uuid>`, `progress_hint: Option<String>`). All `#[derive(Debug, Clone, Serialize)]` with `serde(rename_all = "snake_case")` on the enums.
- [x] T007 [P] Implement `src-tauri/src/zones/job.rs` per data-model.md: `pub struct DropJob` with `id`, `source_path`, `started_at`, `outcome`, `truncated`, `cancel_token: tokio_util::sync::CancellationToken`, `finished_at`. Plus a `pub fn new(source_path: PathBuf) -> Self` constructor that generates a fresh UUID and `CancellationToken`.
- [x] T008 [P] Extend `src/lib/tauri-bridge.ts` with typed wrappers for the new spec 003 surface: `subscribeZone(cb: (snap: ZoneSnapshot) => void): Promise<UnlistenFn>` listening on `juradrop://sammanfatta`, plus `invokeCancelSummary(jobId: string): Promise<void>` calling the `cancel_summary` command.
- [x] T009 [P] Extend `src/lib/status-store.ts` with a `zone: ZoneSnapshot` slice and a `setZone(snap: ZoneSnapshot)` action. The store auto-subscribes to `juradrop://sammanfatta` events on first use, mirroring the spec 002 status auto-subscribe pattern.
- [x] T010 [P] Create `src/components/SammanfattaZone.errors.ts` exporting `SWEDISH_ZONE_ERROR: Record<ZoneFailure, string>` with the nine Swedish strings from FR-013..FR-020 — the TypeScript single source of truth. Include exhaustive type checking via `satisfies Record<ZoneFailure, string>`.

**Checkpoint**: Phase 2 done = code compiles, enums + stubs exist, zustand store extended, JS error-copy map ready. Nothing runs end-to-end yet; that's per-story.

---

## Phase 3: User Story 1 — Drop a Word document, get a Swedish summary back (Priority: P1)

**Goal**: A `.docx` dropped on the zone produces a `.docx` summary sidecar opened automatically. The single most important user-visible feature in this spec.

**Independent Test**: Drag a `.docx` onto the zone with `gemma3:4b` loaded → wait ≤ 60 s → confirm the sidecar `<stem>.sammanfatta.docx` exists, opens cleanly, and the source is byte-identical (SHA-256 match before vs after).

### Implementation for User Story 1

- [x] T011 [US1] Implement `src-tauri/src/zones/docx_extract.rs` per research.md R-001 + R-002: `pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure>`. Open the zip archive, detect password protection via the `EncryptedPackage` heuristic from R-002, walk `word/document.xml` paragraphs, concatenate text with `\n\n` boundaries between paragraphs. Returns `ZoneFailure::PasswordProtected` / `ParseError` / `EmptyText` on the matching conditions.
- [x] T012 [US1] Implement truncation in `docx_extract.rs` per R-003: take the first 24,000 UTF-8 characters on a char boundary (NOT a byte boundary — Swedish characters are multi-byte). Returns `ExtractedText { raw: Redacted<String>, char_count, was_truncated }`.
- [x] T013 [US1] Implement `src-tauri/src/zones/prompts.rs` per R-010: a `pub const SAMMANFATTA_SYSTEM_PROMPT: &str = "Du är en svensk juriststudent…";` constant matching the R-010 text exactly. No template variables — the model receives `<system>\n<user-text>` as the full prompt.
- [x] T014 [US1] Implement `src-tauri/src/zones/sidecar_path.rs` per R-007 + R-008: `pub fn canonical_for(source: &Path) -> PathBuf` returns `<dir>/<stem>.sammanfatta.docx`. `pub fn with_collision_suffix(source: &Path) -> PathBuf` returns the timestamp-suffixed variant using `chrono::Local::now().format("%Y-%m-%d-%H%M%S")`. `pub async fn write_atomically(path: &Path, bytes: &[u8]) -> Result<(), ZoneFailure>` writes to `<path>.tmp`, fsyncs, then `tokio::fs::rename`s. Returns `ZoneFailure::SaveError` on any IO error.
- [x] T015 [US1] Implement `src-tauri/src/zones/docx_write.rs` per `contracts/docx-format.md`: `pub fn build_summary_doc(source: &Path, response: &str, truncated: bool) -> Vec<u8>` constructs a `docx-rs::Docx` value with paragraph 0 = `Sammanfattning av '<basename>'` (bold), paragraph 1 = `Genererad <local-now> av JuraDrop med modellen gemma3:4b.`, optional paragraph 2 = truncation notice (italic), blank paragraph, then `response.split("\n\n")` as body paragraphs. Returns the serialized bytes.
- [x] T016 [US1] Implement `src-tauri/src/zones/sammanfatta.rs`: `pub struct SammanfattaZone` holding `Arc<RwLock<Option<DropJob>>>`. `pub async fn dispatch(&self, source: PathBuf, app: AppHandle, client: &OllamaClient) -> Result<(), ZoneFailure>` orchestrates the flow — extract → truncate-if-needed → call `client.generate(DEFAULT_MODEL, prompt)` via `tokio::select!` on `cancel_token` → build summary doc → choose canonical-or-timestamped path → atomic write → emit success snapshot. Returns `ZoneFailure::ModelError` on `ClientError`, `ZoneFailure::SaveError` on filesystem errors.
- [x] T017 [US1] Implement `pub fn open_summary(path: &Path) -> Result<(), std::io::Error>` in `sammanfatta.rs` (or a new `open.rs`) per R-004 using the `open = "5"` crate. Called after a successful atomic-rename; failure is logged via `eprintln` and surfaced as a secondary hint (does NOT flip success to error per FR-007).
- [x] T018 [US1] Wire `WindowEvent::DragDrop` in `src-tauri/src/lib.rs` per R-006 + R-012: in the existing `tauri::Builder::default().build(...).run(...)` event handler, intercept `WindowEvent::DragDrop { event, .. }` and call `SammanfattaZone::handle_drag_event` with the resolved paths. Reject multi-file and non-.docx drops at the Rust layer (emits the matching `ZoneFailure` snapshot). The WebView never sees the raw paths.
- [x] T019 [US1] Register `SammanfattaZone` in `lib.rs::setup` via `app.manage(Arc::new(SammanfattaZone::new()))`. The zone reads the spec 002 `AppState` to determine `disabled`.
- [x] T020 [US5] Add `#[tauri::command] cancel_summary(state, job_id) -> Result<(), String>` to `src-tauri/src/sidecar/commands.rs` per `contracts/tauri-commands.md` — idempotent cancel of the in-flight job (no-op if id mismatches). Register it in `lib.rs`'s `invoke_handler`. **Sequenced in Phase 3 (US1 phase) so the command surface exists before US5's button work in Phase 7 — but the feature it serves is US5, hence the tag.**
- [x] T021 [US1] Create `src/components/SammanfattaZone.tsx`: a React component rendering the zone with idle styling, hint copy "Släpp ett .docx-dokument här", and the spec 002 status-store wiring. The component subscribes to `useStatusStore.zone` and renders the current state visually. Uses Tailwind + shadcn primitives. **Invoke `frontend-design` skill first per T003a.**
- [x] T022 [US1] Mount `<SammanfattaZone />` in `src/App.tsx` alongside `<WelcomeCard />` and `<ConsentModal />`. The zone occupies the main content area below the welcome card. Position per the design notes from T003.

### Tests for User Story 1

- [x] T023 [P] [US1] Write `src-tauri/tests/zone_sammanfatta_lifecycle.rs` per `quickstart.md` and R-009: end-to-end happy path using `tauri::test::mock_builder` + a `wiremock` mock server for `127.0.0.1:11434`. Place a fixture `.docx` under `tests/fixtures/sample.docx`, compute its SHA-256, dispatch the drop, assert the sidecar exists with the FR-005a structure, assert the source SHA-256 is byte-identical. Marked `#[ignore = "..."]` because it touches the real bundled binary; runnable via `cargo test --test zone_sammanfatta_lifecycle -- --ignored`.
- [x] T024 [P] [US1] Write `src-tauri/src/zones/docx_extract.rs#[cfg(test)] mod tests`: unit tests for the extractor against in-process zip-archive fixtures (no real `.docx` files needed — build them with the `zip` crate at test time). Cover: normal text, multi-paragraph, NFD/NFC paths, truncation at exact 24,000 chars, truncation on a char boundary in the middle of a Swedish word.
- [x] T025 [P] [US1] Write `src-tauri/src/zones/sidecar_path.rs#[cfg(test)] mod tests` covering `canonical_for`, `with_collision_suffix`, and `write_atomically` against a `tempfile::TempDir`. Verify the `.tmp` is gone after a successful write (atomic-write invariant from spec 002's T035 pattern). **SC-006 check**: loop the canonical-then-collision logic 10 times against the same source path in a tight test; assert 10 distinct sidecar paths exist on disk afterwards (no overwrites). The timestamp suffix's seconds precision is high enough that 10 sequential drops in a normal test run produce distinct timestamps; if a test happens to land in the same second, the loop also asserts that case fails CLEANLY (no panic, no data loss) — the test then sleeps 1.1 s and re-tries the colliding pair.
- [x] T026 [P] [US1] Write `src/__tests__/SammanfattaZone.test.tsx` (initial set — US2 expands it): the component renders the Swedish title and hint, calls `subscribeZone` on mount, calls the returned unlisten fn on unmount.

**Checkpoint**: US1 done = a real `.docx` drop produces a real `.sammanfatta.docx` sidecar opened in the OS default handler, source unchanged, tests green.

---

## Phase 4: User Story 2 — Zone communicates its state clearly while processing (Priority: P1)

**Goal**: Every transition (idle/dragover/processing/success/error) is visible to the user within 100 ms; success auto-clears in 2 s; error auto-clears in 5 s; accessibility live region announces transitions.

### Implementation for User Story 2

- [x] T027 [US2] Implement the state machine emit path in `src-tauri/src/zones/sammanfatta.rs`: after every state transition, call a private `emit_snapshot(&self, app: &AppHandle, snap: ZoneSnapshot)` helper that fires `app.emit("juradrop://sammanfatta", snap)`. Transitions to emit: dragover, processing, success, error, idle (auto-clear). Per `contracts/tauri-events.md`.
- [x] T028 [US2] Implement the success auto-clear timer: `tokio::time::sleep(Duration::from_secs(2))` then transition `Success → Idle` and re-emit. Cancellable if a new drop arrives during the 2 s window.
- [x] T029 [US2] Implement the error auto-clear timer: same shape as T028 but with `Duration::from_secs(5)`.
- [x] T030 [US2] Extend `src/components/SammanfattaZone.tsx` with the visible state machine: distinct Tailwind classes per `state`, dragover border pulse, spinner during processing, success checkmark + flash, error flash with the Swedish failure string. Use the `useStatusStore.zone` slice as the single source of truth.
- [x] T031 [US2] Add `aria-live="polite"` + `aria-atomic="true"` to the status announcer inside `SammanfattaZone.tsx` (separate `<p role="status">` if needed). The announcer reads the current Swedish progress hint or error string. Per SC-007.
- [x] T032 [US2] Add a `progressHint(state, failure)` helper in `SammanfattaZone.tsx` returning the appropriate Swedish string for the current state: idle → "Släpp ett .docx-dokument här", dragover → "Släpp för att sammanfatta", processing → "Sammanfattar…", success → "Klar — öppnar fil…", error → `SWEDISH_ZONE_ERROR[failure]`.

### Tests for User Story 2

- [x] T033 [P] [US2] Extend `src/__tests__/SammanfattaZone.test.tsx` with one test per state transition: idle→dragover (mock store mutation), dragover→processing (mock store), processing→success, processing→error, success→idle after 2 s (`vi.useFakeTimers()`), error→idle after 5 s.
- [x] T034 [P] [US2] Add an accessibility test in `SammanfattaZone.test.tsx`: the status announcer carries `aria-live="polite"` and `aria-atomic="true"`, and its text content updates when the store's `zone.state` changes.
- [x] T035 [P] [US2] Write `src-tauri/src/zones/sammanfatta.rs#[cfg(test)] mod tests`: unit tests for the auto-clear timer cancellation — set up a state, schedule the auto-clear, mutate the state before the timer fires, assert the auto-clear is a no-op when the state has already moved.

**Checkpoint**: US2 done = every transition is visible within 100 ms, auto-clears fire on schedule, screen-reader announcements work.

---

## Phase 5: User Story 3 — Zone is disabled when the AI isn't ready (Priority: P2)

**Goal**: The zone is visibly disabled and refuses drops whenever `UserVisibleStatus != Klar`. The Swedish hint matches the welcome-card copy for the current status.

### Implementation for User Story 3

- [x] T036 [US3] In `src/components/SammanfattaZone.tsx`, compute `disabled` from `useStatusStore.status.visible !== 'klar'`. When `disabled === true`, apply a muted Tailwind treatment, drop the `onDrop` / `onDragOver` handlers (defense in depth), and show the Swedish hint matching the current `UserVisibleStatus` via the existing `statusMessage(visible)` helper from spec 002.
- [x] T037 [US3] In `src-tauri/src/zones/sammanfatta.rs::handle_drag_event`, double-check `app.state::<AppState>().sidecar.status() != Ready` and bail with `ZoneFailure::ZoneDisabled` before any extraction work. Defense-in-depth — the React layer also gates, but the Rust layer must enforce.
- [x] T038 [US3] Implement the reactive `disabled` recompute in `sammanfatta.rs`: listen to `juradrop://status` events (the spec 002 status emitter) and re-emit a `juradrop://sammanfatta` snapshot when the global status changes (per the spec.allium `SidecarStatusBecameReady` / `SidecarStatusBecameNotReady` rules).

### Tests for User Story 3

- [x] T039 [P] [US3] Extend `src/__tests__/SammanfattaZone.test.tsx`: for each non-`klar` `UserVisibleStatus` (startar, begar_samtycke, laddar_ner_modell, fel_kunde_inte_starta, fel_porten_upptagen, fel_disk_full, fel_ovantat, fel_modellnedladdning_avbroten, modell_saknas_avbruten), assert the zone is disabled and shows the matching Swedish hint.
- [x] T040 [P] [US3] Extend `src-tauri/tests/zone_sammanfatta_lifecycle.rs` with a test that forces the sidecar status to non-Ready, attempts a drop, asserts `ZoneFailure::ZoneDisabled` is returned and no extraction was attempted.

**Checkpoint**: US3 done = zone tracks global status reactively, drops on a disabled zone fail closed with a Swedish hint.

---

## Phase 6: User Story 4 — Honest Swedish errors for input the zone can't handle (Priority: P2)

**Goal**: Every error path surfaces the matching Swedish string per FR-013..FR-020 — short, no `Error:` prefix, no English, ≤ 80 chars.

### Implementation for User Story 4

- [x] T041 [US4] In `src-tauri/src/zones/sammanfatta.rs::handle_drag_event`, count the dropped paths and bail with `ZoneFailure::MultipleFiles` if `paths.len() >= 2` (FR-014).
- [x] T042 [US4] Same handler: check `path.extension() == Some("docx".as_ref())` and bail with `ZoneFailure::InvalidFormat` otherwise (FR-013).
- [x] T043 [US4] Same handler: if the current job's `outcome == InFlight`, bail with `ZoneFailure::ZoneBusy` and emit a transient toast/inline message (does NOT disturb the in-flight job's UI state — FR-015).
- [x] T044 [US4] Map every `ClientError` from `OllamaClient::generate` to `ZoneFailure::ModelError` inside `sammanfatta.rs::dispatch` (FR-020).
- [x] T045 [US4] Map every `std::io::Error` from `write_atomically` to `ZoneFailure::SaveError` (FR-019 + edge case).

### Tests for User Story 4

- [x] T046 [P] [US4] Write `src-tauri/tests/zone_docx_robustness.rs` covering: corrupt zip → `ParseError`, password-protected → `PasswordProtected`, whitespace-only → `EmptyText`, exact 24,000 chars + 1 → truncation flag set. Each case uses an in-process zip-built fixture (no real Word needed).
- [x] T047 [P] [US4] Write a vitest test `src/__tests__/SammanfattaZone.errors.test.tsx`: for each `ZoneFailure` variant, set the store's `zone.failure` and assert the rendered string matches `SWEDISH_ZONE_ERROR[variant]`. Also asserts no rendered string starts with `Error:` and every string is ≤ 80 characters (mirrors the Allium `SwedishCopy` invariants in JS). **SC-002 check**: wrap each error injection in `vi.useFakeTimers()` and assert the rendered string appears in the DOM within the simulated 3-second budget. The store update is synchronous so this is effectively asserting < 100 ms in practice — but the explicit fake-timer wrapper documents the SC-002 contract in the test source.
- [x] T048 [P] [US4] Cross-language drift assertion: a Rust test that prints every `ZoneFailure::Display` string to a JSON file at build time + a vitest test that imports `SWEDISH_ZONE_ERROR` and asserts byte-for-byte equality against the same JSON file. Catches future refactors that update one side without the other.

**Checkpoint**: US4 done = every error category surfaces its Swedish string; both sides of the Rust/TS boundary agree on every string.

---

## Phase 7: User Story 5 — Cancel an in-flight summarization (Priority: P2)

**Goal**: While processing, a Swedish "Avbryt" affordance lets the user abort the model call within 1 s, write nothing to disk, and return the zone to idle.

### Implementation for User Story 5

- [x] T049 [US5] In `src-tauri/src/zones/sammanfatta.rs::dispatch`, wrap the `client.generate` future in `tokio::select! { _ = client.generate(...) => ..., _ = job.cancel_token.cancelled() => ZoneFailure::Cancelled-or-ignore }` per R-005. On cancel, set `JobOutcome::Cancelled`, emit a "Sammanfattning avbruten" snapshot, do NOT call `write_atomically`.
- [x] T050 [US5] Implement the `DiscardLateModelResponseAfterCancel` rule: if `generate` returns AFTER `cancel_token` was already triggered (race), drop the response and exit — no sidecar write, no success state. Per FR-028.
- [x] T051 [US5] Add a Swedish "Avbryt" button to `src/components/SammanfattaZone.tsx`, visible only when `zone.state === 'processing'`. Click + Enter + Space all trigger `invokeCancelSummary(jobId)`. Per FR-026.
- [x] T052 [US5] In `SammanfattaZone.tsx`, on cancel acknowledgement (next snapshot with `state === 'success'` + `progress_hint === 'Sammanfattning avbruten'`), flash the Swedish text briefly before the standard 2 s auto-clear takes over.

### Tests for User Story 5

- [x] T053 [P] [US5] Write `src-tauri/tests/zone_cancel.rs`: dispatch a job against a `wiremock` mock server that delays its response by ≥ 2 s, fire `cancel_summary` after ~100 ms, assert the job's terminal `outcome == Cancelled`, assert no sidecar file exists at the canonical or timestamped path, assert the source SHA-256 is byte-identical.
- [x] T054 [P] [US5] Extend `src/__tests__/SammanfattaZone.test.tsx`: the "Avbryt" button is hidden when state ≠ processing, visible when state = processing, focusable, activates on Enter + Space + click, invokes `cancelSummary` with the current `jobId`.

**Checkpoint**: US5 done = cancel takes effect within 1 s, no sidecar written on cancel, source byte-identical.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T055 [P] Run the `humanizer` skill on every Swedish string introduced in this spec — the eight `ZoneFailure` strings, the four progress hints, the truncation notice, the cancel flash, the disabled-state hints. Adjust any flagged AI-tinged phrasing. Per FR-021 + CLAUDE.md BLOCKING REQUIREMENT.
- [ ] T056 [P] Static outbound-network audit per spec 002's T053 pattern: `grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/` — every match must be inside `src-tauri/src/sidecar/client.rs` OR `src-tauri/src/zones/sammanfatta.rs` (the dispatch path). `grep -RInE 'https?://[^"]*' src/ src-tauri/src/` — every non-loopback URL must be loopback or `ollama.com`. Any new outbound surface fails the audit.
- [ ] T057 [P] Live-runtime network audit per R-011: while a drop is in flight, `lsof -p $(pgrep -f juradrop | head -1) -i -n -P 2>/dev/null | grep -E '(ESTABLISHED|LISTEN)'` — confirm only `127.0.0.1:*` endpoints. Documented in `quickstart.md`; codified into a Playwright test if time allows (otherwise manual per the spec 002 pattern).
- [ ] T058 [P] Source-immutability test per R-009: extend `zone_sammanfatta_lifecycle.rs` with a SHA-256-before / SHA-256-after comparison around the dispatch call. Verifies FR-024 + SC-004.
- [ ] T059 [P] Update `README.md` with a one-paragraph "Spec 003 progress" note: the first drop zone works end-to-end with `gemma3:4b`; six remaining zones land in spec 004; other formats land in spec 005.
- [ ] T060 [P] Execute destructive test DT-003-equivalent for the zone: close the window mid-summary. Verify the process exits cleanly (spec 002's drain task handles SIGTERM); no orphan ollama; no half-written sidecar (atomic write invariant).
- [ ] T061 [P] Execute destructive test DT-004-equivalent: `kill -9` the app mid-summary. Verify no half-written sidecar, source byte-identical. (Builds on the atomic-write invariant.)
- [ ] T062 [P] Execute destructive test DT-005-equivalent: drop a `.docx` while the sidecar status is `Startar` (delay the spec 002 `wait_ready` by binding port 11434 temporarily). Verify `ZoneFailure::ZoneDisabled` surfaces and no extraction is attempted.
- [ ] T063 [P] Execute destructive test DT-007-equivalent: drop a `.docx` whose path contains exotic characters (emoji, NUL, NFD/NFC). Verify the sidecar is named correctly without shell-injection risk per FR-025.
- [ ] T064 Run all spec-001 + spec-002 verification commands again (`npm test`, `npm run lint`, `npm run typecheck`, `npm run test:e2e`, `cargo test`, `cargo clippy`, `cargo fmt --check`). All MUST still exit 0. Spec 003's additions must not regress spec 001 or 002.
- [ ] T065 Browser-driven Playwright smoke test that drives the actual built `.app`: drop a fixture `.docx` onto the zone, wait for the sidecar to appear, verify the file exists. This is the end-of-pipeline browser test required by CLAUDE.md.
- [ ] T066 SC-001 verification: drop a 5-page `.docx` with `gemma3:4b` warm. Wall-clock from drop to sidecar open ≤ 60 s. **Needs user verification on a real Mac**.
- [ ] T067 SC-005 verification: every visible transition occurs within 100 ms of its trigger. Playwright timing assertions if achievable; otherwise manual verification with a screen recording.
- [ ] T068 SC-008 verification: cancel takes effect ≤ 1 s from click to idle. Covered by T053's wall-clock assertion.
- [ ] T069 Run `/tla` per the feature-pipeline rule. Distills the implementation back to `.allium`, compares against `spec.allium`, extracts TLA+ invariants. Any drift or GAP-N entry gets surfaced via `AskUserQuestion` per `.claude/rules/validation-followup.md`.
- [ ] T070 Tick spec 003 in `specs/INDEX.md` to `[x]` and add a Register history entry. Commit + push to `main` per the project's direct-push workflow.

---

## Dependencies & Execution Order

- Phase 1 (Setup) → no deps.
- Phase 2 (Foundational) → depends on Phase 1. All [P] except where noted.
- Phase 3 (US1) → depends on Phase 2.
- Phase 4 (US2) → depends on Phase 3 (the zone must exist before its transitions are visible).
- Phase 5 (US3) → depends on Phase 2 (the disabled gate is a foundational concern); can run in parallel with US1/US2/US4/US5 once foundational + zone shell exists.
- Phase 6 (US4) → depends on Phase 2; mostly parallel with US1/US3/US5.
- Phase 7 (US5) → depends on Phase 3 (US1's dispatch must exist to cancel into).
- Phase 8 (Polish) → depends on all user stories.

### Within phases

- US1: T011 → T012 → T013 → T014 → T015 → T016 → T017 sequential (each layer feeds the next). T018 → T019 → T020 → T021 → T022 in order. Tests T023..T026 [P] after.
- US2: T027 → T028 → T029 sequential; T030, T031, T032 [P] after. Tests T033..T035 [P].
- US3: T036, T037, T038 mostly [P]. Tests T039..T040 [P].
- US4: T041..T045 mostly [P]. Tests T046..T048 [P].
- US5: T049 → T050 → T051 → T052 sequential. Tests T053..T054 [P].

### Solo (this project)

Per `.claude/rules/project-workflow.md` direct-push solo workflow. Tasks execute sequentially by one developer (or Claude in `/speckit-implement`). `[P]` markers indicate independent file-writes batchable in parallel.

---

## Parallel Example: Phase 2 Foundational

```bash
Task: "Scaffold src-tauri/src/zones/mod.rs"               # T004
Task: "Implement zones/errors.rs with ZoneFailure"        # T005
Task: "Implement zones/snapshot.rs with ZoneSnapshot"     # T006
Task: "Implement zones/job.rs with DropJob"               # T007
Task: "Extend src/lib/tauri-bridge.ts"                    # T008
Task: "Extend src/lib/status-store.ts with zone slice"    # T009
Task: "Create SammanfattaZone.errors.ts copy map"         # T010
```

---

## Implementation Strategy

### MVP First (US1 + US2 + US3)

US1, US2, and US3 together form the MVP: drop a `.docx`, see the state machine work, see the not-ready gate. US4 hardens the error surface; US5 adds the cancel affordance.

1. Phase 1 (Setup) — deps + design notes.
2. Phase 2 (Foundational) — module skeleton + enums + store extensions.
3. Phase 3 (US1) — happy path drop → summary.
4. Phase 4 (US2) — visible state machine.
5. Phase 5 (US3) — disabled-while-not-ready gate.
6. **STOP and validate MVP**: drop a `.docx` with the AI ready → see the summary appear; quit the AI and drop again → see the disabled hint.

### Incremental Delivery

After MVP:

7. Phase 6 (US4) — error coverage.
8. Phase 7 (US5) — cancellation.
9. Phase 8 (Polish) — humanizer, audits, destructive tests, /tla.

---

## Notes

- T011 (extractor), T015 (writer), and T016 (dispatcher) are the heart of US1 and have no parallelism opportunity within themselves — each is a single file's worth of logic.
- T056–T058 (audits + immutability test) are codifying the privacy invariant that this whole project exists to protect. Pay close attention to them.
- T069 (/tla) and T070 (register tick) are the spec-completion gates.
- Cancellation (US5) is non-trivial because it requires the dispatch to be select-able over the cancel token; do not collapse US5 into US1 mid-implementation.
