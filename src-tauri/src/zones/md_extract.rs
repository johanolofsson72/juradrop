// Spec 005 — Markdown extraction.
//
// Same BOM-first cascade as txt_extract (delegated to
// `txt_extract::decode_text`). Additionally captures a leading YAML
// (`---`) or TOML (`+++`) frontmatter block within the first 8 KB
// (FR-008a) into `ExtractedText.frontmatter`. Only the body Markdown
// is sent to the model; the writer prepends the captured frontmatter
// verbatim to the sidecar (handled in md_write).

use std::path::Path;

use super::errors::ZoneFailure;
use super::extract::{finalise, ExtractedText, FRONTMATTER_SCAN_BYTES};

pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let bytes = std::fs::read(path).map_err(|_| ZoneFailure::ParseError)?;
    extract_text_from_bytes(&bytes)
}

pub fn extract_text_from_bytes(bytes: &[u8]) -> Result<ExtractedText, ZoneFailure> {
    let decoded = super::txt_extract::decode_text(bytes)?;
    let (frontmatter, body) = split_frontmatter(&decoded);
    let cleaned = body
        .replace('\0', "")
        .replace("\r\n", "\n")
        .replace('\r', "\n");
    finalise(cleaned, false, frontmatter)
}

/// FR-008a — detect a leading YAML (`---`) or TOML (`+++`) frontmatter
/// block within the first 8 KB. Captures the entire block including
/// fences and trailing newline. Returns
/// `(Some(block), body)` on detection, `(None, full_text)` otherwise.
fn split_frontmatter(text: &str) -> (Option<String>, String) {
    // Helper to find a matching closing fence on its own line.
    fn find_close(text: &str, fence: &str, scan_limit: usize) -> Option<usize> {
        // Look for "\n<fence>\n" within the scan window.
        let needle = format!("\n{fence}\n");
        let scan = &text[..text.len().min(scan_limit)];
        scan.find(&needle).map(|i| i + needle.len())
    }

    if text.starts_with("---\n") {
        if let Some(end) = find_close(text, "---", FRONTMATTER_SCAN_BYTES) {
            let block = text[..end].to_string();
            let body = text[end..].to_string();
            return (Some(block), body);
        }
    } else if text.starts_with("+++\n") {
        if let Some(end) = find_close(text, "+++", FRONTMATTER_SCAN_BYTES) {
            let block = text[..end].to_string();
            let body = text[end..].to_string();
            return (Some(block), body);
        }
    }

    (None, text.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_frontmatter_is_passthrough() {
        let md = "# Heading\n\nBody text.\n";
        let result = extract_text_from_bytes(md.as_bytes()).unwrap();
        assert_eq!(result.frontmatter, None);
        assert_eq!(result.raw.as_inner(), md);
    }

    #[test]
    fn yaml_frontmatter_captured_verbatim() {
        let md = "---\ntitle: Min studie\ntags: [juridik]\n---\n# H1\n\nBody.\n";
        let result = extract_text_from_bytes(md.as_bytes()).unwrap();
        assert_eq!(
            result.frontmatter,
            Some("---\ntitle: Min studie\ntags: [juridik]\n---\n".to_string())
        );
        assert_eq!(result.raw.as_inner(), "# H1\n\nBody.\n");
    }

    #[test]
    fn toml_frontmatter_captured_verbatim() {
        let md = "+++\ntitle = \"x\"\n+++\nBody.\n";
        let result = extract_text_from_bytes(md.as_bytes()).unwrap();
        assert_eq!(
            result.frontmatter,
            Some("+++\ntitle = \"x\"\n+++\n".to_string())
        );
        assert_eq!(result.raw.as_inner(), "Body.\n");
    }

    #[test]
    fn malformed_frontmatter_treated_as_no_frontmatter() {
        // Opening --- but no closing fence within scan window.
        let md = "---\ntitle: oops\nno closing fence ever\n";
        let result = extract_text_from_bytes(md.as_bytes()).unwrap();
        assert_eq!(result.frontmatter, None);
        assert!(result.raw.as_inner().contains("title: oops"));
    }

    #[test]
    fn body_only_whitespace_returns_empty_text() {
        let md = "---\ntitle: x\n---\n\n   \n\t\n";
        let result = extract_text_from_bytes(md.as_bytes());
        assert!(matches!(result, Err(ZoneFailure::EmptyText)));
    }

    #[test]
    fn utf16_md_returns_unsupported_encoding() {
        let bytes: &[u8] = b"\xFF\xFE#\0 \0H\0";
        let result = extract_text_from_bytes(bytes);
        assert!(matches!(result, Err(ZoneFailure::UnsupportedEncoding)));
    }

    #[test]
    fn utf8_bom_with_frontmatter_strips_bom_and_captures_block() {
        let mut bytes = vec![0xEF, 0xBB, 0xBF];
        bytes.extend_from_slice(b"---\ntitle: a\n---\nBody.\n");
        let result = extract_text_from_bytes(&bytes).unwrap();
        assert_eq!(result.frontmatter, Some("---\ntitle: a\n---\n".to_string()));
        assert_eq!(result.raw.as_inner(), "Body.\n");
    }

    #[test]
    fn yaml_fence_must_be_at_byte_zero() {
        // "  ---\n..." doesn't count — extra leading whitespace means
        // the file doesn't start with the fence.
        let md = "  ---\ntitle: x\n---\nBody.\n";
        let result = extract_text_from_bytes(md.as_bytes()).unwrap();
        assert_eq!(result.frontmatter, None);
    }
}
