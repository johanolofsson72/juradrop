# Tasks: Panic-site audit + scoped clippy ratchet

**Feature**: 035-unwrap-audit | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

**Track**: spec-only (hardening-as-lint; no new entities/state). No `.allium`, no `/tla`. No interactive UI → no destructive browser tests. The verification is clippy + the existing Rust suite (byte-identical output).

**Ordering note**: convert/remove the in-scope panic-sites (US2 + the FR-005 edit) BEFORE enabling the `deny` lint, otherwise `cargo clippy -D warnings` would fail on the very `expect`s we're fixing.

## Phase 1: Setup & grounding

- [X] T001 Re-confirm the linted scope and the in-scope production sites: `zones/mod.rs` (barrel → propagates to the tree) + `settings/commands.rs`, `sidecar/commands.rs`, `diagnostics/commands.rs`, `updater/commands.rs`; in-scope production panic-sites = `zones/pii_sweep.rs` (4 regex `expect` + 1 `split_last().unwrap()`) and `zones/docx_write.rs` (1 pack `expect`). Identify the existing output-failure `ZoneFailure` variant to reuse for FR-006 by reading `src/zones/errors.rs`.

## Phase 2: User Story 2 — docx pack failure becomes an honest failure (Priority: P2, done first for ordering)

**Goal**: Remove the `panic!` path on the output `.docx` pack (FR-006) so the lint can be enabled cleanly and a pack failure is an honest `ZoneFailure`.

**Independent test**: `build_summary_doc` returns `Result`; its one production caller maps `Err` to `finalize_with_failure`; existing docx round-trip tests stay byte-identical green.

- [X] T002 [US2] In `src/zones/docx_write.rs`, change `build_summary_doc(...) -> Vec<u8>` to `-> Result<Vec<u8>, ZoneFailure>`; replace `.pack(Cursor::new(&mut buf)).expect("…")` with `.map_err(|_| <existing output-failure ZoneFailure>)?` (variant identified in T001); return `Ok(buf)`.
- [X] T003 [US2] In `src/zones/sammanfatta.rs`, the single `OutputFormat::Docx => build_summary_doc(...)` arm (~L274): handle the new `Result` — on `Err(failure)` call `self.finalize_with_failure(&app, job_id, failure).await; return;` (mirroring the existing `write_atomically` error handling just below); on `Ok(bytes)` proceed unchanged.
- [X] T004 [US2] In `src/zones/docx_write.rs` `#[cfg(test)]` tests, update each `build_summary_doc(...)` call to `.unwrap()`/`.expect(...)` the `Result` (test code — unwrap is fine and exempt from the lint).

## Phase 3: User Story 1 — the scoped clippy ratchet (Priority: P1)

**Goal**: Future `unwrap`/`expect`/`panic!` in the parsing + command modules fail CI; existing benign sites are explicitly justified (FR-001/002/003/005).

**Independent test**: inject a temp `unwrap()` into a linted module → `cargo clippy -D warnings` fails; remove → passes (T011).

- [X] T005 [US1] FR-005: in `src/zones/pii_sweep.rs` `join_swedish`, replace the `_ =>` arm's `let (last, head) = parts.split_last().unwrap();` with `if let Some((last, head)) = parts.split_last() { … } else { … }` (or `match`), deleting the panic-site. Behaviour for `len ≥ 2` unchanged.
- [X] T006 [US1] FR-003: on each of the 4 `LazyLock` `Regex::new("<literal>").expect("… regex")` sites in `src/zones/pii_sweep.rs`, add `#[allow(clippy::expect_used)]` with a one-line justification comment ("static literal regex — infallible, test-covered").
- [X] T007 [US1] FR-001/FR-004: add inner attribute `#![cfg_attr(not(test), deny(clippy::unwrap_used, clippy::expect_used, clippy::panic))]` at the top of `src/zones/mod.rs` (propagates to the whole zones tree). The `cfg_attr(not(test), …)` gate is REQUIRED so the deny hits production code but NOT `#[cfg(test)]` test code (a bare `#![deny]` would fail clippy on every test unwrap).
- [X] T008 [P] [US1] FR-001/FR-004: add the same `#![cfg_attr(not(test), deny(clippy::unwrap_used, clippy::expect_used, clippy::panic))]` inner attribute at the top of `src/settings/commands.rs`, `src/sidecar/commands.rs`, `src/diagnostics/commands.rs`, `src/updater/commands.rs`.
- [X] T009 [US1] Run `cd src-tauri && cargo clippy --all-targets -- -D warnings`. For any production panic-site the lint surfaces in scope that wasn't in the audit's 9 (e.g. a `.unwrap()` the brace-strip missed, or one in a command module), either convert it or add `#[allow(clippy::…)]` + a one-line justification. Iterate until clippy is GREEN (SC-002/SC-003). Confirm the deny in `zones/mod.rs` actually reaches deep submodules (propagation) — T010 proves it.

## Phase 4: Verification & polish

- [X] T010 [US1] SC-001 (the ratchet works + propagation): temporarily insert `let _ = Some(1u8).unwrap();` into a deep linted submodule (`src/zones/pii_sweep.rs`, non-test) → `cd src-tauri && cargo clippy --all-targets -- -D warnings` MUST fail naming `clippy::unwrap_used`. Then REVERT the insertion and confirm clippy passes. (Proves the lint catches new sites AND that `zones/mod.rs`'s deny propagates to submodule files.)
- [X] T011 Run `cd src-tauri && cargo test` — full suite green; the docx (`build_summary_doc` round-trip) + extraction probe tests confirm byte-identical output for valid input (FR-007 / SC-004). The one pre-existing spec-017 concurrency_stress flake is acceptable if it passes in isolation.
- [X] T012 [P] Run `cd src-tauri && cargo fmt --check`; run `npm test` + `npm run typecheck` (unaffected — zero TS change) — all clean (SC-005).
- [X] T013 Run `graphify update .` to refresh the knowledge graph after the Rust change.

## Dependencies & ordering

- T001 first (grounding + identify ZoneFailure variant).
- **US2 (T002–T004) before US1's lint enable (T007)** — the pack `expect` must be gone before `#![deny]` lands on `zones`, else clippy fails on it.
- T005 + T006 (remove/annotate pii_sweep sites) before T007 (enable deny on zones) — same reason.
- T007 before T008 logically independent (`[P]` — different files), both before T009.
- T009 (clippy green) before T010 (inject-and-revert proof) before T011/T012/T013.

## Implementation strategy

MVP = US1 (the ratchet). US2 is a prerequisite cleanup that also delivers a standalone Principle-VIII win. Both are small; the whole spec is ~6 edited files, 0 new files, 0 new deps. No runtime behavior change for valid input.

## Notes

- Net new dependencies: **0**. Net new outbound: **0**. Net new Swedish strings: **0** (FR-006 reuses an existing `ZoneFailure` message). Net new UI: **0**.
- `clippy::unwrap_used`/`expect_used`/`panic` are clippy-only restriction lints — `#![deny(...)]` affects `cargo clippy` only, never `cargo build`/`cargo test`.
- The audit's finding (9 production sites, hot path already `Result`-safe per spec 015) is recorded in spec.md §"Audit result" (FR-008).
