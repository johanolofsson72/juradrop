# Contract: Output mirror rule (extended for long-tail formats)

**Feature**: 009-long-tail-formats
**Date**: 2026-05-28
**Function**: `OutputFormat::mirror_from(InputFormat) -> OutputFormat` in `src-tauri/src/zones/output_format.rs`

This contract pins the mapping from each of the seven `InputFormat` variants to the runtime `OutputFormat`. The function is total: every input has exactly one defined output.

## C-012 — Mapping table (post-spec-009)

| `InputFormat` | `OutputFormat` | Rationale |
|---|---|---|
| `Docx`   | `Docx` | Inherited from spec 003. Same format both sides. |
| `Pdf`    | `Docx` | Inherited from spec 005. Writing polished PDFs is out of scope; `.docx` opens everywhere. |
| `Txt`    | `Txt`  | Inherited from spec 005. Plain text round-trip. |
| `Md`     | `Md`   | Inherited from spec 005. Markdown round-trip. |
| `Rtf`    | `Docx` | NEW — spec 009. No pure-Rust RTF writer available (research R-005). |
| `Pages`  | `Docx` | NEW — spec 009. Apple Pages bundle is proprietary; never written back regardless of writer availability. |
| `Odt`    | `Docx` | NEW — spec 009. No pure-Rust ODT writer available (research R-005). |

## C-013 — Sidecar filename construction

The sidecar filename is built from:
1. Parent directory of the source file.
2. Stem of the source file (basename minus extension).
3. Zone-specific suffix from `ZoneIdentity::sidecar_suffix` (e.g. `.sammanfattning`, `.tillengelska`).
4. The output format extension from `OutputFormat::as_str()` (`docx`, `txt`, `md`).

Examples (for `Sammanfatta` zone, source file in `/Users/jool/Desktop/`):

| Source | Sidecar |
|---|---|
| `kursplan.rtf` | `/Users/jool/Desktop/kursplan.sammanfattning.docx` |
| `meeting.pages` | `/Users/jool/Desktop/meeting.sammanfattning.docx` |
| `case-notes.odt` | `/Users/jool/Desktop/case-notes.sammanfattning.docx` |
| `kursplan.docx` | `/Users/jool/Desktop/kursplan.sammanfattning.docx` (inherited) |
| `report.pdf` | `/Users/jool/Desktop/report.sammanfattning.docx` (inherited) |

## C-014 — Why `.docx` for every long-tail input

- `.docx` opens natively in Apple Pages, Microsoft Word, LibreOffice, TextEdit, Google Docs — every reader the target law student uses.
- The existing `docx-rs` writer is already used for the `.pdf` fallback from spec 005. Reusing the same writer keeps the output formatting consistent across input formats.
- No information loss: the long-tail extractors produce plain text (no styling preserved), and the `.docx` sidecar header + body paragraphs render that plain text faithfully.
- The disclaimer paragraph rendering (for `Anonymisera` and `Förenkla` zones, FR-013/014 from spec 004) reuses the existing `.docx` rendering path — no per-format disclaimer styling to maintain.

## C-015 — When a future spec adds writers

If a future spec (e.g. 011 or beyond) adds a pure-Rust RTF or ODT writer:
1. Add `Rtf` / `Odt` variants to `OutputFormat`.
2. Update `mirror_from` to return the new variants for matching inputs.
3. Update the sidecar writer dispatch (analogue of the existing `docx_writer::write` / `txt_writer::write` / `md_writer::write` arms).
4. Update C-012 of this contract.
5. The mapping for `Pages` MUST remain `Docx` regardless — never write to the proprietary format (constitution Principle IX implies "no proprietary lock-in" both ways).

## C-016 — Invariant: total over `InputFormat`

```rust
#[test]
fn mirror_from_is_total() {
    for input in InputFormat::ALL {
        let _ = OutputFormat::mirror_from(input);  // must not panic
    }
}
```

The match in `mirror_from` MUST NOT use `_ => …` catch-all. Every variant of `InputFormat` is named explicitly so adding a future `InputFormat::Foo` is a compile error until the contract is updated.
