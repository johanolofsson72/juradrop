// Spec 009 — Apple Pages text extraction (FR-004).
//
// Best-effort extraction:
//   1. Open the `.pages` bundle as a zip (existing `zip = 0.6` dep).
//   2. If the zip contains an `index.xml` member (legacy Pages, pre-IWA),
//      walk the XML with `quick-xml`, joining paragraphs with `\n` and
//      sections with `\n\n` per the Q4 clarification in spec.md.
//   3. If the zip is modern IWA-based (`Index.zip` / `Index/Document.iwa`),
//      surface `PagesParseError`. No pure-Rust IWA decoder exists; the
//      named-format error is the honest best-effort failure per spec.
//
// Any other failure mode — corruption, encrypted zip, malformed XML —
// also surfaces as `PagesParseError`. Password-protected Pages bundles
// collapse into the same variant per FR-008.
//
// The directory-form `.pages` bundle (legacy macOS, pre-v5) is routed
// to `InvalidFormat` at the dispatch layer (FR-019), before reaching
// this extractor.

use std::io::Read;
use std::path::Path;

use quick_xml::events::Event;
use quick_xml::Reader;

use super::errors::ZoneFailure;
use super::extract::{finalise, ExtractedText};

/// Extract plain text from an Apple Pages bundle. Modern IWA-based
/// bundles surface `Err(PagesParseError)` because no pure-Rust IWA
/// decoder is available; legacy bundles with an `index.xml` member
/// are walked and produce a successful `ExtractedText`.
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let file = std::fs::File::open(path).map_err(|_| ZoneFailure::PagesParseError)?;
    let mut zip = zip::ZipArchive::new(file).map_err(|_| ZoneFailure::PagesParseError)?;

    if let Ok(mut xml_member) = zip.by_name("index.xml") {
        let mut buf = String::new();
        xml_member
            .read_to_string(&mut buf)
            .map_err(|_| ZoneFailure::PagesParseError)?;
        let raw = walk_legacy_pages_xml(&buf)?;
        return finalise(raw, false, None);
    }

    Err(ZoneFailure::PagesParseError)
}

/// FR-004 + Q4 clarification — paragraphs joined with `\n`, sections
/// joined with `\n\n`. Headers and footers are extracted inline at
/// their visual position with no `Sidhuvud:` / `Sidfot:` prefix.
fn walk_legacy_pages_xml(source: &str) -> Result<String, ZoneFailure> {
    let mut reader = Reader::from_str(source);
    reader.config_mut().trim_text(false);
    let mut buf = Vec::new();
    let mut out = String::new();
    let mut depth_in_paragraph = 0u32;
    let mut paragraph_buffer = String::new();
    let mut first_section = true;
    let mut just_closed_paragraph = false;

    loop {
        match reader
            .read_event_into(&mut buf)
            .map_err(|_| ZoneFailure::PagesParseError)?
        {
            Event::Start(e) => {
                let qname = e.name();
                let local = local_name(qname.as_ref());
                if local == "section" {
                    if !first_section {
                        out.push_str("\n\n");
                    }
                    first_section = false;
                    just_closed_paragraph = false;
                } else if local == "p" || local == "h" {
                    depth_in_paragraph = 1;
                    paragraph_buffer.clear();
                }
            }
            Event::End(e) => {
                let qname = e.name();
                let local = local_name(qname.as_ref());
                if (local == "p" || local == "h") && depth_in_paragraph == 1 {
                    if just_closed_paragraph {
                        out.push('\n');
                    }
                    out.push_str(&paragraph_buffer);
                    just_closed_paragraph = true;
                    depth_in_paragraph = 0;
                    paragraph_buffer.clear();
                }
            }
            Event::Text(t) if depth_in_paragraph > 0 => {
                let decoded = t.unescape().map_err(|_| ZoneFailure::PagesParseError)?;
                paragraph_buffer.push_str(decoded.as_ref());
            }
            Event::CData(c) if depth_in_paragraph > 0 => {
                paragraph_buffer.push_str(
                    std::str::from_utf8(c.as_ref()).map_err(|_| ZoneFailure::PagesParseError)?,
                );
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }

    Ok(out)
}

/// Strip an XML namespace prefix and return just the local name as
/// a borrowed byte slice converted to a `&str`. Used to match `<sf:p>`
/// and `<text:p>` against the same `"p"` token.
fn local_name(qname: &[u8]) -> &str {
    let name = std::str::from_utf8(qname).unwrap_or("");
    match name.rfind(':') {
        Some(idx) => &name[idx + 1..],
        None => name,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;
    use zip::write::FileOptions;
    use zip::ZipWriter;

    fn write_temp(bytes: &[u8]) -> NamedTempFile {
        let mut f = NamedTempFile::new().expect("tempfile");
        f.write_all(bytes).expect("write");
        f
    }

    fn zip_with_index_xml(xml: &str) -> NamedTempFile {
        let f = NamedTempFile::new().expect("tempfile");
        let mut zw = ZipWriter::new(f.reopen().expect("reopen"));
        zw.start_file("index.xml", FileOptions::default()).unwrap();
        zw.write_all(xml.as_bytes()).unwrap();
        zw.finish().unwrap();
        f
    }

    #[test]
    fn extracts_legacy_xml_paragraphs() {
        let xml = r#"<?xml version="1.0"?>
<document xmlns:sf="http://example.com/sf">
  <sf:section>
    <sf:p>Hej Jura.</sf:p>
    <sf:p>Andra raden.</sf:p>
  </sf:section>
</document>"#;
        let f = zip_with_index_xml(xml);
        let result = extract_text(f.path()).expect("happy path");
        let raw = result.raw.as_inner();
        assert!(raw.contains("Hej Jura"));
        assert!(raw.contains("Andra raden"));
    }

    #[test]
    fn joins_sections_with_double_newline() {
        let xml = r#"<?xml version="1.0"?>
<document xmlns:sf="http://example.com/sf">
  <sf:section><sf:p>första.</sf:p></sf:section>
  <sf:section><sf:p>andra.</sf:p></sf:section>
</document>"#;
        let f = zip_with_index_xml(xml);
        let result = extract_text(f.path()).expect("happy path");
        let raw = result.raw.as_inner();
        // Find both paragraphs; verify the join between them is the
        // section break (\n\n) — and not the inner-paragraph join (\n).
        let idx_a = raw.find("första").expect("first paragraph present");
        let idx_b = raw.find("andra").expect("second paragraph present");
        assert!(idx_b > idx_a);
        let between = &raw[idx_a + "första.".len()..idx_b];
        assert!(
            between.contains("\n\n"),
            "section break missing between paragraphs: {between:?}"
        );
    }

    #[test]
    fn rejects_modern_iwa_bundle_without_index_xml() {
        // A .pages bundle with only an Index/Document.iwa member
        // surfaces PagesParseError.
        let f = NamedTempFile::new().unwrap();
        {
            let mut zw = ZipWriter::new(f.reopen().unwrap());
            zw.start_file("Index/Document.iwa", FileOptions::default())
                .unwrap();
            zw.write_all(b"fake-iwa-bytes").unwrap();
            zw.finish().unwrap();
        }
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::PagesParseError)));
    }

    #[test]
    fn rejects_garbage_bytes_without_panic() {
        let f = write_temp(&[0xFF; 1024]);
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::PagesParseError)));
    }

    #[test]
    fn rejects_missing_file() {
        let result = extract_text(Path::new("/nonexistent/path/does/not/exist.pages"));
        assert!(matches!(result, Err(ZoneFailure::PagesParseError)));
    }

    #[test]
    fn whitespace_only_pages_maps_to_empty_text() {
        let xml = r#"<?xml version="1.0"?>
<document xmlns:sf="http://example.com/sf">
  <sf:section><sf:p>   </sf:p></sf:section>
</document>"#;
        let f = zip_with_index_xml(xml);
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::EmptyText)));
    }
}
