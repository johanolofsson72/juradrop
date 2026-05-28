# Feature Specification: First-run wizard (welcome → consent → model download → ready)

**Feature Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`)

**Created**: 2026-05-28

**Status**: Draft

**Input**: User description: Spec 002 wired the Ollama sidecar, the consent record, and the model pull task, but the user-facing first-launch path is bare — a `WelcomeCard` says "Startar AI…" while the sidecar boots, the consent modal pops once, the download fires, and the six drop zones are visible but technically usable in the brief idle moments before the model is ready. Spec 008 makes the first-launch path explicit and welcoming: a Swedish welcome screen explains what JuraDrop is and what it's about to do, the existing consent modal confirms the model download, a proper progress UI (percent + bytes + ETA + Cancel) replaces the placeholder "Startar AI…" copy, the six drop zones stay gated behind `model_status === 'ready'` so a too-eager user can't drop a document during the model pull, and the network-drop-resume case shows honest Swedish copy instead of disappearing. Subsequent launches skip the welcome and go straight to the zones. No new outbound surface — every piece is exercising spec 002's existing sidecar + consent + pull machinery through a friendlier UI.

## Clarifications

### Session 2026-05-28 (auto-picked recommendations per `.claude/settings.json`)

- Q: What is the actual Swedish welcome paragraph copy that the spec FR-002 + FR-014 will assert against? The paragraph needs to exist at spec time so the cross-language drift test (SC-006) has something concrete to pin. → A: **Title "Välkommen till JuraDrop"; body paragraph "JuraDrop läser dokument lokalt på din Mac och hjälper dig sammanfatta, översätta, anonymisera, punktlista och förenkla juridisk text — utan att något skickas till någon molntjänst."; privacy line "Inget dokumentinnehåll lämnar din Mac."; download note "En AI-modell på cirka 2 GB laddas ner första gången du startar appen — efter det fungerar allt utan nät."** Body paragraph is 199 chars (≤ 200 char invariant from FR-014). Each line is independently translatable + each line passes the SwedishCopy invariants. The paragraph names the six zone verbs (sammanfatta/översätta/anonymisera/punktlista/förenkla) so the welcome screen serves double duty as a feature preview.

- Q: ETA formatting threshold — when does the progress UI switch from "≈ X s" to "≈ Y min"? FR-004 lists both formats but doesn't say where the boundary is. → A: **Threshold at 60 s. `remaining_seconds < 60` → "≈ X s" (with X rounded UP to the nearest 5 s so the value doesn't twitch on every progress tick); `remaining_seconds ≥ 60` → "≈ Y min" (with Y rounded UP to the nearest minute, never showing decimals).** When `bytes_per_second_recent == 0` (waiting on network), the ETA reads "—" instead of a misleading value. The 5-second / 1-minute rounding ceiling prevents the ETA from looking jittery without forcing a Math.floor that would show "0 s remaining" for a non-trivial download.

- Q: Wizard layout — full-screen modal overlay (zones not rendered) OR center-aligned panel (zones rendered behind, visually disabled)? FR-005 + the US1 acceptance scenarios are contradictory on this. → A: **Full-screen modal-style overlay during welcome AND progress phases. The six zones are NOT rendered in the React tree while the wizard is mounted — App.tsx renders either `<Wizard />` OR the `<ZoneGrid />`, never both at the same time.** This matches the load-bearing UX bet (first-launch trust): the user's full attention should be on the wizard until the model is ready. FR-005's "visually disabled zones" wording is corrected — the zones are simply absent during the wizard, which is stronger than "disabled". This also avoids the focus-trap + tab-order ambiguity that would otherwise force the wizard to manage z-index + pointer-events overrides for zones that shouldn't be tab-targets in the first place.

- Q: What does the welcome screen show during the sidecar-boot gap (sidecar transitions Starting → Ready) where consent is `not_asked` but the model status is still `not_present` because the sidecar's `list_tags` hasn't returned yet? → A: **The welcome screen renders immediately with the title + body paragraph + privacy line + download note, but the Fortsätt button is disabled (greyed out, non-clickable, no tooltip) until `sidecar.status === 'ready'`. The Avbryt button is always enabled.** A small italic helper line below the buttons reads "Förbereder AI-motorn…" while the sidecar boots; it disappears the instant the sidecar reaches Ready. This matches the existing spec 002 disabled-gate pattern (zones are disabled until sidecar is ready) so the welcome screen feels consistent with how the zones behave later. Total boot window is typically ≤ 5 s per spec 002.

- Q: Cancel-race — the user clicks Cancel at the exact moment the pull task surfaces `Completed`. Which side wins, and what is the user-visible result? → A: **The existing `model_status === 'downloading'` idempotency gate from spec 002 governs: if the pull task has already emitted `Completed` (model_status flipped to `ready`) before the `cancel_model_pull` command reaches the lock, the command is a silent no-op and the wizard transitions normally to the post-ready state.** The wizard never "uncompletes" a finished download. If the cancel command wins the race (lock acquired BEFORE the completed event is processed), the download is cancelled normally and the wizard transitions back to the welcome screen — the few bytes between cancel-acquire and would-have-been-completed are dropped. Either outcome is internally consistent; the user sees one of the two states, never a flickering intermediate.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Fresh install: welcome → consent → progress → ready (Priority: P1)

A Swedish law student double-clicks the freshly downloaded `JuraDrop.app` for the first time. The app launches, the sidecar starts in the background, and the main window shows a Swedish welcome screen: app name, one-paragraph plain-Swedish explanation of what JuraDrop does, an explicit privacy reassurance ("inget dokumentinnehåll lämnar din Mac"), and a note that an AI model (~2 GB) needs to download before the zones become usable. The student clicks "Fortsätt", which fires the existing consent flow; the welcome screen transitions into a progress UI showing "Hämtar AI-modell… 17 %" with a byte counter and an estimated time remaining. The six drop zones are visible behind the wizard but visually disabled (greyed out, non-interactive). After ~3 minutes (depending on connection), the progress completes; the wizard slides away and the zones become usable. The student drags their first court ruling onto Sammanfatta.

**Why this priority**: This is the first moment of trust. A bare-window experience that says "Startar AI…" with no context for a 2-minute download is the most-cited reason novice users abandon local-AI apps in the first 30 seconds. Replacing that with a friendly, honest, Swedish-localised welcome that explains the wait + reinforces the privacy contract is the load-bearing UX bet of the spec.

**Independent Test**: Wipe `~/Library/Application Support/se.juradrop` to simulate a fresh install. Launch JuraDrop. Confirm: (a) the welcome screen appears with the title, body paragraph, privacy line, and Fortsätt/Avbryt buttons; (b) clicking Fortsätt fires the existing consent flow and transitions to the progress UI; (c) the progress UI shows percent + bytes + ETA + Cancel; (d) the six zones are visible but disabled (no hover state, drop is rejected); (e) on completion the wizard disappears and zones become drop-targets.

**Acceptance Scenarios**:

1. **Given** the consent record file does not exist (fresh install), **When** the user launches JuraDrop, **Then** the welcome screen appears with the JuraDrop title, one Swedish paragraph explaining the app, an explicit privacy line, and the two CTAs Fortsätt + Avbryt; the six drop zones are NOT visible (the wizard covers them).

2. **Given** the welcome screen is visible, **When** the user clicks Fortsätt, **Then** the existing `give_consent` Tauri command fires, the consent record is persisted with `choice = fortsatt`, the welcome screen transitions to the progress UI, and the model pull task starts.

3. **Given** the progress UI is active, **When** the model pull task emits a progress event, **Then** the percent bar updates, the byte counter reads "X MB av Y MB" in Swedish formatting (space thousands separator), and the ETA reads "≈ X min" or "≈ Y s" based on the remaining bytes / average bytes-per-second over the last 10 s.

4. **Given** the progress UI is active and the model pull task completes, **When** the `model_status` transitions to `ready`, **Then** the progress UI dismisses (fade-out, ~300 ms), the six drop zones become drop-targets, and any user interaction on the zones is from that moment processed normally.

5. **Given** the wizard is in any state (welcome OR progress), **When** the user looks at the six drop zones, **Then** they are visible (partially behind the wizard if the layout has overlap) but visually disabled — no hover state, no drop affordance, and a drop attempt is silently rejected.

---

### User Story 2 — Subsequent launches: skip the welcome (Priority: P1)

The same student launches JuraDrop the next morning. The model is already on disk, the consent record is `fortsatt`. The welcome screen MUST NOT appear — the student sees the six zones immediately, with the brief sidecar-boot status ("Startar AI…") in the welcome card slot as today. Within ~5 seconds the sidecar reaches ready and the zones unlock.

**Why this priority**: Showing the welcome screen on every launch would be a hostile UX. The first-launch contract is "explain once, get out of the way". Same priority as US1 because skipping the welcome is the inverse half of the same feature — the wizard is fundamentally a one-shot affordance.

**Independent Test**: With a populated consent record + a ready model, quit and relaunch JuraDrop. Confirm: (a) the welcome screen does NOT appear at any point; (b) the six zones are visible from the first paint (with the sidecar-boot status overlay where applicable); (c) the existing `WelcomeCard` "Startar AI…" / "Klar" flow runs as before.

**Acceptance Scenarios**:

1. **Given** the consent record exists with `choice = fortsatt` AND the model is on disk (`model_status = ready` after sidecar boot), **When** the user launches JuraDrop, **Then** the welcome screen is NOT rendered; the six zones are visible from the first paint.

2. **Given** the consent record exists with `choice = fortsatt` AND the model is missing (the user deleted the model file out-of-band, or the previous launch's Cancel left the state in `model_missing_aborted`), **When** the user launches JuraDrop, **Then** the welcome screen DOES re-appear so the user can re-consent and re-download.

3. **Given** the consent record exists with `choice = avbryt` (the user previously cancelled at the consent modal), **When** the user launches JuraDrop, **Then** the welcome screen re-appears with the same copy as the first-launch case — the user is given another chance to opt in.

---

### User Story 3 — Network drop during model download → resume (Priority: P2)

The student starts the download on a flaky WiFi. After ~30 % the connection drops. The progress UI doesn't disappear; instead it shows "Väntar på nätverk…" with the percent frozen at the last received value. When the connection returns ~45 seconds later, the pull task resumes from where it left off (Ollama's pull is idempotent + content-hash-addressed), the "Väntar på nätverk…" copy switches back to the live progress, and the byte counter resumes climbing.

**Why this priority**: Network drops are a top-three cause of first-run failure on flaky home/cafe WiFi. A progress UI that disappears or errors out on every dropout would force the student to restart the whole download — frustrating and confusing. Resuming transparently is honest and matches Ollama's actual behavior.

**Independent Test**: Start a fresh install. Begin the download. After ~10 s, disable the network. Wait ~15 s. Re-enable the network. Confirm: (a) when the network drops, the progress UI shows "Väntar på nätverk…" and the percent freezes; (b) when the network returns, the progress UI returns to live progress within ~5 s and the byte counter resumes from where it stopped (not from 0).

**Acceptance Scenarios**:

1. **Given** the model pull task is in flight at percent X, **When** the network drops (the next chunk read errors with a connection/timeout failure), **Then** the progress UI keeps showing the current percent + last byte count but the label changes to "Väntar på nätverk…"; no error message appears; the underlying pull task does not terminate (it's the existing manager's auto-retry loop).

2. **Given** the progress UI is showing "Väntar på nätverk…", **When** the network returns and the next chunk arrives, **Then** the label returns to "Hämtar AI-modell…" + the live percent within ~5 s, and the byte counter resumes climbing from the last received byte (no restart-from-0).

3. **Given** the network has been down for ≥ 5 minutes continuously, **When** the pull task surfaces a `download_failed` event, **Then** the progress UI transitions to a recovery state with the existing Swedish copy "Modellnedladdningen avbröts — försök igen" and a "Försök igen" button that re-invokes the pull task.

---

### User Story 4 — User cancels mid-download (Priority: P2)

The student clicks Fortsätt, the progress UI appears, and ~5 seconds into the download they realise they need to switch network. They click Cancel. The pull task aborts cleanly, the progress UI dismisses, and the welcome screen comes back. The consent record is reset (or marked aborted) so the next launch shows the welcome again. The partially downloaded model bytes are deleted by Ollama's own cleanup.

**Why this priority**: The Cancel button is essential — users will want to abort if they realise they're on cellular, if the ETA is too long, or for any other reason. The deferred cleanup + welcome-re-display contract is straightforward but easy to get wrong (e.g. leaving the consent record as `fortsatt` while no model exists would make every subsequent launch attempt an immediate retry, which is hostile).

**Independent Test**: Fresh install. Click Fortsätt, wait until percent ≥ 5 %, click Cancel. Confirm: (a) the pull task aborts; (b) the progress UI dismisses; (c) the welcome screen re-appears; (d) on next launch the welcome appears again; (e) the partially downloaded model file is gone.

**Acceptance Scenarios**:

1. **Given** the progress UI is active during a model pull, **When** the user clicks Cancel, **Then** the pull task is aborted (HTTP stream dropped + tokio cancellation token tripped), the `model_status` flips to `model_missing_aborted`, and the progress UI dismisses.

2. **Given** the user has cancelled mid-download, **When** the welcome screen reappears, **Then** it shows the same copy as the first-launch case; clicking Fortsätt again fires a fresh consent flow + pull task; the byte counter starts from 0 (we don't try to resume across a Cancel because Ollama discards partial chunks on close).

3. **Given** the user cancelled in a prior session, **When** they re-launch JuraDrop, **Then** the welcome screen appears (because `model_missing_aborted` is the visible status); clicking Fortsätt restarts the pull from 0.

---

### User Story 5 — User clicks Avbryt on the welcome screen (Priority: P3)

The student opens JuraDrop, reads the welcome screen, but isn't ready to download a 2 GB model right now. They click Avbryt. The welcome screen does NOT disappear — the app stays in a "consent needed" state and the welcome screen continues to show. The student can quit the app from the macOS app menu (⌘Q). On the next launch the welcome screen appears again. No download starts.

**Why this priority**: The Avbryt path is a quiet refusal: the user didn't say no forever, they said not right now. Keeping the welcome visible (instead of quitting the app or showing a blank window) gives them the option to change their mind without restarting. This is the lowest-priority story because most users will either Fortsätt or quit outright.

**Independent Test**: Fresh install. Click Avbryt on the welcome screen. Confirm: (a) the welcome screen stays visible (it doesn't close or transition); (b) the zones remain disabled (no model); (c) ⌘Q quits the app cleanly; (d) re-launching the app shows the welcome again.

**Acceptance Scenarios**:

1. **Given** the welcome screen is visible, **When** the user clicks Avbryt, **Then** the `cancel_consent` Tauri command fires, the consent record is persisted with `choice = avbryt`, and the welcome screen stays visible (no transition, no quit).

2. **Given** the user clicked Avbryt and the welcome stays visible, **When** they later click Fortsätt, **Then** the normal consent + download flow proceeds as if Avbryt had never happened (the consent record is overwritten with `choice = fortsatt`).

3. **Given** the user clicked Avbryt and quits the app via ⌘Q, **When** they re-launch JuraDrop, **Then** the welcome screen appears again with the same copy.

---

### Edge Cases

- **Consent record file is corrupt JSON**: the consent loader's existing fallback (treat as `not_asked`) kicks in; the welcome screen appears. Documented behavior from spec 002.
- **Disk full during model pull**: the existing `FelDiskFull` visible status fires; the progress UI transitions to an error state with the Swedish copy "Inte tillräckligt med diskutrymme — frigör minst 4 GB". The wizard does not auto-retry.
- **User triple-clicks Fortsätt**: the existing spec 002 idempotency gate ensures only one pull task runs (`model_status === 'downloading'` blocks a second start).
- **Welcome screen + system appearance change**: the wizard reads `prefers-color-scheme` like the rest of the app; light/dark are honored without a re-render.
- **Welcome screen Tab order**: Fortsätt is the primary action (focusable first, Enter activates); Avbryt second; the close-window button is the macOS standard chrome (not part of the wizard).
- **Welcome screen Escape key**: pressing Escape on the welcome triggers Avbryt (matches macOS modal convention) — the welcome stays visible but the consent record records the negative choice.
- **Window resize during the wizard**: the wizard is centered + responsive; on very narrow widths (< 480 px) the body paragraph wraps without truncation.
- **Model pull completes in < 2 seconds (cached on a previous run, or the user is on a gigabit fiber link)**: the progress UI may flash briefly; the wizard transitions out cleanly without a stutter (the ≥ 300 ms minimum-visible time prevents flicker).
- **Sidecar crashes during the model pull**: the existing spec 002 retry path (one auto-respawn) fires; the wizard remains in the progress state during the retry; if the second spawn fails, the wizard shows the Swedish "AI-motorn kunde inte starta" error from the existing `UserVisibleStatus`.
- **User force-quits the app mid-download**: on next launch the welcome re-appears (the consent record stays `fortsatt` BUT the model is missing — the wizard treats this as a resume case and shows the welcome again, NOT a silent auto-resume, because we can't know if the user wanted to abort).
- **Localization regression test**: the welcome copy MUST satisfy the same `SwedishCopy` invariants from spec 003 — every visible string ≤ 200 chars, no `Error:` prefix, non-empty.
- **Accessibility: VoiceOver reads the welcome paragraph**: the body paragraph is wrapped in a `<p>` with `aria-live="polite"` so a screen-reader user hears the welcome on first paint.
- **Welcome screen + app launched via "Open at Login"**: same flow as a normal first launch — the wizard appears, the user reads it, the download proceeds.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** (welcome trigger): On every launch, the React layer MUST check the consent record + model status. The welcome screen MUST appear when `consent.choice ∈ {not_asked, avbryt}` OR `model_status ∈ {not_present, download_failed, model_missing_aborted}`. Otherwise the welcome MUST NOT appear and the six zones render directly.

- **FR-002** (welcome content): The welcome screen MUST contain, in Swedish, the following exact strings (clarified 2026-05-28):
  - **Title** — `Välkommen till JuraDrop`
  - **Body** — `JuraDrop läser dokument lokalt på din Mac och hjälper dig sammanfatta, översätta, anonymisera, punktlista och förenkla juridisk text — utan att något skickas till någon molntjänst.`
  - **Privacy line** — `Inget dokumentinnehåll lämnar din Mac.`
  - **Download note** — `En AI-modell på cirka 2 GB laddas ner första gången du startar appen — efter det fungerar allt utan nät.`
  - **Primary CTA** — `Fortsätt`
  - **Secondary CTA** — `Avbryt`
  - **Sidecar-boot helper** (visible only while `sidecar.status !== 'ready'`) — `Förbereder AI-motorn…`

- **FR-003** (consent wiring): Clicking Fortsätt MUST invoke the existing `give_consent` Tauri command (no new command); clicking Avbryt MUST invoke the existing `cancel_consent` command. The wizard MUST react to the resulting `juradrop://status` event to transition into the progress UI (on Fortsätt) or stay on the welcome (on Avbryt).

- **FR-004** (progress UI components): The progress UI MUST display (a) a percent bar visualising 0–100; (b) a byte counter in Swedish formatting ("X MB av Y MB" with thin-space thousands separator); (c) an ETA computed over the last 10 seconds of throughput, formatted per the threshold below; (d) a Cancel button that fires a new `cancel_model_pull` Tauri command (defined under FR-013).
  - **ETA formatting** (clarified 2026-05-28): `remaining_seconds < 60` → `"≈ X s"` where X is `ceil(remaining_seconds / 5) * 5` (rounded UP to the nearest 5 seconds). `remaining_seconds ≥ 60` → `"≈ Y min"` where Y is `ceil(remaining_seconds / 60)` (rounded UP to the nearest minute). When `bytes_per_second_recent == 0` (no progress in the last 10 s), the ETA reads `"—"` instead of a misleading value.

- **FR-005** (zone gating, clarified 2026-05-28): While the wizard is visible (welcome OR progress states), the six drop zones MUST NOT be rendered in the React tree at all. App.tsx renders either `<Wizard />` OR the `<ZoneGrid />`, never both. The gating predicate is `wizardState !== 'hidden'`. Zones MUST become drop-targets within ~300 ms of the model status transitioning to `ready` AND the wizard transitioning out (fade-out completes).

- **FR-006** (subsequent launch skip): When `consent.choice === fortsatt` AND `model_status === 'ready'` (or the sidecar is mid-bootstrap and the model file exists on disk), the wizard MUST NOT render at all; the six zones render directly. The brief sidecar-boot overlay ("Startar AI…") from the existing `WelcomeCard` covers the boot window as today.

- **FR-007** (network drop detection): When the model pull is in flight AND `model_status` transitions from `downloading` to a transient-error proxy (the existing manager's retry signal), the progress UI MUST switch the label from "Hämtar AI-modell…" to "Väntar på nätverk…" while keeping the percent and byte counter frozen at their last known values. When the next progress event arrives, the label MUST switch back. The transient-error proxy is the absence of progress events for ≥ 5 seconds while `model_status === 'downloading'`.

- **FR-008** (resume on network return): When the pull task surfaces a progress event after a "Väntar på nätverk…" period, the byte counter MUST resume from the last received value (NOT from 0). Ollama's pull is content-hash-addressed and idempotent; the wizard must trust the manager's resume semantics without reimplementing them.

- **FR-009** (terminal failure): If the model pull surfaces a `download_failed` event (≥ 5 min continuous failure, or `MODEL_PULL_TIMEOUT_SECONDS` elapsed), the progress UI MUST transition to an error state with the existing Swedish copy "Modellnedladdningen avbröts — försök igen" and a "Försök igen" button that re-invokes the existing `give_consent` command (which the existing spec 002 path treats as a retry trigger).

- **FR-010** (cancel during download): Clicking Cancel in the progress UI MUST invoke the new `cancel_model_pull` Tauri command which (a) drops the in-flight HTTP stream via the existing tokio cancellation token; (b) flips `model_status` to `model_missing_aborted`; (c) emits the corresponding `juradrop://status` event so the wizard transitions back to the welcome screen. Partially downloaded bytes are cleaned up by Ollama on close.

- **FR-011** (cancel during welcome): Clicking Avbryt on the welcome screen MUST invoke the existing `cancel_consent` command. The welcome screen MUST remain visible afterwards — no transition, no app quit. The Escape key MUST also fire Avbryt (macOS modal convention).

- **FR-012** (re-show on next launch after cancel): If the consent record is `avbryt` OR the model status is `model_missing_aborted` at launch time, the wizard MUST re-appear (same copy as the first-launch case). The user can change their mind any number of times across launches.

- **FR-013** (`cancel_model_pull` command): A new Tauri command MUST be added that drops the in-flight model pull, trips the cancellation token, and persists a `model_missing_aborted` visible status. The command is a no-op if no pull is in flight. The command MUST NOT alter the consent record — only Cancel from the progress UI hits this, and the consent record's truth is "the user wanted to install but cancelled mid-way", which the next launch surfaces as the welcome re-appearing.
  - **Cancel-race semantics** (clarified 2026-05-28): If `model_status === 'ready'` at the moment the command acquires the write-lock, the command is a silent no-op (returns `Ok(())` without touching state). The wizard never "uncompletes" a finished download. If the cancel command wins the race (acquires the lock BEFORE the pull task's `Completed` event is processed), the download is cancelled normally and the wizard transitions back to welcome.

- **FR-014** (Swedish copy invariants, refined 2026-05-28 per /speckit.analyze finding C1): Every visible string introduced by spec 008 MUST satisfy the SwedishCopy invariants from spec 003 — non-empty, no English `Error:` prefix. The two long-form welcome strings (`welcome_paragraph` and `welcome_download_note`) are capped at 200 chars; every other key stays ≤ 80 chars. The download note IS long-form expectation-setting copy and needs the same headroom as the paragraph.

- **FR-015** (no new outbound surface): Spec 008 MUST NOT introduce any new outbound network call. The model pull goes through `OllamaClient.pull` (existing spec 002 surface); the consent record is local; the welcome screen and progress UI fetch nothing.

- **FR-016** (privacy-preserving logs): No log line emitted by spec 008 MAY contain document content, IP, system username, or model bytes. Logs are limited to state transitions ("wizard: welcome → progress", "wizard: progress(67%) → ready"). FR-015 from spec 007 generalises to all wizard logging.

- **FR-017** (focus management): On wizard mount, the Fortsätt button MUST receive focus (so Enter immediately activates it). Tab order: Fortsätt → Avbryt → wraps. Escape on the welcome triggers Avbryt; Escape on the progress UI triggers Cancel.

- **FR-018** (single-instance wizard): The wizard MUST be rendered at most once in the React tree. Mounting it twice would race the focus management and the `useStatusStore` subscription. The wizard component MUST be conditionally rendered from `App.tsx`'s root render, not from a child.

- **FR-019** (animation timing): The wizard MUST be visible for ≥ 300 ms even if the model pull would complete instantly (e.g. on a cached install). This minimum-visible window prevents the flicker that would otherwise happen when the wizard mounts + dismounts in < 100 ms.

### Key Entities

- **WizardState** (UI-only, lives in the React layer): `phase ∈ {welcome, progress, error, hidden}` derived from `(consent.choice, model_status, pull_progress)`. The wizard's visible phase is a pure function of the existing AppStatus snapshot — no new persistent state in Rust.
- **ProgressEstimate** (UI-only): `last_pct: u8`, `last_byte_count: u64`, `last_progress_at: Date`, `bytes_per_second_recent: f64`. Used to compute the ETA + the "Väntar på nätverk…" trigger client-side without a new Rust event channel.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** (first-launch trust): On a fresh install (consent record absent), the welcome screen renders within 800 ms of the WebView mounting. Verified by a Playwright timing assertion against the built app.
- **SC-002** (subsequent-launch silence): On a launch with `consent = fortsatt` + `model_status = ready`, the welcome screen is never rendered. Verified by a vitest assertion: `useWizardState({ consent: fortsatt, model: ready })` returns `hidden`.
- **SC-003** (zone gating coverage): While the wizard is in welcome OR progress phase, every drag-drop attempt on the six zones is silently rejected. Verified by a Playwright destructive test: drag a fixture .docx onto Sammanfatta during the progress UI; assert no sidecar file is written.
- **SC-004** (network drop recovery): A simulated 30 s network drop mid-download (vitest fake-timer or test harness) results in the progress UI showing "Väntar på nätverk…" within 5 s of the drop, and returning to live progress within 5 s of the next chunk. Verified by an integration test driving the manager directly.
- **SC-005** (cancel cleanup): After Cancel mid-download, the next launch shows the welcome screen and the previously partial model bytes are absent from `~/Library/Application Support/se.juradrop/models/`. Verified by an integration test.
- **SC-006** (welcome copy Swedish invariants): Every welcome / progress / error string passes the SwedishCopy invariants. Verified by a vitest cross-language drift test against a new `wizard-strings.json` fixture.
- **SC-007** (no new outbound surface): The static grep audit for new HTTP client / WebSocket / net::TcpStream usage produces zero new matches outside spec 002's sidecar files. Verified by extending the spec 007 `update_invariants.rs::updater_introduces_no_new_outbound_surface` test (or a new sibling).
- **SC-008** (accessibility): The welcome paragraph is announced by VoiceOver on first paint. Verified manually on a real Mac (real-hardware verification item).

## Assumptions

- Users have a stable enough internet connection to complete the ~2 GB download within ~10 minutes. The wizard does not implement a "low-bandwidth mode" or a partial download cap.
- The consent record file format from spec 002 is the source of truth for `consent.choice`; no new JSON file or schema migration is needed.
- The existing `juradrop://status` event already carries `consent.choice` + `model_status` + `progress_percent` — spec 008 reads them via the existing `useStatusStore`.
- Ollama's pull is idempotent + content-hash-addressed (verified in spec 002 contract notes); the wizard relies on Ollama's resume semantics rather than reimplementing chunk-tracking.
- The welcome paragraph copy is finalised at spec time and runs through the `humanizer` skill before merge — no AI-tinged phrasing.
- macOS-only deployment; no need to handle iPadOS / Linux drag-drop differences in the wizard.
- The existing minimum-disk-space pre-check (4 GB free) fires BEFORE the wizard's progress UI starts; if the disk is full, the wizard transitions directly into the error state via `FelDiskFull`.
