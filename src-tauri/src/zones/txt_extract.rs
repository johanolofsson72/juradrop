// Spec 005 — .txt extraction with BOM-first / strict-UTF-8 /
// Windows-1252 cascade (FR-005, FR-006, FR-007).
//
// Decode cascade:
//   (1) read full file bytes
//   (2) sniff BOM from the first 4 bytes
//   (3) UTF-16 / UTF-32 BOM → UnsupportedEncoding (FR-007)
//   (4) UTF-8 BOM → strip BOM, decode rest as strict UTF-8
//   (5) no BOM → try strict UTF-8; on failure, fall back to Windows-1252
//   (6) strip null bytes, normalise CRLF → LF
//   (7) finalise (collapse blank lines + truncate + redact + EmptyText check)

use std::path::Path;

use super::errors::ZoneFailure;
use super::extract::{finalise, ExtractedText};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum BomKind {
    None,
    Utf8,
    Utf16Le,
    Utf16Be,
    Utf32Le,
    Utf32Be,
}

impl BomKind {
    /// Sniff the leading 4 bytes. UTF-32 LE must be checked BEFORE
    /// UTF-16 LE because their first two bytes are identical.
    fn detect(bytes: &[u8]) -> Self {
        match bytes {
            [0xFF, 0xFE, 0x00, 0x00, ..] => Self::Utf32Le,
            [0x00, 0x00, 0xFE, 0xFF, ..] => Self::Utf32Be,
            [0xFF, 0xFE, ..] => Self::Utf16Le,
            [0xFE, 0xFF, ..] => Self::Utf16Be,
            [0xEF, 0xBB, 0xBF, ..] => Self::Utf8,
            _ => Self::None,
        }
    }

    fn byte_length(self) -> usize {
        match self {
            Self::Utf8 => 3,
            Self::Utf16Le | Self::Utf16Be => 2,
            Self::Utf32Le | Self::Utf32Be => 4,
            Self::None => 0,
        }
    }
}

pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let bytes = std::fs::read(path).map_err(|_| ZoneFailure::ParseError)?;
    extract_text_from_bytes(&bytes)
}

pub fn extract_text_from_bytes(bytes: &[u8]) -> Result<ExtractedText, ZoneFailure> {
    let decoded = decode_text(bytes)?;
    let cleaned = decoded
        .replace('\0', "")
        .replace("\r\n", "\n")
        .replace('\r', "\n");
    finalise(cleaned, false, None)
}

/// Shared decode cascade — used by both `txt_extract` and
/// `md_extract`. Returns the decoded text or
/// `Err(ZoneFailure::UnsupportedEncoding)` for UTF-16 / UTF-32 BOMs.
pub fn decode_text(bytes: &[u8]) -> Result<String, ZoneFailure> {
    let bom = BomKind::detect(bytes);
    match bom {
        BomKind::Utf16Le | BomKind::Utf16Be | BomKind::Utf32Le | BomKind::Utf32Be => {
            Err(ZoneFailure::UnsupportedEncoding)
        }
        BomKind::Utf8 => {
            // Strip the 3-byte BOM, decode the rest as strict UTF-8.
            let body = &bytes[bom.byte_length()..];
            std::str::from_utf8(body)
                .map(|s| s.to_string())
                .map_err(|_| ZoneFailure::ParseError)
        }
        BomKind::None => {
            // Strict UTF-8 first.
            if let Ok(s) = std::str::from_utf8(bytes) {
                return Ok(s.to_string());
            }
            // Windows-1252 fallback. The decoder is total — every
            // byte 0x00–0xFF maps to a Unicode codepoint — so this
            // never errors.
            let (cow, _, _) = encoding_rs::WINDOWS_1252.decode(bytes);
            Ok(cow.into_owned())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bom_detect_utf8() {
        assert_eq!(BomKind::detect(b"\xEF\xBB\xBFhello"), BomKind::Utf8);
    }

    #[test]
    fn bom_detect_utf16_le() {
        assert_eq!(BomKind::detect(b"\xFF\xFEh\0i\0"), BomKind::Utf16Le);
    }

    #[test]
    fn bom_detect_utf16_be() {
        assert_eq!(BomKind::detect(b"\xFE\xFF\0h\0i"), BomKind::Utf16Be);
    }

    #[test]
    fn bom_detect_utf32_le() {
        // UTF-32 LE is 0xFF 0xFE 0x00 0x00 — must beat the UTF-16 LE
        // prefix match.
        assert_eq!(
            BomKind::detect(b"\xFF\xFE\x00\x00h\0\0\0"),
            BomKind::Utf32Le
        );
    }

    #[test]
    fn bom_detect_utf32_be() {
        assert_eq!(
            BomKind::detect(b"\x00\x00\xFE\xFF\0\0\0h"),
            BomKind::Utf32Be
        );
    }

    #[test]
    fn bom_detect_none_for_plain_ascii() {
        assert_eq!(BomKind::detect(b"hello"), BomKind::None);
    }

    #[test]
    fn bom_detect_none_for_empty_input() {
        assert_eq!(BomKind::detect(b""), BomKind::None);
    }

    #[test]
    fn utf8_no_bom_decodes_cleanly() {
        let bytes = "Hej världen".as_bytes();
        let result = extract_text_from_bytes(bytes).unwrap();
        assert_eq!(result.raw.as_inner(), "Hej världen");
        assert!(!result.was_truncated);
        assert!(!result.was_partial);
        assert_eq!(result.frontmatter, None);
    }

    #[test]
    fn utf8_bom_is_stripped() {
        let mut bytes = vec![0xEF, 0xBB, 0xBF];
        bytes.extend_from_slice("Hej".as_bytes());
        let result = extract_text_from_bytes(&bytes).unwrap();
        assert_eq!(result.raw.as_inner(), "Hej");
    }

    #[test]
    fn windows_1252_fallback_decodes_swedish_chars() {
        // Windows-1252 "Förbjudet" — å, ö, ä have specific Win1252 byte
        // mappings (0xE5, 0xF6, 0xE4) that are invalid UTF-8.
        let bytes: &[u8] = &[0x46, 0xF6, 0x72, 0x62, 0x6A, 0x75, 0x64, 0x65, 0x74];
        let result = extract_text_from_bytes(bytes).unwrap();
        assert_eq!(result.raw.as_inner(), "Förbjudet");
    }

    #[test]
    fn utf16_le_returns_unsupported_encoding() {
        let bytes: &[u8] = b"\xFF\xFEh\0i\0";
        let result = extract_text_from_bytes(bytes);
        assert!(matches!(result, Err(ZoneFailure::UnsupportedEncoding)));
    }

    #[test]
    fn utf16_be_returns_unsupported_encoding() {
        let bytes: &[u8] = b"\xFE\xFF\0h\0i";
        let result = extract_text_from_bytes(bytes);
        assert!(matches!(result, Err(ZoneFailure::UnsupportedEncoding)));
    }

    #[test]
    fn utf32_le_returns_unsupported_encoding() {
        let bytes: &[u8] = b"\xFF\xFE\x00\x00h\0\0\0";
        let result = extract_text_from_bytes(bytes);
        assert!(matches!(result, Err(ZoneFailure::UnsupportedEncoding)));
    }

    #[test]
    fn whitespace_only_returns_empty_text() {
        let result = extract_text_from_bytes(b"   \n\n\t  ");
        assert!(matches!(result, Err(ZoneFailure::EmptyText)));
    }

    #[test]
    fn crlf_normalised_to_lf() {
        let result = extract_text_from_bytes(b"line1\r\nline2\r\nline3").unwrap();
        assert_eq!(result.raw.as_inner(), "line1\nline2\nline3");
    }

    #[test]
    fn null_bytes_stripped() {
        let bytes: &[u8] = b"hel\0lo\0world";
        let result = extract_text_from_bytes(bytes).unwrap();
        assert_eq!(result.raw.as_inner(), "helloworld");
    }
}
