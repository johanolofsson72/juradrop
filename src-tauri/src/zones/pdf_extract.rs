// Spec 005 — PDF text extraction via the pure-Rust `pdf-extract` crate.
//
// Strict step order (the NoExtractableText / EmptyText boundary
// depends on it, per spec.md FR-004):
//   (1) read full file bytes
//   (2) probe encryption via lopdf trailer /Encrypt dict → PasswordProtected
//   (3) count pages via lopdf::Document::get_pages().len()
//   (4) call pdf_extract::extract_text_from_mem(&bytes)
//   (5) if raw_text.is_empty() AND pages >= 1 → NoExtractableText (pre-trim)
//   (6) strip null bytes, normalise CRLF → LF
//   (7) if whitespace-only AFTER trim → EmptyText
//   (8) count \n\n-separated blocks → was_partial = blocks < pages
//   (9) finalise (collapse blank lines + truncate + redact) via extract::finalise

use std::path::Path;

use super::errors::ZoneFailure;
use super::extract::{finalise, ExtractedText};

pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let bytes = std::fs::read(path).map_err(|_| ZoneFailure::ParseError)?;
    extract_text_from_bytes(&bytes)
}

/// Bytes-level overload — used by unit tests that build fixtures in
/// memory without touching the filesystem.
pub fn extract_text_from_bytes(bytes: &[u8]) -> Result<ExtractedText, ZoneFailure> {
    // (2) Probe encryption. We try to load the trailer; if the document
    // is encrypted, lopdf returns a specific encryption error variant
    // OR successfully loads with an /Encrypt dict in the trailer.
    if is_encrypted(bytes) {
        return Err(ZoneFailure::PasswordProtected);
    }

    // (3) Page count via lopdf.
    let pages_total = match lopdf::Document::load_mem(bytes) {
        Ok(doc) => doc.get_pages().len(),
        Err(_) => return Err(ZoneFailure::ParseError),
    };

    // (4) Run pdf-extract page-by-page. The by-pages API returns one
    // String per page; we both join them (for the model body) AND use
    // the per-page lengths for the FR-002a partial-extraction flag.
    let per_page =
        pdf_extract::extract_text_from_mem_by_pages(bytes).map_err(|_| ZoneFailure::ParseError)?;

    let pages_with_text = per_page.iter().filter(|s| !s.trim().is_empty()).count();
    let raw_text = per_page.join("\n\n");

    // (5) NoExtractableText boundary — when pdf-extract recovers ZERO
    // text from EVERY page (image-only / scanned PDFs with no embedded
    // text content streams). Distinct from EmptyText (which means
    // pdf-extract did find content but it was all whitespace — see
    // step 8 + extract::finalise).
    if pages_total >= 1 && pages_with_text == 0 {
        return Err(ZoneFailure::NoExtractableText);
    }

    // (6) Strip null bytes + normalise CRLF to LF.
    let cleaned = raw_text
        .replace('\0', "")
        .replace("\r\n", "\n")
        .replace('\r', "\n");

    // (7) EmptyText vs NoExtractableText — finalise() handles whitespace
    // detection. If pdf-extract returned content that turns out to be
    // whitespace-only, that's EmptyText (not NoExtractableText).

    // (8) Partial-extraction flag (FR-002a). We use the precise per-page
    // recovery count from pdf-extract (one String per page) rather than
    // the earlier block-counting proxy. A page is "recovered" iff its
    // String is non-empty after trim. Conservative — false positives
    // (over-warning) are acceptable per the FR-002a clarification, but
    // this is materially more accurate than the proxy was.
    let was_partial = pages_total > 0 && pages_with_text < pages_total;

    // (9) Finalise — applies blank-line collapse + 24k truncation +
    // Redacted wrapping + the EmptyText check.
    finalise(cleaned, was_partial, None)
}

/// Probe whether a PDF is encrypted by inspecting the trailer
/// `/Encrypt` dict. lopdf returns a documented encryption error when
/// loading an encrypted document with no password; treat that path as
/// PasswordProtected too.
fn is_encrypted(bytes: &[u8]) -> bool {
    // Strategy: parse with lopdf. If it returns an Encryption error,
    // we're protected. If it succeeds but the trailer carries an
    // /Encrypt key, also protected. If it fails for other reasons, let
    // the caller see the parse error.
    match lopdf::Document::load_mem(bytes) {
        Ok(doc) => doc.trailer.has(b"Encrypt"),
        Err(lopdf::Error::Decryption(_)) => true,
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn garbage_bytes_return_parse_error() {
        let result = extract_text_from_bytes(b"not a pdf");
        assert!(matches!(result, Err(ZoneFailure::ParseError)));
    }

    #[test]
    fn empty_bytes_return_parse_error() {
        let result = extract_text_from_bytes(b"");
        assert!(matches!(result, Err(ZoneFailure::ParseError)));
    }
}
