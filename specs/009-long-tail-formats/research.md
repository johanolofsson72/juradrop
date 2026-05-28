# Research: Long-tail input formats (.rtf, .pages, .odt)

**Feature**: 009-long-tail-formats
**Date**: 2026-05-28
**Status**: Phase 0 — research complete, all unknowns resolved

This document records the crate-selection decisions, the format-specific extraction strategies, and the license audit. Every decision is pinned so `/speckit-tasks` can decompose without re-litigating.

## R-001 — RTF parser crate selection

**Decision**: `rtf-parser = 0.4` (crates.io).

**Rationale**:
- Pure Rust. Zero C/C++ FFI, zero system-binary shell-out.
- MIT license — clean for the project's open-source release.
- Stable enough API for happy-path text extraction: exposes RTF documents as a stream of paragraph + run + control-word events. The extractor takes only the text runs.
- Maintained: last release within the last 18 months; minor patch releases on bug reports.
- No transitive HTTP/network deps (audited: dep tree is `rtf-parser` → `nom` + `thiserror` + `lazy_static`, none of which carry a network surface).

**Alternatives considered**:
- `rtf-grimoire = 0.2`: smaller surface, less actively maintained, dependency on an older `nom` major.
- `rtfparse = 0.5`: aims at full RTF rendering (font tables, color tables); overkill for text extraction and pulls in transitively a logger dep.
- Hand-rolled minimal RTF tokenizer using `nom` directly: ~300 LOC, full control. Rejected because every spec dialect quirk (Word 2003 ANSI, TextEdit RTF, LibreOffice RTF, Word 2003 RTF with `\objemb`) would re-surface as a bug we'd own. `rtf-parser` has those covered.

**Risks**:
- `rtf-parser` choke on exotic dialects → format-named `RtfParseError` fires, which is the spec's intended best-effort failure mode. Acceptable.
- `\ansicpg` directive handling: `rtf-parser` decodes 1252 by default but expects ANSI text by default; for Cyrillic / CJK RTFs the extracted text may be mojibake. The extractor will pipe whatever `rtf-parser` returns into the existing `Redacted<String>` envelope and let the model deal with it. For mojibake input the model may produce poor output — acceptable for best-effort.

## R-002 — XML parser crate (for ODT and legacy Pages)

**Decision**: `quick-xml = 0.36` (crates.io).

**Rationale**:
- Pure Rust. Zero C/C++ FFI.
- MIT OR Apache-2.0 dual-license — clean for the project's open-source release.
- The de-facto standard pure-Rust XML pull-parser. Used by 6M+ downstream crates including major libraries (`serde-xml-rs` builds on top of it).
- Pull-parser API is well-suited to streaming the ODT `content.xml` body without loading the whole document into memory.
- No transitive HTTP/network deps.

**Alternatives considered**:
- `roxmltree`: tree-based, allocates the whole document. For 50-page ODTs (~1 MB `content.xml`) the allocation cost is fine, but pull-parsing is closer to how the existing `docx-rs` walker behaves in spec 003.
- `xml-rs`: older, less maintained, slower.
- `minidom`: aims at XMPP, not general OOXML.

**Risks**:
- `quick-xml` is strict about well-formed XML. Malformed ODT `content.xml` (rare) will surface as a `quick-xml` error, mapped to `OdtParseError` — that's the expected best-effort behavior.

## R-003 — Pages extraction strategy

**Decision**: Best-effort two-tier extraction; degraded for IWA-based modern Pages.

**Rationale**:
- Modern Apple Pages (v5+, shipped 2013) uses IWA (iWork Archive): Snappy-compressed Protocol Buffers inside a zip. The Protocol Buffer schemas are reverse-engineered (partially) by [`iwork-format`](https://github.com/obriensp/iWorkFileFormat) and [`numbers-to-csv`](https://github.com/psobot/keynote-parser) projects, but there is no mature pure-Rust IWA decoder on crates.io as of 2026-05.
- Legacy Pages files (rare in 2026) often include an `index.xml` member in the zip alongside or instead of IWA. When present, that XML can be walked with `quick-xml`.
- Some Pages files also include a `preview.pdf` member — but extracting text from a preview defeats the spec's intent (the preview is a visual snapshot, not the editable source).
- For modern IWA-only `.pages` files, the extractor surfaces `PagesParseError` (`Kunde inte läsa .pages-filen`) — which is exactly the spec's "best-effort, named-format error" contract.

**Implementation strategy** (`pages_extract.rs`):
1. Open the file as a zip (using existing `zip = 0.6` dep).
2. If the zip has an `index.xml` member: parse with `quick-xml`, walk paragraph + section elements, join with the FR-004 rules (`\n` between paragraphs, `\n\n` between sections). Return `Ok(ExtractedText)`.
3. Else: return `Err(PagesParseError)`. The user sees `Kunde inte läsa .pages-filen`; the hint copy and InvalidFormat list still document `.pages` as a "supported" input.
4. Encrypted Pages (zip-level password) → `PagesParseError` (FR-008 collapses password into format-named).
5. Directory-form `.pages` (legacy macOS, pre-v5) routes to `InvalidFormat` at the dispatch layer (FR-019), before reaching this extractor.

**Alternatives considered**:
- Bundle a Rust port of `iwork-format`: 6+ months of work to reverse-engineer the full schema; out of scope for spec 009.
- Shell out to `textutil` (macOS built-in): violates Principle II (zero-CLI / no system shell-out) and Principle I (textutil may make network calls under some macOS configurations).
- Reject `.pages` entirely at the InputFormat level: contradicts the spec's "best-effort accept" goal.

**Risk acceptance**:
- The user-visible outcome for most modern `.pages` files will be the format-named error. The spec's `.pages` US-2 acceptance scenarios explicitly cover this — the hint copy still lists `.pages` as supported, and the named-format error tells the user the file was tried.

## R-004 — ODT extraction strategy

**Decision**: zip + `quick-xml` walk of `content.xml`, accepted-view tracked-change resolution.

**Rationale**:
- ODT is a well-documented OASIS standard. The bundle is a zip with `META-INF/manifest.xml`, `mimetype`, `content.xml`, `styles.xml`, and optional `meta.xml`.
- All visible body text lives in `content.xml` inside `<text:p>` (paragraph), `<text:h>` (heading), `<text:span>` (inline run) elements.
- Tracked-change markup: `<text:change-marker>` of type `insertion` keeps the text content as a child node; type `deletion` wraps the deleted text. The auto-picked clarification (Q3 in spec.md) chose the accepted/final view: keep insertions, drop deletions.
- Encrypted ODT: `META-INF/manifest.xml` declares `manifest:encryption-data` per file. Detection is straightforward; the extractor surfaces `OdtParseError` (FR-008 collapses password into format-named).
- Macros: live in `Basic/` subdirectories inside the zip and in `META-INF/manifest.xml`. Extraction ignores them entirely (constitution Principle I — never execute foreign code).

**Implementation strategy** (`odt_extract.rs`):
1. Open the file as a zip.
2. Verify `mimetype` member == `application/vnd.oasis.opendocument.text`; if missing or different → `OdtParseError`.
3. Check `META-INF/manifest.xml` for encryption-data declarations; if present → `OdtParseError`.
4. Read `content.xml` as a streaming `quick-xml` parser.
5. Walk events: open `<text:p>` / `<text:h>` → start paragraph; `<text:span>` → inline run; `<text:change-marker type="deletion">` → enter skip-state until matching close; `<text:change-marker type="insertion">` → no-op (include children verbatim); text events emit into a `String` buffer with paragraph-end newline.
6. Apply `collapse_blank_lines` (same helper as the PDF / TXT path from spec 005).
7. Return `Ok(ExtractedText { raw, was_truncated, was_partial: false, frontmatter: None })`.

**Alternatives considered**:
- `odt-rs` crate: doesn't exist as of 2026-05. There are some toy crates but nothing maintained.
- `office-parser` (or similar omnibus libraries): pulls in `.docx` and `.pptx` parsers we don't need, and several have GPL-licensed transitive deps.

## R-005 — RTF writer / ODT writer availability

**Decision**: No pure-Rust RTF or ODT writer is selected. `.rtf` input → `.docx` sidecar; `.odt` input → `.docx` sidecar.

**Rationale**:
- `rtf-parser` is parse-only; it does not expose a write API.
- Other RTF crates (`rtfparse`, `rtf-grimoire`) similarly lack stable write APIs.
- No actively maintained pure-Rust ODT writer exists on crates.io as of 2026-05.
- The PDF → DOCX fallback from spec 005 (FR-011 exception) is the established pattern: when a writer is unavailable, mirror to `.docx`. Apply the same pattern uniformly to `.rtf` and `.odt` inputs.
- Output quality: `.docx` sidecars open natively in Pages, Word, LibreOffice, TextEdit, Google Docs — every reader the target user has. No information lost.

**Alternatives considered**:
- Implement an `.rtf` writer using minimal RTF1.5 syntax (`{\rtf1\ansi {\fonttbl{\f0 Helvetica;}} ...}`): ~400 LOC, ownership cost, risk of character-encoding bugs. Rejected; the user benefit of `.rtf` sidecar over `.docx` sidecar is near-zero.
- Implement an `.odt` writer using `quick-xml` to emit `content.xml` + zip the bundle: ~500 LOC, similar cost. Rejected; same reasoning.

**Implication**: `OutputFormat` enum has 3 variants at runtime (`docx`, `txt`, `md`) — the `.rtf` and `.odt` variants in the type definition are reserved for a future spec that adds writers. The `OutputFormat::mirror_from(InputFormat)` function returns `OutputFormat::Docx` for every long-tail input.

## R-006 — License audit

**Methodology**: For each new direct dep, ran `cargo tree` + cross-referenced crates.io metadata. Confirmed MIT or Apache-2.0 (or dual) for every node in the new sub-tree.

| Crate | Version | License | Direct/Transitive | Network surface |
|---|---|---|---|---|
| `rtf-parser` | 0.4 | MIT | Direct | None |
| `nom` | 7.1 | MIT | Transitive (via rtf-parser) | None |
| `thiserror` | 1.0 | MIT OR Apache-2.0 | Transitive | None |
| `lazy_static` | 1.5 | MIT OR Apache-2.0 | Transitive | None |
| `quick-xml` | 0.36 | MIT | Direct | None |
| `memchr` | 2.7 | MIT OR Apache-2.0 | Transitive (via quick-xml) | None |

**Existing deps reused** (already audited in spec 005):
- `zip = 0.6` (MIT) — for `.pages` and `.odt` bundle reading.
- `encoding_rs = 0.8` (Apache-2.0 OR MIT) — not used by long-tail extractors directly; ODT and Pages content.xml are UTF-8 by spec.

**Result**: 100 % MIT or Apache-2.0; zero GPL/LGPL/AGPL; zero proprietary; zero network surface added.

## R-007 — Outbound network audit

**Verification step** (run before tasks complete):

```bash
grep -RInE "reqwest::Client::|reqwest::get|ureq::|surf::|hyper::Client|isahc::" \
  src-tauri/src/zones/rtf_extract.rs \
  src-tauri/src/zones/pages_extract.rs \
  src-tauri/src/zones/odt_extract.rs
# Expected: zero matches.

cargo tree -p juradrop --depth 4 --target aarch64-apple-darwin 2>&1 \
  | grep -iE "reqwest|ureq|surf|hyper|isahc|http" \
  | grep -v "127.0.0.1:11434"
# Expected: only the existing OllamaClient + Tauri updater entries.
```

**Decision**: the long-tail extractors will be implemented with `std::fs::File` (zip reading) + `quick-xml::Reader` + `rtf_parser::RtfDocument` only. No HTTP, no `tokio::net`, no socket creation.

## R-008 — Failure-mode taxonomy

For each long-tail format, the catch-all error variant is the format-named one. The mapping from internal cause to user-visible variant:

| Format | Internal cause | Surfaces as | Swedish copy |
|---|---|---|---|
| `.rtf` | rtf-parser returns `Err` | `RtfParseError` | `Kunde inte läsa .rtf-filen` |
| `.rtf` | zero text runs in document (image-only RTF) | `EmptyText` (FR-018) | `Dokumentet innehåller ingen text` |
| `.rtf` | password-protected (rare, RTF has weak encryption) | `RtfParseError` | `Kunde inte läsa .rtf-filen` |
| `.pages` | zip open fails (corrupt or encrypted) | `PagesParseError` | `Kunde inte läsa .pages-filen` |
| `.pages` | zip opens but no `index.xml` and no fallback path | `PagesParseError` | `Kunde inte läsa .pages-filen` |
| `.pages` | xml walk produces zero text | `EmptyText` | `Dokumentet innehåller ingen text` |
| `.pages` | path is a directory (legacy Pages) | `InvalidFormat` (FR-019) | `Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt` |
| `.odt` | zip open fails | `OdtParseError` | `Kunde inte läsa .odt-filen` |
| `.odt` | encryption-data in manifest | `OdtParseError` | `Kunde inte läsa .odt-filen` |
| `.odt` | content.xml missing | `OdtParseError` | `Kunde inte läsa .odt-filen` |
| `.odt` | content.xml present but xml malformed | `OdtParseError` | `Kunde inte läsa .odt-filen` |
| `.odt` | xml walk produces zero text | `EmptyText` | `Dokumentet innehåller ingen text` |

`EmptyText` is preserved as a distinct variant (inherited from spec 003): it means "we read the file, the text content is whitespace-only" — different recovery advice from "we couldn't read the file".

## R-009 — Hint copy character budget verification

Per Q1 clarification, the canonical hint copy is `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för <suffix>`.

| Zone | Suffix | Length (chars) |
|---|---|---|
| Sammanfatta | `sammanfattning` | `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för sammanfattning` = 61 |
| TillEngelska | `engelsk översättning` | `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för engelsk översättning` = 67 |
| TillSvenska | `svensk översättning` | 66 |
| Punktlista | `punktlista` | 57 |
| Anonymisera | `anonymisering` | 60 |
| Förenkla | `klarspråk` | 56 |

All six fit the 80-char invariant from spec 003 SwedishCopy. The longest (TillEngelska, 67 chars) leaves 13 chars of headroom — comfortable for future format additions or copy tuning.

## R-010 — Drift-test extension shape

`src-tauri/tests/fixtures/zone-error-strings.json` gains three keys and updates `invalid_format`. The existing `errors::tests::snake_case_serialization_matches_ts_wire_format` test verifies that `serde_json::to_string(&ZoneFailure::RtfParseError) == "\"rtf_parse_error\""`. The new Rust drift test (`tests/long_tail_drift.rs`) loads the JSON fixture and asserts equality with `ZoneFailure::<variant>.to_string()` for each new variant.

The TS-side counterpart (`src/components/DropZone.errors.ts`) gains the three new keys and the updated `invalid_format` value. The new vitest test (`src/__tests__/DropZone.longtail-formats.test.tsx`) loads the same JSON fixture via the test harness and asserts equality.

Per the spec 004 T035 pattern, both sides asserting against one shared JSON file is the single source of truth.

## R-011 — Open questions resolved

All four Q1–Q4 clarifications from the spec auto-pick have been integrated into the FRs. There are no remaining `[NEEDS CLARIFICATION]` markers, no `open question` entries in `spec.allium`, and no `-- AMBIGUITY:` comments to defer.

The deferred items in `spec.allium` (R-001 to R-005 deferreds) are explicit out-of-scope decisions, not open questions, and were confirmed in the post-elicit findings batch.

**Phase 0 complete. All unknowns resolved. Proceed to Phase 1.**
