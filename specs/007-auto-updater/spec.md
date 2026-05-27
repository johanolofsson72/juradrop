# Feature Specification: Auto-updater (Swedish UI, per-zone-aware, v0.1 → v0.2 path)

**Feature Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`)

**Created**: 2026-05-27

**Status**: Draft

**Input**: User description: Spec 006 wired Tauri's updater plugin and shipped its built-in modal dialog (English; blocks user immediately on launch). Spec 007 replaces that modal with a non-intrusive Swedish in-app surface, owns a proper update-lifecycle state machine in Rust (Unknown → Checking → UpToDate | Available → Downloading → ReadyToInstall → Restarting | Failed) mirrored to React via Zustand, defers restart-prompts while any zone is mid-document-processing, and proves the v0.1 → v0.2 upgrade path works end-to-end via a Rust integration test that stubs the GitHub Releases manifest endpoint. Six new Swedish-localized `UpdateFailure` variants. Background re-checks every 4 hours while the app is running. The Tauri signature-verification path stays intact — spec 007 NEVER disables it.

## Clarifications

### Session 2026-05-27 (auto-picked recommendations per `.claude/settings.json`)

- Q: When the restart is deferred because a zone was processing at the user-click moment, and the last zone later returns to non-processing — should the app auto-restart, or wait for the user to click "Starta om" a second time? → A: **Auto-restart fires automatically because consent was already given by the original click.** The user's first click on "Starta om för att uppdatera" is the consent moment. The deferral is a politeness mechanism to avoid losing in-flight work, not a fresh-consent moment. The badge during deferral says "Väntar tills jobben är klara…" and the user can cancel the deferred restart by clicking that text (a chevron expands a "Avbryt" affordance). For the FIRST entry into ReadyToInstall (the user has not yet clicked), no auto-restart fires regardless of zone idleness — explicit click is required.
- Q: What does "no zones are processing" mean for the deferral predicate — strictly `Processing`, or also Success / Error (which auto-clear 2–5s later)? → A: **Strictly `Processing` only.** Success / Error states are short-lived (FR-010/FR-011 from spec 003 auto-clear them within 2–5 s) and show the user a result they can read at their own pace; they're not "work in flight". Restarting through a Success/Error state loses nothing — the sidecar file is already on disk. The deferral predicate is the boolean `any zone.visible_state == Processing` and nothing else. FR-008 wording is amended to drop the `Idle | Dragover` whitelist in favour of the simpler `NOT Processing` predicate.
- Q: What does the UI show during the brief Restarting state window (~2–3 seconds between user click and the new process launching)? → A: **The badge text changes to "Startar om…" and the main window stays usable.** No full-window overlay, no spinner blocking the rest of the UI. The disabled gate from spec 003/004 (zones already turn disabled when status != Klar) handles new drops if the user tries one mid-restart. The window then blanks naturally as the new process takes over. Minimal-friction is the consistent theme; a full overlay would feel modal in a spec that explicitly removed the modal dialog.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A user installs v0.2 without losing in-flight work (Priority: P1)

A Swedish law student has JuraDrop 0.1.0 installed. They drop a 12-page court ruling on Sammanfatta; processing kicks off. While `gemma3:4b` is mid-inference, the background updater task wakes up, finds that v0.2.0 has been published, and updates the in-app indicator badge to show "Uppdatering tillgänglig" in the top-right corner. The Sammanfatta zone keeps processing — no modal interrupts it. When the sidecar `.docx` is written and the zone returns to idle, the student notices the badge, clicks it, reads the "Nyheter i version 0.2.0" notes, clicks "Installera nu", waits ~10 seconds for the signed download to verify, sees the badge change to "Klar att installera — starta om?", clicks "Starta om för att uppdatera", and the app relaunches as 0.2.0 with the previous sidecar still on disk untouched.

**Why this priority**: The whole point of an auto-updater is to deliver new versions without disrupting the workflow. Tauri's built-in modal interrupts that workflow the moment the app launches — for users who run JuraDrop continuously over study sessions, the modal would be a noisy intrusion that erodes trust. Replacing it with a non-modal Swedish surface that respects in-flight zone processing is the load-bearing UX choice for the spec.

**Independent Test**: With JuraDrop 0.1.0 running and a 5-page `.docx` mid-processing on Sammanfatta, publish v0.2.0 to the staging endpoint. Confirm: (a) no modal appears at any point; (b) the indicator badge "Uppdatering tillgänglig" appears in the top-right within 4h of v0.2.0 going live (or immediately on next manual check); (c) the Sammanfatta sidecar completes successfully; (d) clicking the badge opens a non-modal panel; (e) clicking "Installera nu" downloads + verifies the signature; (f) clicking "Starta om för att uppdatera" replaces the .app in place and the new process launches as 0.2.0.

**Acceptance Scenarios**:

1. **Given** JuraDrop 0.1.0 is running and a zone is in `Processing`, **When** the background updater task wakes up and the manifest shows v0.2.0, **Then** the indicator badge "Uppdatering tillgänglig" appears in the top-right corner; no modal pops; the in-flight zone job is NOT interrupted.

2. **Given** the indicator badge is visible and all six zones are idle, **When** the user clicks the badge, **Then** a non-modal panel expands showing the new version number, the release-notes text (rendered as plain text — not raw Markdown), and an "Installera nu" button.

3. **Given** the user clicks "Installera nu", **When** the download starts, **Then** the badge text changes to "Hämtar uppdatering… N%" where N is the cumulative download progress in 0–100; the value updates at least every ~500 ms; the user can still drag documents onto any idle zone while the download runs.

4. **Given** the download completes and Tauri verifies the `.sig` signature against the embedded pubkey, **When** the verification passes, **Then** the badge text changes to "Klar att installera — starta om?" with a "Starta om för att uppdatera" button.

5. **Given** the badge says "Klar att installera" and ALL six zones are idle, **When** the user clicks "Starta om för att uppdatera", **Then** the .app is replaced in place by Tauri's updater plugin and the new process launches; the previous sidecar files on disk are byte-identical to before the update.

6. **Given** the badge says "Klar att installera" and at least one zone is still in `Processing`, **When** the user clicks "Starta om för att uppdatera", **Then** the restart is DEFERRED — a Swedish notice "Väntar tills jobben är klara…" appears with an "Avbryt" affordance — and the actual restart fires automatically the moment the last processing zone transitions out of `Processing` (consent was given by the original click; no second click required).

7. **Given** the badge says "Klar att installera" and the user has NOT yet clicked the restart button, **When** the user lets the app sit idle for an hour, **Then** no auto-restart fires. The badge stays visible until the user explicitly clicks "Starta om för att uppdatera".

---

### User Story 2 — Background check on a dead network (Priority: P2)

The user opens their MacBook on a train without internet. JuraDrop launches; the background updater check fires within ~5 seconds, fails because DNS can't resolve `github.com`, and quietly transitions the state to `Failed { reason: NoNetwork }`. The badge is hidden (we don't show update errors as nag-screens). When the user later connects to WiFi at home, the next 4-hour tick re-runs the check, finds nothing newer (the user is already on 0.2.0), and the state transitions to `UpToDate`. No modal, no toast, no nag.

**Why this priority**: Offline detection is the most common "non-happy-path" the updater will hit (every cafe, every train, every plane). Showing a red error banner every time the user is offline would train them to ignore all update notifications. Silent failure with retry on the next tick is the only sane behavior.

**Independent Test**: Disable network. Launch JuraDrop. Confirm: (a) the state transitions to `Failed { reason: NoNetwork }`; (b) NO badge appears in the top-right; (c) Rust logs (local only) show one line `update_check: failed (NoNetwork)`; (d) when network returns, the next manual check (or 4-hour tick) successfully transitions to `UpToDate`.

**Acceptance Scenarios**:

1. **Given** the network is unreachable, **When** the launch-time update check runs, **Then** the state transitions to `Failed { reason: NoNetwork }` within ~10 seconds; the indicator badge is NOT shown; no popup is displayed.

2. **Given** the state is `Failed { reason: NoNetwork }`, **When** the user opens the "Sök efter uppdateringar igen" affordance (in the failure-recovery panel — accessible by clicking the silent-but-present "Senast kollat" footnote in the main window's chrome), **Then** a fresh check runs.

3. **Given** the manifest URL responds with malformed JSON, **When** the check runs, **Then** the state transitions to `Failed { reason: ManifestMalformed }` and the failure-recovery affordance shows "Uppdateringsservern svarade med ogiltigt innehåll." No retry storm — the next attempt waits for the 4-hour tick or a manual click.

4. **Given** the `.sig` signature on the downloaded DMG doesn't verify against the embedded pubkey, **When** the download completes and verification runs, **Then** the state transitions to `Failed { reason: SignatureInvalid }`, no installation happens, the partial download is discarded, and the user-visible copy is "Säkerhetskontrollen misslyckades — uppdateringen installeras inte."

---

### User Story 3 — Manual "check again" trigger (Priority: P3)

The user has just published v0.3.0 manually (they ARE the developer) and wants to verify the updater path works without waiting for the 4-hour tick. They open the small "Senast kollat: 14:23" footnote in the bottom-right of the main window, click "Sök efter uppdateringar igen", and within 5 seconds the state transitions from `UpToDate` to `Available { version: "0.3.0" }`.

**Why this priority**: The manual trigger is essential for the developer's release-smoke-test loop but rare for end users (who never need to think about updates). Lower priority than the auto-flow.

**Independent Test**: Set the state to `UpToDate`. Publish a synthetic newer manifest on the stub endpoint. Click "Sök efter uppdateringar igen". Confirm the state transitions to `Available` within 5 seconds.

**Acceptance Scenarios**:

1. **Given** the state is `UpToDate` or `Failed`, **When** the user invokes the manual-check command, **Then** the state transitions to `Checking` immediately, then to whichever of `Available | UpToDate | Failed` the manifest resolves to.

2. **Given** the state is `Downloading | ReadyToInstall | Restarting`, **When** the user invokes the manual-check command, **Then** the command is a no-op (returns silently) — we don't re-check while a download is in flight or a restart is queued.

3. **Given** the state is `Checking`, **When** the user clicks the manual-check affordance again, **Then** the existing check completes (the second click is a no-op); no duplicate request is sent.

---

### Edge Cases

- **App backgrounded for 24+ hours, then foregrounded**: the 4-hour tick fired multiple times in the background. The most recent result is shown; intermediate ticks don't queue up indicator state.
- **Update available but `was_partial` PDF processing in flight on TWO zones**: the restart prompt stays deferred until BOTH zones return to idle (the deferral predicate is "any zone is processing", not "exactly one").
- **User dismisses the indicator badge with the X chevron**: the state stays `Available` but the badge is hidden. The badge re-appears on the next state transition (e.g. a fresh check tick finds the same version still available). User can also re-open it from the manual-check affordance.
- **System sleeps mid-download**: Tauri's HTTP client either resumes (transient sleep) or fails with `DownloadInterrupted` on long sleeps. The state cleanly transitions to `Failed { reason: DownloadInterrupted }` and the user retries with a click.
- **User runs the app on a macOS version older than the new version's `minimumSystemVersion`**: the manifest carries the macOS requirement; the state transitions to `Failed { reason: UnsupportedPlatform }` and the user-visible Swedish copy is "Den nya versionen kräver en nyare macOS — uppdatera macOS först." NOT a generic "install failed" — honest about the cause.
- **Pubkey mismatch (developer rotated keys without a transition release)**: signature verification fails for every user on the old key. The state transitions to `Failed { reason: SignatureInvalid }` for every user; they stay on their current version until the developer either reverts to the old key or ships a transition release that ships BOTH keys. Documented in `.claude/docs/deployment.md`'s edge-case list.
- **Newer version's manifest has empty release notes**: indicator panel shows "Inga noteringar för denna version." in place of the notes section. The "Installera nu" button is still present and works.
- **Download URL returns a 404 (release was unpublished after manifest was cached)**: state transitions to `Failed { reason: DownloadInterrupted }`. User retries; the next check will fetch a fresh manifest.
- **Tag pushed without bumping version**: caught by `release-prep.sh` from spec 006 — never reaches the manifest. Out of scope here.
- **User clicks "Installera nu" twice in quick succession**: the second click is a no-op because the state has already transitioned to `Downloading`. The state machine is the gate.
- **The 4-hour tick fires while state is `Failed`**: it triggers a fresh check (state allowed: `Unknown | UpToDate | Failed`). If the cause was transient (network), this auto-recovers.
- **The 4-hour tick fires while state is `Downloading`**: it's a no-op — we don't kick off a parallel check while a download is in flight.
- **Restart fails (Tauri returns an install error)**: state transitions to `Failed { reason: InstallFailed }` and the user sees "Kunde inte installera uppdateringen." The running v0.1.0 is unaffected — atomic install means either the new version is in place or the old one stays.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST flip the Tauri updater plugin's `dialog` setting in `tauri.conf.json` from `true` to `false`. The app drives the check + the UI from Rust; the built-in modal is no longer used.
- **FR-002**: System MUST maintain a single source-of-truth `UpdateStatus` enum in Rust with eight variants: `Unknown`, `Checking`, `UpToDate { version: SemVer, checked_at: Timestamp }`, `Available { version: SemVer, notes: String, download_url: Url }`, `Downloading { progress_pct: u8, version: SemVer }`, `ReadyToInstall { version: SemVer }`, `Restarting { version: SemVer }`, `Failed { reason: UpdateFailure }`.
- **FR-003**: System MUST emit a Tauri event on the `juradrop://update-status` channel on every transition of `UpdateStatus`. The React layer mirrors the state into a Zustand slice.
- **FR-004**: System MUST run an automatic update check ~5 seconds after first launch and every 4 hours thereafter while the app is running. The 4-hour tick fires ONLY when the current state is `Unknown | UpToDate | Failed`; it's a no-op for the in-flight states (`Checking | Downloading | ReadyToInstall | Restarting`).
- **FR-005**: System MUST expose a Tauri command `check_for_updates_now` invokable from the React layer. The command transitions `UpToDate | Failed | Unknown → Checking` and is a silent no-op when called in any other state.
- **FR-006**: When state is `Available`, the React layer MUST display a non-modal indicator badge in the top-right of the main window with the text "Uppdatering tillgänglig". Clicking the badge expands a panel with the version number, the release notes, and an "Installera nu" button.
- **FR-007**: When state is `Downloading`, the indicator badge MUST update its text to "Hämtar uppdatering… N%" where N is the cumulative download progress in 0–100. The badge MUST update at least every 500 ms during the download.
- **FR-008**: When state is `ReadyToInstall` AND no drop zone is in `Processing` (Success/Error states are short-lived and do not block the prompt), the indicator badge MUST display "Klar att installera — starta om?" with a "Starta om för att uppdatera" button. Clicking the button calls the Tauri updater plugin's install method, which atomically replaces the running .app and restarts the process. The deferral predicate is the boolean `any zone.visible_state == Processing` and nothing else.
- **FR-009**: When state is `ReadyToInstall` and any zone is in `Processing`, clicking "Starta om för att uppdatera" MUST defer the install. A Swedish notice "Väntar tills jobben är klara…" replaces the button; a chevron next to the notice expands an "Avbryt" affordance that lets the user cancel the deferred restart (state remains `ReadyToInstall` after cancel; the badge re-shows "Starta om?"). The actual install fires automatically the moment the last zone transitions out of `Processing` (consent was given by the original click — no second click required). Cancelled-jobs and error transitions both count as "no longer processing".
- **FR-009a**: When state is `ReadyToInstall` and the user has NOT yet clicked "Starta om för att uppdatera", no auto-restart fires regardless of zone idleness. The first click is the explicit consent gate; the deferral is a politeness mechanism, not a fresh-consent gate.
- **FR-010**: When state is `Failed`, the indicator badge MUST NOT be shown (failures are silent). Recovery is exposed via the secondary "Senast kollat" footnote in the bottom-right of the main window — clicking it expands a small panel with the failure reason in Swedish + a "Sök efter uppdateringar igen" button.
- **FR-011**: System MUST never show the Tauri built-in modal dialog. `dialog: false` in `tauri.conf.json` makes this impossible at the plugin level; the React layer never renders one either.
- **FR-012**: The signature-verification path in Tauri's updater plugin MUST stay intact. Spec 007 does NOT disable, bypass, or fake signature verification. The `.sig` file is fetched alongside the DMG and verified against the embedded pubkey before any disk write happens — same behavior shipped by spec 006.
- **FR-013**: System MUST define a Swedish-localised `UpdateFailure` enum with exactly six variants and copy:
  - `NoNetwork` → "Kan inte nå GitHub — kontrollera nätverksanslutningen."
  - `ManifestMalformed` → "Uppdateringsservern svarade med ogiltigt innehåll."
  - `SignatureInvalid` → "Säkerhetskontrollen misslyckades — uppdateringen installeras inte."
  - `DownloadInterrupted` → "Nedladdningen avbröts — försök igen."
  - `InstallFailed` → "Kunde inte installera uppdateringen."
  - `UnsupportedPlatform` → "Den nya versionen kräver en nyare macOS — uppdatera macOS först."
- **FR-014**: Every Swedish update-related string MUST satisfy the existing SwedishCopy invariants from spec 003 (≤ 80 chars, no English `Error:` prefix, non-empty) and MUST be reviewed via the `humanizer` skill before commit.
- **FR-015**: System MUST log every state transition locally via the existing Rust `eprintln!` (or `tracing` if it already exists in the project) with format `update_status: <old_state> → <new_state> (version: X.Y.Z)`. Logs MUST NOT include the release-notes content, the user's IP, the user's username, any document content, or any user-identifying information. Local logs only — Principle I.
- **FR-016**: System MUST NOT introduce any new outbound network endpoint. The updater's only outbound surface is the existing GitHub Releases manifest URL (`releases/latest/download/latest.json`) + the signed DMG download URL referenced inside that manifest. Both are already permitted by Principle I as the "release artefact" channel; no new endpoint is added.
- **FR-017**: The per-zone single-flight invariant from spec 003/004 MUST hold across every transition of `UpdateStatus`. Specifically: the updater MUST NEVER call `DropZone.handle_drop`, `DropZone.cancel_summary`, or otherwise interfere with the zone state machine. The two state machines are independent except for the FR-008/FR-009 deferral gate.
- **FR-018**: System MUST expose a Tauri command `dismiss_update_indicator` that hides the badge while preserving the `Available | ReadyToInstall` state. The badge re-appears on the next state transition (e.g. when a new check tick happens and the version is still available).
- **FR-019**: The "Nyheter i version X.Y.Z" notes section MUST render the manifest's `notes` field as plain text (newlines preserved). Markdown syntax (asterisks, hashes, blockquotes) in the source MUST NOT be parsed or rendered as rich formatting. If the field is empty, render the literal string "Inga noteringar för denna version."
- **FR-020**: The 4-hour tick MUST be implemented as a single `tokio::spawn`-ed task scoped to the app's lifetime, not a per-event-handler timer. The task wakes every 4 hours, reads the current state, and triggers a check only if the state allows it (per FR-004). On app shutdown the task is cancelled cleanly.
- **FR-020a**: During the `Restarting` state window (~2–3 s between the consenting click and the new process taking over), the indicator badge text MUST change to "Startar om…" but the main window stays usable — no full-window overlay, no modal spinner. The zone-disabled gate from spec 003/004 (zones disabled when status != Klar) handles new drops that arrive in this window; the window then blanks naturally as the new process replaces the running .app.
- **FR-021**: Spec 007 MUST NOT introduce any new outbound surface in CI either. The release workflow from spec 006 stays unchanged; spec 007 only modifies the running app + UI + a Rust integration test that uses an in-process stub server (no real network).
- **FR-022**: The Rust integration test MUST drive the state machine through `Unknown → Checking → Available → Downloading → ReadyToInstall` with a stubbed manifest endpoint (using the existing `wiremock` dev-dep from spec 002). The test MUST verify the user-visible Swedish copy at each step (e.g. asserting that the React-mirrored payload contains "Uppdatering tillgänglig" when state is `Available`). The test MUST NOT actually replace the running binary.

### Key Entities

- **UpdateStatus**: Source-of-truth Rust enum (seven variants). Owned by the AppState; mirrored to React via a Tauri event.
- **UpdateFailure**: Six-variant enum carrying the Swedish copy. Independent of `ZoneFailure` because update failures are app-global, not per-zone.
- **UpdaterTask**: The 4-hour background tick — single tokio task. Cancellable on app shutdown.
- **UpdateIndicator**: The React component owning the top-right badge + expandable panel. Reads from the Zustand slice; emits `dismiss_update_indicator` + `check_for_updates_now` Tauri commands.
- **UpdateRetry**: The bottom-right "Senast kollat: …" footnote + its failure-recovery panel. Lower priority than the indicator badge — only visible when state is `Failed` AND the user has explicitly clicked the timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An update from v0.1.0 to v0.2.0 completes end-to-end (download + signature verify + install + restart) within 90 seconds on a standard residential broadband connection (~100 Mbps), measured from "Installera nu" click to the new process being live.
- **SC-002**: While any zone is in `Processing`, ZERO restart events fire — the FR-009 deferral predicate holds in every test run.
- **SC-003**: The Rust integration test stubbing the manifest endpoint drives the state machine through every transition `Unknown → Checking → Available → Downloading → ReadyToInstall` in ≤ 5 seconds wall-clock and asserts the Swedish copy at every step.
- **SC-004**: 100% of the six `UpdateFailure` variants surface their specific Swedish copy in the failure-recovery panel — no generic "Ett fel uppstod" fallback path.
- **SC-005**: The 4-hour tick fires within ±5 minutes of every 4-hour anniversary of app launch (4h00m–4h05m precision is sufficient; we're not building a real-time system).
- **SC-006**: The launch-time update check completes within 10 seconds on a normal network, and within 30 seconds on a slow but reachable network. On an unreachable network the state transitions to `Failed { NoNetwork }` within 30 seconds (the DNS timeout dominates).
- **SC-007**: No `juradrop://` Tauri event channel name introduced by spec 007 collides with any existing channel from specs 002/003/004/005/006. Specifically, `juradrop://update-status` is new and unique.

## Assumptions

- The Tauri updater plugin's `Update::install` method atomically replaces the running `.app` and relaunches the process. This is the plugin's documented behaviour; spec 007 does not reimplement it.
- The plugin's `check()` method does NOT cache results across launches — every call hits the network. The 4-hour tick + the launch-time check together govern check cadence; the plugin itself is stateless about timing.
- The manifest's `notes` field is plain text (or harmless Markdown). Rich-text rendering is out of scope; we render as plain text per FR-019. If the developer wants formatting, they put it in the GitHub Release notes (visible on the web), not in the manifest.
- The plugin's `download_and_install` method emits progress events as a Rust stream/callback. We map those to `UpdateStatus::Downloading { progress_pct }` and emit a `juradrop://update-status` event for each new percentage value (debounced to one emission per integer percent to avoid spam).
- The `.sig` signature check in the plugin is total — either it passes (and the install proceeds) or it fails (and the install rejects). There is no partial-success path.
- Tauri's plugin reads `dialog: true|false` from `tauri.conf.json` at app startup. Spec 007 sets it to `false`; spec 006's `true` is overridden in the source code change.
- The "Senast kollat" footnote uses local time (the user's Mac time). Server time is irrelevant — this is a "when did the app last check" timestamp, not a release-publish-time timestamp.
- The 4-hour cadence is sufficient — most legal-studies sessions are shorter than 4 hours. A user who runs the app for 8 straight hours will get exactly two background checks. Faster cadences would only matter if updates were security-critical, which they aren't (legal-document-summarization).
- The user's `tauri.conf.json` `pubkey` field (from spec 006) is non-placeholder by the time spec 007 ships. Without a real pubkey, no signature can verify, and every update attempt would fall through to `Failed { SignatureInvalid }`. This is documented as the "first release is the manual ceremony" assumption — by the time spec 007 is in the field, the user has already done the spec 006 prereqs.
- The Rust integration test uses `wiremock` (already a dev-dep) to stub the manifest endpoint. The test does NOT actually call `Update::install` — that requires write access to the running .app, which is out of scope for an in-process test.

## Out of Scope

- A "Settings" panel with a manual "Check for updates" toggle — that's spec 010 (settings-panel).
- Differential / delta updates (Tauri 2.x doesn't support them).
- Beta-channel toggle / pre-release subscription — spec 012 (polish-and-public-beta) territory.
- Update history view ("you skipped these versions") — over-engineering for a single-user app.
- Rich-text / Markdown rendering of the release notes — plain text is sufficient (FR-019).
- Auto-restart at a scheduled time (e.g. "install at 3am") — Mac apps don't run unattended; relying on this would be a footgun.
- Crash reporting if the install fails — Principle I forbids it. The local log line is the only record.
- Swedish localisation of the Tauri plugin's own internal error messages (the plugin's English errors don't surface to the user; the React layer maps every failure to one of the six `UpdateFailure` variants per FR-013).
- Auto-downloading the update before the user clicks "Installera nu" — that would burn the user's mobile bandwidth without consent. Explicit user-initiated download is the v1 contract.
- Re-trying a failed download automatically. The user clicks "Sök efter uppdateringar igen". No automated retry storm.
- Telemetry of update install success/failure rates. Principle I.
