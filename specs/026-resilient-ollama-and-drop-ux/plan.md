# Implementation Plan: Resilient Ollama coexistence + drop-zone affordances

**Branch**: `main` (direct-push workflow) | **Spec**: [spec.md](./spec.md) | **Allium**: [spec.allium](./spec.allium)

## Summary

Make JuraDrop reach a single, consistent "ready" truth regardless of whether the user already runs their own Ollama on `127.0.0.1:11434`. On startup, probe the port first: if a usable Ollama answers, **reuse** it (mark the sidecar Ready, ownership = reused-external, never kill it on shutdown); if the port is free, spawn the bundled sidecar as today (ownership = we-started); if the port is held by a non-Ollama listener, enter an honest plain-Swedish error state. Drive **both** the global header status and the per-zone `disabled` gate from that one readiness signal so they can never drift. Reconcile the already-written drag-over highlight (Rust `Over`/`Leave` → `createDragHoverTracker`) and the 1160×760 startup window so all nine zones are interactive with correct hover feedback.

## Technical Context

**Language/Version**: Rust (Tauri 2.x core) + React 18 / TypeScript (frontend)
**Primary Dependencies**: Tauri 2.x, `reqwest` (already in tree — used by `wait_ready`), tokio; React + Zustand + Tailwind
**Storage**: N/A (no new persistence; readiness is in-memory; window size is config)
**Testing**: `cargo test` (Rust unit + integration), `vitest` (React), gated real-Ollama suite (spec 018)
**Target Platform**: macOS 12+ desktop (Tauri WKWebView)
**Project Type**: single-user desktop app (Rust core + WKWebView frontend)
**Performance Goals**: startup readiness resolved within the existing wizard window; probe timeout ~2 s; no perceptible launch regression
**Constraints**: Principle I (no new outbound traffic), III (localhost-only, no remote host), VII (Ollama invisible — no port/errno/Ollama leaks in UI), VIII (honest Swedish failure)
**Scale/Scope**: 9 zones, 1 readiness model; ~3 Rust modules touched (sidecar manager/status, lib.rs startup, zones gate), ~4 frontend files (3 already partly done)

## Constitution Check

*GATE: must pass before Phase 0. Re-checked after Phase 1 — still passing.*

- **I. Privacy by Architecture** ✅ — No new outbound traffic. The startup probe hits `127.0.0.1:11434/api/tags` (loopback, already used by `wait_ready`). Reusing an external Ollama sends zero new data anywhere. Verified later against the telemetry/privacy denylist guards (SC-008).
- **III. Local-Only Inference** ✅ — Reusing an *already-running localhost* Ollama is **not** a remote-host override. The host stays hardcoded `127.0.0.1:11434`; no config field for a remote host is added. The constitution forbids *remote* hosts, not coexistence with a local one.
- **VII. Bundled Sidecar — Ollama Is Internal Plumbing** ⚠️ **GATE REFINEMENT**: the spec's illustrative copy "Porten 11434 används av ett annat program" leaks the port number and implies the sidecar. Per VII the user must never see a port, "EADDRINUSE", or learn what Ollama is. **Resolution**: the port-conflict copy MUST be implementation-hiding plain Swedish (no "11434", no "Ollama", no errno), finalized via the `humanizer` skill. Captured as a research decision + a copy task.
- **VIII. Honest Failure States** ✅ — port-conflict is a real, named failure surfaced as a calm Swedish status state in the existing `fel_*` family, no stack trace.
- **II / V / VI** ✅ — no CLI exposure; Swedish UI strings via humanizer; no new chrome, reuses existing zone styling.

No violations requiring Complexity Tracking.

## Project Structure

### Documentation (this feature)

```
specs/026-resilient-ollama-and-drop-ux/
├── spec.md
├── spec.allium
├── plan.md              # this file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/readiness-and-drag-events.md   # Phase 1
└── checklists/requirements.md
```

### Source Code (affected)

```
src-tauri/src/
├── lib.rs                     # startup: probe-before-spawn; status→zone refresh already lives here
├── sidecar/
│   ├── manager.rs             # OllamaSidecar: add ownership + reuse path; stop() honors ownership; reuse wait_ready as probe
│   └── status.rs              # SidecarStatus / UserVisibleStatus: single readiness truth; add port-conflict
└── zones/sammanfatta.rs       # refresh_disabled gate (keys off sidecar readiness)
src/
├── App.tsx                    # drag-over tracker wiring (DONE, uncommitted)
├── lib/drag-hover.ts          # tracker (DONE, uncommitted) + __tests__/drag-hover.test.ts
├── lib/tauri-bridge.ts        # file-dragover/leave subs (DONE) + port-conflict status type
├── lib/status-store.ts        # AppStatus: surface port-conflict state
└── components/DropZone.tsx     # disabled gate (verify it mirrors the single truth)
src-tauri/tauri.conf.json       # window 1160×760 (DONE, uncommitted)
```

## Phase 0 — Research

See [research.md](./research.md). Key decisions: probe-before-spawn via the existing `/api/tags` reachability check; an `ownership` enum on the sidecar; the single-readiness-truth alignment (both global `UserVisibleStatus` and per-zone `refresh_disabled` key off `SidecarStatus::Ready` — the fix makes the reused-external path actually set `SidecarStatus::Ready` so they converge); macOS drop-cursor behavior; implementation-hiding port-conflict copy.

## Phase 1 — Design & Contracts

See [data-model.md](./data-model.md), [contracts/readiness-and-drag-events.md](./contracts/readiness-and-drag-events.md), [quickstart.md](./quickstart.md).

## Phase 2 — Task generation (next: /speckit-tasks)

Tasks cover: probe-before-spawn + ownership (Rust); single-truth alignment + port-conflict state (Rust + frontend status type + humanizer'd Swedish copy); reconcile the committed drag-over tracker + window size; functional + destructive tests; `/tla` on the readiness state machine.
