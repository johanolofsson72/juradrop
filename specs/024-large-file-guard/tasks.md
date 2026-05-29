# Tasks: Large-file guard (Spec 024)

- [ ] T001 `errors.rs`: add `FileTooLarge` variant (`#[error("Filen är för stor — max 50 MB")]`, serde `file_too_large`); add to `ALL_VARIANTS`.
- [ ] T002 `extract.rs`: `const MAX_INPUT_FILE_BYTES: u64 = 50 * 1024 * 1024;` + size guard at the top of `extract_text` (metadata error falls through, no panic).
- [ ] T003 Cross-language: add `file_too_large` to `zone-error-strings.json`, `DropZone.errors.ts`, and the TS `ZoneFailure` union in `tauri-bridge.ts` — identical string.
- [ ] T004 [P] Integration test `tests/large_file_guard.rs`: a > 50 MB sparse temp file → `FileTooLarge`; a small file → extracts. (Use a sparse/zero file to avoid writing 50 MB.)
- [ ] T005 Gate: cargo test (errors.rs invariants + drift + new test) + clippy + fmt; vitest drift + typecheck + lint.
- [ ] T006 Commit + push; tick 024 in `specs/INDEX.md`.

## Dependencies
T001→T002. T003 parallel-ish. T004 after T001/T002. T005/T006 last.
