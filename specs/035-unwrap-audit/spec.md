# Feature Specification: Panic-site audit + scoped clippy ratchet

**Feature Branch**: `035-unwrap-audit` (direct-push to `main`, no feature branch per project workflow)

**Created**: 2026-06-03

**Status**: Draft

**Input**: User description: "Audit the production `unwrap()`/`expect()`/`panic!`/`unreachable!` sites; convert any on the document-processing hot path to honest `ZoneFailure`s (Principle VIII), leave benign mutex locks; add a scoped `clippy::unwrap_used`/`expect_used` lint on the command + parsing modules to ratchet it down."

## Audit result (the finding that shapes this spec)

A brace-aware strip of `#[cfg(test)]` modules and `#[test]`/`#[tokio::test]` functions across `src-tauri/src/**/*.rs` finds **9 production panic-sites** — not the register's rounded "167", which counted test-code assertions. Breakdown: **1 `.unwrap()`, 8 `.expect()`, and ZERO `panic!`/`unreachable!`/`todo!`/`unimplemented!`** in production code.

**Critically, none are on the malformed-input hot path.** The document extractors (`.docx`/`.pdf`/`.rtf`/`.odt`/`.txt`/`.md`) already return `Result<_, ZoneFailure>` and were fuzz-hardened in spec 015 (82-case battery, 0 panics). So the register's "convert hot-path unwraps to ZoneFailure" premise finds essentially nothing to convert — that work already shipped.

The 9 sites, classified:

| # | Site | Kind | Class |
|---|---|---|---|
| 1–4 | `zones/pii_sweep.rs` (4×) | `Regex::new("<literal>").expect(...)` in `LazyLock` | **Infallible by construction** — compile-time-constant regex, test-covered |
| 5 | `zones/pii_sweep.rs` `join_swedish` | `parts.split_last().unwrap()` | **Provably infallible** — only reached in the `_ =>` arm of `match parts.len()` (len ≥ 2) |
| 6 | `sidecar/client.rs` `with_base_url` | `reqwest::Client::builder()…build().expect(...)` | **Infallible by construction** — static config; constructor returns `Self` |
| 7 | `lib.rs` `run()` | `.expect("…build JuraDrop tauri application")` | **Acceptable startup panic** — nothing to recover to if the app can't build |
| 8 | `help/zone_help.rs` | `.expect("ZONE_HELP_STRINGS is total over ZoneId")` | **Infallible by construction** — static map over the `ZoneId` enum, test-locked |
| 9 | `zones/docx_write.rs` `to_docx_bytes` | `docx.build().pack(Cursor::new(&mut buf)).expect(...)` | **On the output path** — effectively infallible (Vec cursor) but the one genuine Principle-VIII conversion candidate |

The real deliverable is therefore the **preventive ratchet**, not a mass conversion: a scoped clippy lint so the parsing + command modules cannot accrue *new* panic-sites, plus two local hardening edits (remove site 5's unwrap outright; make site 9 return a `Result`).

## Clarifications

### Session 2026-06-03

- Q: FR-006 — convert site 9 (`build_summary_doc` docx pack) to return a `Result`, or keep the `expect` with an `#[allow]` + justification? → A: **Convert.** `build_summary_doc` has exactly ONE production caller (`zones/sammanfatta.rs` `OutputFormat::Docx` arm), which already sits directly above an existing `finalize_with_failure(...)` honest-failure path. The ripple is a single `match` arm reusing the existing `ZoneFailure` output-failure machinery — small enough that converting (Principle VIII) is preferred over allow-listing.
- Q: What lint level for the scoped lints — `deny` or `warn`? → A: **`deny`** (`#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic)]`). The `clippy::*` restriction lints affect only `cargo clippy`, never `cargo build`/`cargo test`, so `deny` is safe for normal builds AND red both locally and under the CI `-D warnings` gate — the strongest ratchet with no downside.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A future careless `unwrap()` in a parser fails CI, not a user's Mac (Priority: P1)

A contributor (or a future me) adds `something.unwrap()` to a document parser or a Tauri command handler — the exact place where malformed input or a sidecar hiccup could make it panic and crash the WKWebView with no honest Swedish error (Principle VIII violation). Today nothing stops that. After this spec, the scoped `clippy::unwrap_used`/`expect_used`/`panic` lints on those modules turn it into a hard `cargo clippy -D warnings` failure in the existing CI gate (spec 031), so it never reaches a release. Legitimately-infallible sites stay compiling only because each carries an explicit `#[allow(...)]` with a one-line justification — making every exception auditable instead of silent.

**Why this priority**: This is the feature. The value is preventive: the document-processing surface is the one place a panic becomes a user-visible crash, and the lint makes that class of regression impossible to merge unnoticed.

**Independent Test**: Add a throwaway `let _ = Some(1u8).unwrap();` to a linted parser module and run `cargo clippy -- -D warnings` → it MUST fail. Remove it → clippy passes. The kept-benign sites compile clean because of their justified `#[allow]`.

**Acceptance Scenarios**:

1. **Given** the lint is installed on the parsing + command modules, **When** a new `.unwrap()`/`.expect()`/`panic!` is added to one of those modules in non-test code, **Then** `cargo clippy --all-targets -- -D warnings` fails with a clippy diagnostic naming the lint and the site.
2. **Given** the existing benign sites in those modules, **When** clippy runs, **Then** it passes — because each benign site carries an `#[allow(clippy::…)]` with a justification comment; there are no un-annotated panic-sites left in the linted scope.
3. **Given** test code in the linted modules, **When** clippy runs, **Then** `unwrap()`/`expect()` in `#[cfg(test)]` / `#[test]` code does NOT trip the lint (tests legitimately use them for assertions).

### User Story 2 - A `.docx` pack failure becomes an honest failure, not a panic (Priority: P2)

The output writer packs the model's result into an in-memory `.docx`. Today a pack failure would `panic!` (crash). After this spec it returns a `Result` so the existing sidecar-output pipeline surfaces an honest Swedish failure (Principle VIII), consistent with how every other output/parse failure is already handled.

**Why this priority**: Smaller, concrete Principle-VIII improvement on the one production site that is on a real I/O-shaped path. P2 because in practice an in-memory Vec pack does not fail; the value is removing the panic *path*, not fixing a live crash.

**Independent Test**: `to_docx_bytes` (or its return-type-changed form) returns a `Result`; its caller maps an `Err` to the existing output-failure handling. Existing docx round-trip tests still pass byte-identically for valid input.

**Acceptance Scenarios**:

1. **Given** a valid model response, **When** the output `.docx` is built, **Then** the bytes are produced exactly as before (byte-identical; existing docx probe tests stay green).
2. **Given** a (hypothetical) pack failure, **When** the writer runs, **Then** it returns an error that the caller surfaces as an honest failure — no `panic!`, no crash, no stack trace to the UI.

### Edge Cases

- **A benign site that the lint flags but is genuinely infallible** (static regex, match-guarded): handled by an explicit `#[allow(clippy::expect_used)]` + a one-line "why this can't panic" comment. No site is silently exempted.
- **Site 5 (`split_last().unwrap()`)**: removed outright by restructuring to `if let Some((last, head)) = parts.split_last()` — a panic-site deleted rather than allow-listed, because deletion is cheaper than justification here.
- **A new contributor adds `unwrap()` outside the linted modules** (e.g. `lib.rs` startup, `updater/`): out of scope — the lint is deliberately scoped to the parsing + command surface where a panic becomes a user-visible document-processing crash. Widening to a workspace deny would force annotating dozens of benign startup/test expects for no safety gain.
- **`cargo clippy` without `-D warnings`**: the lint is set so it integrates with the existing `-D warnings` CI gate; locally `cargo clippy` may merely warn, but CI (spec 031) runs `-D warnings` and blocks.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST enable `clippy::unwrap_used`, `clippy::expect_used`, and `clippy::panic` at **`deny`** level (Clarifications Q2) on the document-parsing/processing modules (the `zones` module tree) and the Tauri command modules, scoped so they apply to non-test production code in those modules and affect only `cargo clippy` (not `cargo build`/`cargo test`).
- **FR-002**: The lints MUST be configured so that, under the existing CI gate `cargo clippy --all-targets -- -D warnings` (spec 031), any new `unwrap()`/`expect()`/`panic!` in the linted production scope causes a CI failure.
- **FR-003**: Every existing production panic-site that remains inside a linted module MUST carry an explicit `#[allow(clippy::…)]` attribute with a one-line justification comment explaining why it cannot panic. No panic-site in the linted scope may be left both un-converted and un-annotated.
- **FR-004**: Test code (`#[cfg(test)]` modules, `#[test]`/`#[tokio::test]` functions) MUST NOT be subject to these lints — tests may use `unwrap()`/`expect()` freely.
- **FR-005**: The `split_last().unwrap()` site in `pii_sweep.rs` MUST be removed by restructuring to a non-panicking form (e.g. `if let`/`match`), eliminating the panic-site rather than allow-listing it.
- **FR-006**: The `build_summary_doc` output-pack `expect` in `docx_write.rs` MUST be converted so the function returns a `Result` and a pack failure surfaces as an honest `ZoneFailure` via the existing `finalize_with_failure` path in its single production caller (`zones/sammanfatta.rs`, `OutputFormat::Docx` arm), rather than panicking (Principle VIII). The ripple is confirmed small (one production caller — Clarifications Q1), so conversion is required, not allow-listing.
- **FR-007**: The change MUST NOT alter behavior for valid inputs. Output bytes and extraction results MUST be unchanged (locked by the existing docx/extraction probe tests staying green).
- **FR-008**: The audit finding (9 production sites, classification, hot-path-already-`Result`-safe) MUST be recorded in this spec as the durable rationale for why a mass conversion was not performed.

### Key Entities

*Not applicable — this is a code-quality/lint hardening with no new domain entities or state.*

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Adding a `.unwrap()` (or `.expect()`/`panic!`) to any linted parsing/command module in non-test code causes `cargo clippy --all-targets -- -D warnings` to fail; removing it makes clippy pass again (verified by a temporary edit during review).
- **SC-002**: `cargo clippy --all-targets -- -D warnings` passes clean on the unmodified codebase after this spec — i.e. every benign site in scope is either removed or `#[allow]`-justified (0 un-annotated panic-sites in the linted scope).
- **SC-003**: Zero production `unwrap()`/`expect()`/`panic!` remain un-annotated in the linted scope (verified by clippy passing under the deny gate, which is equivalent to this statement).
- **SC-004**: The full Rust test suite and the existing docx/extraction probe tests pass with byte-identical output for valid inputs (no behavior regression — SC for FR-007).
- **SC-005**: No new outbound network endpoints, no new dependencies, no user-facing string or UI change (Principle I intact; verified by existing no-outbound + string-drift tests staying green and a 0-dependency diff).

## Assumptions

- The existing CI gate runs `cargo clippy --all-targets -- -D warnings` (established in spec 031 ci-on-push), so configuring the lints at deny/warn level in scope is sufficient to block new panic-sites — no new CI wiring is required.
- Module-level inner attributes `#![cfg_attr(not(test), deny(clippy::unwrap_used, clippy::expect_used, clippy::panic))]` on the `zones` tree and the command modules are the mechanism — the `cfg_attr(not(test), …)` gate is REQUIRED so the deny applies to production code but NOT to `#[cfg(test)]` code (FR-004); a bare `#![deny]` would fail `cargo clippy --all-targets` on every test `unwrap()`. `clippy.toml` is not used (it would apply workspace-wide, which is explicitly out of scope).
- `clippy::expect_used` and `clippy::unwrap_used` are `restriction`-group lints (off by default), so enabling them is purely additive and affects only the annotated modules — it does not change any other clippy behavior.
- The `docx_write.rs` pack conversion (FR-006) ripples to a small, contained set of callers (the output pipeline); the clarify step confirms the scope and the error variant to reuse.
- This is a hardening/quality spec with no new entities and no new state transitions → **spec-only track** (spec → clarify → impl). No `.allium`, no `/tla`. No interactive UI changes → no destructive browser tests.
