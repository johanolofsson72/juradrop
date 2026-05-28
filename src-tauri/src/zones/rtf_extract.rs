// Spec 009 — RTF text extraction (FR-003).
//
// Best-effort pure-Rust RTF text extraction via the `rtf-parser` crate.
// Embedded `\pict` / `\object` / `\objemb` runs are skipped silently —
// the crate's `RtfDocument::get_text()` only concatenates text from
// `StyleBlock.text` fields, so image and object blob data is structurally
// absent from the extracted output. The presence of an embedded object
// in a `.rtf` does NOT trigger `RtfParseError` on its own (per the Q2
// clarification in spec.md).
//
// Any parse failure — corruption, exotic dialect, encrypted, garbage
// bytes, non-UTF-8 source — surfaces as `RtfParseError`. Password-
// protected RTFs collapse into the same variant per FR-008.

use std::path::Path;

use rtf_parser::RtfDocument;

use super::errors::ZoneFailure;
use super::extract::{finalise, ExtractedText};

/// Extract plain text from a `.rtf` file. Returns `Err(RtfParseError)`
/// for any failure mode (filesystem error, non-UTF-8 source, malformed
/// RTF, exotic dialect, encrypted). Embedded objects and images are
/// silently skipped.
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let bytes = std::fs::read(path).map_err(|_| ZoneFailure::RtfParseError)?;
    let source = std::str::from_utf8(&bytes).map_err(|_| ZoneFailure::RtfParseError)?;
    let document = RtfDocument::try_from(source).map_err(|_| ZoneFailure::RtfParseError)?;
    let raw = document.get_text();
    finalise(raw, false, None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn write_temp(bytes: &[u8]) -> NamedTempFile {
        let mut f = NamedTempFile::new().expect("tempfile");
        f.write_all(bytes).expect("write");
        f
    }

    #[test]
    fn extracts_plain_text_from_minimal_rtf() {
        let rtf = b"{\\rtf1\\ansi{\\fonttbl\\f0\\fswiss Helvetica;}\\f0\\pard Hej JuraDrop.\\par}";
        let f = write_temp(rtf);
        let result = extract_text(f.path()).expect("happy path");
        assert!(result.raw.as_inner().contains("Hej JuraDrop"));
        assert!(!result.was_truncated);
        assert!(!result.was_partial);
        assert_eq!(result.frontmatter, None);
    }

    #[test]
    fn rejects_garbage_bytes_without_panic() {
        let f = write_temp(&[0xFF; 1024]);
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::RtfParseError)));
    }

    #[test]
    fn rejects_non_rtf_text() {
        let f = write_temp(b"This is not RTF.\nNo control word in sight.");
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::RtfParseError)));
    }

    #[test]
    fn rejects_missing_file() {
        let result = extract_text(Path::new("/nonexistent/path/does/not/exist.rtf"));
        assert!(matches!(result, Err(ZoneFailure::RtfParseError)));
    }

    #[test]
    fn whitespace_only_rtf_maps_to_empty_text() {
        // Valid RTF with no text body should fall through `finalise`
        // and surface as EmptyText, not RtfParseError.
        let rtf = b"{\\rtf1\\ansi\\par}";
        let f = write_temp(rtf);
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::EmptyText)));
    }
}
