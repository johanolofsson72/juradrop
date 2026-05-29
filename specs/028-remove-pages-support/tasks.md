# Tasks: Remove .pages support (spec-only)

- [ ] T001 `src-tauri/src/zones/errors.rs`: rename `PagesParseError` → `PagesUnsupported`; change Display to the actionable Swedish message; tag `pages_parse_error` → `pages_unsupported`; update the `invalid_format` message to drop `.pages` (supported set = `.docx, .pdf, .txt, .md, .rtf, .odt`); update the ALL array, the serde test, the Display test, and the ext-list test (line ~246). Humanizer-review the new message.
- [ ] T002 `src-tauri/src/zones/input_format.rs`: remove the `Pages` variant, the `"pages" => Some(Self::Pages)` detect arm, the `Self::Pages => "pages"` extension arm, the `Self::Pages` ALL entry, and the three Pages detection tests (`f.pages`, `Letter.Pages`, `project.old.pages`).
- [ ] T003 `src-tauri/src/zones/extract.rs`: remove the `InputFormat::Pages => super::pages_extract::extract_text(path)` dispatch arm.
- [ ] T004 Delete `src-tauri/src/zones/pages_extract.rs`; remove its `mod pages_extract;` (or `pub mod`) declaration in `src-tauri/src/zones/mod.rs`.
- [ ] T005 `src-tauri/src/zones/sammanfatta.rs`: replace the dir-form `.pages` → `InvalidFormat` guard with a case-insensitive `.pages` (file OR dir) → `PagesUnsupported` guard, placed BEFORE the generic `detect_from_path().is_none()` → `InvalidFormat` fallthrough (FR-003).
- [ ] T006 `src-tauri/src/zones/zone_id.rs`: update all nine hint strings to drop `.pages` (`.docx/.pdf/.txt/.md/.rtf/.odt`).
- [ ] T007 Fixtures: `src-tauri/tests/fixtures/zone-identity.json` (8 hint_copy strings) + `src-tauri/tests/fixtures/zone-error-strings.json` (`invalid_format` de-paged; `pages_parse_error` key → `pages_unsupported` with the new message + update the `_comment`).
- [ ] T008 `src/components/DropZone.errors.ts`: mirror the fixture — rename the key + message, de-page `invalid_format`. Keep the TS drift test green.
- [ ] T009 Update affected tests: `src/__tests__/DropZone.longtail-formats.test.tsx`, `SammanfattaZone.errors.test.tsx`, `SammanfattaZone.test.tsx`, `DropZone.picker.test.tsx` — drop `.pages` rows, add an assertion that a `.pages` drop yields the unsupported message.
- [ ] T010 Check the spec-025 diagnostics tag-parity test + any `ZoneFailure` count assertion; update the expected tag set (`pages_parse_error` → `pages_unsupported`). Grep for any remaining `pages_extract`/`PagesParseError`/`.pages` in `src-tauri/`, `src/`, integration tests.
- [ ] T011 `README.md`: remove `.pages` from the format list + delete/replace the "Moderna Apple Pages-filer …" sentence; supported set = six formats.
- [ ] T012 Verify: `cd src-tauri && cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check`; `npm test -- --run`, `npm run lint && npm run typecheck`. Confirm zero `.pages`/`pages_parse_error` leftovers (grep, SC-002).
- [ ] T013 Browser/functional check: drop `~/Downloads/svensk.pages` (modern zip) → actionable Pages-unsupported message, no spinner-to-parse-error (SC-001).
