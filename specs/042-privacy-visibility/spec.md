# Feature Specification: Privacy Visibility (make the local-only guarantee unmissable)

**Feature Branch**: `042-privacy-visibility`

**Created**: 2026-06-04

**Status**: Draft

**Input**: User description: "Make the local-only guarantee VISIBLE (field insight from beta tester Meja, user directive 2026-06-04: 'användaren ska vara väl medveten om att ingenting lämnar datorn — detta måste framgå tydligt'). The tester believed the AI fetches information from the internet. The guarantee is structurally true (CSP wall, localhost-only inference, Principle I) but INVISIBLE in the UI. Deliver: persistent UI affordance near the zone grid, reinforced first-run wizard copy, README/help section. Honest framing only. No new outbound anything; static UI + copy."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The main window itself answers "where does my document go?" (Priority: P1)

A law student looks at the main window before (or while) dropping a confidential document. Without opening any panel or reading any documentation, a short Swedish line near the zone grid tells them that documents are processed on this Mac and never leave it. Meja's exact failure ("the AI must be fetching things from the internet") becomes impossible to hold while looking at the app.

**Why this priority**: This is the user directive verbatim — the guarantee must be unmissable at the moment of use. Everything else in this spec is reinforcement.

**Independent Test**: Render the main window in the ready state and verify a persistent, always-visible privacy line exists near the grid, in natural Swedish, visible in both light and dark appearance, without displacing the twelve-zone grid.

**Acceptance Scenarios**:

1. **Given** the app is in the ready state (zones visible), **When** the user looks at the main window, **Then** a privacy affordance stating that documents are processed locally and never leave the computer is visible without any interaction.
2. **Given** any zone is processing, in error, or showing success, **When** the user looks at the window, **Then** the privacy affordance is still visible and unchanged (it is not a status indicator — it is a standing fact).
3. **Given** macOS switches between light and dark appearance, **Then** the affordance remains legible in both.
4. **Given** the window is at its default size, **Then** the twelve-zone grid, the instruction field, and the privacy affordance all fit without scrolling.

---

### User Story 2 - The first-run wizard explains WHY it works offline (Priority: P2)

A first-time user goes through the wizard. The download step explains that the app is downloading the AI model TO this Mac — once — and that this is exactly why documents never need to leave the machine afterwards. The mental model "local model on my disk" is planted before the first document is ever dropped, pre-empting Meja's "hur kan den generera text när den är lokal?" confusion.

**Why this priority**: The wizard is the one moment the app has the user's attention for explanation. The model download is also the one moment the app visibly uses the network — explaining it honestly there converts the most suspicious-looking moment into the proof of the privacy story.

**Independent Test**: Drive the wizard states and verify the welcome and download copy explain the local model and the one-time nature of the download.

**Acceptance Scenarios**:

1. **Given** the first-run wizard welcome screen, **Then** its copy states that processing happens on this Mac and nothing the user drops is sent anywhere.
2. **Given** the model download step, **Then** its copy explains the AI model is being downloaded to this Mac, once, and that the app works without internet after that.
3. **Given** a completed wizard, **When** the user later reinstalls or sees the wizard again, **Then** the same explanation appears (no state-dependent dilution).

---

### User Story 3 - Help and README carry the honest fine print (Priority: P3)

A skeptical user (or the friend they ask) wants the details: what network traffic DOES exist? The help panel and README state exactly: the one-time model download at install, the update check against the release service — neither carrying any document content — and that documents, custom instructions, and results never leave the machine.

**Why this priority**: Trust survives scrutiny only if the claim is precise. "No internet at all" would be false (model download, updater) and one discovered falsehood poisons the whole guarantee. The detailed surfaces carry the exact truth.

**Independent Test**: Open the help panel and read the README section; verify both enumerate the two non-content network uses and the never-leaves list, with consistent facts across all surfaces.

**Acceptance Scenarios**:

1. **Given** the help panel is open, **Then** a privacy entry states what never leaves the Mac (documents, instructions, results) AND names the only two network uses (one-time model download, update check), in Swedish.
2. **Given** the README, **Then** its privacy section makes the same claims with the same facts.
3. **Given** all four surfaces (badge, wizard, help, README), **Then** no surface contradicts another — same facts, appropriately sized for each surface.

---

### Edge Cases

- During the model download itself, the badge's "nothing leaves your computer" claim must coexist honestly with visible network activity → the claim is scoped to user content ("dokument lämnar aldrig din dator"), and the wizard download copy explains the download is the model coming TO the Mac. No surface claims "the app never uses the internet".
- The updater check runs in the background ~every 4 hours → same scoping; the help/README fine print names it.
- The spec-041 instruction field already promises "skickas bara till AI-modellen på din dator och sparas aldrig" → vocabulary must stay consistent (same "din dator" phrasing, no synonym drift between surfaces).
- Window real estate: the 1160×1000 window now holds WelcomeCard + instruction field + 3×4 grid; the affordance must be compact enough to fit without scroll at default size (US1 scenario 4).
- The badge must not look like a clickable control if it is not one — no false affordance.
- Screen reader users must encounter the privacy statement (it is content, not decoration).
- The badge is NOT a trust seal/certificate icon theater — plain honest text in the app's voice, no padlock-iconography arms race. (A small icon consistent with the design system is acceptable; the claim is the text.)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The main window MUST display a persistent privacy affordance near the zone grid, visible whenever the grid is visible, stating in Swedish that documents are processed on this Mac and never leave it.
- **FR-002**: The affordance MUST be static fact, not status: identical in idle/processing/success/error, with no state machine and no network dependency.
- **FR-003**: All privacy copy MUST be honestly scoped: claims concern user content (documents, custom instructions, results); no surface may claim the app never uses the network.
- **FR-004**: The first-run wizard welcome copy MUST state that processing happens locally on this Mac.
- **FR-005**: The wizard model-download copy MUST explain that the AI model is downloaded to this Mac once and the app then works without internet access.
- **FR-006**: The help panel MUST gain a privacy entry stating what never leaves the machine AND naming the only two network uses (one-time model download, update check), mirrored across the established three-way help-string surfaces.
- **FR-007**: The README privacy section MUST be updated to the same facts, consistent with the in-app copy.
- **FR-008**: All surfaces MUST use consistent vocabulary ("din dator"/"din Mac" consistently, no synonym drift), and MUST NOT contradict each other.
- **FR-009**: The feature MUST add zero network calls, zero new dependencies, zero behavioral changes — static UI and copy only.
- **FR-010**: The affordance MUST be accessible: screen-reader reachable as content, legible contrast in both appearances.
- **FR-011**: At the default window size, the grid, instruction field, and affordance MUST all fit without scrolling.
- **FR-012**: All new Swedish copy MUST pass the humanizer gate; the affordance UI MUST pass the frontend-design gate.

### Key Entities

- **Privacy affordance**: a static, always-rendered text element near the zone grid. No state, no persistence, no interaction (unless design review adds a link-to-help, which must look like what it is).
- **Copy set**: one fact base (what never leaves; the two network uses) rendered at four sizes: badge (one line), wizard (two short passages), help entry (short paragraph), README (section).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the zone grid visible, the privacy affordance is present in 100% of UI states (idle, processing, success, error, panels open) — verified by automated UI tests.
- **SC-002**: A first-time user encounters the local-processing explanation BEFORE the first document drop is possible (wizard precedes ready state by construction) — verified by wizard copy tests.
- **SC-003**: Zero new network destinations: the existing no-egress checks and CSP pins pass unchanged.
- **SC-004**: Fact consistency: automated checks pin that badge, help entry, and wizard copy share the agreed fact base (no surface claims "never uses internet"; all name user content as the never-leaves scope).
- **SC-005**: The affordance is discoverable without interaction and readable by assistive technology — verified by accessibility assertions in UI tests.
- **SC-006**: Qualitative (deferred to field): the next tester round does not reproduce Meja's "it must be fetching from the internet" belief. Tracked, not CI-gated.

## Assumptions

- **Placement: footer line under the zone grid** — the area was deliberately left free when the spec-041 instruction field took the above-grid slot. Final visual treatment is the frontend-design gate's call.
- **Not interactive by default**: a static line; if design review wants "läs mer" → it opens the existing help panel (no new surfaces).
- **The wizard copy is amended, not redesigned**: existing welcome/download screens gain/adjust sentences; no new wizard steps.
- **Help entry rides the established chrome-level help mechanism** introduced in spec 041 (`_instruction_help` pattern) — same three-way mirror discipline.
- **README "Privacy guarantees" section exists** and is updated in place; the stale nine-zone/3×3 README copy is a separate doc-fix, not this spec (noted in the register since 040).
- **No telemetry to measure SC-006** — by design (Principle I); it stays a field observation.
