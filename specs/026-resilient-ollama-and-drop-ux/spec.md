# Feature Specification: Resilient Ollama coexistence + drop-zone affordances

**Feature Branch**: `026-resilient-ollama-and-drop-ux`

**Created**: 2026-05-29

**Status**: Draft

**Input**: User description: "Make JuraDrop work regardless of whether the user already runs their own Ollama, and fix the drop-zone interaction affordances (drag-over highlight, drop cursor, Välj fil clickability, startup window size)."

## Clarifications

### Session 2026-05-29

*(Auto-picked recommended answers per the project's clarify auto-pick policy; rationale in parentheses.)*

- Q: What exactly distinguishes a "usable local AI" (reuse it) from "port occupied by something else" (honest error)? → A: A successful `2xx` response to the standard Ollama readiness probe (`GET /api/tags`) within a short timeout (~2 s) means *usable → reuse*. Port bound but no `2xx` to that probe (non-Ollama listener, or an Ollama that won't answer) means *port-conflict → honest error*. (Reuses the exact reachability signal the app already trusts elsewhere; avoids inventing a new health check.)
- Q: When JuraDrop reused an externally-started AI, what happens to that AI on shutdown? → A: JuraDrop only stops an AI process it started itself (tracked via an "ownership" flag); a reused external AI is left running untouched. (Killing a process we didn't start would surprise the user and could break their other work — FR-006.)
- Q: Is the startup window size a hard value or a derived "fits 3×3" rule? → A: A hard default of **1160×760** logical points (comfortably past the 1024 three-column breakpoint); minimum-size and responsive reflow are unchanged. (Deterministic, already implemented, and testable as a fixed config value.)
- Q: When reusing an external AI, does the app verify the configured model is present at startup? → A: No — startup readiness is purely "the AI answers its probe"; a missing/incompatible model surfaces per-document through the existing honest-failure path, not as a startup hang. (Keeps startup fast and avoids coupling readiness to model state; matches the edge-case section.)
- Q: How is the port-conflict situation presented — blocking modal or a status state? → A: A non-blocking honest Swedish **status state** in the same family as the existing `fel_*` failure states (no crash, no stack trace, no modal). (Consistent with Principle VIII honest-failure handling already in the app.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The app works even when Ollama is already running (Priority: P1)

A law student installed Ollama earlier (Homebrew, the Ollama.app, or `ollama serve` in a terminal) for some other purpose. They launch JuraDrop. Because something already owns the local AI port, today JuraDrop ends up in a silently broken state: the header says the AI is ready, but every drop zone is inert — files can't be picked or dropped. The student has no idea why. This story makes JuraDrop **detect the already-running local AI and use it**, so the app is fully functional, or — if the port is held by something that is *not* a usable AI — tell the student plainly what's wrong instead of looking ready while doing nothing.

**Why this priority**: This is the core defect. The product's single promise — "drop a confidential document onto a zone and it gets processed locally" — is completely broken for any user who already runs Ollama, and it fails *silently* (the UI claims readiness). A silently broken core flow is worse than a crash. Everything else in this spec is cosmetic by comparison.

**Independent Test**: With a local AI already serving on the standard local port before launch, start JuraDrop and confirm all nine zones become interactive (a document can be processed end-to-end). Separately, occupy the port with a non-AI process and confirm JuraDrop shows an honest Swedish error rather than a "ready" header over dead zones.

**Acceptance Scenarios**:

1. **Given** a usable local AI is already serving on the standard local port, **When** JuraDrop launches, **Then** the app reaches a genuinely-ready state (header *and* every zone agree it is ready) and a dropped document is processed successfully.
2. **Given** no local AI is running, **When** JuraDrop launches, **Then** the app starts its own bundled AI as before and reaches the genuinely-ready state once that AI is serving.
3. **Given** the local port is occupied by a process that is not a usable AI, **When** JuraDrop launches, **Then** the app shows an honest Swedish error state explaining the port conflict, and does NOT present a "ready" header over disabled zones.
4. **Given** the app is in any non-ready state, **When** the user views the zones, **Then** the per-zone readiness and the global header convey the **same** readiness truth — they can never contradict each other.
5. **Given** the app reused an already-running local AI, **When** the app later shuts down, **Then** it does NOT terminate an AI process it did not start (it only stops a sidecar it launched itself).

---

### User Story 2 - Clear, responsive drop-zone feedback (Priority: P2)

When the student drags a document toward a zone, the zone should visibly respond — it lights up to confirm "drop here" — and the mouse cursor should show the drop is welcome, not a "forbidden" sign. As a keyboard/accessibility alternative, the per-zone "Välj fil" button must be clickable to open the native file picker whenever the app is genuinely ready.

**Why this priority**: Without hover feedback the drop target feels dead and users don't trust it; the forbidden cursor actively signals "this won't work." These are the visible symptoms users hit first, but they are only meaningful once US1 makes zones genuinely interactive (a highlight on a falsely-disabled zone helps no one).

**Independent Test**: With the app genuinely ready, drag a file over each zone and confirm it highlights and the cursor indicates an accepted drop; release and confirm the file is processed. Click "Välj fil" on a zone and confirm the native picker opens.

**Acceptance Scenarios**:

1. **Given** the app is ready, **When** the user drags a file over a zone, **Then** that zone (and only that zone) shows the drag-over highlight, and the highlight follows the cursor from zone to zone.
2. **Given** a file is being dragged over a zone, **When** the user looks at the cursor, **Then** it indicates an accepted drop (no "forbidden / one-way" icon).
3. **Given** the user drags off a zone or out of the window without dropping, **When** the drag ends, **Then** the highlight clears and no zone stays stuck lit.
4. **Given** the app is ready, **When** the user clicks "Välj fil" on a zone, **Then** the native file picker opens filtered to that zone's accepted formats; choosing a file processes it through the same path a drop uses.
5. **Given** the app is NOT ready, **When** the user attempts drag-over or "Välj fil", **Then** no highlight appears and the picker does not open (the zone is correctly inert and visibly so).

---

### User Story 3 - All nine zones visible at launch (Priority: P3)

When JuraDrop opens, the window is large enough that the full 3×3 grid of nine zones is visible without the user having to resize it.

**Why this priority**: A first impression issue — the app opened too small and showed a 2-column layout, forcing a manual resize every launch. Real but cosmetic, and independent of the readiness/affordance work.

**Independent Test**: Launch the app on a default-sized display and confirm all nine zones render in a 3×3 grid without resizing.

**Acceptance Scenarios**:

1. **Given** a fresh launch on a typical display, **When** the window appears, **Then** all nine zones are visible in a three-column grid.
2. **Given** the user shrinks the window below the three-column threshold, **When** the layout reflows, **Then** it still degrades gracefully to the responsive two-up / one-up layouts (existing behavior preserved).

---

### Edge Cases

- The already-running local AI responds on the port but is an **incompatible version** (cannot serve the configured model): the app should still reach a ready state for the readiness gate (it answers the readiness probe), and a per-document failure surfaces the model problem at process time via the existing honest-failure path — not a startup hang.
- The port is **free at launch but becomes occupied** between the readiness probe and the bundled-AI spawn (race): the app must resolve to a single consistent state (ready via whichever AI ends up serving, or the honest port-conflict error) — never a half-ready state.
- The already-running AI **stops mid-session**: the existing crash/auto-restart + honest-failure behavior applies; the app must not claim ready while no AI is reachable.
- A drag enters the window but is released **outside any zone**: nothing is processed and no highlight stays stuck.
- **Rapid zone-to-zone dragging**: only one zone is highlighted at a time; the previously-lit zone reverts.
- A drag-over arrives **before the app is ready**: no highlight (zones inert until genuinely ready).
- The window is opened on a **very small display** smaller than the requested startup size: the OS clamps the size; the responsive layout still applies.

## Requirements *(mandatory)*

### Functional Requirements

**Readiness & Ollama coexistence**

- **FR-001**: On startup the system MUST probe whether a usable local AI is already serving on the standard local AI port before attempting to start its own bundled AI.
- **FR-002**: If a usable local AI is already serving, the system MUST reuse that instance and MUST NOT attempt to start a second competing AI on the same port.
- **FR-003**: If no local AI is serving, the system MUST start its own bundled AI as it does today.
- **FR-004**: The system MUST reach a single, consistent "genuinely ready" state derived from one readiness truth; the global header readiness and the per-zone readiness gate MUST be driven by that same truth and MUST NOT be able to contradict each other.
- **FR-005**: If the standard local AI port is occupied by a process that does not answer the AI readiness probe, the system MUST present an honest Swedish error state describing the port conflict, and MUST NOT present a "ready" header over disabled zones.
- **FR-006**: The system MUST NOT terminate an AI process it did not itself start (reusing an external AI must not kill it on shutdown).
- **FR-007**: All AI communication MUST remain local-only (the standard loopback address); this feature MUST NOT introduce any remote-host configuration or any new outbound network traffic (Principle I + III).
- **FR-008**: Per-document failures (e.g., the reused AI lacks the model) MUST continue to surface through the existing honest Swedish failure path, not as a silent no-op or a startup hang.

**Drop-zone affordances**

- **FR-009**: While a file is dragged over a zone and the app is ready, that zone MUST display the drag-over highlight; only the zone under the cursor is highlighted at any moment.
- **FR-010**: The drag-over highlight MUST follow the cursor across zones (the previously-highlighted zone reverts when the cursor moves to another zone) and MUST clear when the drag leaves all zones, leaves the window, or a drop occurs.
- **FR-011**: While a file is dragged over the window, the operating-system cursor MUST indicate that the drop is accepted (no "forbidden / not-allowed" indicator).
- **FR-012**: The per-zone "Välj fil" control MUST be operable (open the native file picker) whenever the app is genuinely ready, and inert when it is not.
- **FR-013**: A drag-over or "Välj fil" attempt while the app is NOT ready MUST NOT highlight a zone or open the picker.

**Startup window**

- **FR-014**: On a fresh launch the default window size MUST be large enough to render all nine zones in a three-column grid without user resizing.
- **FR-015**: The existing responsive degradation to two-column / one-column layouts when the window is made smaller MUST be preserved.

### Key Entities *(include if feature involves data)*

- **Local AI readiness**: the single source of truth for whether the local AI is usable — either an externally-running AI was detected and reused, or the bundled AI was started and is serving. Carries an "ownership" notion (did we start it, or are we reusing an external one?) used to decide shutdown behavior. Feeds both the global header status and the per-zone disabled gate.
- **Zone interaction state**: per-zone visual/interaction state including the transient "drag-over" highlight, driven by which zone is under the cursor during an OS drag.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With a local AI already running before launch, 100% of the nine zones become interactive and a dropped document is processed end-to-end — no manual intervention, no resize, no quitting the other AI.
- **SC-002**: The global header readiness and per-zone readiness never disagree: in every reachable state there is zero contradiction between "header says ready" and "zones are usable."
- **SC-003**: When the port is held by a non-AI process, the user sees a clear Swedish explanation of the conflict within the normal startup window, instead of a "ready" header over dead zones.
- **SC-004**: During a drag, the zone under the cursor highlights and the cursor shows an accepted-drop indicator in 100% of drag-over attempts on a ready app; exactly one zone is highlighted at a time.
- **SC-005**: "Välj fil" opens the native picker on every attempt when the app is ready, and never when it is not.
- **SC-006**: On a fresh launch at the default display size, all nine zones are visible without resizing.
- **SC-007**: Reusing an external AI never terminates it: after JuraDrop quits, an externally-started AI is still running.
- **SC-008**: No new outbound network destinations are introduced; all AI traffic stays on the local loopback (verified against the telemetry/privacy denylist guards).

## Assumptions

- "Usable local AI" is determined by the AI answering its standard readiness probe on the standard local port — the same signal already used elsewhere in the app to consider the AI reachable.
- Reusing an external AI is acceptable for privacy because it is still a local-loopback process; the constitution's localhost-only constraint (Principle III) is satisfied and no remote override is added.
- The drag-over highlight reuses the existing per-zone "drag-over" visual styling already present in the design system; no new visual language is introduced.
- The startup window size only changes the default launch dimensions; minimum-size and responsive behavior are unchanged.
- The macOS drop cursor is governed by the windowing layer accepting the drag; "accepted-drop indicator" means the app's window registers as a valid drop target while dragging.
- Some implementation already exists uncommitted (the native drag-over event forwarding + a unit-tested drag-over tracker, and the larger default window size) and will be reconciled into this feature rather than rebuilt.
