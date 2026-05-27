# Implementation Plan: First drop zone — Sammanfatta

**Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`) | **Date**: 2026-05-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-first-zone-sammanfatta/spec.md` plus the formal contract in [spec.allium](spec.allium).

## Summary

The user drags a `.docx` onto a single zone labelled "Sammanfatta" in the main window. The Rust core extracts the document body via `docx-rs`, truncates at 24,000 UTF-8 characters if needed, sends the text wrapped in `Redacted<String>` to the local Ollama (`gemma3:4b` via the spec 002 `OllamaClient::generate`) with a fixed Swedish summarization system prompt, then writes the response as a sidecar `.docx` next to the original (`<stem>.sammanfatta.docx` or with a `.YYYY-MM-DD-HHMMSS` suffix on collision) and invokes the OS default handler. The zone surface drives a five-state machine (idle / dragover / processing / success / error) plus a Swedish "Avbryt" cancel affordance during processing. Every error path lands a Swedish honest-failure string per spec 002's pattern. No document bytes leave the Mac (Principle I).

## Technical Context

**Language/Version**: Rust 1.95+ (stable), TypeScript 5.x. Same toolchain as spec 002.

**Primary Dependencies**:
- Rust new: `docx-rs = "0.4"` (extract + write `.docx`), `sha2 = "0.10"` (file-immutability hash for tests), `open = "5"` (OS default-handler invocation — preferred over Tauri's deprecated `shell::open`).
- Rust reused from spec 002: `tauri-plugin-shell`, `reqwest`, `tokio`, `parking_lot`, `thiserror`, `serde`, `chrono`.
- JS new: none (the cancel affordance and drop zone are React + Tailwind only; no new packages).
- JS reused from spec 002: `zustand`, shadcn primitives, `@tauri-apps/api`, `@tauri-apps/plugin-shell`.

**Storage**: filesystem — sidecar `.docx` lands next to the source. No database, no app-data state changes beyond what spec 002 already persists (consent + pidfile). State machine state lives in memory.

**Testing**:
- Rust: `cargo test` (unit + the existing integration files in `src-tauri/tests/`).
- JS: `vitest` (component + hook tests).
- E2E: Playwright smoke test that drives the actual built `.app` per the project's existing pattern.
- TLA+: `/tla` after browser tests per the spec-register pipeline.

**Target Platform**: macOS 12+ on Apple Silicon (M-series) per the constitution + spec 001 platform choice. x86_64 not actively tested.

**Project Type**: Desktop app (Tauri 2.x — Rust core + WKWebView UI). Single binary, no client/server split.

**Performance Goals**:
- SC-001: ≤ 60 s wall-clock for a 5-page `.docx` summary on warm `gemma3:4b`.
- SC-002: ≤ 3 s from any error trigger to its Swedish surface.
- SC-005: ≤ 100 ms visible state transitions (idle→dragover, etc.).
- SC-008: ≤ 1 s from cancel click to zone returning to idle.

**Constraints**:
- Principle I (privacy): no outbound network during a drop. Reuse the FR-023 / SC-003 `lsof` audit pattern from spec 002.
- Principle V (Swedish UI, English code): every user-visible string in Swedish; every identifier/comment in English.
- Principle VIII (honest failure): no `Error:` prefixes, no stack traces, no English fragments.
- spec 002 budget: drop zone disabled when `UserVisibleStatus != Klar`.

**Scale/Scope**: Single user, one zone, one in-flight job at a time. Files in the range of typical Swedish legal documents (≤ ~50 pages). Larger docs are truncated per FR-019.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Privacy by Architecture | No new outbound calls. The model call routes through the existing spec 002 `OllamaClient` to `127.0.0.1:11434`. Document text is wrapped in `Redacted<String>` end-to-end. The runtime `lsof` audit from spec 002 (T054) extends to the drop window. | ✅ |
| II. Zero-CLI Install | No new CLI dependencies. `docx-rs`, `sha2`, `open` are Rust crates linked into the existing `.app`. No Homebrew, no `pip`, no shell scripts in the user path. | ✅ |
| III. Local-Only Inference | All inference goes via spec 002's `OllamaClient::generate` against the bundled Ollama at `127.0.0.1:11434`. No remote-host override. Default model `gemma3:4b`. | ✅ |
| IV. Single-User Desktop App | No backend, no daemon. State machine lives in memory. The zone is a window-bound surface that disappears when the window closes. | ✅ |
| V. Swedish-First UI, English-First Code | All copy in the spec is Swedish. Rust + TS identifiers are English. The output sidecar suffix `.sammanfatta.docx` is Swedish-named per Principle V's filesystem-visible-strings clause. | ✅ |
| VI. Native macOS Feel | The drop zone follows `design-system/MASTER.md` (dashed border, dark/light auto, SF Pro, subtle dragover pulse). File picker not used (drag-and-drop only). OS open uses `open(1)` semantics via the `open` crate, which maps to LaunchServices. | ✅ |
| VII. Bundled Sidecar — Ollama is Internal | The user never sees Ollama. Errors map to Swedish strings (FR-020) — no `connection refused`, no `EADDRINUSE`. The cancel button aborts the inference cleanly; user sees only "Sammanfattning avbruten". | ✅ |
| VIII. Honest Failure States | FR-013 through FR-020 enumerate the seven Swedish error categories. FR-021 forbids `Error:` prefix and English fragments. No silent fallback — every failure reaches a visible Swedish string. | ✅ |
| IX. Open Source, Free, No Lock-In | Output is standard `.docx`. No paywall, no license check, no proprietary format. | ✅ |

**All gates pass. No Complexity Tracking entries required.**

## Project Structure

### Documentation (this feature)

```text
specs/003-first-zone-sammanfatta/
├── spec.md                    # already written
├── spec.allium                # already written + cancel pulled in
├── plan.md                    # this file
├── research.md                # Phase 0 — decisions for new crates and approaches
├── data-model.md              # Phase 1 — Rust/TS data shapes mirroring spec.allium
├── quickstart.md              # Phase 1 — how to exercise the feature end-to-end
├── contracts/                 # Phase 1
│   ├── tauri-commands.md      # invoke API (open_summary, cancel_summary)
│   ├── tauri-events.md        # events emitted to the WebView
│   └── docx-format.md         # sidecar .docx layout per FR-005a
├── checklists/
│   └── requirements.md        # spec quality checklist (already passing)
└── tasks.md                   # Phase 2 — produced by /speckit-tasks (NOT here)
```

### Source Code (repository root)

Spec 002 already established `src/` (React) and `src-tauri/` (Rust core). Spec 003 extends both — no restructuring.

```text
src-tauri/
├── src/
│   ├── lib.rs                                 # MODIFIED — register new commands + events
│   ├── sidecar/                               # existing (spec 002)
│   │   ├── client.rs                          # MODIFIED — accept caller-supplied AbortHandle for cancellation
│   │   ├── commands.rs                        # MODIFIED — add open_summary, cancel_summary tauri::commands
│   │   └── ...
│   ├── zones/                                 # NEW module — drop-zone domain
│   │   ├── mod.rs
│   │   ├── sammanfatta.rs                     # zone state machine + job dispatcher
│   │   ├── docx_extract.rs                    # docx-rs read path; truncation; password detection
│   │   ├── docx_write.rs                      # docx-rs write path (header + truncation notice + body)
│   │   ├── sidecar_path.rs                    # canonical + timestamp-suffix naming, atomic-write helpers
│   │   ├── prompts.rs                         # the fixed Swedish summarization prompt
│   │   ├── job.rs                             # DropJob entity + outcome state machine
│   │   └── errors.rs                          # ZoneError enum + Swedish-string mapping
│   └── ...
├── tests/                                     # existing dir from spec 002
│   ├── zone_sammanfatta_lifecycle.rs          # NEW — drop → summary roundtrip with mock ollama
│   ├── zone_docx_robustness.rs                # NEW — corrupt/password/empty/truncate cases
│   ├── zone_cancel.rs                         # NEW — cancel mid-inference, verify no sidecar written
│   └── ...
└── Cargo.toml                                 # MODIFIED — add docx-rs, sha2, open dev-deps + tempfile

src/
├── App.tsx                                    # MODIFIED — mount SammanfattaZone alongside WelcomeCard
├── components/
│   ├── SammanfattaZone.tsx                    # NEW — drop zone with state machine + cancel button
│   ├── SammanfattaZone.errors.ts              # NEW — Swedish copy mapping (single source of truth)
│   └── ...
├── lib/
│   ├── tauri-bridge.ts                        # MODIFIED — add invokeRunSummary, cancelSummary, listen events
│   └── status-store.ts                        # MODIFIED — add zone state to store
├── __tests__/
│   ├── SammanfattaZone.test.tsx               # NEW — state machine, render, accessibility
│   ├── SammanfattaZone.errors.test.tsx        # NEW — Swedish copy for every error variant
│   └── ...
└── ...

design-system/
└── pages/
    └── 003-sammanfatta-zone.md                # NEW — design notes per the design system
```

**Structure Decision**: Extend spec 002's existing tree. New domain module `src-tauri/src/zones/` keeps drop-zone logic together; spec 004 will add sibling zone modules (`tillengelska.rs`, `tillsvenska.rs`, etc.) under the same prefix. UI gets a new top-level component but reuses the shadcn primitives already in `src/components/ui/`.
