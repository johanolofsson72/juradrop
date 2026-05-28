// Spec 009 — ODT (OpenDocument Text) extraction (FR-005).
//
// Walks the `content.xml` member of the ODT zip bundle with `quick-xml`,
// concatenating `<text:p>`, `<text:h>`, and `<text:span>` runs in
// document order. Tracked-change markup is resolved to the accepted /
// final view per the Q3 clarification in spec.md: insertions are kept
// as plain text, deletions are skipped.
//
// Failure modes that surface as `OdtParseError`:
//   - Filesystem error opening the file
//   - Not a valid zip
//   - Missing `mimetype` or wrong `mimetype` value
//   - Encrypted content (declared in `META-INF/manifest.xml`)
//   - Missing `content.xml`
//   - Malformed XML inside `content.xml`
//
// Per FR-008, password-protected ODTs collapse into `OdtParseError`,
// NOT `PasswordProtected` — the long-tail failure surface is uniform.

use std::io::Read;
use std::path::Path;

use quick_xml::events::Event;
use quick_xml::Reader;

use super::errors::ZoneFailure;
use super::extract::{finalise, ExtractedText};

const ODT_MIMETYPE: &str = "application/vnd.oasis.opendocument.text";

/// Extract plain text from an `.odt` file. Returns `Err(OdtParseError)`
/// for any failure mode; returns `Err(EmptyText)` when extraction
/// succeeds but produces only whitespace.
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let file = std::fs::File::open(path).map_err(|_| ZoneFailure::OdtParseError)?;
    let mut zip = zip::ZipArchive::new(file).map_err(|_| ZoneFailure::OdtParseError)?;

    verify_mimetype(&mut zip)?;
    if has_encryption_data(&mut zip) {
        return Err(ZoneFailure::OdtParseError);
    }

    let mut content_xml = String::new();
    {
        let mut entry = zip
            .by_name("content.xml")
            .map_err(|_| ZoneFailure::OdtParseError)?;
        entry
            .read_to_string(&mut content_xml)
            .map_err(|_| ZoneFailure::OdtParseError)?;
    }

    let raw = walk_content_xml_accepted_view(&content_xml)?;
    finalise(raw, false, None)
}

fn verify_mimetype<R: std::io::Read + std::io::Seek>(
    zip: &mut zip::ZipArchive<R>,
) -> Result<(), ZoneFailure> {
    let mut entry = zip
        .by_name("mimetype")
        .map_err(|_| ZoneFailure::OdtParseError)?;
    let mut value = String::new();
    entry
        .read_to_string(&mut value)
        .map_err(|_| ZoneFailure::OdtParseError)?;
    if value.trim() != ODT_MIMETYPE {
        return Err(ZoneFailure::OdtParseError);
    }
    Ok(())
}

/// Detect `<manifest:encryption-data ... />` inside
/// `META-INF/manifest.xml`. Returns `false` if the manifest is missing
/// (the caller surfaces that as a different error later) or if no
/// encryption-data element is present.
fn has_encryption_data<R: std::io::Read + std::io::Seek>(zip: &mut zip::ZipArchive<R>) -> bool {
    let mut manifest = match zip.by_name("META-INF/manifest.xml") {
        Ok(m) => m,
        Err(_) => return false,
    };
    let mut buf = String::new();
    if manifest.read_to_string(&mut buf).is_err() {
        return false;
    }
    buf.contains("encryption-data")
}

/// Q3 clarification — walk `<text:p>` / `<text:h>` / `<text:span>`
/// runs, joining paragraphs/headings with `\n`. Inside any
/// `<text:change-marker type="deletion">` (or the older
/// `<text:deletion>` form), skip all child text events until the
/// matching close. Insertions and unmarked text are kept verbatim.
fn walk_content_xml_accepted_view(source: &str) -> Result<String, ZoneFailure> {
    let mut reader = Reader::from_str(source);
    reader.config_mut().trim_text(false);
    let mut buf = Vec::new();
    let mut out = String::new();
    let mut depth_in_block = 0u32;
    let mut block_buffer = String::new();
    let mut skip_depth: Option<u32> = None;
    let mut current_depth = 0u32;
    let mut just_closed_block = false;

    loop {
        match reader
            .read_event_into(&mut buf)
            .map_err(|_| ZoneFailure::OdtParseError)?
        {
            Event::Start(e) => {
                current_depth += 1;
                let qname = e.name();
                let local = local_name(qname.as_ref());
                if is_deletion_marker(local, &e) {
                    if skip_depth.is_none() {
                        skip_depth = Some(current_depth);
                    }
                } else if (local == "p" || local == "h") && depth_in_block == 0 {
                    depth_in_block = current_depth;
                    block_buffer.clear();
                }
            }
            Event::End(_) => {
                if let Some(d) = skip_depth {
                    if current_depth == d {
                        skip_depth = None;
                    }
                }
                if depth_in_block != 0 && current_depth == depth_in_block {
                    if just_closed_block {
                        out.push('\n');
                    }
                    out.push_str(&block_buffer);
                    just_closed_block = true;
                    depth_in_block = 0;
                    block_buffer.clear();
                }
                current_depth = current_depth.saturating_sub(1);
            }
            Event::Text(t) => {
                if skip_depth.is_some() {
                    continue;
                }
                if depth_in_block > 0 {
                    let decoded = t.unescape().map_err(|_| ZoneFailure::OdtParseError)?;
                    block_buffer.push_str(decoded.as_ref());
                }
            }
            Event::CData(c) => {
                if skip_depth.is_some() {
                    continue;
                }
                if depth_in_block > 0 {
                    block_buffer.push_str(
                        std::str::from_utf8(c.as_ref()).map_err(|_| ZoneFailure::OdtParseError)?,
                    );
                }
            }
            Event::Empty(_e) => {
                // Self-closing tags don't affect depth and contribute
                // no body text (self-closing change-marker is a no-op
                // for the accepted-view extractor).
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }

    Ok(out)
}

fn is_deletion_marker(local: &str, e: &quick_xml::events::BytesStart<'_>) -> bool {
    if local == "deletion" {
        return true;
    }
    if local != "change-marker" {
        return false;
    }
    for attr in e.attributes().flatten() {
        let key = attr.key.as_ref();
        let key_str = std::str::from_utf8(key).unwrap_or("");
        let local_key = match key_str.rfind(':') {
            Some(i) => &key_str[i + 1..],
            None => key_str,
        };
        if local_key == "type" {
            // Compare raw bytes — avoids the `unescape_value` API,
            // which is gated on `encoding` feature toggle in quick-xml.
            // ODT attribute values for change-marker types are ASCII
            // ("insertion" / "deletion"), so byte equality is correct.
            if attr.value.as_ref() == b"deletion" {
                return true;
            }
        }
    }
    false
}

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

    fn build_odt(content_xml: &str) -> NamedTempFile {
        let f = NamedTempFile::new().expect("tempfile");
        let mut zw = ZipWriter::new(f.reopen().expect("reopen"));
        zw.start_file("mimetype", FileOptions::default()).unwrap();
        zw.write_all(ODT_MIMETYPE.as_bytes()).unwrap();
        zw.start_file("content.xml", FileOptions::default())
            .unwrap();
        zw.write_all(content_xml.as_bytes()).unwrap();
        zw.finish().unwrap();
        f
    }

    fn build_odt_encrypted(content_xml: &str) -> NamedTempFile {
        let f = NamedTempFile::new().expect("tempfile");
        let mut zw = ZipWriter::new(f.reopen().expect("reopen"));
        zw.start_file("mimetype", FileOptions::default()).unwrap();
        zw.write_all(ODT_MIMETYPE.as_bytes()).unwrap();
        zw.start_file("META-INF/manifest.xml", FileOptions::default())
            .unwrap();
        zw.write_all(
            br#"<?xml version="1.0"?>
<manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">
  <manifest:file-entry manifest:full-path="content.xml">
    <manifest:encryption-data />
  </manifest:file-entry>
</manifest>"#,
        )
        .unwrap();
        zw.start_file("content.xml", FileOptions::default())
            .unwrap();
        zw.write_all(content_xml.as_bytes()).unwrap();
        zw.finish().unwrap();
        f
    }

    #[test]
    fn extracts_paragraphs_and_headings() {
        let xml = r#"<?xml version="1.0"?>
<office:document-content xmlns:office="urn:office" xmlns:text="urn:text">
  <office:body><office:text>
    <text:h>Rubrik</text:h>
    <text:p>Första stycket.</text:p>
    <text:p>Andra stycket.</text:p>
  </office:text></office:body>
</office:document-content>"#;
        let f = build_odt(xml);
        let result = extract_text(f.path()).expect("happy path");
        let raw = result.raw.as_inner();
        assert!(raw.contains("Rubrik"));
        assert!(raw.contains("Första stycket"));
        assert!(raw.contains("Andra stycket"));
    }

    #[test]
    fn tracked_changes_accepted_view_keeps_insertions_drops_deletions() {
        let xml = r#"<?xml version="1.0"?>
<office:document-content xmlns:office="urn:office" xmlns:text="urn:text">
  <office:body><office:text>
    <text:p>Stycket innehåller <text:change-marker text:type="insertion">infogad text</text:change-marker> samt <text:change-marker text:type="deletion">struken text</text:change-marker>.</text:p>
  </office:text></office:body>
</office:document-content>"#;
        let f = build_odt(xml);
        let result = extract_text(f.path()).expect("happy path");
        let raw = result.raw.as_inner();
        assert!(raw.contains("infogad text"), "insertion should be kept");
        assert!(
            !raw.contains("struken text"),
            "deletion should be dropped: {raw:?}"
        );
    }

    #[test]
    fn rejects_encrypted_odt() {
        let xml = r#"<office:document-content/>"#;
        let f = build_odt_encrypted(xml);
        let result = extract_text(f.path());
        assert!(
            matches!(result, Err(ZoneFailure::OdtParseError)),
            "encrypted ODT must surface OdtParseError, NOT PasswordProtected"
        );
    }

    #[test]
    fn rejects_wrong_mimetype() {
        let f = NamedTempFile::new().unwrap();
        {
            let mut zw = ZipWriter::new(f.reopen().unwrap());
            zw.start_file("mimetype", FileOptions::default()).unwrap();
            zw.write_all(b"application/zip").unwrap();
            zw.finish().unwrap();
        }
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::OdtParseError)));
    }

    #[test]
    fn rejects_missing_content_xml() {
        let f = NamedTempFile::new().unwrap();
        {
            let mut zw = ZipWriter::new(f.reopen().unwrap());
            zw.start_file("mimetype", FileOptions::default()).unwrap();
            zw.write_all(ODT_MIMETYPE.as_bytes()).unwrap();
            zw.finish().unwrap();
        }
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::OdtParseError)));
    }

    #[test]
    fn rejects_garbage_bytes_without_panic() {
        let f = write_temp(&[0xFF; 1024]);
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::OdtParseError)));
    }

    #[test]
    fn rejects_missing_file() {
        let result = extract_text(Path::new("/nonexistent/path/does/not/exist.odt"));
        assert!(matches!(result, Err(ZoneFailure::OdtParseError)));
    }

    #[test]
    fn whitespace_only_content_maps_to_empty_text() {
        let xml = r#"<?xml version="1.0"?>
<office:document-content xmlns:office="urn:office" xmlns:text="urn:text">
  <office:body><office:text>
    <text:p>   </text:p>
  </office:text></office:body>
</office:document-content>"#;
        let f = build_odt(xml);
        let result = extract_text(f.path());
        assert!(matches!(result, Err(ZoneFailure::EmptyText)));
    }
}
