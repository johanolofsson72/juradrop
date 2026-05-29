# Feature Specification: On-demand tier download

**Feature Branch**: `main` (solo, direct-push — no feature branch per spec-register workflow)

**Created**: 2026-05-29

**Status**: Draft

**Input**: User description: "Make the Settings panel 'Ladda ned' button actually download a model tier on demand (Snabb llama3.2:1b / Stor gemma3:12b) via streaming /api/pull, with progress, downloading/error/cancel states, and auto-flip to selectable on completion. Replaces the spec-010 emit-into-the-void stub."

## Clarifications

### Session 2026-05-29

- Q: How should download progress be displayed in the row? → A: Percent as the primary signal with a secondary human-readable size (e.g. "62 % · 5,0 / 8,1 GB"); fall back to an indeterminate "Laddar ned…" label when the pull stream does not report a total.
- Q: Must a download survive the settings panel being closed/reopened, and where does its state live? → A: Yes — the pull runs as a backend-owned background task keyed by tier; the panel subscribes to its progress and queries the current download state on open. The download is NOT tied to the panel's (or any component's) lifetime.
- Q: Can a tier download run while a document is being processed in a zone? → A: Yes — a download may run concurrently with document processing; Ollama serves the pull and inference independently. Inference may be slower while a large pull saturates bandwidth, but correctness is unaffected. (The one-at-a-time limit in FR-009 is download-vs-download only.)
- Q: Is there a limit on how many times a failed download can be retried? → A: No limit — retries are unlimited and always user-initiated (the **Försök igen** affordance). The system never retries automatically.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Download a model tier on demand (Priority: P1)

A law student opens **Inställningar → Modell**. Only the bundled **Smart** model is installed; **Snabb** and **Stor** show a **Ladda ned** button with their size. The student clicks **Ladda ned** on **Stor**. The row switches to a live progress state showing how far the download has come. When it finishes, the row turns into a selectable choice and the student can pick **Stor** as their model.

**Why this priority**: This is the entire feature. Without it the button is the dead stub it has been since spec 010 — clicking does nothing. Everything else (cancel, error recovery) only matters once the happy path works.

**Independent Test**: With the mock-Ollama test seam returning a streaming pull, click **Ladda ned** on an unpulled tier and assert the row transitions `not_pulled → downloading (progress visible) → radio_selectable`, and that the tier becomes selectable.

**Acceptance Scenarios**:

1. **Given** the Stor tier is not pulled and Ollama is ready, **When** the user clicks **Ladda ned** on Stor, **Then** the Stor row enters the downloading state and shows streaming progress (a percentage and/or a human-readable byte count).
2. **Given** a Stor download is in progress, **When** the pull stream reports completion, **Then** the Stor row becomes a selectable radio option and the underlying model is reported as pulled by the tier pull-state.
3. **Given** the Snabb tier just finished downloading, **When** the user selects it, **Then** Snabb becomes the active model tier (the existing `set_model_tier` gate accepts it because the model is now on disk).

---

### User Story 2 - Honest failure and retry (Priority: P2)

The student starts a **Stor** download (~8 GB) and the network drops, the disk fills up, or Ollama is not reachable. Instead of a silent hang or a leaked stack trace, the row shows a calm Swedish error explaining what went wrong, and offers to try again. Clicking **Försök igen** restarts the download.

**Why this priority**: Large downloads on student laptops over flaky wifi fail often. An honest failure state (Principle VIII) is what separates "robust" from "looks done in the demo". It is second only to the happy path because a feature that breaks silently on first real use is not shipped.

**Independent Test**: With the mock-Ollama seam injecting a mid-stream error (and separately a connection failure), assert the row enters the error state with the correct Swedish message and a retry affordance, and that retry re-enters the downloading state.

**Acceptance Scenarios**:

1. **Given** a download is in progress, **When** the pull stream errors mid-way (network drop), **Then** the row enters an error state with a Swedish message and a **Försök igen** affordance — no stack trace, no English.
2. **Given** a download fails because the disk is full, **When** the error surfaces, **Then** the Swedish message names the disk-full cause distinctly from a generic network failure.
3. **Given** a tier is in the error state, **When** the user clicks **Försök igen**, **Then** the row re-enters the downloading state and a fresh pull starts.
4. **Given** Ollama is not ready (still starting, or port-conflict from spec 026), **When** the user clicks **Ladda ned**, **Then** the row shows a Swedish "AI inte redo ännu" style message rather than starting a doomed pull.

---

### User Story 3 - Cancel an in-progress download (Priority: P3)

The student starts the **Stor** download, realises it is 8 GB and they are on mobile data, and clicks **Avbryt**. The download stops promptly, the row returns to the **Ladda ned** state, and no partial selection happens.

**Why this priority**: Cancellation is a quality-of-life and data-cost safeguard, not the core value. It reuses the spec 008 cancellation pattern, so it is cheap once the streaming path exists, but the feature delivers value without it.

**Independent Test**: With the mock-Ollama seam streaming slowly, click **Avbryt** mid-download and assert the row returns to `not_pulled` (the **Ladda ned** button) and the tier is not reported as pulled.

**Acceptance Scenarios**:

1. **Given** a download is in progress, **When** the user clicks **Avbryt**, **Then** the download stops and the row returns to the **Ladda ned** (not_pulled) state.
2. **Given** a download was cancelled, **When** the panel re-reads tier pull-state, **Then** the cancelled tier is reported as not pulled (a cancelled partial pull does not count as installed).

---

### Edge Cases

- **Concurrent download attempt**: while one tier is downloading, the other unpulled tier's **Ladda ned** is disabled (at most one concurrent download — see FR-009) so the single Ollama pull path is not contended.
- **Panel closed mid-download**: closing the settings panel (or reopening it) does not abort the download; on reopen the row reflects the still-in-progress download with current progress.
- **App already pulling the bundled model**: if the spec 008 first-run wizard is still pulling Smart, a tier download is refused with an "AI inte redo ännu" message until the bundled pull completes (no two pulls at once).
- **Selecting the tier mid-download**: the downloading row is not selectable; the radio does not appear until the pull completes.
- **Download completes while a different tier is active**: completion flips the row to selectable but does NOT silently change the active tier — selection stays an explicit user action (see FR-008; auto-select is out of scope, see Assumptions).
- **Pull reports model-not-found / invalid tag**: surfaces as a distinct Swedish error, retryable, no crash.
- **Progress stream reports total = 0 or missing**: the row shows an indeterminate "Laddar ned…" state rather than dividing by zero or showing a misleading percentage.
- **Repeated rapid clicks on Ladda ned**: a double/triple click starts exactly one download (idempotent within the downloading state).
- **Download running while a zone is processing a document**: both proceed; the download is not blocked by inference and inference is not blocked by the download (FR-015). Only a second *download* is blocked (FR-009).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST start a real model download for a tier when the user clicks **Ladda ned** on that tier's row, pulling the tier's specific model (Snabb → `llama3.2:1b`, Stor → `gemma3:12b`).
- **FR-002**: The download MUST go through the local Ollama instance only (`127.0.0.1:11434`), reusing the existing streaming pull mechanism — no new outbound endpoint, no remote-host override (Principle I + III).
- **FR-003**: While a tier is downloading, its row MUST display live progress derived from the pull stream — a percentage as the primary signal with a secondary human-readable size (e.g. "62 % · 5,0 / 8,1 GB"), falling back to an indeterminate "Laddar ned…" label when the stream reports no total.
- **FR-004**: Each tier MUST follow the state machine `not_pulled → downloading → pulled`, with `downloading → error` on failure and `downloading → not_pulled` on cancel; `error → downloading` on retry. `pulled` is terminal for the download concern (selection is governed by spec 010).
- **FR-005**: On successful completion, the tier MUST be reported as pulled by the tier pull-state and its row MUST become a selectable radio option without requiring a panel reload.
- **FR-006**: On failure, the row MUST show a Swedish, stack-trace-free message (Principle VIII) that distinguishes at minimum: network/stream failure, disk-full, Ollama-not-ready, and model-not-found/invalid causes.
- **FR-007**: A failed tier MUST offer a retry affordance (**Försök igen**) that restarts the pull from the `error` state. Retries are unlimited and always user-initiated; the system MUST NOT retry a failed download automatically.
- **FR-008**: A user MUST be able to cancel an in-progress download (**Avbryt**); cancelling returns the row to `not_pulled` and the tier MUST NOT be reported as pulled.
- **FR-009**: At most one tier download MUST run at a time; while one tier is downloading, the other unpulled tier's **Ladda ned** action MUST be disabled. This limit is download-vs-download only — it does NOT block document processing in a zone (see FR-015).
- **FR-010**: A tier download MUST be refused with an "AI inte redo ännu" style Swedish message when Ollama is not in a ready state (still starting, port-conflict, or the bundled first-run pull is still active).
- **FR-011**: The download MUST survive the settings panel being closed and reopened — the pull MUST run as a backend-owned background task that is NOT tied to the panel's (or any frontend component's) lifetime; closing the panel MUST NOT abort the download, and reopening MUST show the current download state/progress (subscribed live + queried on open).
- **FR-015**: A tier download MAY run concurrently with document processing in a zone; the system MUST NOT block a download on active inference nor block inference on an active download. Correctness MUST be unaffected (inference throughput may degrade while a large pull saturates bandwidth, which is acceptable).
- **FR-012**: The feature MUST reconcile the spec-010 stub: the dead `subscribeTierDownloadRequested` listener and the emit-only `trigger_tier_download` event MUST be either wired to drive the real pull or replaced by a direct streaming command — no dead event path may remain.
- **FR-013**: The download path MUST NOT log, transmit, or persist any document content (Principle I) — it concerns model files only; the only data crossing the wire is the model pull between Ollama and its registry.
- **FR-014**: All user-facing copy introduced by this feature (progress label, error messages, **Avbryt**, **Försök igen**, "AI inte redo ännu") MUST be Swedish (sv-SE) and pass the humanizer review.

### Key Entities *(include if feature involves data)*

- **TierDownload**: the in-progress (or failed) download of one model tier. Attributes: which tier, current phase (`downloading`/`error`/done), progress (completed/total bytes or percent, possibly indeterminate), and on failure a categorised reason (network, disk-full, not-ready, not-found). At most one exists at a time.
- **ModelTier** (existing, spec 010): Snabb / Smart / Stor, each mapping to an Ollama model id. This feature adds the on-demand acquisition path for the non-bundled tiers.
- **TierPullState** (existing, spec 010): per-tier pulled/not-pulled truth that drives whether a row is a radio or a download button. This feature drives transitions into the pulled state and consumes it to flip the row.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can install a non-bundled model tier entirely from within the Settings panel — from clicking **Ladda ned** to the tier becoming selectable — with zero use of the Terminal or any external tool.
- **SC-002**: During a download the user always sees movement: progress updates are reflected in the row at least once per second while the pull stream is producing data (no frozen-looking UI).
- **SC-003**: 100% of the four failure categories (network, disk-full, not-ready, not-found) produce a distinct, Swedish, stack-trace-free message, verified by test.
- **SC-004**: A cancelled download leaves the tier reported as not-pulled in 100% of cancel cases (a partial download never masquerades as installed).
- **SC-005**: Starting a tier download never starts a second concurrent pull — at most one download is active at any time, verified by test.

## Assumptions

- **Auto-select is out of scope**: completing a download flips the row to selectable but does NOT automatically switch the active model tier; selection remains an explicit, separate user action (keeps the completion behaviour unsurprising and avoids changing the active model behind the user's back). This narrows requirement 4 of the user's note ("optionally auto-select").
- **One download at a time** (FR-009) is chosen over concurrent multi-tier downloads: the app drives a single local Ollama, large pulls are I/O- and bandwidth-bound, and serialising avoids contention and confusing dual-progress UI. This resolves the user note's "or define concurrent behavior".
- **Resume semantics**: "retry" means starting the pull again, not byte-range resume. Ollama's pull is itself layer-cached, so a retry after a partial pull re-uses already-fetched layers — good-enough resume without app-level range tracking.
- The existing streaming pull client (used by the spec 008 first-run wizard) and its cancellation token are reusable and can be parameterised by an arbitrary model id rather than the hardcoded bundled model.
- The model-pull traffic between Ollama and its registry is the same traffic the constitution already permits as "the initial Ollama model download" — this feature does not introduce a new category of outbound traffic, it lets the user trigger the already-permitted kind for additional models.
- Tier → model id mapping is the existing spec-010 mapping (Snabb `llama3.2:1b`, Stor `gemma3:12b`); this spec does not change it.
- The model sizes shown in the UI (~1.3 GB Snabb, ~8.1 GB Stor) are the existing spec-010 display strings and are not recomputed by this feature.
