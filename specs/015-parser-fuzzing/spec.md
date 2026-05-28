# Feature Specification: Parser robustness battery

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: Draft
**Track**: Spec-only (hardening expressed as tests; no new entities, no new state transitions → no `.allium`, no `/tla`).

**Input**: The six document extractors (docx, pdf, txt, md, rtf, odt) take untrusted, potentially malformed or maliciously-crafted files — users drop confidential documents that may be corrupt, truncated, or hostile. A panic or hang in an extractor leaks a Rust stack trace to the UI (violates Principle VIII) or freezes the app. Add a deterministic robustness battery that feeds each extractor a wide range of malformed inputs and asserts: no panic, no crash, a `ZoneFailure` on failure (never an `unwrap`/index panic), bounded time.

## Why this spec exists

The extractors have spot robustness tests (a few garbage-byte cases per format), but no systematic coverage. Crafted input is exactly the class of bug that survives happy-path testing. A reproducible, deterministic battery (committed, runs on every `cargo test`, no nightly) hardens the highest-risk attack surface: parsing untrusted files.

## What's IN scope

| Item | Type |
|---|---|
| `tests/parser_robustness.rs` — battery across all 6 formats | Test |
| Malformed input generators (deterministic, seeded): empty, single-byte, seeded-random bytes, truncated-valid, valid-header+garbage-body, null bytes, invalid UTF-8, oversized-bounded | Test |
| `catch_unwind` wrapper asserting no extractor panics | Test |
| Assert failures surface as `ZoneFailure` (the typed error), not a panic | Test |

## What's OUT of scope

| Item | Reason |
|---|---|
| `cargo-fuzz` coverage-guided fuzzing | Needs nightly + a separate `fuzz/` crate + long run times; not CI-friendly here. Documented as a future option. The deterministic battery covers the same failure classes reproducibly. |
| Fixing any specific parser bug | If the battery finds one, that's a follow-up fix; this spec adds the net. |
| Performance/timeout enforcement via threads | Inputs are size-bounded so a hang can't come from huge allocations; library infinite-loops on bounded input are out of scope (would be an upstream bug). |

## Clarifications

### Session 2026-05-29 (auto-picked)

- Q: Real cargo-fuzz or a deterministic in-tree battery? → A: **Deterministic battery.** Reproducible, runs on every `cargo test` with zero new tooling, and covers the same failure classes (truncation, garbage, malformed containers). cargo-fuzz noted as a future enhancement.
- Q: What counts as "pass" for a malformed input? → A: **No panic + returns** (either `Ok` with best-effort text or `Err(ZoneFailure)`). Best-effort extractors (txt/md) may return `Ok` on garbage; container formats (docx/odt/pdf/rtf) should return `Err`. The universal invariant is "no panic, no hang."
- Q: How is randomness made deterministic? → A: **Seeded xorshift, no rng dep.** Fixed seeds → identical bytes every run → reproducible failures.

## Requirements

- **FR-001**: `src-tauri/tests/parser_robustness.rs` MUST feed each of the 6 extractors a battery of malformed inputs and assert no panic via `std::panic::catch_unwind`.
- **FR-002**: The battery MUST include: empty file, single byte, seeded-random bytes (≥3 fixed seeds), each committed valid probe truncated at 1/4 / 1/2 / 3/4, a valid magic header followed by garbage, embedded null bytes, and invalid UTF-8 sequences.
- **FR-003**: For every (format, input) pair the extractor MUST return a value (Ok or Err) — never panic. On failure it MUST be the typed `ZoneFailure`, asserting the error path is wired (no `unwrap`/index-panic leak).
- **FR-004**: Inputs MUST be size-bounded (≤ ~1 MB) so the battery cannot hang on allocation. Deterministic — identical bytes every run.
- **FR-005**: If the battery surfaces a real panic in an extractor, that extractor MUST be fixed (the panic patched to a `ZoneFailure`) as part of this spec.

## Success Criteria

- **SC-001**: `cargo test --test parser_robustness` passes — zero panics across all (format × malformed-input) pairs.
- **SC-002**: The battery covers all 6 formats × ≥8 malformed-input classes.
- **SC-003**: Deterministic — two runs produce identical results.
- **SC-004**: Net new deps: 0 (seeded xorshift, no rng crate).
- **SC-005**: Runtime < 5s (size-bounded inputs).
