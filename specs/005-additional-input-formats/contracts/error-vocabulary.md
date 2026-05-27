# Error vocabulary contract — Spec 005

Two new `ZoneFailure` variants. Both surface in the existing UI error state — no new state-machine transitions.

## NoExtractableText

**Fires when:** input is `.pdf`, the file is unencrypted, has ≥ 1 page, but pdf-extract returned zero bytes of text content (the PDF is image-only / scanned with no embedded text layer).

**Swedish copy:** `Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än.`

**Length:** 73 chars (under the SwedishCopy 80-char invariant).

**Rationale for separating from EmptyText:**
- `EmptyText` = "the document is blank" → user action: add content.
- `NoExtractableText` = "the document has content but I can't read it" → user action: re-export with text layer, or wait for OCR support.
- Different recovery actions deserve different Swedish copy.

**Cross-language presence:** added to `src-tauri/tests/fixtures/zone-error-strings.json` AND `src/components/DropZone.errors.ts`. The existing T035-style drift check enforces lock-step.

## UnsupportedEncoding

**Fires when:** input is `.txt` or `.md`, the leading 4 bytes contain a UTF-16 LE (`FF FE`), UTF-16 BE (`FE FF`), UTF-32 LE (`FF FE 00 00`), or UTF-32 BE (`00 00 FE FF`) BOM.

**Swedish copy:** `Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen.`

**Length:** 66 chars.

**Rationale:** UTF-16 / UTF-32 files would decode as Windows-1252 garbage under the FR-005 cascade (every byte 0x00–0xFF maps to something in Windows-1252). Better to refuse explicitly with a recoverable instruction.

**Cross-language presence:** same fixture + TS mirror as NoExtractableText.

## UnsupportedFormat (copy update)

Existing variant from spec 003. The Swedish copy is UPDATED to list all four supported formats:

| Old (spec 003) | New (spec 005) |
|---|---|
| `Filformatet stöds inte — endast .docx i denna version.` | `Filformatet stöds inte — dra ett .docx, .pdf, .txt eller .md.` |

The variant name and the UI behaviour are unchanged; only the displayed text differs.

## Mapping to UI

All three (NoExtractableText, UnsupportedEncoding, updated UnsupportedFormat) transition the zone to the existing `error` visible state via the existing `juradrop://zone/<slug>` event channel. The TypeScript `DropZone.errors.ts` look-up table is the only frontend touch point — no new React state, no new component.

## Backwards compatibility

The spec 003 `ZoneFailure` enum was already serialized with `serde(tag = "kind", rename_all = "snake_case")`. Adding new variants is additive: the existing TS deserializer will silently fall back to a generic-error display if it sees an unknown variant. With the spec 005 TS-side update (adding the two new keys to `DropZone.errors.ts`), full Swedish copy renders correctly.

No JSON-schema migration is needed because there's no persisted state — error variants only exist transiently in the dispatch event payload.
