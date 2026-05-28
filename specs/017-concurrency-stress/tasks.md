# Tasks: Concurrency stress tests (Spec 017)

- [ ] T001 Create `src-tauri/tests/concurrency_stress.rs`: ZONE_CASES table (9 × zone/fixture/response/markers), a per-zone async runner returning (zone, sidecar_text, source_sha_ok), a 3-round `join_all` loop.
- [ ] T002 Assertions: every zone's sidecar correct (suffix + markers + non-empty); no cross-zone contamination (no foreign unique marker); all sources byte-identical; disclaimer present for disclaimer zones.
- [ ] T003 Run `cargo test --test concurrency_stress`. If a race/contamination/deadlock surfaces, fix the code (FR-006), re-run.
- [ ] T004 Full suite + clippy -D warnings + fmt.
- [ ] T005 Commit + push; tick 017 in `specs/INDEX.md`.

## Dependencies
T001→T002→T003→T004→T005.
