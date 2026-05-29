# Tasks: Prompt-injection input framing (Spec 022)

- [ ] T001 Create `src-tauri/src/prompts/framing.rs`: marker + guard constants (Swedish, humanizer); `frame_prompt(zone, system_prompt, document) -> String` (Generera = INSTRUKTIONER markers, no guard; others = guard + DOKUMENT markers). Wire `pub mod framing;` + re-export in `prompts/mod.rs`.
- [ ] T002 [P] Unit tests in framing.rs: transform-zone has guard + DOKUMENT markers with document between them; Generera has INSTRUKTIONER markers + NO guard; injection string fully contained; empty document framed without panic.
- [ ] T003 Wire `frame_prompt` into `sammanfatta.rs` (replace the raw `format!("{}\n\n{}", system_prompt, extracted)`); keep the `Redacted` wrap.
- [ ] T004 Humanizer the guard sentence; pin as a constant.
- [ ] T005 Gate: `cargo test` (zone-pipeline + real-ollama still green) + clippy -D warnings + fmt.
- [ ] T006 Commit + push; tick 022 in `specs/INDEX.md`.

## Dependencies
T001→T003. T002 after T001. T005/T006 last.
