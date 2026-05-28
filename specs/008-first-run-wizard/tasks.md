# Tasks: First-run wizard (welcome → consent → progress → ready)

**Spec**: [spec.md](spec.md) · **Allium**: [spec.allium](spec.allium) · **Plan**: [plan.md](plan.md)

**Input**: Spec 008 wraps the existing spec 002 consent + model-pull machinery in a Swedish-first wizard. Four React-side phases (welcome / progress / error / hidden) derived from `AppStatus` via a pure `useWizardState` hook. One new Tauri command `cancel_model_pull`. 12 new Swedish strings under a cross-language `wizard-strings.json` fixture. Full-track pipeline.

Total tasks: 42 across 9 phases (Setup, Foundational, US1, US2, US3, US4, US5, Polish, TLA+/close). Track: **full** (Allium done; /tla still pending after browser tests).

---

## Phase 1 — Setup

- [x] T001 Create skeleton files (each with `// Spec 008 — placeholder` + module declaration where applicable): `src/components/Wizard.tsx`, `src/components/WelcomeWizard.tsx`, `src/components/FirstRunProgress.tsx`, `src/lib/use-wizard-state.ts`, `src/lib/use-progress-estimate.ts`, `src/lib/wizard-strings.ts`. These files MUST compile as no-op exports so subsequent phases can land incrementally.
- [x] T002 Create the fixture file `src-tauri/tests/fixtures/wizard-strings.json` exactly as defined in `data-model.md` (12 string keys + `_comment`). Validate the JSON parses cleanly with `python3 -c "import json; json.load(open('src-tauri/tests/fixtures/wizard-strings.json'))"`.

---

## Phase 2 — Foundational (blocking for every user story)

- [x] T003 [P] Mirror the 12 Swedish strings into `src/lib/wizard-strings.ts` as a `WIZARD_STRINGS` const satisfying `Record<WizardStringKey, string>` (per data-model.md). Export a `WizardStringKey` union type.
- [x] T004 [P] Cross-language drift fixture test — Rust side: `src-tauri/tests/wizard_strings.rs`. Reads the JSON fixture, asserts every key is non-empty, no key starts with `Error:`, no key contains the case-insensitive substring `error`, `welcome_paragraph` ≤ 200 chars, every other key ≤ 80 chars. Exactly 13 keys (12 strings + `_comment`).
- [x] T005 [P] Cross-language drift vitest — TS side: `src/__tests__/WizardCopy.errors.test.tsx`. Reads the same JSON fixture, asserts byte-for-byte equality with `WIZARD_STRINGS`, and re-runs the four SwedishCopy invariants client-side. 8+ assertions.
- [x] T006 Implement the `useWizardState` hook in `src/lib/use-wizard-state.ts` per the R-001 truth table. Pure function of the existing `useStatusStore` snapshot. Returns one of `'welcome' | 'progress' | 'error' | 'hidden'`. No side effects, no useState, no useEffect.
- [x] T007 [P] vitest `src/__tests__/useWizardState.test.tsx`: assert the truth table — 9 input combinations × the expected output phase. 12+ assertions.
- [x] T008 Implement `useProgressEstimate` in `src/lib/use-progress-estimate.ts` per R-002. Rolling 10s sample buffer in `useRef`. Subscribes to `juradrop://progress` via `subscribeProgress` from the bridge layer. Computes mean-bps, ETA, and the `downloading` / `waiting` label flip. ETA formatter applies the FR-004 clarification rules (`ceil(secs/5)*5` for < 60 s; `ceil(secs/60)` for ≥ 60 s; `'—'` for bps=0).
- [x] T009 [P] vitest `src/__tests__/useProgressEstimate.test.tsx`: assert ETA formatting at the boundary (59 s → "≈ 60 s"; 60 s → "≈ 1 min"; 1 s → "≈ 5 s"; 0 bps → "—"); assert the waiting-label trigger at exactly 5 s of staleness; assert resume from last byte after a waiting period. 10+ assertions.
- [x] T010 Implement `Wizard.tsx` as a thin parent that reads `useWizardState()` + `useMinVisibleHold` and renders either `<WelcomeWizard />` or `<FirstRunProgress />`. The parent owns the `mountedAt` timestamp for the FR-019 minimum-visible hold. Returns null when phase is `hidden`.
- [x] T011 [P] Implement the `useMinVisibleHold` hook (inside `src/lib/use-wizard-state.ts` or a sibling file). Holds the previous phase for at least `minMs` after a phase change. Default 300 ms per FR-019. Unit-tested in T007.

---

## Phase 3 — US1: Welcome → progress → ready happy path (P1)

**Story goal**: Fresh install renders the welcome screen, the user clicks Fortsätt, the progress UI shows percent + bytes + ETA, and on completion the wizard fades out + the zone-grid mounts.

**Independent test**: Wipe `~/Library/Application Support/se.juradrop/`. Launch JuraDrop. Confirm: (a) welcome screen renders with the locked Swedish copy; (b) Fortsätt fires consent; (c) progress UI shows live percent + bytes + ETA; (d) zone-grid is NOT rendered behind the wizard; (e) on completion the wizard dismounts and zones render.

- [x] T012 [US1] Implement `WelcomeWizard.tsx` — renders the 7 welcome strings from `WIZARD_STRINGS` (title + paragraph + privacy line + download note + Fortsätt + Avbryt + sidecar helper line). Uses Tailwind primitives + shadcn/ui per `design-system/MASTER.md`. The Fortsätt button reads `sidecar.status` from `useStatusStore` and renders `disabled={sidecar !== 'ready'}`. Clicking Fortsätt invokes `giveConsent()` via the Tauri bridge. Clicking Avbryt invokes `cancelConsent()`. Escape key handler invokes the secondary action (`cancelConsent`). Tab order: Fortsätt focused on mount → Avbryt → wraps. Full-screen centered layout; body width ≤ 480 px max-width.
- [x] T013 [US1] Implement `FirstRunProgress.tsx` — renders the active-download UI. Reads `useProgressEstimate()` for the percent / bytes / ETA / label. Reads `useStatusStore()` for the `visible` UserVisibleStatus to detect error sub-states. Cancel button invokes the new `cancelModelPull()` bridge wrapper. Error sub-state renders the failure copy + "Försök igen" button that re-invokes `giveConsent()`. Tailwind percent-bar; Swedish byte formatter (thin-space thousands separator); ETA renderer from the hook.
- [x] T014 [US1] Modify `src/App.tsx` — root render branches on `useWizardState()`: renders `<Wizard />` when phase !== 'hidden', else renders the existing 2×3 zone-grid (refactored into `<ZoneGrid />` or inlined as the existing JSX). The two paths MUST NOT both mount. Existing UpdateIndicator + UpdateRetryFootnote from spec 007 stay mounted in either path (they're top-right / bottom-right chrome).
- [x] T015 [US1] Add `pull_cancel: Arc<CancellationToken>` field to `AppState` in `src-tauri/src/sidecar/commands.rs`. Initialize to a fresh CancellationToken in `AppState::new()`. Modify `spawn_pull_task` to replace `state.pull_cancel` with a fresh token at start AND wrap the `OllamaClient::pull` future in `tokio::select!` against `state.pull_cancel.cancelled()`.
- [x] T016 [US1] Implement the new `cancel_model_pull` command in `src-tauri/src/sidecar/commands.rs` per `contracts/tauri-commands.md`. Acquires `model_status` write-lock; branches on Ready (no-op) / Downloading (trip token + flip status + emit) / else (idempotent no-op). Register in `lib.rs` `tauri::generate_handler!`.
- [x] T017 [US1] Add `cancelModelPull()` wrapper to `src/lib/tauri-bridge.ts` — `async function cancelModelPull(): Promise<void>` invoking `invoke<void>('cancel_model_pull')`.
- [x] T018 [P] [US1] vitest `src/__tests__/WelcomeWizard.test.tsx`: render the wizard with various `useStatusStore` snapshots; assert (a) each of the 7 welcome strings appears verbatim; (b) Fortsätt is disabled when sidecar !== 'ready'; (c) "Förbereder AI-motorn…" helper visible only during boot; (d) Fortsätt click calls `giveConsent` mock; (e) Avbryt click calls `cancelConsent` mock; (f) Escape calls `cancelConsent` mock; (g) Tab order; (h) Enter on focused Fortsätt fires the same as click. 15+ assertions.
- [x] T019 [P] [US1] vitest `src/__tests__/FirstRunProgress.test.tsx`: render the progress UI with synthesized progress estimates; assert (a) percent bar renders correct width; (b) byte counter format (Swedish thin-space); (c) ETA text matches the formatter for boundary values; (d) "Hämtar AI-modell…" label during active download; (e) "Väntar på nätverk…" label after staleness; (f) Cancel button calls `cancelModelPull` mock; (g) error sub-state shows the right Swedish copy for each UserVisibleStatus error variant; (h) "Försök igen" calls `giveConsent` mock. 12+ assertions.
- [x] T020 [US1] Rust integration test `src-tauri/tests/cancel_model_pull.rs` — drives the new command against a wiremock-backed pull flow. Asserts: (a) command is silent no-op when model_status is Ready; (b) command trips the cancellation token + flips status to NotPresent when model_status is Downloading; (c) command is idempotent across NotPresent / DownloadFailed states; (d) the existing pull task exits cleanly within ~100 ms of cancel.

---

## Phase 4 — US2: Subsequent-launch silence (P1)

**Story goal**: With `consent = fortsatt` + `model = ready`, the wizard never renders; the zone-grid shows from the first paint.

**Independent test**: Pre-populate consent + ensure model is present. Launch the app. Confirm welcome screen never appears + zones render immediately (with the spec 002 "Startar AI…" overlay during sidecar boot).

- [x] T021 [US2] Verify the T006 truth table includes the `(fortsatt, ready, *, ready) → hidden` row. Add a focused vitest assertion in `useWizardState.test.tsx` (T007) covering this row with explicit values.
- [x] T022 [US2] Verify `App.tsx`'s root conditional correctly renders the zone-grid (NOT the wizard) for the hidden phase. Manual smoke via `npm run tauri dev` on a populated install: confirm no welcome flash, zones interactive within 5 s.

---

## Phase 5 — US3: Network drop + resume (P2)

**Story goal**: A network drop mid-download switches the progress label to "Väntar på nätverk…", freezes the percent + byte counter, and resumes seamlessly when the network returns.

**Independent test**: Fresh install. Click Fortsätt. After 10 s, kill the network. Wait 15 s. Re-enable network. Confirm the label flips correctly + byte counter resumes from where it stopped.

- [x] T023 [US3] Verify `useProgressEstimate` (T008) correctly fires the `'waiting'` label at exactly 5 s of staleness. Add a focused vitest assertion with `vi.useFakeTimers()` advancing the clock past 5 s without any progress event.
- [x] T024 [US3] Verify `useProgressEstimate` resumes the byte counter from the last received value after a waiting period (no reset to 0). Add a focused vitest assertion that pushes a progress event AFTER fake-timer advance + asserts the new sample is appended to the buffer (not replacing it).
- [x] T025 [US3] Verify `FirstRunProgress` renders the label change correctly via the existing T019 assertions. Add one more vitest assertion: render the component with `progress.label === 'waiting'` + assert the rendered text matches `WIZARD_STRINGS.progress_label_waiting` byte-for-byte.

---

## Phase 6 — US4: Cancel mid-download (P2)

**Story goal**: Clicking "Avbryt nedladdning" aborts the pull cleanly + transitions the wizard back to welcome + cleans up partial bytes.

**Independent test**: Fresh install. Click Fortsätt. Wait until percent ≥ 5%. Click Cancel. Confirm: pull aborts within 1 s + welcome reappears + partial model bytes are gone.

- [x] T026 [US4] Verify T016's `cancel_model_pull` command behavior via T020's integration test cases. No new test code; assert the existing tests cover the Cancel-from-Downloading path.
- [x] T027 [US4] Verify T013's `FirstRunProgress` Cancel button correctly invokes `cancelModelPull()` via T019's vitest mock. No new test code; assert the existing assertion covers this.
- [ ] T028 [US4] Manual smoke verification (deferred to T040 manual flow 4): cancel during a real download leaves Ollama's model directory empty.

---

## Phase 7 — US5: Avbryt on welcome (P3)

**Story goal**: Clicking Avbryt on the welcome screen persists the negative choice but keeps the welcome visible (no quit, no transition).

**Independent test**: Fresh install. Click Avbryt. Confirm welcome stays visible + consent record now reads `avbryt`. Quit + relaunch → welcome appears again.

- [x] T029 [US5] Verify `WelcomeWizard.tsx` (T012) does NOT transition out of welcome phase after Avbryt. Add a vitest assertion in T018: render the wizard, click Avbryt, re-read `useWizardState()`, assert it still returns `'welcome'`.
- [x] T030 [US5] Verify the spec 002 `cancel_consent` command persists `choice = avbryt` to the consent record file. Existing spec 002 `consent_persistence.rs` test covers this; assert it still passes after the wizard changes (no regression).

---

## Phase 8 — Cross-cutting polish

- [x] T031 [P] Static network audit: `grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/` — every match must remain in spec 002's `manager.rs` + `client.rs`. Spec 008 adds ZERO new outbound surface. Extend `src-tauri/tests/update_invariants.rs` (or add `wizard_invariants.rs`) with `wizard_introduces_no_new_outbound_surface` per `contracts/wizard-events.md` SC-007 audit.
- [x] T032 [P] Run the `humanizer` skill on every new Swedish string introduced in spec 008: the 12 wizard strings (welcome title, body, privacy, download note, 2 CTAs, sidecar helper, 3 progress strings, ETA-unknown placeholder, retry button). Adjust any AI-tinged phrasing. BLOCKING per CLAUDE.md.
- [x] T033 [P] Run the `frontend-design` skill on the WelcomeWizard + FirstRunProgress components BEFORE writing UI code in T012 + T013 (this task IS the skill-invocation marker; the actual edits happen in those tasks). Verify the wizard matches the existing design system: color tokens, typography scale, spacing rhythm. No new design language.
- [x] T034 [P] Update `README.md`: extend the "Installation" section with a paragraph about the first-run wizard — what the user sees on first launch + the expected ~3 minute model download. Mention that subsequent launches skip the wizard.
- [x] T035 [P] Playwright smoke extension `tests/e2e/first-run-wizard.spec.ts` (best-effort — see spec 003's note about Tauri + Playwright). At minimum, the existing placeholder test stays green.
- [x] T036 Run the full regression suite: `npm run lint && npm run typecheck && npm test`, then `cd src-tauri && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`, then `npm run test:e2e`. All MUST exit 0. Spec 008's additions must not regress spec 001–007.

---

## Phase 9 — TLA+ verification + manual close + commit

- [x] T037 Run `/tla` for spec 008. Full track; 4 React-side phases × 9 UserVisibleStatus variants + async pull + sidecar boot + cancel-race = non-trivial. Expect TLA+ to surface invariants like `ZonesGatedOnModelReady` + `WizardSingleInstance` + `NeverUncompleteACompletedDownload`. Address any findings per `.claude/rules/validation-followup.md`.
- [ ] T038 Execute `quickstart.md` flows 1–8 against `npm run tauri dev` on real hardware. SC-001 (welcome ≤ 800 ms first paint), SC-004 (network drop recovery ≤ 5 s), SC-005 (cancel cleanup) need real-hardware verification. **Needs user verification on real Mac.**
- [x] T039 Tick spec 008 in `specs/INDEX.md` to `[x]` and append a Register history entry dated today with task count, test count delta, deferrals, and the spec 009 next-up note.
- [x] T040 Stage + commit + push to `origin/main` per the direct-push workflow. Commit message: `feat(spec-008): first-run wizard — welcome + progress + cancel + Swedish copy + cross-language fixture`. Then emit the per-spec stop summary per `.claude/rules/spec-register.md`.

---

## Dependencies & ordering

- **Phase 1 (Setup)** blocks every later phase — the skeleton files + the JSON fixture must exist before any test references them.
- **Phase 2 (Foundational)** blocks Phases 3–7 — the cross-language fixture tests + the two hooks + the wizard parent component are load-bearing.
- **Phase 3 (US1)** is the load-bearing implementation. Its sub-steps have internal dependencies: T015→T016→T017 (Rust command chain); T012 + T013 are independent and can be parallel with T018 + T019 (vitest tests); T020 (integration test) requires T015–T017.
- **Phase 4 (US2)** layers on Phase 2's truth table — no new component code, just verification.
- **Phases 5–7** are independent of each other after Phase 3 lands.
- **Phase 8 (Polish)** depends on all user stories being complete — humanizer + regression sweep need the final strings + tests. T033 (frontend-design) marker MUST happen BEFORE T012 + T013.
- **Phase 9 (TLA+ + close)** runs last per the full-track pipeline.

## Parallel execution opportunities

Phase 2: T003, T004, T005, T007, T009, T011 are all `[P]` — six files / tests, no shared state. T006 + T008 + T010 are foundational sequential.

Phase 3 (within US1): T015–T017 are sequential (Rust command chain); T012 + T013 + T018 + T019 are parallel after T010 lands.

Phases 4 + 5 + 6 + 7: independent of each other.

Phase 8: T031, T032, T033, T034, T035 are all `[P]`. T036 (regression sweep) is the final blocker.

## MVP scope

Minimum shippable slice: **Phase 1 + Phase 2 + Phase 3 (US1) + Phase 4 (US2)**. With those four phases, the user has the full happy path: welcome on fresh install, consent click, progress UI, zone-grid on completion, no welcome on subsequent launch. US3 (network drop), US4 (cancel), US5 (Avbryt welcome) layer on without touching the MVP code paths.

## Format validation

Every task above starts with `- [ ]` + `T###` ID + optional `[P]` marker + optional `[US#]` label + concrete description + explicit file path. No task references "the codebase" or "appropriate files" without naming them.
