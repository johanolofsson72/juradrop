# Implementation Plan: All six drop zones (2×3 grid)

**Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`) | **Date**: 2026-05-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-all-six-zones/spec.md` plus the formal contract in [spec.allium](spec.allium).

## Summary

Refactor the spec 003 `SammanfattaZone` into a generic `DropZone` parameterised by a new `ZoneId` enum (six variants), add five new per-zone prompt modules (`tillengelska`, `tillsvenska`, `punktlista`, `anonymisera`, `forenkla`), wire a 2×3 CSS-grid layout in `App.tsx`, and route OS-level drag-drops to the correct zone via the WebView's `elementFromPoint` pattern (FR-010a). Disclaimer paragraphs for Anonymisera (FR-013) and Förenkla (FR-014) get inserted between the per-zone FR-009 header and the model body. State machine, error variants, atomic write, cancel semantics, and the disabled gate carry over from spec 003 unchanged — only cardinality (1 → 6) and per-zone identity vary.

## Technical Context

**Language/Version**: Rust 1.95+, TypeScript 5.x. Same toolchain as spec 003.

**Primary Dependencies**: Same as spec 003 — `docx-rs`, `open`, `tokio-util`, `uuid`, `zip`, `chrono`, `reqwest`. **No new external deps.**

**Storage**: Filesystem (sidecar `.docx` next to source). No state changes beyond what spec 002 + 003 already persist.

**Testing**:
- Rust: `cargo test` + the existing `tests/` integration files; new `tests/zone_parametric.rs` for the six-way table test.
- JS: vitest; new parameterised tests in `src/__tests__/DropZone.parametric.test.tsx` covering all six zones.
- Light pipeline → no `/tla` (state machine unchanged from spec 003).
- E2E: Playwright stub stays as-is (manual verification via `npm run tauri dev`).

**Target Platform**: macOS 12+ on Apple Silicon (M-series). Unchanged.

**Project Type**: Desktop app (Tauri 2.x). Unchanged.

**Performance Goals**:
- SC-001 per zone: ≤ 60 s wall-clock for a 5-page `.docx` summary with `gemma3:4b` warm.
- SC-002: two zones in Processing simultaneously without UI blocking.
- SC-005: 2×3 grid visible at ≥ 920 px viewport; collapses to 3×2 below.
- SC-006: cancel on zone A does NOT touch zone B's in-flight job.

**Constraints**:
- Principle I (privacy): no new outbound surface; the elementFromPoint routing keeps paths in the Rust event payload, not the HTML5 drag-drop API.
- Per-zone independence: each zone owns its single-flight slot + cancel token + event channel.
- Single shared `OllamaClient` (Ollama serialises inference queue server-side).

**Scale/Scope**: Six zones, one user, sub-50-page documents. Bulk multi-zone drop is explicitly out of scope.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Privacy by Architecture | No new outbound calls. Drop routing via elementFromPoint keeps file paths in the Rust event payload; the WebView only receives the zone id + ack. Every prompt still wrapped in `Redacted<String>`. | ✅ |
| II. Zero-CLI Install | No new dependencies. Pure refactor + new module files. | ✅ |
| III. Local-Only Inference | All six zones route through the existing `OllamaClient` to `127.0.0.1:11434`. | ✅ |
| IV. Single-User Desktop App | Six zones, one user, in-memory state. No backend. | ✅ |
| V. Swedish-First UI, English-First Code | Six per-zone hints + six titles + two disclaimer paragraphs — all Swedish. Code in English. Filesystem-visible suffixes (`tillengelska`, `anonymiserad`, etc.) are Swedish per Principle V's clause. | ✅ |
| VI. Native macOS Feel | Same dashed-border treatment per zone. SF Pro. Grid layout uses CSS grid, not a heavy table component. | ✅ |
| VII. Bundled Sidecar Internal | Six zones, one bundled Ollama. The user never sees model selection per zone. | ✅ |
| VIII. Honest Failure States | Per-zone disclaimers on Anonymise + Förenkla make the model's limitations honest in the `.docx` itself. All nine spec 003 error variants apply per zone. | ✅ |
| IX. Open Source, Free, No Lock-In | Output is still standard `.docx`. No paywall, no licence check. | ✅ |

**All gates pass.** No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/004-all-six-zones/
├── spec.md                    # written
├── spec.allium                # written + per-zone hints pulled in
├── plan.md                    # this file
├── research.md                # Phase 0 — decisions for new layout + routing
├── data-model.md              # Phase 1 — ZoneId enum + ZoneIdentity table
├── quickstart.md              # Phase 1 — six smoke flows
├── contracts/                 # Phase 1
│   ├── tauri-commands.md      # dispatch_to_zone, cancel_summary (zone-aware)
│   ├── tauri-events.md        # juradrop://file-dropped + juradrop://zone/<slug>
│   └── docx-format.md         # per-zone header templates + disclaimer rules
├── checklists/
│   └── requirements.md        # already passing
└── tasks.md                   # Phase 2 — produced by /speckit-tasks
```

### Source Code (repository root)

```text
src-tauri/
├── src/
│   ├── lib.rs                                 # MODIFIED — handle_drag_drop emits juradrop://file-dropped + new dispatch_to_zone command registered
│   ├── sidecar/
│   │   └── commands.rs                        # MODIFIED — cancel_summary takes zone_id; new dispatch_to_zone command
│   ├── zones/                                 # MODIFIED — refactored
│   │   ├── mod.rs                             # MODIFIED — re-export ZoneId
│   │   ├── zone_id.rs                         # NEW — ZoneId enum + ZoneIdentity associated functions
│   │   ├── drop_zone.rs                       # NEW — generalised version of sammanfatta.rs (six instances)
│   │   ├── sammanfatta.rs                     # MODIFIED — kept as a thin alias during the refactor, eventually deleted or repurposed
│   │   ├── docx_write.rs                      # MODIFIED — header template per ZoneId; disclaimer for Anonymise + Förenkla
│   │   ├── sidecar_path.rs                    # MODIFIED — canonical_for(source, zone_id) takes the suffix from ZoneId
│   │   └── ...
│   └── prompts/                               # NEW MODULE
│       ├── mod.rs                             # re-exports per-zone constants
│       ├── sammanfatta.rs                     # MOVED from zones/prompts.rs
│       ├── tillengelska.rs                    # NEW
│       ├── tillsvenska.rs                     # NEW
│       ├── punktlista.rs                      # NEW
│       ├── anonymisera.rs                     # NEW
│       └── forenkla.rs                        # NEW
├── tests/
│   ├── zone_sammanfatta_lifecycle.rs          # MODIFIED — parameterised over ZoneId where possible
│   ├── zone_parametric.rs                     # NEW — six-way table asserting suffix + header + prompt presence
│   ├── zone_cancel.rs                         # MODIFIED — per-zone scope assertions
│   ├── zone_docx_robustness.rs                # MODIFIED — extends fixture with the two disclaimer strings
│   └── fixtures/
│       └── zone-error-strings.json            # unchanged (no new ZoneFailure variants)

src/
├── App.tsx                                    # MODIFIED — 2×3 grid layout, mounts six DropZone instances
├── components/
│   ├── DropZone.tsx                           # RENAMED from SammanfattaZone.tsx; takes zoneId prop + reads identity from a TS mirror
│   ├── DropZone.errors.ts                     # RENAMED from SammanfattaZone.errors.ts
│   ├── DropZone.identity.ts                   # NEW — per-zone title + hint + suffix + slug TS mirror of ZoneIdentity
│   └── ...
├── lib/
│   ├── tauri-bridge.ts                        # MODIFIED — cancelSummary(zoneId, jobId); subscribeZone(zoneId, cb); dispatchToZone(zoneId, paths); fileDropped subscription
│   └── status-store.ts                        # MODIFIED — zone slice keyed by ZoneId (record of per-zone snapshots)
├── __tests__/
│   ├── DropZone.test.tsx                      # RENAMED + extended; parameterised over ZoneId
│   ├── DropZone.errors.test.tsx               # RENAMED
│   ├── DropZone.identity.test.tsx             # NEW — asserts per-zone copy + suffix table
│   └── ...

design-system/
└── pages/
    └── 004-six-zone-grid.md                   # NEW — 2×3 grid layout + responsive collapse notes
```

**Structure Decision**: Bounded refactor. The existing spec 003 module structure stays; we generalise `SammanfattaZone` → `DropZone` and add five new prompt modules. No new crates, no new external dependencies. The React layer renames the component but keeps the same shadcn/Tailwind primitives. The Rust prompts move from `src-tauri/src/zones/prompts.rs` to a sibling `src-tauri/src/prompts/` module with one file per zone so each prompt has its own commit history and review surface.
