# Spec register

Order of execution. Tick when done. Append new specs to the end unless renumbering is justified.

The pipeline track for each spec is triaged per `.claude/rules/specs.md`:
- **full** — behavior-changing, new entities or state machines → spec → `/clarify` → `/allium:elicit` → impl → browser tests → `/tla`
- **light** — UI feature, single actor, no new concurrency → spec → `/clarify` → `/allium:elicit` → impl → browser tests (skip `/tla` unless state is non-trivial)
- **spec-only** — pure refactor, config, docs, infra → spec → `/clarify` → impl

## Specs

- [x] 001 — tauri-bootstrap — light — scaffold Tauri 2.x + React + TypeScript + Tailwind + shadcn/ui, empty window, package.json scripts wired
- [x] 002 — ollama-sidecar-poc — full — bundle Ollama binary, start/stop lifecycle from Rust, prove first-launch model pull + one inference round-trip works end-to-end
- [ ] 003 — first-zone-sammanfatta — full — one drop zone ("Sammanfatta"), .docx in → .docx sidecar out, full state machine (idle → dragover → processing → success/error), Swedish error states
- [ ] 004 — all-six-zones — light — extend to 2×3 grid: TillEngelska, TillSvenska, Sammanfatta, Punktlista, Anonymisera, Förenkla; per-zone system prompts in src-tauri/src/prompts/
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
