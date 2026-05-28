# Tasks: Parser robustness battery (Spec 015)

- [ ] T001 Create `src-tauri/tests/parser_robustness.rs`: seeded xorshift byte generator, truncation helper, static malformed cases; iterate all 6 formats × all inputs through `extract_text` inside `catch_unwind`; assert no panic + (Ok | Err(ZoneFailure)).
- [ ] T002 Run `cargo test --test parser_robustness`. If any panic surfaces, patch that extractor to return `ZoneFailure` instead of panicking (FR-005), then re-run.
- [ ] T003 Full suite (`cargo test`) + clippy -D warnings + fmt clean.
- [ ] T004 Commit + push; tick 015 in `specs/INDEX.md`.

## Dependencies
T001→T002→T003→T004.
