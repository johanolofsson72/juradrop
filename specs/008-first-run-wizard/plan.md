# Implementation Plan: First-run wizard (welcome → consent → model download → ready)

**Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`) | **Date**: 2026-05-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-first-run-wizard/spec.md` plus the formal contract in [spec.allium](spec.allium).

## Summary

Wrap the existing spec 002 consent + model-pull machinery in a Swedish-first first-launch wizard. Build a four-phase React-side state machine (welcome → progress → error → hidden) whose phase is a pure function of the existing `AppStatus` snapshot (`consent.choice`, `model.status`, `sidecar.status`, `progress_percent`). Render `<Wizard />` OR `<ZoneGrid />` from `App.tsx`'s root — never both at once (FR-005 + FR-018). The welcome screen carries the spec's clarified Swedish copy (title + body paragraph + privacy line + download note + Fortsätt/Avbryt CTAs + sidecar-boot helper). The progress UI carries percent bar + Swedish-formatted byte counter + ETA (clarified: < 60 s → "≈ X s" rounded to 5 s; ≥ 60 s → "≈ Y min") + Cancel button. A new `cancel_model_pull` Tauri command (FR-013) trips the existing tokio cancellation token + flips `model_status` to `model_missing_aborted`. Zero new outbound network surface — the wizard reads existing `juradrop://status` + `juradrop://progress` events and invokes existing or one-new Tauri commands. The state machine is single-actor and synchronous from the React perspective, but the underlying pull task + sidecar lifecycle inherit spec 002's concurrency model; `/tla` MUST run after browser tests per the full-track pipeline.

## Technical Context

**Language/Version**: Rust 1.95+, TypeScript 5.x. Same toolchain as spec 007.

**Primary Dependencies**: Existing — `tauri`, `tauri-plugin-shell`, `tokio`, `parking_lot`, `serde`, `serde_json`, `wiremock` (dev-dep), `tempfile` (dev-dep), `zustand` (already pinned for spec 007). **No new external deps** — spec 008 is pure UI + a small new Tauri command that wraps the existing `OllamaSidecar` cancellation token.

**Storage**: Filesystem (existing `~/Library/Application Support/se.juradrop/consent.json` from spec 002). Spec 008 adds NO new persisted state — the wizard reads the existing consent record + the existing in-memory `model_status`. The `ProgressEstimate` value (last_pct, last_byte_count, last_progress_at, bytes_per_second_recent) lives entirely in React state.

**Testing**:
- Rust: `cargo test` + new integration test `tests/cancel_model_pull.rs` (drives the new command against a wiremock-backed pull flow). Existing pull tests stay green.
- Vitest: `src/__tests__/WelcomeWizard.test.tsx` + `src/__tests__/FirstRunProgress.test.tsx` + `src/__tests__/useWizardState.test.tsx` + `src/__tests__/WizardCopy.errors.test.tsx` (cross-language drift against a new `wizard-strings.json` fixture).
- Playwright: 1 new smoke `tests/e2e/first-run-wizard.spec.ts` (best-effort — see spec 003's note about Tauri + Playwright; the placeholder smoke stays green at minimum).
- TLA+: state machine has 4 React-side phases × the existing 9 `UserVisibleStatus` variants. Combined with the async pull lifecycle + the sidecar boot + the cancel-race semantics, the state space is large enough that `/tla` is required. The triviality gate fails (too many states + multiple actors).

**Target Platform**: macOS 12+ on Apple Silicon. Unchanged.

**Project Type**: Desktop app (Tauri 2.x). Unchanged.

**Performance Goals**:
- SC-001 — welcome screen renders within 800 ms of the WebView mounting on a fresh install (Playwright timing assertion).
- SC-002 — subsequent launches with `consent = fortsatt` + `model = ready` MUST NOT render the wizard at all (vitest assertion on `useWizardState` return value).
- SC-004 — simulated 30 s network drop produces "Väntar på nätverk…" within 5 s, returns to live progress within 5 s (integration test driving the manager directly).
- SC-005 — Cancel mid-download leaves no partial model bytes on disk (integration test asserts absence under `models/`).
- SC-008 — VoiceOver announces the welcome paragraph on first paint (manual real-hardware verification item).

**Constraints**:
- Principle I (privacy): zero new outbound endpoints. The wizard reads existing `juradrop://status` + `juradrop://progress` events and invokes existing or one-new Tauri commands. Logs MUST NOT include document content, IP, system username, or model bytes.
- Principle V (Swedish-first UI): every visible string in Swedish, humanizer-reviewed.
- Principle VIII (Honest failure states): existing 9 `UserVisibleStatus` variants reused; no new variants needed — the wizard distinguishes welcome / progress / error visually but doesn't add a new error vocabulary.
- Single-instance wizard (FR-018): exactly one `<Wizard />` mount across the React tree. App.tsx's root conditional renders either `<Wizard />` OR `<ZoneGrid />`.
- Minimum-visible time (FR-019): 300 ms ceiling on the hide-on-ready transition to prevent flicker on instant-completion paths.

**Scale/Scope**: Single user, single window. ~120 lines of new TypeScript for the wizard + ~40 lines for `useWizardState` + ~30 lines for the progress estimator. ~25 lines of new Rust for `cancel_model_pull`. ~6 new strings in the wizard Swedish-copy fixture. 1 new Tauri command, 0 new event channels (reuses `juradrop://status` + `juradrop://progress`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Privacy by Architecture | Zero new outbound endpoints. Local-logs-only invariant inherited from spec 007's `UpdaterLogsHaveNoUserContent` pattern. No telemetry of wizard interactions. | ✅ |
| II. Zero-CLI Install | No new external deps. The signed DMG flow from spec 006 stays unchanged. | ✅ |
| III. Local-Only Inference | The wizard wraps the existing local-only Ollama pull. No remote inference. | ✅ |
| IV. Single-User Desktop App | Single in-memory `WizardState` per running app. The consent record is per-user under `app_data_dir`. | ✅ |
| V. Swedish-First UI, English-First Code | All wizard strings in Swedish (title + body + privacy + download note + 2 buttons + sidecar helper + 3 progress strings + 1 error retry); humanizer-reviewed. Code/comments/commits English. | ✅ |
| VI. Native macOS Feel | Full-screen welcome wizard matches the macOS first-launch convention (Onboarding modal). SF Pro typography inherited. Escape closes via Avbryt (macOS modal convention). | ✅ |
| VII. Bundled Sidecar Internal | The wizard wraps spec 002's sidecar lifecycle. No new sidecar work. | ✅ |
| VIII. Honest Failure States | Existing 9 `UserVisibleStatus` variants reused; the wizard's error phase reads `visible` and renders the matching Swedish copy. No generic catch-all. | ✅ |
| IX. Open Source, Free, No Lock-In | All work is in the existing MIT-licensed Tauri + Ollama stack. No new third-party SaaS. | ✅ |

**All gates pass.** No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/008-first-run-wizard/
├── spec.md                       # written + 5 auto-picked clarifications
├── spec.allium                   # written + 0 errors (14 warnings dismissed as by-design)
├── plan.md                       # this file
├── research.md                   # Phase 0 — wizard-state derivation, ETA throughput estimate, cancel-race semantics, sidecar-boot gating
├── data-model.md                 # Phase 1 — WizardPhase enum, ProgressEstimate value, useWizardState hook signature, fixture schema
├── quickstart.md                 # Phase 1 — 8 smoke flows (5 user stories × happy + edge variants)
├── contracts/                    # Phase 1
│   ├── tauri-commands.md         # cancel_model_pull command shape + races
│   ├── wizard-events.md          # No new event channels — documents which existing channels feed which wizard transitions
│   └── wizard-copy.md            # 9-string Swedish vocabulary + welcome paragraph + length invariants
├── checklists/
│   └── requirements.md           # already passing
└── tasks.md                      # Phase 2 — produced by /speckit-tasks
```

### Source Code (repository root)

```text
src-tauri/
├── Cargo.toml                                       # UNCHANGED — no new deps
├── src/
│   ├── lib.rs                                       # MODIFIED — register cancel_model_pull command
│   ├── sidecar/
│   │   └── commands.rs                              # MODIFIED — add cancel_model_pull command body using the existing CancellationToken
│   └── (other modules unchanged)
└── tests/
    └── cancel_model_pull.rs                         # NEW — integration test for FR-013

src/
├── components/
│   ├── WelcomeWizard.tsx                            # NEW — title + body + privacy + download note + Fortsätt/Avbryt + sidecar helper
│   ├── FirstRunProgress.tsx                         # NEW — percent bar + byte counter + ETA + Cancel + error/retry sub-state
│   └── Wizard.tsx                                   # NEW — thin parent that branches on useWizardState() and renders WelcomeWizard or FirstRunProgress
├── lib/
│   ├── tauri-bridge.ts                              # MODIFIED — add cancelModelPull() wrapper
│   ├── use-wizard-state.ts                          # NEW — pure hook deriving WizardPhase from AppStatus
│   ├── use-progress-estimate.ts                     # NEW — rolling-window ETA estimator + waiting-on-network trigger
│   └── wizard-strings.ts                            # NEW — TS-side Swedish copy (asserted against the JSON fixture)
├── __tests__/
│   ├── WelcomeWizard.test.tsx                       # NEW — render + Fortsätt/Avbryt + sidecar-boot helper + Tab order + Escape
│   ├── FirstRunProgress.test.tsx                    # NEW — percent + bytes + ETA formatting + waiting-on-network + Cancel + retry
│   ├── useWizardState.test.tsx                      # NEW — derivation truth table (consent × model × sidecar)
│   └── WizardCopy.errors.test.tsx                   # NEW — cross-language drift vs wizard-strings.json
├── App.tsx                                          # MODIFIED — root conditional: render <Wizard /> OR <ZoneGrid /> based on useWizardState
└── (existing components unchanged)

src-tauri/tests/fixtures/
└── wizard-strings.json                              # NEW — single source of truth for the 9 wizard Swedish strings + welcome paragraph
```

**Structure Decision**: Three new small React components + two new hooks + one new Tauri command. The existing six DropZones, the spec 002 ConsentModal, the spec 002 OllamaSidecar lifecycle, and the spec 007 UpdateIndicator/UpdateRetryFootnote all stay untouched. The wizard sits ABOVE the zone-grid in the conditional render — App.tsx renders one or the other, never both, which closes the FR-005 + FR-018 gates structurally.
