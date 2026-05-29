# Feature Specification: Large-file guard

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: Draft
**Track**: Light (new failure state → `.allium`; no new state machine → skip `/tla`).

**Input**: Every extractor reads the whole file into memory (`std::fs::read`). A dropped multi-GB file (a huge PDF, a mis-dropped video) would balloon memory and could OOM-kill the app — with no honest error, just a crash. Add a pre-read file-size guard: before extraction, check the file size; if it exceeds a cap, return a new `ZoneFailure::FileTooLarge` with a plain-Swedish message instead of reading it. Cheap `metadata().len()` check, one central chokepoint.

## Why this spec exists

Confirmed gap: the only pre-read guard is the multi-file check (`paths.len() >= 2`); nothing bounds a single file's size. For a tool that ingests arbitrary user-dropped files, an unbounded read is an OOM/DoS waiting to happen — and the fix is one `metadata` call before the read.

## What's IN scope

| Item | Type |
|---|---|
| `ZoneFailure::FileTooLarge` variant + Swedish copy | Code |
| `MAX_INPUT_FILE_BYTES` cap (50 MB) | Code |
| Size guard at the top of `extract::extract_text` (covers all 6 formats) | Code |
| Cross-language: `zone-error-strings.json` + `DropZone.errors.ts` + TS `ZoneFailure` union | Code |
| Tests: oversized file → FileTooLarge; at/under cap → no guard trip; drift parity | Test |

## What's OUT of scope

| Item | Reason |
|---|---|
| Streaming/chunked extraction of huge files | Out of scope; the contract is "reject politely", not "handle arbitrarily large" |
| Per-format caps | One cap for all formats is simpler + sufficient |
| Configurable cap in settings | YAGNI; a constant is fine |

## Clarifications

### Session 2026-05-29 (auto-picked)

- Q: Cap value? → A: **50 MB.** Generous for legal documents (even large PDFs are well under) while preventing a multi-GB read. `MAX_INPUT_FILE_BYTES = 50 * 1024 * 1024`.
- Q: Where does the guard live? → A: **Top of `extract::extract_text`** — the single dispatch point all 6 formats pass through; one `metadata().len()` check before any per-format read.
- Q: New failure variant or reuse ParseError? → A: **New `FileTooLarge` variant** — the user needs a specific, honest message ("filen är för stor"), not a generic parse error.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A huge file is rejected politely, not via OOM (Priority: P1)

A student accidentally drops a 2 GB file on a zone. Instead of the app freezing/crashing, the zone shows "Filen är för stor — max 50 MB" and stays usable.

**Independent Test**: integration — a file just over the cap returns `Err(ZoneFailure::FileTooLarge)`; a file under the cap is read normally.

**Acceptance Scenarios**:
1. **Given** a file > 50 MB, **When** `extract_text` runs, **Then** it returns `Err(FileTooLarge)` WITHOUT reading the whole file.
2. **Given** a file ≤ 50 MB, **When** `extract_text` runs, **Then** the guard does not trip (normal extraction proceeds).
3. **Given** the `FileTooLarge` error reaches the UI, **Then** the Swedish copy "Filen är för stor — max 50 MB" is shown (drift parity Rust ↔ JSON ↔ TS).

### Edge Cases

- File exactly at the cap → allowed (`>` not `>=`).
- A file that disappears between metadata and read → falls through to the format extractor's existing fs-error handling (no panic).
- Copy ≤ 80 chars, no English "error", non-empty (existing ZoneFailure invariants).

## Requirements

- **FR-001**: Add `ZoneFailure::FileTooLarge` (serde `file_too_large`) with Swedish copy "Filen är för stor — max 50 MB" (≤ 80 chars, no "error", matches the existing error-copy house style). Add it to the `ALL_VARIANTS` test array.
- **FR-002**: Define `MAX_INPUT_FILE_BYTES: u64 = 50 * 1024 * 1024`.
- **FR-003**: `extract::extract_text` MUST, before dispatching to any per-format extractor, `std::fs::metadata(path)` and return `Err(FileTooLarge)` if `len() > MAX_INPUT_FILE_BYTES`. A metadata error falls through to the existing per-format read error path (no panic).
- **FR-004**: `zone-error-strings.json` + `DropZone.errors.ts` + the TS `ZoneFailure` union MUST gain `file_too_large` with the identical Swedish string (drift parity enforced by the existing drift tests).
- **FR-005**: No new outbound surface; pure local metadata check. Net new deps: 0.

## Success Criteria

- **SC-001**: A > 50 MB file yields `FileTooLarge`; a ≤ 50 MB file extracts normally. Verified by integration test.
- **SC-002**: Rust ↔ JSON ↔ TS drift parity for `file_too_large`. Verified by existing drift tests (extended).
- **SC-003**: The `FileTooLarge` copy passes the ZoneFailure invariants (≤80, no "error", non-empty). Verified by the errors.rs tests.
- **SC-004**: Net new deps: 0.
