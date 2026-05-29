# Implementation Plan: On-demand tier download

**Branch**: `main` (solo, direct-push) | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/027-on-demand-tier-download/spec.md`

## Summary

Make the Settings → Modell **Ladda ned** button actually pull a non-bundled tier's model (Snabb `llama3.2:1b`, Stor `gemma3:12b`) through the local Ollama, with streaming progress, an honest categorised failure state, retry, and cancel. The spec-010 stub (`trigger_tier_download` emitting an event consumed by the dead `subscribeTierDownloadRequested` listener) is replaced by a real backend-owned download path.

**Technical approach**: Add a dedicated, parameterised tier-download path in Rust that reuses the existing `OllamaClient::pull(model, on_event)` (already model-generic) but runs **independently** of the spec-008 bundled-model flow — its own at-most-one download state, its own cancel token, its own event channel — so a tier download never disturbs the global `klar` gate or the active model. Extend `PullEvent::Progress` to carry the `completed`/`total` bytes (already parsed in `PullLine`, currently discarded) so the row can show "62 % · 5,0 / 8,1 GB". Categorise pull failures into the four Swedish error buckets. The frontend gets a per-tier downloading/error row in `SettingsPanelModelTier.tsx`, driven by a new tier-download store that subscribes to the backend channel.

## Technical Context

**Language/Version**: Rust (Tauri 2.x core) + TypeScript/React 18 (WKWebView frontend)

**Primary Dependencies**: existing only — `OllamaClient` (reqwest streaming), `tokio_util::sync::CancellationToken`, Zustand. **Net-new deps target: 0.**

**Storage**: none new — model files live in Ollama's own store; tier pulled-state is derived live from `/api/tags` (existing `get_tier_pull_state`).

**Testing**: vitest (frontend store + row component), `cargo test` (tier-download module: state machine, failure categorisation, concurrency guard, model-id mapping), mock-Ollama seam (wiremock, already a dev-dep) for streaming pull / mid-stream error.

**Target Platform**: macOS 12+ desktop (Parallels-tested)

**Project Type**: desktop-app (Tauri Rust core + React frontend)

**Performance Goals**: progress reflected in the row ≥ once/second while the stream produces data (SC-002); start/cancel feel instant.

**Constraints**: localhost-only Ollama (`127.0.0.1:11434`); no new outbound endpoint; no document content on the download path; Swedish, stack-trace-free failures.

**Scale/Scope**: 2 downloadable tiers, at most 1 concurrent download. ~1 new Rust module, ~1 new TS store, edits to `SettingsPanelModelTier.tsx`, `client.rs` (byte-bearing progress), `commands.rs`/`lib.rs` (command wiring), string fixtures.

## Constitution Check

*GATE: Must pass before Phase 0. Re-checked after Phase 1.*

- **I. Privacy by Architecture (NON-NEGOTIABLE)** — ✅ The download is a model pull between the local Ollama and its registry — the exact traffic the constitution already permits ("the initial Ollama model download"). This feature lets the user trigger that already-permitted kind for additional models. No document content touches the path (FR-013); no telemetry; no new outbound endpoint.
- **II. Zero-CLI Install** — ✅ Strengthens it: a user can install a model tier entirely from the GUI instead of `ollama pull` in a Terminal (SC-001).
- **III. Local-Only Inference** — ✅ Pull targets `127.0.0.1:11434/api/pull` only; no remote-host override (invariant `LocalhostOnly`).
- **IV. Single-User Desktop App** — ✅ No service, no accounts; one local actor; in-memory at-most-one download state.
- **V. Swedish-First UI** — ✅ All new copy (progress label, 4 error messages, Avbryt, Försök igen, "AI inte redo ännu") is Swedish + humanizer-reviewed (FR-014).
- **VI. Native macOS Feel** — ✅ Reuses the spec-008 FirstRunProgress visual language and the spec-010 panel styling; no new design language.
- **VII. Bundled Sidecar — Ollama Is Internal Plumbing** — ✅ The UI says "Ladda ned modell", never exposes ports or `ollama` commands; the pull is internal plumbing.
- **VIII. Honest Failure States** — ✅ Core to the spec: four distinct Swedish failure categories, no stack traces, retryable (FR-006/007, SC-003).
- **IX. Open Source, Free** — ✅ No proprietary dependency; net-new deps 0.

**Result: PASS, no violations. Complexity Tracking not required.**

## Project Structure

### Documentation (this feature)

```text
specs/027-on-demand-tier-download/
├── plan.md              # This file
├── research.md          # Phase 0 — design decisions
├── data-model.md        # Phase 1 — entities + state machine
├── quickstart.md        # Phase 1 — manual verification flows
├── contracts/
│   └── tier-download.md # Phase 1 — command + event contract
├── checklists/requirements.md
├── spec.md
└── spec.allium
```

### Source Code (repository root)

```text
src-tauri/src/sidecar/
├── client.rs            # EDIT: PullEvent::Progress gains completed/total bytes (parsed, currently discarded)
└── commands.rs          # unchanged bundled flow; reads new bytes via `Progress { percent, .. }`

src-tauri/src/settings/
├── tier_download.rs     # NEW: at-most-one TierDownload state, start/cancel, failure categorisation, spawn task
├── commands.rs          # EDIT: replace stub trigger_tier_download; add start/cancel/get tier-download commands
└── mod.rs               # EDIT: expose tier_download

src-tauri/src/
└── lib.rs               # EDIT: register the new commands; init tier-download state

src-tauri/tests/
├── tier_download_*.rs   # NEW: state machine, concurrency guard, failure mapping, model-id mapping, no-content-leak
└── fixtures/settings-panel-strings.json  # EDIT: + new Swedish keys

src/components/
└── SettingsPanelModelTier.tsx  # EDIT: download_button row gains downloading/error sub-states + progress + Avbryt/Försök igen

src/lib/
├── tier-download-store.ts   # NEW: Zustand store subscribing to juradrop://settings/tier-download
├── tauri-bridge.ts          # EDIT: replace triggerTierDownload/subscribeTierDownloadRequested with real start/cancel/subscribe
└── settings-panel-strings.ts # EDIT: + new Swedish strings (mirrored to fixture + Rust drift test)

src/__tests__/
├── tier-download-store.test.ts      # NEW
└── SettingsPanelModelTier.test.tsx  # NEW/EDIT: row sub-states
```

**Structure Decision**: Desktop-app split. The tier-download logic lives in a NEW `settings/tier_download.rs` module rather than extending `sidecar/commands.rs::spawn_pull_task`, because that function is hardwired to the bundled model and the global `model_status`/`progress`/`klar` gate. A tier download must NOT move the global gate or the active model — so it gets its own independent state + channel, reusing only the model-generic `OllamaClient::pull`. This keeps the spec-008 first-run flow untouched (lowest regression risk) while satisfying FR-004/005/008/009.

## Complexity Tracking

No constitution violations — section intentionally empty.
