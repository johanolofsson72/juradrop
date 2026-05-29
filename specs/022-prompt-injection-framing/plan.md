# Implementation Plan: Prompt-injection input framing (Spec 022)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: light

## Summary

A single `prompts::frame_prompt(zone, system_prompt, document)` assembles the model prompt with the document delimited + a Swedish anti-injection guard (except Generera, framed as instructions without the guard). The dispatcher uses it instead of raw concatenation. Pure string assembly, no new deps. No state machine → skip `/tla`.

## Constitution Check
- **I. Privacy:** PASS — pure local string assembly, still Redacted before logging, no outbound.
- **V. Swedish-first:** PASS — guard + markers Swedish, humanizer.
- Gate: PASS.

## Approach

- `src-tauri/src/prompts/framing.rs` (or in `prompts/mod.rs`): constants for the markers + guard; `frame_prompt(zone, system_prompt, document) -> String`.
  - Generera: `{system_prompt}\n\n{instr_begin}\n{document}\n{instr_end}`.
  - Others: `{system_prompt}\n\n{GUARD}\n\n{doc_begin}\n{document}\n{doc_end}`.
- Wire `prompts::frame_prompt(self.id, self.id.system_prompt(), extracted.raw.as_inner())` into `sammanfatta.rs` (replace the raw `format!`), still wrapped in `Redacted`.
- Unit tests in framing.rs: transform-zone shape, Generera shape, injection-contained, empty doc.
- Humanizer the guard sentence.

## Phases
1. `framing.rs` + constants + `frame_prompt` + unit tests.
2. Wire into dispatcher; humanizer guard copy.
3. Gate: cargo test (zone-pipeline + real-ollama stay green) + clippy + fmt.
