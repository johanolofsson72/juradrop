# Quickstart: Long-tail input formats (.rtf, .pages, .odt)

**Feature**: 009-long-tail-formats
**Date**: 2026-05-28
**Audience**: developer verifying spec 009 locally after `/speckit-implement` completes

This document is the **manual verification harness** for spec 009. Eight scenarios; each one ≤ 60 seconds to execute. If any scenario fails, the spec is not done.

## Prereqs

1. `git pull origin main` — confirm spec 009 implementation is checked in.
2. `npm install && cd src-tauri && cargo build` — both must succeed.
3. Confirm `JuraDrop.app` launches (`npm run tauri dev` for dev mode).
4. Confirm the Ollama sidecar is `Klar` (the model has finished downloading from prior runs).

## Flow 1 — Happy path: `.rtf` → sidecar

1. Open TextEdit. Type 3 paragraphs of Swedish legal-flavoured prose (or paste a sample from `src-tauri/tests/fixtures/long_tail/sample.rtf`). Save as `kursplan.rtf` on Desktop.
2. Drag `kursplan.rtf` onto the **Sammanfatta** zone.
3. **Expect**:
   - Zone transitions: `idle → dragover (green border) → processing (spinner) → success (checkmark)`.
   - A file `kursplan.sammanfattning.docx` appears on Desktop next to the source.
   - The sidecar file opens automatically in Pages/Word.
   - The source `kursplan.rtf` is unchanged (SHA-256 invariant).
4. **Fail conditions**: zone stays in `error`; no sidecar appears; sidecar has wrong extension; source file was modified.

## Flow 2 — Happy path: `.odt` → sidecar

1. Open LibreOffice (or use the fixture `src-tauri/tests/fixtures/long_tail/sample.odt`). Save a 3-paragraph document as `notes.odt` on Desktop.
2. Drag `notes.odt` onto the **TillEngelska** zone.
3. **Expect**:
   - Same state transitions as Flow 1.
   - A file `notes.tillengelska.docx` appears on Desktop.
   - The English translation opens automatically.
4. **Fail conditions**: same as Flow 1, plus: `.odt` writer was used instead of `.docx` (output extension should be `.docx`, not `.odt`).

## Flow 3 — Degraded path: modern `.pages` → format-named error

1. Open Apple Pages. Type 3 paragraphs. Save as `meeting.pages` on Desktop. (Modern Pages defaults to IWA-based format.)
2. Drag `meeting.pages` onto any zone.
3. **Expect**:
   - Zone transitions: `idle → dragover (green border) → processing (briefly) → error`.
   - The error message displayed: **`Kunde inte läsa .pages-filen`** (exact string).
   - NO sidecar file appears on Desktop.
   - The source `meeting.pages` is unchanged.
   - After the standard error-display duration (~3 s), the zone returns to `idle`.
4. **Note**: This is the **expected degraded behavior** per research R-003. Modern Pages files use IWA Protocol Buffers which no pure-Rust crate decodes yet. The spec accepts this as best-effort failure with a named-format error.
5. **Fail conditions**: error message reads "Kunde inte läsa dokumentet" (generic, not format-named); error reads "Filformatet stöds inte" (.pages should be accepted-but-failed, not unsupported); zone surfaces `Dokumentet är lösenordsskyddat` (long-tail collapses password into format-named per FR-008); the zone shows a Rust panic / English error.

## Flow 4 — Best-effort: legacy `.pages` with `index.xml` → sidecar

(Optional — requires a legacy Pages file. Skip if you don't have one.)

1. Use the fixture `src-tauri/tests/fixtures/long_tail/legacy.pages` (a single-file zip with `index.xml`).
2. Drag onto **Punktlista**.
3. **Expect**:
   - Same state transitions as Flow 1.
   - A file `legacy.punktlista.docx` appears on Desktop.
   - The bullet-list output opens automatically.

## Flow 5 — Honest failure: corrupt `.rtf` → format-named error

1. Use the fixture `src-tauri/tests/fixtures/long_tail/corrupt.rtf` (deliberately mangled — opening `{\rtf` but malformed body).
2. Drag onto any zone.
3. **Expect**:
   - Zone transitions: `idle → dragover → processing (briefly) → error`.
   - Error message: **`Kunde inte läsa .rtf-filen`**.
   - NO sidecar appears.
   - Source unchanged.
4. **Fail conditions**: error reads "Kunde inte läsa dokumentet" (must be .rtf-named); zone shows a Rust panic; sidecar appears anyway.

## Flow 6 — Honest failure: corrupt `.odt` → format-named error

1. Use the fixture `src-tauri/tests/fixtures/long_tail/missing-content.odt` (a zip without `content.xml`).
2. Drag onto any zone.
3. **Expect**:
   - Error message: **`Kunde inte läsa .odt-filen`**.
   - NO sidecar appears.
   - Source unchanged.

## Flow 7 — Regression guard: unsupported extension → InvalidFormat

1. Save any text file as `legacy.doc` (Word 97 binary, NOT `.docx`). Or use the fixture `src-tauri/tests/fixtures/long_tail/legacy.doc`.
2. Drag onto any zone.
3. **Expect**:
   - Zone transitions: `idle → dragover → error` (no processing step — pre-model rejection).
   - Error message: **`Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt`** (note the 7-format list).
   - NO sidecar appears.
4. Repeat with `report.epub`, `page.html`, `data.csv`, `mail.eml`. All should produce the same error.
5. **Fail conditions**: error message still lists only 4 formats (spec 005 copy); zone tries to extract and surfaces a parse error instead of `InvalidFormat`.

## Flow 8 — Discoverability: hint copy lists all 7 formats

1. With the model `Klar` and no recent drops, look at each of the six zones in `idle` state.
2. **Expect** each zone's hint copy to read exactly:
   - Sammanfatta: `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för sammanfattning`
   - TillEngelska: `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för engelsk översättning`
   - TillSvenska: `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för svensk översättning`
   - Punktlista: `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för punktlista`
   - Anonymisera: `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för anonymisering`
   - Förenkla: `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för klarspråk`
3. **Verify visually**: the hint copy fits in the zone visual budget — no horizontal overflow, no wrap-to-three-lines, no ellipsis truncation.
4. **Fail conditions**: hint still lists only 4 formats; hint uses comma separator instead of slash; hint exceeds 80 chars (the longest is 67); hint wraps unexpectedly.

## Final checks

- [ ] `npm test` — all vitest tests green (existing + new spec 009 tests).
- [ ] `cd src-tauri && cargo test` — all Rust tests green.
- [ ] `cd src-tauri && cargo clippy -- -D warnings` — zero warnings.
- [ ] `cd src-tauri && cargo fmt --check` — clean.
- [ ] `npm run lint && npm run typecheck` — clean.
- [ ] `npm run test:e2e` — Playwright smoke green for all three new format scenarios.
- [ ] `cargo tree -p juradrop 2>&1 | grep -iE "reqwest|ureq|surf|hyper"` — only the existing OllamaClient + updater entries.
- [ ] `grep -RInE "reqwest::Client::|ureq::|surf::" src-tauri/src/zones/rtf_extract.rs src-tauri/src/zones/pages_extract.rs src-tauri/src/zones/odt_extract.rs` — zero matches.

## If anything fails

1. Read the test output and the failing assertion.
2. Check `data-model.md` for the type-level expectations.
3. Check `contracts/extractor-trait.md` for the function-level expectations.
4. Check `spec.md` clarifications for the user-facing expectations.
5. Fix the code OR amend the spec — never paper over with a try/catch.
