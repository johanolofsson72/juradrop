# Feature Specification: Remove .pages support

**Branch**: `main` (solo, direct-push) | **Created**: 2026-05-29 | **Status**: Draft | **Track**: spec-only

**Input**: User: "jag tycker vi plockar bort stödet för pages i appen" + a field-failing file (`svensk.pages`) and `diagnostics.log` showing two `pages_parse_error` events.

## Why

`.pages` was added in spec 009 as "best-effort". Modern Pages (v5+, 2013→) stores document text in `Index/*.iwa` — Snappy-compressed, undocumented Apple Protobuf — NOT the readable `index.xml` that the spec-009 extractor relied on. The supplied `svensk.pages` is exactly this: a zip whose only text payload is `Index/Document.iwa`. Extraction therefore fails for any Pages file made in the last decade, which the field log confirms (`category=pages_parse_error` ×2). Decoding `.iwa` is a large, brittle reverse-engineering effort with no stable upstream contract. The honest, maintainable fix is to **stop claiming to support `.pages`** and tell the user what to do instead.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A dropped .pages gets honest, actionable guidance (Priority: P1)

A law student drops a `.pages` file on any zone. Instead of a spinner that ends in "Kunde inte läsa .pages-filen" (a misleading *parse* error implying a transient problem), they get a clear message that Pages files are not supported and what to do: export to Word or PDF in Pages first, then drop that.

**Independent Test**: drop both a modern zip-form `.pages` and a legacy directory-form `.pages`; both surface the same actionable "stöds inte / exportera först" Swedish message; neither attempts extraction.

**Acceptance Scenarios**:

1. **Given** a modern `.pages` (zip with `.iwa`), **When** dropped on a zone, **Then** the zone shows the Pages-unsupported message and does not attempt extraction (no `pages_parse_error`).
2. **Given** a legacy directory-form `.pages` bundle, **When** dropped, **Then** the same Pages-unsupported message is shown (previously this routed to the generic InvalidFormat).
3. **Given** the supported set, **When** the user reads any zone's hint copy or the generic unsupported-format message, **Then** `.pages` is NOT listed (the supported set is `.docx, .pdf, .txt, .md, .rtf, .odt`).

### Edge Cases

- A file literally named `something.pages.docx` → detected as `.docx` (extension is the last segment), unaffected.
- `.pages` with mixed-case extension (`.Pages`, `.PAGES`) → still routed to the Pages-unsupported message (case-insensitive).
- A `.pages` dropped while a job is processing → same single-flight rules as any other drop; the busy toast wins.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST NOT list `.pages` among supported input formats anywhere user-visible (all nine zone hint strings, the generic unsupported-format message, README).
- **FR-002**: The system MUST NOT attempt to extract text from a `.pages` file — the `InputFormat::Pages` variant and the `pages_extract` path are removed.
- **FR-003**: A dropped `.pages` (modern zip form OR legacy directory bundle, any letter case) MUST surface a single, honest, actionable Swedish message telling the user Pages is not supported and to export to Word/PDF first (Principle VIII). It MUST NOT surface a "parse error".
- **FR-004**: Removing `.pages` MUST NOT change the behaviour of the six remaining formats (`.docx, .pdf, .txt, .md, .rtf, .odt`).
- **FR-005**: The cross-language Swedish error-string fixtures (Rust ↔ JSON ↔ TS) MUST stay drift-consistent after the change (no orphaned `pages_parse_error` key, no dangling `.pages` substring).
- **FR-006**: The spec-025 diagnostics tag set MUST remain coherent — the content-free `ZoneFailure` tag for the Pages case is updated (no `pages_parse_error` tag emitted for a removed code path).

## Success Criteria *(mandatory)*

- **SC-001**: Dropping any `.pages` file produces the actionable Pages-unsupported message in 100% of cases (zip + dir, any case), verified by test — zero `pages_parse_error`.
- **SC-002**: No `.pages` substring remains in any user-facing string (hint copy, error copy, README) — verified by grep/test.
- **SC-003**: All six remaining formats still extract correctly — the existing extraction tests stay green.
- **SC-004**: Net new dependencies: 0 (this is a removal; the `pages_extract` module and any Pages-only crate usage go away if unused elsewhere).

## Clarifications

### Session 2026-05-29

- Q: When a `.pages` is dropped after removal, show the generic "format stöds inte" list (de-paged) or a Pages-specific actionable message? → A: A Pages-specific, actionable message ("Pages-filer stöds inte. Exportera till Word eller PDF i Pages och dra hit den filen istället.") — strictly more helpful for a user who has a `.pages` in hand, and consistent with Principle VIII (honest, useful failures). Implemented by repurposing the existing `.pages` failure variant from a parse-error into an unsupported-with-guidance message (keeps the `ZoneFailure` variant count stable).

## Assumptions

- The legacy directory-form `.pages` guard in `sammanfatta.rs` is retargeted from `InvalidFormat` to the new Pages-unsupported message (same honest-failure intent, better copy).
- No `.pages` test fixture needs to remain; any committed `.pages` fixture used only by long-tail extraction tests is removed or repurposed to assert the unsupported path.
- `rtf`/`odt` long-tail support is unaffected and stays (only `.pages` is broken-by-format; `.rtf` and `.odt` have working extractors).
