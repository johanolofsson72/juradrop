# Spec register

Order of execution. Tick when done. Append new specs to the end unless renumbering is justified.

The pipeline track for each spec is triaged per `.claude/rules/specs.md`:
- **full** — behavior-changing, new entities or state machines → spec → `/clarify` → `/allium:elicit` → impl → browser tests → `/tla`
- **light** — UI feature, single actor, no new concurrency → spec → `/clarify` → `/allium:elicit` → impl → browser tests (skip `/tla` unless state is non-trivial)
- **spec-only** — pure refactor, config, docs, infra → spec → `/clarify` → impl

## Specs

- [x] 001 — tauri-bootstrap — light — scaffold Tauri 2.x + React + TypeScript + Tailwind + shadcn/ui, empty window, package.json scripts wired
- [x] 002 — ollama-sidecar-poc — full — bundle Ollama binary, start/stop lifecycle from Rust, prove first-launch model pull + one inference round-trip works end-to-end
- [x] 003 — first-zone-sammanfatta — full — one drop zone ("Sammanfatta"), .docx in → .docx sidecar out, full state machine (idle → dragover → processing → success/error), Swedish error states
- [x] 004 — all-six-zones — light — extend to 2×3 grid: TillEngelska, TillSvenska, Sammanfatta, Punktlista, Anonymisera, Förenkla; per-zone system prompts in src-tauri/src/prompts/
- [ ] 005 — additional-input-formats — light — add .pdf (via pdf-extract), .txt, .md input parsers; mirror-input output rules
- [ ] 006 — signing-and-ci — spec-only — Apple Developer cert into GitHub Secrets, tauri-action workflow, first signed + notarized DMG to GitHub Releases on tag push
- [ ] 007 — auto-updater — full — wire Tauri's built-in updater (signed manifest, restart prompt, update state machine), test v0.1 → v0.2 path end-to-end
- [ ] 008 — first-run-wizard — full — welcome screen, model download progress UI, first-launch state (not-downloaded → downloading → ready), graceful resume on network drop
- [ ] 009 — long-tail-formats — light — best-effort .rtf, .pages, .odt input; degrade to "format not supported" with named-format Swedish error when extraction fails
- [ ] 010 — settings-panel — light — gear-icon slide-in panel, model selector ("Snabb / Smart / Stor"), appearance follows system, About section
- [ ] 011 — error-recovery — full — sidecar crash detection + auto-restart (one retry), Swedish failure messages, no stack traces leaked to UI, telemetry-free
- [ ] 012 — polish-and-public-beta — spec-only — final pass before public announcement: README polish, screenshots, beta test with 3+ Swedish law students, fix surfaced rough edges

## Register history

Append a line every time the register is rewritten or reordered. Date + reason.

- 2026-05-25 — initial register, 12 specs identified during project inception (`/project-wizard`). Phases from PROJECT-BRIEF.md decomposed into one-task-sized specs.
- 2026-05-26 — spec 001 (tauri-bootstrap) marked done; spec 002 (ollama-sidecar-poc) started. Implementation pushed in commit fc98a68; user confirmed manual destructive-test verifications.
- 2026-05-27 — spec 002 (ollama-sidecar-poc) marked done; 65/70 tasks ticked. Five tasks acknowledged-as-deferred per user direction: T017a (retrospective frontend-design checkpoint that cannot be backfilled), T063 (double-click guard on `run_roundtrip_dev` deferred to spec 003 where the real drop-zone state machine lives), T064/T067/T068 (manual real-hardware user verifications). Final commit 7976d02. Spec 003 (first-zone-sammanfatta) next.
- 2026-05-27 — spec 003 (first-zone-sammanfatta) marked done; 70/70 tasks ticked. Full pipeline: spec → /clarify (3 auto-picked) → /allium:elicit (cancel pulled in mid-elicitation) → /plan → /tasks → /speckit-analyze (G1+G2+C1 auto-applied) → /implement (Phase 3-7) → browser tests (zone_sammanfatta_lifecycle, zone_docx_robustness, zone_cancel + 5 vitest blocks) → /tla (1 GAP closed, 1 drift item amended). 79 Rust unit + 36 Rust integration + 123 vitest tests = 238 tests green. T066/T067 (SC-001 60s cold launch, SC-005 100ms transitions) ticked but flagged as manual-real-hardware in the task notes — automated tests cover the invariants; the wall-clock verification needs a real M-series Mac. Spec 004 (all-six-zones) next.
- 2026-05-27 — spec 004 (all-six-zones) marked done; 51/51 tasks ticked. Light track per the register — spec → /clarify (3 auto-picked) → /allium:elicit (per-zone hint copy pulled in mid-elicitation) → /plan → /tasks → /speckit-analyze (3 low findings, none blocking) → /implement (Phases 2-7, refactor + 5 new zones + grid + parametric tests) → /tla skipped (light track, state machine unchanged from spec 003). 90 Rust unit + 8 parametric + 37 spec 003 integration + 133 vitest tests = 268 tests green. SammanfattaZone refactored into a generic DropZone parameterised by ZoneId; six per-zone Swedish system prompts in src-tauri/src/prompts/; FR-013/014 disclaimer paragraphs on Anonymisera + Förenkla; 2×3 CSS grid in App.tsx with elementFromPoint drop routing; per-zone juradrop://zone/<slug> event channels; zone-aware cancel_summary + new dispatch_to_zone tauri commands; zone-error-strings.json and new zone-identity.json fixtures keep Rust/TS in lock-step. T038/T041–T046 (lsof, parallel-zones, seam-drop, resize, SC-001, SC-005) flagged manual; T049 (compat shim deletion) deferred to spec 005 — three lines of code, low risk, paired with the spec 005 reorg. Spec 005 (additional input formats — .pdf, .txt, .md) next.
