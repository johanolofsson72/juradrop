# Implementation Plan: Panic-site audit + scoped clippy ratchet

**Branch**: `main` (solo / direct-push, no feature branch) | **Date**: 2026-06-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/035-unwrap-audit/spec.md`

## Summary

Audit found **9 production panic-sites** (1 `unwrap`, 8 `expect`, 0 `panic!`), **none on the malformed-input hot path** (extractors already return `Result`, fuzz-hardened in spec 015). So instead of a mass conversion, install a **scoped `deny`-level clippy ratchet** (`unwrap_used` + `expect_used` + `panic`) on the `zones` module tree and the four Tauri command modules, so future panic-sites in the document-processing/command surface fail the existing `cargo clippy -D warnings` CI gate (spec 031). Two local edits: delete the one `split_last().unwrap()` outright (FR-005), and convert `build_summary_doc`'s pack `expect` to a `Result` surfaced through the existing `finalize_with_failure` path (FR-006). The four static-regex `expect`s get explicit `#[allow]` + justification.

## Technical Context

**Language/Version**: Rust 2021 (`src-tauri`). Backend-only. No TS/React.

**Primary Dependencies**: none new. `clippy::unwrap_used`/`expect_used`/`panic` are built-in clippy `restriction` lints (off by default; enabling them is purely additive and clippy-only). `ZoneFailure` (existing) reused for FR-006.

**Storage**: N/A.

**Testing**: `cargo test` (no behavior change — existing docx/extraction probe tests lock byte-identical output); `cargo clippy --all-targets -- -D warnings` is the *primary* gate this spec hardens — it must stay green after annotations/edits, and a temporary injected `unwrap()` must make it fail (SC-001).

**Target Platform**: macOS desktop (Tauri). Pure Rust change.

**Project Type**: Desktop app, Rust core.

**Performance Goals**: none (compile-time lint + 2 trivial refactors; zero runtime impact).

**Constraints**: No behavior change for valid input (FR-007 / SC-004). No new outbound, deps, strings, or UI (SC-005). Lint scope strictly the `zones` tree + command modules — NOT workspace-wide (Assumptions).

**Scale/Scope**: ~3 files edited for the lint attrs + annotations (`zones/mod.rs`, the 4 `*/commands.rs` or their `mod.rs`, `zones/pii_sweep.rs`), 2 behavioral-shape edits (`pii_sweep.rs` split_last; `docx_write.rs` + its 1 caller `sammanfatta.rs`). No new files.

**Key technical decision (lint mechanism — `cfg_attr(not(test))`)**: the inner attribute is `#![cfg_attr(not(test), deny(clippy::unwrap_used, clippy::expect_used, clippy::panic))]`, NOT a bare `#![deny(...)]`. Rationale (caught by `/speckit.analyze`): a bare module-level `#![deny(clippy::unwrap_used)]` ALSO applies to that module's `#[cfg(test)]` submodules, and `cargo clippy --all-targets` lints test code — so a bare deny would fail clippy on every test `unwrap()` (dozens across the zones/command test modules), violating FR-004. Gating with `cfg_attr(not(test), …)` makes the deny active only in the non-test build (where production code is compiled and caught) and absent in the test build (so test `unwrap`/`expect` is never linted) — one attribute per module, no per-test-module `#![allow]`s. Lint levels still cascade: the attribute in `zones/mod.rs` propagates to all `pub mod` children (file-separated submodules included). The four command modules (`settings/`, `sidecar/`, `diagnostics/`, `updater/` `commands.rs`) each get the attribute at their own file top. **Verified empirically in T010** by injecting a temporary `unwrap()` into a deep submodule (`pii_sweep.rs`) and confirming `cargo clippy --all-targets -- -D warnings` fails, then reverting.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment |
|---|---|
| **I. Privacy by Architecture** | ✅ Unaffected — no network, no telemetry, no new outbound. Pure code-quality lint + local refactors. |
| **VIII. Honest Failure States** | ✅ **Strengthened** — removes a `panic!` path on the output `.docx` pack in favour of a `ZoneFailure`, and structurally prevents new panic-sites in the document-processing surface (the one place a panic becomes a user-visible WKWebView crash). |
| **V. Swedish-First UI, English-First Code** | ✅ No new user-facing strings (FR-006 reuses an existing `ZoneFailure` Swedish message). English code/comments. |
| **VII. Bundled Sidecar** | ✅ Reinforced — fewer ways the sidecar-output pipeline can crash without an honest message. |
| **II / III / IV / VI / IX** | ✅ Not implicated. |

**Result: PASS. Zero violations. Strengthens Principle VIII.** No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/035-unwrap-audit/
├── plan.md              # This file
├── spec.md              # audit finding + FR/SC (with Clarifications)
├── tasks.md             # Phase 2 output (/speckit-tasks)
└── checklists/requirements.md
# spec-only track: no research.md/data-model.md/contracts/ — no entities, no unknowns,
# no external interface. The one technical decision (lint propagation) lives in
# Technical Context above and is verified empirically in tasks.
```

### Source Code (repository root)

```text
src-tauri/src/zones/mod.rs
  - ADD inner attr: #![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
    (propagates to the whole zones tree).
src-tauri/src/{settings,sidecar,diagnostics,updater}/commands.rs
  - ADD the same inner attr at each file top (the command modules).
src-tauri/src/zones/pii_sweep.rs
  - FR-005: replace `parts.split_last().unwrap()` with `if let Some((last, head)) = …`.
  - FR-003: add #[allow(clippy::expect_used)] + "// static literal regex, infallible"
    on the 4 LazyLock Regex::new(...).expect(...) sites.
src-tauri/src/zones/docx_write.rs
  - FR-006: `build_summary_doc` returns Result<Vec<u8>, ZoneFailure>; pack().expect ->
    map_err to an existing output-failure ZoneFailure variant.
src-tauri/src/zones/sammanfatta.rs
  - FR-006: the single OutputFormat::Docx caller maps Err -> existing finalize_with_failure.
src-tauri/src/zones/docx_write.rs (#[cfg(test)])
  - update the in-file tests that call build_summary_doc (now Result) — unwrap in test is fine.
```

**Structure Decision**: Module-level lint attributes in the existing `zones` tree + command modules — the smallest, most idiomatic Rust mechanism, scoped exactly to the document-processing/command surface per the spec. No `clippy.toml` (workspace-wide, out of scope). No new module or file.

## Complexity Tracking

> No Constitution Check violations. Section intentionally empty.
