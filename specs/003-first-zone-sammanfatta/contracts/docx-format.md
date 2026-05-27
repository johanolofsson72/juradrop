# Sidecar `.docx` format contract — spec 003

The output `.docx` produced by a successful summarization has a fixed structure per FR-005a. This document pins that structure so it's testable.

## Document structure

A successful summary produces a `.docx` containing exactly these paragraphs, in order:

| Paragraph index | Content | Style |
|---|---|---|
| 0 | `Sammanfattning av '<original-filename-with-extension>'` | Plain body, bold |
| 1 | `Genererad <YYYY-MM-DD HH:MM> av JuraDrop med modellen gemma3:4b.` | Plain body, regular weight |
| 2 (conditional) | `(Dokumentet förkortades innan sammanfattning — endast början är sammanfattad.)` | Plain body, italic — present iff source was truncated per FR-019 |
| 2 or 3 | (empty paragraph) | Spacer between header and body |
| 3+ (or 4+ if truncated) | Model's response, split on `\n\n` into one paragraph per chunk | Plain body |

The model's response is split on double-newline boundaries to produce paragraph breaks; lone newlines inside a paragraph are preserved as line breaks within the same `<w:p>`. Empty trailing chunks are dropped.

## File-level metadata

- Title: omitted (no copy from source).
- Author: omitted (no copy from source).
- Language: `sv-SE` (Swedish).
- No comments, no tracked changes, no embedded images, no headers/footers.

## Filename

- Canonical: `<source-stem>.sammanfatta.docx`
- Collision: `<source-stem>.sammanfatta.YYYY-MM-DD-HHMMSS.docx` where the timestamp is local time per FR-006.

## Filesystem location

Same directory as the source per FR-005 and the Allium `SidecarLandsBesideSource` invariant.

## Atomic write

The write proceeds:

1. Build the `docx-rs` `Docx` value in memory.
2. Serialise to bytes.
3. Open `<target>.tmp` with `O_WRONLY | O_CREAT | O_TRUNC`.
4. Write all bytes; `fsync`.
5. Drop the file handle.
6. `rename` `<target>.tmp` → `<target>`. Atomic on the same filesystem per POSIX.
7. The `juradrop://sammanfatta` event with `state=success` is emitted AFTER the rename succeeds — never before.

If any step fails, the `.tmp` file is removed best-effort and `ZoneFailure::SaveError` is surfaced.

## Source file invariants

- The source `.docx` is opened read-only.
- Its mtime is not touched.
- Its bytes are not modified.
- A test-time SHA-256 comparison before vs after every drop scenario asserts this — see `tests/zone_sammanfatta_lifecycle.rs`.

## Testing artifacts

The `.docx` produced by a real run is validated in tests by:
- Re-reading it with `docx-rs` and asserting the paragraph count matches the model response.
- Opening it with the `python-docx` library on CI (out of project scope but useful in manual QA) to confirm Word + Pages can parse it.
- Asserting the bytes of the first two header paragraphs match the FR-005a strings exactly (modulo the dynamic filename + timestamp).
