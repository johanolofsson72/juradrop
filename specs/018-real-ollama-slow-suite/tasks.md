# Tasks: Real-Ollama slow suite (Spec 018)

- [ ] T001 Create `src-tauri/tests/real_ollama_zones.rs`: one `#[ignore = "HARDWARE: ..."]` looping test; skip guard (list_tags Err / no gemma3:4b → eprintln + return); per-zone real handle_drop on the fixture; assert sidecar + non-empty + source-unchanged + disclaimer.
- [ ] T002 Update `src-tauri/tests/ignore_audit.rs`: expected `ignore_count` 1 → 2, comment naming sidecar_roundtrip + real_ollama_zones.
- [ ] T003 Verify: `cargo test` green (slow test ignored); `cargo test --test real_ollama_zones -- --ignored` skips cleanly (no model here); clippy -D warnings + fmt.
- [ ] T004 Commit + push; tick 018 in `specs/INDEX.md`.

## Dependencies
T001→T002→T003→T004.
