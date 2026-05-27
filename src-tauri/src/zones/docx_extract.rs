// Spec 003 / T011 + T012 — .docx text extraction + truncation.
//
// Reads a `.docx` from disk, detects password protection (R-002),
// extracts paragraph text via docx-rs, truncates at the FR-019 boundary
// (R-003 — 24,000 UTF-8 characters), and wraps the result in
// `Redacted<String>` so accidental logging surfaces `<redacted>`
// rather than document content.

use std::io::Cursor;
use std::path::Path;

use crate::sidecar::log_safe::Redacted;
use docx_rs::DocumentChild;

use super::errors::ZoneFailure;

// Spec 005 — the canonical `ExtractedText` shape + truncation constant
// now live in `super::extract`; this module re-exports them so the
// spec 003 import path (`use ...::zones::docx_extract::ExtractedText`)
// keeps working byte-identically.
pub use super::extract::{ExtractedText, TRUNCATION_CHAR_LIMIT};

/// Read a `.docx` file from disk and return its extracted text.
///
/// Returns:
///   - `Ok(ExtractedText)` on success.
///   - `Err(ZoneFailure::ParseError)` for corrupt zip / malformed XML.
///   - `Err(ZoneFailure::PasswordProtected)` for encrypted documents.
///   - `Err(ZoneFailure::EmptyText)` when extraction yields only whitespace.
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let bytes = std::fs::read(path).map_err(|_| ZoneFailure::ParseError)?;
    extract_text_from_bytes(&bytes)
}

/// Bytes-level overload — used by unit tests that build .docx fixtures
/// in memory without touching the filesystem.
pub fn extract_text_from_bytes(bytes: &[u8]) -> Result<ExtractedText, ZoneFailure> {
    // Probe for password protection BEFORE handing to docx-rs. A
    // password-protected .docx is still a valid zip; only the
    // `word/document.xml` payload is replaced with `EncryptedPackage`.
    if is_password_protected(bytes) {
        return Err(ZoneFailure::PasswordProtected);
    }

    let docx = docx_rs::read_docx(bytes).map_err(|_| ZoneFailure::ParseError)?;

    // Walk top-level paragraphs. Tables are intentionally NOT walked in
    // v1 — spec 003 scope is plain Swedish legal text. Tables and other
    // structures fall through silently and contribute no text.
    let mut paragraphs: Vec<String> = Vec::new();
    for child in &docx.document.children {
        if let DocumentChild::Paragraph(p) = child {
            let text = p.raw_text();
            if !text.is_empty() {
                paragraphs.push(text);
            }
        }
    }

    let joined = paragraphs.join("\n\n");
    if joined.trim().is_empty() {
        return Err(ZoneFailure::EmptyText);
    }

    let (final_text, was_truncated) = truncate_to_char_limit(joined, TRUNCATION_CHAR_LIMIT);
    let char_count = final_text.chars().count();

    Ok(ExtractedText {
        raw: Redacted::new(final_text),
        char_count,
        was_truncated,
        // Spec 005 — these flags only fire for PDF / MD respectively.
        was_partial: false,
        frontmatter: None,
    })
}

/// Truncate `text` at the first `limit` UTF-8 characters on a char
/// boundary. Swedish characters (å, ä, ö, é) are multi-byte; a naive
/// byte-slice would corrupt the boundary.
fn truncate_to_char_limit(text: String, limit: usize) -> (String, bool) {
    if text.chars().count() <= limit {
        return (text, false);
    }
    let truncated: String = text.chars().take(limit).collect();
    (truncated, true)
}

/// True iff the zip archive contains an `EncryptedPackage` entry and
/// no `word/document.xml` — the canonical Microsoft Office encrypted
/// document shape per R-002.
fn is_password_protected(bytes: &[u8]) -> bool {
    let cursor = Cursor::new(bytes);
    let Ok(mut archive) = zip::ZipArchive::new(cursor) else {
        return false; // Not a zip at all — let read_docx surface ParseError.
    };

    let mut has_encrypted_package = false;
    let mut has_document_xml = false;
    for i in 0..archive.len() {
        if let Ok(entry) = archive.by_index(i) {
            let name = entry.name();
            if name.eq_ignore_ascii_case("EncryptedPackage") {
                has_encrypted_package = true;
            }
            if name == "word/document.xml" {
                has_document_xml = true;
            }
        }
    }

    has_encrypted_package && !has_document_xml
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    /// Build an in-memory minimal `.docx` containing one paragraph per
    /// supplied line via docx-rs itself — guarantees the resulting
    /// bytes round-trip through `read_docx` regardless of which
    /// `[Content_Types].xml` parts docx-rs requires.
    fn build_minimal_docx(paragraphs: &[&str]) -> Vec<u8> {
        use docx_rs::*;
        let mut docx = Docx::new();
        for p in paragraphs {
            docx = docx.add_paragraph(Paragraph::new().add_run(Run::new().add_text(*p)));
        }
        let mut buf = Vec::new();
        docx.build().pack(Cursor::new(&mut buf)).expect("pack docx");
        buf
    }

    /// Build an in-memory password-protected-looking .docx: same outer
    /// zip but with an `EncryptedPackage` entry instead of word/document.xml.
    fn build_encrypted_package() -> Vec<u8> {
        let buf = Vec::new();
        let mut zip = zip::ZipWriter::new(Cursor::new(buf));
        let opts =
            zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Deflated);
        zip.start_file("EncryptedPackage", opts).unwrap();
        zip.write_all(&[0u8; 64]).unwrap();
        zip.finish().unwrap().into_inner()
    }

    #[test]
    fn extracts_simple_paragraph_text() {
        let docx = build_minimal_docx(&["Hello, world."]);
        let result = extract_text_from_bytes(&docx).expect("extract ok");
        assert_eq!(result.raw.as_inner(), "Hello, world.");
        assert_eq!(result.char_count, 13);
        assert!(!result.was_truncated);
    }

    #[test]
    fn handles_swedish_multi_byte_characters() {
        // Pick a phrase that exercises lowercase å, ä, ö — all three
        // are multi-byte in UTF-8 and would corrupt at a byte boundary.
        let docx = build_minimal_docx(&["såg ärligt över ön"]);
        let result = extract_text_from_bytes(&docx).expect("extract ok");
        let body = result.raw.as_inner();
        assert!(body.contains('å'), "missing å in {body:?}");
        assert!(body.contains('ä'), "missing ä in {body:?}");
        assert!(body.contains('ö'), "missing ö in {body:?}");
    }

    #[test]
    fn empty_paragraph_returns_empty_text_error() {
        let docx = build_minimal_docx(&["   "]);
        let err = extract_text_from_bytes(&docx).expect_err("should error on whitespace-only");
        assert!(matches!(err, ZoneFailure::EmptyText));
    }

    #[test]
    fn multiple_paragraphs_join_with_double_newline() {
        let docx = build_minimal_docx(&["First.", "Second.", "Third."]);
        let result = extract_text_from_bytes(&docx).expect("extract ok");
        assert_eq!(result.raw.as_inner(), "First.\n\nSecond.\n\nThird.");
    }

    #[test]
    fn corrupt_bytes_returns_parse_error() {
        let garbage = b"this is not a zip file";
        let err = extract_text_from_bytes(garbage).expect_err("should error on non-zip");
        assert!(matches!(err, ZoneFailure::ParseError));
    }

    #[test]
    fn encrypted_package_returns_password_protected() {
        let encrypted = build_encrypted_package();
        let err = extract_text_from_bytes(&encrypted).expect_err("should detect encryption");
        assert!(matches!(err, ZoneFailure::PasswordProtected));
    }

    #[test]
    fn truncation_at_char_boundary_for_swedish_text() {
        // 25,000-char Swedish-style text — å is 2 bytes in UTF-8 so a
        // naive byte slice at index 24,000 could land mid-char.
        let chunk = "å".repeat(25_000);
        let (truncated, was_truncated) = truncate_to_char_limit(chunk, TRUNCATION_CHAR_LIMIT);
        assert!(was_truncated);
        assert_eq!(truncated.chars().count(), TRUNCATION_CHAR_LIMIT);
        // String::chars validates UTF-8 boundaries — if we corrupted
        // a char, this iteration would panic.
        assert_eq!(
            truncated.chars().filter(|c| *c == 'å').count(),
            TRUNCATION_CHAR_LIMIT
        );
    }

    #[test]
    fn text_at_exact_limit_is_not_marked_truncated() {
        let exact = "a".repeat(TRUNCATION_CHAR_LIMIT);
        let (text, was_truncated) = truncate_to_char_limit(exact.clone(), TRUNCATION_CHAR_LIMIT);
        assert!(!was_truncated);
        assert_eq!(text, exact);
    }

    #[test]
    fn text_one_over_limit_is_truncated() {
        let over = "a".repeat(TRUNCATION_CHAR_LIMIT + 1);
        let (text, was_truncated) = truncate_to_char_limit(over, TRUNCATION_CHAR_LIMIT);
        assert!(was_truncated);
        assert_eq!(text.len(), TRUNCATION_CHAR_LIMIT);
    }
}
