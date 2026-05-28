# Tasks: Anonymisera PII-residue sweep (Spec 014)

- [ ] T001 Promote `regex` to a direct dep in `src-tauri/Cargo.toml` (already transitive).
- [ ] T002 Create `src-tauri/src/zones/pii_sweep.rs`: `PiiFindings` + `scan_residual_pii` (personnummer/email/phone regex via LazyLock, placeholder-masked) + `warning_paragraph`. Wire `pub mod pii_sweep;` in `zones/mod.rs`.
- [ ] T003 [P] Unit tests in pii_sweep.rs: personnummer shapes (YYMMDD-NNNN, YYYYMMDD+NNNN), email, phone (0..., +46); negatives: `T 4521-25` case number, `2015–2020` range, `[Personnr 1]` placeholder; warning builder omits zero categories + returns None when clean.
- [ ] T004 Wire the sweep into `sammanfatta.rs` Anonymisera write path (only `ZoneId::Anonymisera`, output text, prepend warning when residue>0). Humanizer the warning copy.
- [ ] T005 [P] Integration cases in `zone_pipeline_anonymisera.rs`: (a) mock output retains `19010101-0101` → sidecar warning names 1 personnummer; (b) clean placeholder output → no warning paragraph.
- [ ] T006 Full suite (`cargo test`, clippy -D warnings, fmt) + telemetry denylist green (SC-004).
- [ ] T007 `/tla` (distill + drift vs spec.allium + invariant coverage). Surface findings.
- [ ] T008 Commit + push; tick 014 in `specs/INDEX.md`.

## Dependencies
T001→T002→T004. T003/T005 after their targets. T006/T007 last.
