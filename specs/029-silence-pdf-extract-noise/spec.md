# Feature Specification: Silence pdf-extract stdout noise

**Branch**: `main` (solo, direct-push) | **Created**: 2026-05-29 | **Status**: Draft | **Track**: spec-only

**Input**: User dev-run log showed dozens of `missing char N in unicode map {…} … falling back to encoding N -> "X"` lines while extracting a `.pdf` (a document set in Microsoft's Aptos subset font, whose embedded `ToUnicode` table omits some glyphs). The text still extracted; the lines are pure noise.

## Why

`pdf-extract` 0.7.12 emits these messages with **unconditional `println!`** (to stdout) from its font-decoding path (`src/lib.rs:791,796,841,846`) — there is no `log`-crate level or verbosity flag to turn them off. In `npm run tauri dev` they spam the terminal. (In the packaged app there is no terminal, so end users never see them — this is a developer-experience fix only.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 — quiet dev terminal when extracting PDFs (Priority: P1)

A developer running `npm run tauri dev` drops a PDF on a zone. The terminal stays readable — the `pdf-extract` font-fallback chatter no longer floods it — while the extracted text and all real logging (sidecar status, errors) are unchanged.

**Independent Test**: extract a PDF fixture and assert the returned text is byte-identical to extracting it without the suppression wrapper (the wrapper is transparent to output).

**Acceptance Scenarios**:

1. **Given** a PDF whose font omits `ToUnicode` entries, **When** it is extracted, **Then** the extracted text is identical to before this change (no corruption from the stdout redirect).
2. **Given** extraction runs, **When** it completes (or errors), **Then** stdout fd 1 is restored to its original target afterwards (no leaked redirect).

### Edge Cases

- Two PDF extractions running concurrently → the redirect window is serialized by a mutex, so they never race the saved fd.
- Extraction panics or returns Err mid-call → the fd is still restored (guard restores on scope exit).
- Non-unix target → no-op wrapper (the redirect is unix-only; release target is macOS).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `pdf-extract` font-fallback `println!` output MUST NOT reach the process stdout during extraction.
- **FR-002**: The suppression MUST NOT alter the extracted text, the partial-extraction flag, or any `ZoneFailure` outcome — the wrapper is transparent.
- **FR-003**: Process stdout (fd 1) MUST be restored to its original target after extraction, including on panic/early-return.
- **FR-004**: Concurrent extractions MUST NOT race the redirect — the redirect window is serialized.
- **FR-005**: The change MUST suppress ONLY stdout, never stderr (all JuraDrop logging uses `eprintln!`/stderr and must remain visible).
- **FR-006**: Net new dependencies: 0 (use `libc`, already in the tree).

## Success Criteria *(mandatory)*

- **SC-001**: Extracted text from a PDF fixture is byte-identical with and without the wrapper (test-locked).
- **SC-002**: After extraction, a marker written to stdout is observed normally (fd restored) — verified by test where feasible, else by the existing extraction-probe + dev observation.
- **SC-003**: Net new deps: 0.

## Clarifications

### Session 2026-05-29

- Q: Redirect stdout (fd 1) only, or stderr too? → A: stdout only. All JuraDrop logging uses `eprintln!`/stderr; suppressing stderr would hide our own real messages. pdf-extract's noise is on stdout.
- Q: Suppress for all targets or unix-only? → A: unix-only `dup2` redirect (the release target is macOS; dev is macOS). Non-unix builds get a transparent no-op wrapper.

## Assumptions

- `pdf-extract` offers no API/feature/log-level to disable the messages (confirmed: raw `println!` in 0.7.12). Forking the crate is out of scope; the stdout redirect is the standard, contained workaround.
- The redirect window is brief (one extraction call) and serialized; the small risk of swallowing an unrelated concurrent stdout write is acceptable given JuraDrop logs to stderr.
