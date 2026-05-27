# Feature Specification: First drop zone — Sammanfatta

**Feature Branch**: `main` (per `.claude/rules/spec-register.md` — direct-to-main, no feature branches)

**Created**: 2026-05-27

**Status**: Draft

**Input**: User description: Add the first drop zone — a single "Sammanfatta" (Swedish for "Summarize") area in the main window. Drag a `.docx` → app extracts text via `docx-rs` → local Ollama (`gemma3:4b`) produces a Swedish summary → app writes the summary as a sidecar `.docx` next to the original (`<stem>.sammanfatta.docx`) and opens it via the OS default handler. The zone has a full visible state machine: `idle → dragover → processing → success → idle` (or `… → error → idle`). All copy is Swedish; error states follow the spec 002 honest-failure pattern. The zone respects the spec 002 sidecar status — disabled with a Swedish hint when `UserVisibleStatus != Klar`. No document content ever leaves the Mac (Principle I).

## Clarifications

### Session 2026-05-27 (auto-picked recommendations per `.claude/settings.json`)

- Q: How is the summary `.docx` structured — flat model output, or with a small self-documenting header? → A: **Header-with-source.** The sidecar `.docx` begins with a small Swedish header (paragraph 1: "Sammanfattning av '<original-filename>'"; paragraph 2: "Genererad <YYYY-MM-DD HH:MM> av JuraDrop med modellen gemma3:4b."), then a blank paragraph, then the model's response as one or more paragraphs. The header makes the sidecar self-documenting when re-opened weeks later and preserves the audit trail without leaking any document content into logs.
- Q: When the canonical sidecar name collides and a timestamp suffix is appended, which timezone is the timestamp in? → A: **Local time.** The collision suffix `YYYY-MM-DD-HHMMSS` uses the user's local timezone so the filename matches what their clock said when they did the drop. UTC would produce filenames that feel "off-by-some-hours" to the user.
- Q: The FR-019 truncation says "first ~6,000 tokens" but real tokenization depends on the model; how is the boundary actually computed? → A: **Character-count proxy.** Truncate at the first 24,000 UTF-8 characters of extracted text (roughly 6,000 English tokens; conservative for Swedish — Swedish averages slightly more characters-per-token than English). Real tokenization sits inside Ollama; a fixed character count is deterministic, testable, and doesn't require coupling to a model-specific tokenizer.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Drop a Word document, get a Swedish summary back (Priority: P1)

A law student has a 5-page court ruling in a `.docx` file. They drag it onto the "Sammanfatta" zone. A spinner appears with the Swedish text "Sammanfattar…". Within about a minute, a new file `<original-stem>.sammanfatta.docx` appears next to the original on disk and opens automatically in Word (or Pages, or whatever the user's default `.docx` handler is). The summary is a few paragraphs of plain Swedish that capture the ruling's essence — facts, holding, reasoning. The original file is untouched.

**Why this priority**: This is the entire reason the app exists. Spec 001 stood up a window, spec 002 wired the local LLM; this spec is the first feature a real user can use end-to-end. Everything that comes later (more zones, more formats, signing, polish) is sequencing around this one user story.

**Independent Test**: With a fresh dev build and a small `.docx` on disk: drag the file onto the zone → see the spinner → wait ≤ 60 s → confirm the sidecar `.sammanfatta.docx` exists, is non-empty, opens cleanly in Word/Pages, and the original `.docx` is byte-identical to before the drop.

**Acceptance Scenarios**:

1. **Given** the AI status is `Klar` and a 5-page `.docx` is on disk, **When** the user drags the file onto the zone and releases, **Then** the zone enters processing, the local Ollama produces a Swedish summary, and a sidecar `.docx` is written and opened automatically within 60 s.
2. **Given** the summary completed successfully, **When** the user inspects the sidecar `.docx`, **Then** the file is well-formed (opens in Word and Pages without prompts), contains a Swedish summary, and the original file is unmodified.
3. **Given** a successful summary, **When** the user re-drops the same source file, **Then** a fresh summary is generated (any existing sidecar is preserved via a timestamp-suffixed name so previous summaries are never overwritten).

---

### User Story 2 — Zone communicates its state clearly while processing (Priority: P1)

The drop zone is a visible UI surface, not a black box. The user sees the zone change as they drag a file over it (highlight border), drop the file (spinner appears with "Sammanfattar…"), and finish (a brief Swedish "Klar — öppnar fil…" confirmation that fades back to idle within 2 s). If something goes wrong, the zone shows a Swedish error message in the same surface and returns to idle automatically.

**Why this priority**: Without visible state, the user can't tell whether the drop registered, whether the AI is working, or whether they should re-drop. Tied to US1 because they're the same surface.

**Independent Test**: Drag a `.docx` over the zone without releasing → zone shows the dragover highlight. Drop it → zone shows the spinner + processing copy. Wait → zone shows brief success copy → returns to idle. Each transition must be visible within 100 ms of the trigger.

**Acceptance Scenarios**:

1. **Given** the zone is idle, **When** the user drags any file over the zone, **Then** the zone enters dragover state (visible highlight + cursor change) within 100 ms.
2. **Given** the user has dropped a valid `.docx`, **When** processing begins, **Then** the zone shows a spinner and the Swedish text "Sammanfattar…" within 100 ms of the drop.
3. **Given** processing completes successfully, **When** the sidecar is written, **Then** the zone shows the Swedish text "Klar — öppnar fil…" and returns to idle within 2 s.
4. **Given** the user drags a file over the zone but then drags off (no drop), **When** the cursor leaves the zone, **Then** the zone returns to idle within 100 ms.

---

### User Story 3 — Zone is disabled when the AI isn't ready (Priority: P2)

The drop zone respects the spec 002 sidecar status. If the AI is starting (`Startar`), downloading a model (`LaddarNerModell` — possibly with a percent), or in any error state (`FelKundeIntStarta`, `FelPortenUpptagen`, `FelDiskFull`, `FelOvantat`, `FelModellnedladdningAvbroten`, `ModellSaknasAvbruten`), the zone is visibly disabled — it shows a Swedish hint pointing at the current status and the zone refuses drops without spawning a confused "no AI" error.

**Why this priority**: Without this gate, a user could drop a file before the AI is up and get a misleading "summarization failed" error. The right message is "AI är inte redo ännu — vänta tills `<current-status>`". Strictly cosmetic at the MVP level; functional at first-launch level.

**Independent Test**: Force the sidecar status to each non-`Klar` value (via the existing spec 002 test surface or by killing the bundled Ollama mid-run). Confirm the zone shows disabled styling and the right Swedish hint for each status.

**Acceptance Scenarios**:

1. **Given** `UserVisibleStatus` is `Startar`, **When** the user views the zone, **Then** the zone is disabled and shows "AI startar…" as the hint.
2. **Given** `UserVisibleStatus` is `LaddarNerModell` with `progress_percent: 42`, **When** the user views the zone, **Then** the hint reads "Laddar ner AI-modell… 42%" and the zone refuses drops.
3. **Given** `UserVisibleStatus` is any `Fel*` variant, **When** the user views the zone, **Then** the hint surfaces the same Swedish error string the welcome card uses (single source of truth).
4. **Given** the AI status flips from `LaddarNerModell` to `Klar`, **When** the welcome card updates, **Then** the zone transitions from disabled to idle automatically.

---

### User Story 5 — Cancel an in-flight summarization (Priority: P2)

The user changed their mind, dropped the wrong document, or doesn't want to wait for the model to finish. While the zone is in the processing state, a small Swedish "Avbryt" button is visible (inside or alongside the spinner). Clicking it aborts the in-flight model call, leaves the original `.docx` untouched, writes nothing to disk, and returns the zone to idle within ~1 s. A brief Swedish flash "Sammanfattning avbruten" precedes the return to idle.

**Why this priority**: Originally deferred to spec 011 (error-recovery) but pulled into spec 003 during clarification (2026-05-27). Cancellation rounds out the visible state machine — without it, the user has no way out of a long-running summary they no longer want. Sits at P2 because the happy path (US1) and the visible state machine (US2) are still more important; cancel is a polish-of-the-flow feature.

**Independent Test**: With the AI in `Klar`, drop a `.docx` → see the spinner + the "Avbryt" button → click Avbryt → confirm the zone returns to idle within 1 s, no sidecar `.docx` was written, and the original is byte-identical (matching SHA-256 before vs after the drop).

**Acceptance Scenarios**:

1. **Given** the zone is in processing state with an in-flight model call, **When** the user clicks "Avbryt", **Then** the model call is aborted within 1 s and the zone shows the Swedish flash "Sammanfattning avbruten" before returning to idle.
2. **Given** a summary was cancelled, **When** the user inspects the source directory, **Then** no new `.docx` sidecar file exists (canonical or timestamp-suffixed) — cancellation guarantees no partial output is persisted.
3. **Given** the user is dragging another `.docx` over the zone, **When** the previous job is in flight, **Then** the cancel button is the only way to free the zone (per FR-015 single-flight); dropping is rejected with the existing "Vänta tills föregående dokument är klart" copy.
4. **Given** a cancel was issued, **When** the model completes its inference *after* the abort signal was sent, **Then** the response is discarded — no sidecar is written even if bytes arrived after the abort.

---

### User Story 4 — Honest Swedish errors for input the zone can't handle (Priority: P2)

When the user drops something the zone can't process — a `.pdf`, an image, two files at once, a corrupt `.docx`, a password-protected `.docx`, an empty `.docx`, or a `.docx` that exceeds the model's context — the zone shows a Swedish error string that names the cause without leaking stack traces, English, or technical jargon. The error displays for ~5 s, then the zone returns to idle.

**Why this priority**: Real users will drop the wrong thing. The product's tone is "honest failure"; this is where it earns the tone.

**Independent Test**: For each error category, drop the offending input and read the message. Each message must be (a) Swedish, (b) ≤ ~80 characters, (c) free of English words, (d) free of any `Error:` prefix or stack trace fragment.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar`, **When** the user drops a `.pdf` (or any non-`.docx`), **Then** the zone shows "Endast .docx i denna version".
2. **Given** the AI is `Klar`, **When** the user drops two or more files at once, **Then** the zone shows "Ett dokument i taget".
3. **Given** the AI is `Klar`, **When** the user drops a `.docx` that fails to parse (corrupt zip), **Then** the zone shows "Kunde inte läsa dokumentet".
4. **Given** the AI is `Klar`, **When** the user drops a password-protected `.docx`, **Then** the zone shows "Dokumentet är lösenordsskyddat".
5. **Given** the AI is `Klar`, **When** the user drops a `.docx` whose extracted text is empty, **Then** the zone shows "Dokumentet innehåller ingen text".
6. **Given** processing is already in flight, **When** the user drops a second `.docx`, **Then** the zone shows "Vänta tills föregående dokument är klart" and does not queue the second job.
7. **Given** the model returns an error (e.g. inference timeout), **When** processing fails, **Then** the zone shows "AI-motorn svarade inte — försök igen".

---

### Edge Cases

- **Empty extraction**: a `.docx` whose body is only whitespace, images, or tables-with-no-text → "Dokumentet innehåller ingen text" (US4 #5).
- **Context overflow**: extracted text exceeds `gemma3:4b`'s context window. Truncate the input to the first ~6,000 tokens (a tested margin under the model's hard limit) and prepend the summary with a Swedish notice "(Dokumentet förkortades innan sammanfattning — endast början är sammanfattad.)". Do NOT silently truncate without notice; do NOT refuse outright.
- **Sidecar collision**: the canonical sidecar name `<stem>.sammanfatta.docx` already exists. Append a timestamp suffix: `<stem>.sammanfatta.2026-05-27-153012.docx`. The previous summary is preserved.
- **OS default handler missing**: if `open <sidecar>` fails (no `.docx` handler registered), the zone still ends in success state (file is on disk); a Swedish secondary hint reads "Filen sparades — kunde inte öppna automatiskt".
- **Drop on disabled zone**: the OS may still fire the drop event on a visually-disabled zone. The handler must double-check sidecar status and surface the same disabled-hint copy ("AI är inte redo ännu") rather than processing.
- **Drag-leave without drop**: returns to idle within 100 ms.
- **App backgrounded mid-processing**: processing continues; success/error state is reached when the user returns to the foreground. The visible state machine is consistent regardless of focus.
- **Sidecar process crashes mid-summary**: the spec 002 one-retry mechanism re-spawns Ollama; if the retry succeeds within reasonable time, the summary completes. If not, the zone shows "AI-motorn svarade inte — försök igen" (US4 #7).
- **System sleep mid-processing**: on wake, the connection to the local Ollama is re-established or the inference call surfaces a timeout error mapped to US4 #7.
- **Drop a `.docx` whose path contains exotic characters** (emoji, NUL, control bytes): path is normalized to NFC, no shell expansion, no command injection; if writing the sidecar fails because of filesystem rules (e.g., name too long on the target volume), shows "Kunde inte spara sammanfattningen".

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The main window MUST display a single drop zone with the Swedish heading "Sammanfatta" and a one-line Swedish hint (e.g., "Släpp ett .docx-dokument här").
- **FR-002**: The drop zone MUST accept files dragged from Finder via the macOS drag-and-drop file protocol.
- **FR-003**: When a `.docx` file is dropped while `UserVisibleStatus == Klar`, the system MUST extract text from the file locally (no network).
- **FR-004**: The system MUST send the extracted text to the local Ollama at `127.0.0.1:11434` with a Swedish summarization system prompt. The text-bearing parameter MUST be wrapped in `Redacted<String>` end-to-end so the content never appears in logs or telemetry.
- **FR-005**: The system MUST write the generated summary to a sidecar `.docx` file in the same directory as the source file, using the naming convention `<source-stem>.sammanfatta.docx`. The write MUST be atomic (temp file + rename) so a crash mid-write cannot corrupt either the source or a previous summary.
- **FR-005a**: The sidecar `.docx` MUST begin with a small Swedish header (paragraph 1: `Sammanfattning av '<original-filename>'`; paragraph 2: `Genererad <YYYY-MM-DD HH:MM> av JuraDrop med modellen gemma3:4b.`), followed by a blank paragraph, then the model's response as one or more body paragraphs. The header makes the sidecar self-documenting when re-opened later. (Resolved during clarification 2026-05-27.)
- **FR-006**: If the canonical sidecar name already exists, the system MUST append a timestamp suffix in the form `<stem>.sammanfatta.YYYY-MM-DD-HHMMSS.docx` rather than overwriting. The timestamp uses **local timezone** so the filename reflects what the user's clock said at drop time. (Resolved during clarification 2026-05-27.)
- **FR-007**: On successful write, the system MUST invoke the OS default `.docx` handler on the sidecar path. If the open call fails, the summary is still considered successful; a secondary hint indicates the file was saved but not opened.
- **FR-008**: The drop zone MUST present a visible state machine with the states `idle`, `dragover`, `processing`, `success`, and `error`. Each state has a distinct visual treatment per `design-system/MASTER.md`.
- **FR-009**: The state machine MUST transition between visible states within 100 ms of the triggering event (drag enter, drag leave, drop, processing start, processing complete, error surface, success-to-idle reset).
- **FR-010**: The success state MUST return to idle automatically within 2 s of being entered.
- **FR-011**: The error state MUST return to idle automatically within 5 s of being entered. Errors are not blocking — the user can re-drop immediately.
- **FR-012**: The drop zone MUST be visibly disabled (no hover effect, no drop acceptance) whenever `UserVisibleStatus != Klar`. The disabled state shows the same Swedish copy the welcome card displays for that status (single source of truth).
- **FR-013**: Non-`.docx` drops MUST surface the Swedish string "Endast .docx i denna version".
- **FR-014**: Multi-file drops (≥ 2 files in one drop event) MUST surface the Swedish string "Ett dokument i taget".
- **FR-015**: A drop while a previous drop is still processing MUST surface the Swedish string "Vänta tills föregående dokument är klart" and MUST NOT queue the second job. The zone enforces a per-zone single-flight invariant.
- **FR-016**: A `.docx` that fails to parse (zip-level error, malformed XML, etc.) MUST surface the Swedish string "Kunde inte läsa dokumentet".
- **FR-017**: A password-protected `.docx` MUST be detected before any prompt is sent to the model and MUST surface the Swedish string "Dokumentet är lösenordsskyddat".
- **FR-018**: A `.docx` whose extracted text is empty (whitespace-only) MUST surface the Swedish string "Dokumentet innehåller ingen text".
- **FR-019**: Extracted text exceeding the model's safe-input window MUST be truncated at the first **24,000 UTF-8 characters** (a character-count proxy for ~6,000 English tokens; conservative for Swedish, deterministic, and decoupled from any specific tokenizer). The summary file MUST begin with a Swedish notice "(Dokumentet förkortades innan sammanfattning — endast början är sammanfattad.)" inserted *between* the FR-005a header and the model-body paragraphs. Silent truncation is forbidden. (Resolved during clarification 2026-05-27.)
- **FR-020**: A model failure (timeout, empty response, transport error) MUST surface the Swedish string "AI-motorn svarade inte — försök igen". No stack trace, no English fragment, no `Error:` prefix.
- **FR-021**: All user-visible copy in this feature MUST be Swedish, MUST avoid English fragments, MUST contain no `Error:` prefix, and MUST be ≤ 80 characters per error line. Copy is reviewed via the `humanizer` skill before shipping per CLAUDE.md.
- **FR-022**: The drop zone MUST be operable by screen readers — it is announced as a drop target, state transitions are announced via `aria-live="polite"`, and the disabled state is announced with the reason.
- **FR-023**: The drop zone MUST NOT initiate any outbound network call. The only outbound calls in the app remain (a) the auto-updater check and (b) the spec 002 model pull from `ollama.com`. A live-runtime `lsof` check during a drop MUST show only `127.0.0.1` connections.
- **FR-024**: The drop zone MUST keep the source file byte-identical — no modification, no write, no atime mutation beyond what reading the file requires.
- **FR-025**: The system MUST tolerate paths that contain spaces, accented characters, emoji, and the macOS NFD/NFC dual encodings without crashing or corrupting the sidecar filename.
- **FR-026**: While the zone is in the processing state, the system MUST present a Swedish "Avbryt" affordance (inside or adjacent to the spinner) that, when activated, aborts the in-flight model call. The affordance MUST be reachable by both mouse click and keyboard (focusable + Enter/Space).
- **FR-027**: Activating the cancel affordance MUST abort the inference request within 1 s of activation, MUST NOT write any sidecar `.docx` (canonical or timestamped), MUST flash the Swedish text "Sammanfattning avbruten" for ~1 s, and MUST return the zone to idle. The source file MUST remain byte-identical (SHA-256 unchanged).
- **FR-028**: If the model response arrives *after* the cancel signal was issued, the system MUST discard the response — no sidecar is written and no success state is entered. The cancel signal is a one-way decision.

### Key Entities

- **DropZone (UI)**: visible state (`idle | dragover | processing | success | error`), title ("Sammanfatta"), hint text, current job (Option). Wired to `useStatusStore` so the disabled gate is reactive.
- **DropJob**: source file path (PathBuf), extracted text length (usize, never the content), prompt-payload-bytes (Redacted), response-bytes (Redacted), sidecar output path, started/finished timestamps. Lives at most one at a time per drop zone.
- **SummaryDoc**: a `.docx` artifact with a fixed structure per FR-005a — a two-paragraph Swedish header (`Sammanfattning av '<name>'` + generation timestamp + model identifier), an optional truncation-notice paragraph per FR-019, a blank paragraph as separator, and the model's response as one or more body paragraphs. No metadata is copied from the source `.docx`; the sidecar is a clean new document.
- **ZoneStatus (existing)**: spec 002's `UserVisibleStatus` enum drives the zone's disabled gate. The mapping is `Klar → active`, everything else → `disabled`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From the moment the user drops a small (~5-page) `.docx` to the moment the sidecar file opens, the wall-clock time MUST be under 60 s on an M-series Mac with `gemma3:4b` already in memory.
- **SC-002**: For each of the seven Swedish error categories in FR-013 through FR-020, the user sees the right Swedish string within 3 s of the trigger event (drop / parse / model response).
- **SC-003**: 100% of summaries produced by this feature MUST be written to a sidecar `.docx` next to the source file. No summaries are sent over the network. Verified by a live-runtime `lsof` capture during a drop.
- **SC-004**: The original `.docx` MUST be byte-identical (matching SHA-256) before and after every drop, success or failure.
- **SC-005**: All visible state-machine transitions (idle → dragover, dragover → processing, processing → success, success → idle, processing → error, error → idle, drag-leave → idle) MUST be observable within 100 ms of the triggering event.
- **SC-006**: Across 10 consecutive successful drops on the same source file, the sidecar collision policy MUST produce 10 distinct files on disk (no overwrites). The first file uses the canonical `<stem>.sammanfatta.docx`; subsequent files use timestamp suffixes.
- **SC-007**: A user with VoiceOver enabled MUST hear (a) the drop zone announced as a drop target on focus, (b) the state transitions announced as they happen, (c) the disabled-with-reason announcement when the AI isn't ready.
- **SC-008**: Cancellation MUST take effect within 1 s of activation, measured wall-clock from the click/keypress to the zone re-entering idle. No sidecar file is created — verifiable by listing the source directory before vs after the cancellation.

## Assumptions

- Users have `.docx` files (Word's native modern format). Legacy `.doc`, `.rtf`, `.pages`, `.odt`, `.pdf`, `.txt`, `.md` are explicitly out of scope and arrive in spec 005 (or later, per the spec register).
- The default Ollama model is the spec 002 default `gemma3:4b`. Switching models is a spec 010 concern.
- The model's safe-input window is large enough for the common case (a ~5-page court ruling fits easily); long documents are truncated with a Swedish notice per FR-019.
- The user's macOS has a default `.docx` handler. If none is configured, the secondary "could not open" hint covers the case; users still get the file on disk.
- Filesystem paths are case-sensitive-or-insensitive depending on the volume; the sidecar naming and collision-detection logic MUST work identically on both.
- The drop zone is the only interactive surface in this spec. The remaining five zones (TillEngelska, TillSvenska, Punktlista, Anonymisera, Förenkla) arrive in spec 004, which extends the same state machine and reuses this spec's job pipeline.
- The system prompt for summarization is fixed for this spec (a single, project-curated Swedish prompt). User-configurable prompts arrive in spec 010 (settings panel).
- Cancellation mid-processing IS in scope for this spec — pulled in from the original spec 011 deferral during clarification (2026-05-27). See US5, FR-026/027/028, SC-008.
- The spec 002 one-retry sidecar recovery applies transparently — if the bundled Ollama crashes mid-summary, the retry happens under the hood and the user sees either a successful summary or the FR-020 "svarade inte" error.
