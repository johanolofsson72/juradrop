# Contract: Long-tail extractor trait

**Feature**: 009-long-tail-formats
**Date**: 2026-05-28

This contract pins the function signature, return shape, and failure-mode taxonomy for every long-tail extractor module (`rtf_extract`, `pages_extract`, `odt_extract`).

## C-001 — Signature

Every long-tail extractor module exposes exactly one public function:

```rust
pub fn extract_text(path: &std::path::Path) -> Result<ExtractedText, ZoneFailure>;
```

- **Input**: a borrowed `Path`. The extractor MUST NOT mutate the path or its target file.
- **Output (Ok)**: an `ExtractedText` value (shape pinned in D-005 of `data-model.md`) wrapping the raw text inside the `Redacted<String>` envelope. The `was_partial` field is `false` and the `frontmatter` field is `None` for all long-tail formats.
- **Output (Err)**: a single `ZoneFailure` variant — never a panic, never an unwrap that can fire on user input.

## C-002 — Return-value taxonomy

| Module | Allowed `Ok` shape | Allowed `Err` variants |
|---|---|---|
| `rtf_extract` | `ExtractedText { raw, was_truncated, was_partial: false, frontmatter: None }` | `RtfParseError`, `EmptyText` |
| `pages_extract` | same shape as above | `PagesParseError`, `EmptyText` |
| `odt_extract` | same shape as above | `OdtParseError`, `EmptyText` |

`InvalidFormat` is NOT raised by any extractor — that variant is reserved for the dispatch layer (unsupported extension or directory-form `.pages`).

`PasswordProtected` is NOT raised by any long-tail extractor — per FR-008, password-protected long-tail files collapse into the format-named error.

`NoExtractableText` is NOT raised by any long-tail extractor — that variant is `.pdf`-exclusive (FR-004 from spec 005).

`UnsupportedEncoding` is NOT raised by any long-tail extractor — that variant is `.txt`/`.md`-exclusive (FR-007 from spec 005).

## C-003 — Privacy envelope

The `ExtractedText.raw` field MUST be inside the project's `Redacted<String>` newtype before the function returns. The extractor MUST NOT log, persist, or transmit the raw text anywhere outside the return value. The format-named error variants MUST NOT include the source file's name or path in their `Display` impl — `to_string()` on `RtfParseError` returns exactly `Kunde inte läsa .rtf-filen`, nothing more.

## C-004 — Performance budget

| Module | 2-page document | 50-page document | Failure detection |
|---|---|---|---|
| `rtf_extract` | < 100 ms | < 500 ms | < 50 ms |
| `pages_extract` | < 300 ms (legacy XML) / < 50 ms (IWA → fail) | < 1 s | < 100 ms |
| `odt_extract` | < 200 ms | < 800 ms | < 100 ms |

Budgets are pre-truncation. Post-truncation (24,000-char cap) the model inference dominates downstream latency.

## C-005 — Thread-safety

Extractors run on the Tokio runtime's blocking pool via `tokio::task::spawn_blocking`. Each call is independent — no shared mutable state between extractor invocations, no module-level statics that mutate. `rtf-parser`, `quick-xml`, and the `zip` crate are all safe for this usage pattern.

## C-006 — Cancellation

Extractors do NOT need to honour the spec 003 cancellation token directly. The dispatcher's `tokio::select!` between the extractor and the cancellation channel handles the cancel path: if the user cancels mid-extraction, the future is dropped and the extractor's open file handles + memory are reclaimed by Rust's destructors. The extractor sees no cancellation signal.

## C-007 — Test coverage requirement

Each extractor module ships with an integration test file (`src-tauri/tests/<format>_extract.rs`) containing at minimum:
1. **Happy path** — a valid 2-page document of the format, asserts `Ok(ExtractedText)` with non-empty `raw`.
2. **Empty document** — a valid but content-free document of the format, asserts `Err(EmptyText)`.
3. **Corrupt file** — a deliberately mangled file (truncated zip, broken RTF control word, malformed XML), asserts `Err(<format>ParseError)`.
4. **Password-protected** (where applicable) — asserts `Err(<format>ParseError)`.
5. **24,000-char truncation** — a long document exceeding the cap, asserts `Ok(ExtractedText { was_truncated: true, .. })` and `raw.chars().count() == 24_000`.
6. **No panic on garbage bytes** — feed `[0xFF; 1024]` to the extractor, asserts `Err(<format>ParseError)` and not a panic.
