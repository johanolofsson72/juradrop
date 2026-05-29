// Spec 009 — failure-taxonomy invariant test for the long-tail
// extractors. Spec 028 removed the Pages extractor, leaving Rtf + Odt.
//
// For every fixture exercised across the extractors, the surfaced
// ZoneFailure variant MUST be in the allowed set
// {RtfParseError, OdtParseError, EmptyText}.
//
// Specifically, the long-tail formats NEVER surface:
//   - PasswordProtected   (FR-008 — collapsed into format-named error)
//   - ParseError          (.docx-specific; not for long-tail)
//   - InvalidFormat       (the dispatcher's responsibility, not the extractor's)
//   - NoExtractableText   (.pdf-specific)
//   - UnsupportedEncoding (.txt/.md-specific)
//
// The fixtures are generated inline (zip + xml strings + raw bytes)
// so the test is hermetic — no external fixture files to keep in sync.

use std::io::Write;

use juradrop_lib::zones::ZoneFailure;
use juradrop_lib::zones::{odt_extract, rtf_extract};
use tempfile::NamedTempFile;
use zip::write::FileOptions;
use zip::ZipWriter;

const ODT_MIMETYPE: &str = "application/vnd.oasis.opendocument.text";

fn allowed(failure: ZoneFailure) -> bool {
    matches!(
        failure,
        ZoneFailure::RtfParseError | ZoneFailure::OdtParseError | ZoneFailure::EmptyText
    )
}

fn write_temp(bytes: &[u8]) -> NamedTempFile {
    let mut f = NamedTempFile::new().expect("tempfile");
    f.write_all(bytes).expect("write");
    f
}

fn build_odt_encrypted() -> NamedTempFile {
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
    zw.write_all(b"<office:document-content/>").unwrap();
    zw.finish().unwrap();
    f
}

#[test]
fn rtf_extractor_failure_modes_are_in_allowed_set() {
    // Garbage bytes.
    let f1 = write_temp(&[0xFF; 1024]);
    let r1 = rtf_extract::extract_text(f1.path()).expect_err("garbage rtf");
    assert!(
        allowed(r1),
        "RTF garbage surfaced disallowed variant: {r1:?}"
    );

    // Empty / whitespace-only RTF.
    let f2 = write_temp(b"{\\rtf1\\ansi\\par}");
    let r2 = rtf_extract::extract_text(f2.path()).expect_err("empty rtf");
    assert!(allowed(r2), "RTF empty surfaced disallowed variant: {r2:?}");
    assert_eq!(r2, ZoneFailure::EmptyText);

    // Non-RTF text.
    let f3 = write_temp(b"This is not RTF at all.");
    let r3 = rtf_extract::extract_text(f3.path()).expect_err("non-rtf");
    assert!(
        allowed(r3),
        "RTF non-rtf surfaced disallowed variant: {r3:?}"
    );
    assert_eq!(r3, ZoneFailure::RtfParseError);
}

// Spec 028 — the Pages extractor was removed; a dropped .pages now routes to
// ZoneFailure::PagesUnsupported at the drop handler (see sammanfatta.rs +
// errors.rs unit tests), never through an extractor.

#[test]
fn odt_extractor_failure_modes_are_in_allowed_set() {
    // Garbage bytes.
    let f1 = write_temp(&[0xFF; 1024]);
    let r1 = odt_extract::extract_text(f1.path()).expect_err("garbage odt");
    assert!(allowed(r1));
    assert_eq!(r1, ZoneFailure::OdtParseError);

    // Encrypted ODT → format-named error (FR-008 collapse).
    let f2 = build_odt_encrypted();
    let r2 = odt_extract::extract_text(f2.path()).expect_err("encrypted odt");
    assert!(allowed(r2));
    assert_eq!(
        r2,
        ZoneFailure::OdtParseError,
        "encrypted ODT must surface format-named error, not PasswordProtected"
    );
}

#[test]
fn long_tail_extractors_never_surface_password_protected() {
    // Explicit negative invariant — none of the failure modes
    // exercised above should ever equal PasswordProtected. The
    // assertions above already establish this; this test pins the
    // contract as its own named case so a regression is loud.
    for forbidden in [
        ZoneFailure::PasswordProtected,
        ZoneFailure::ParseError,
        ZoneFailure::NoExtractableText,
        ZoneFailure::UnsupportedEncoding,
        ZoneFailure::InvalidFormat,
    ] {
        assert!(
            !allowed(forbidden),
            "ZoneFailure::{forbidden:?} must NOT be in the long-tail allowed set"
        );
    }
}
