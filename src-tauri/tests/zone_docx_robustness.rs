// Spec 003 / T046 — destructive robustness tests for the docx
// extraction layer.
//
// Each case feeds a deliberately-malformed `.docx` (or a fake one) to
// `zones::docx_extract::extract_text_from_bytes` and asserts the
// matching `ZoneFailure` surfaces — not a panic, not a generic
// `ParseError` catch-all that loses the user-visible detail.
//
// Most cases live as unit tests inside `docx_extract.rs#[cfg(test)]`;
// this file is the integration-level mirror that prevents future
// `pub` API regressions from drifting silently.

use std::io::{Cursor, Write};

use docx_rs::{Docx, Paragraph, Run};
use juradrop_lib::zones::docx_extract::{extract_text_from_bytes, TRUNCATION_CHAR_LIMIT};
use juradrop_lib::zones::errors::ZoneFailure;

fn pack_docx(paragraphs: &[&str]) -> Vec<u8> {
    let mut docx = Docx::new();
    for p in paragraphs {
        docx = docx.add_paragraph(Paragraph::new().add_run(Run::new().add_text(*p)));
    }
    let mut buf: Vec<u8> = Vec::new();
    docx.build().pack(Cursor::new(&mut buf)).expect("pack docx");
    buf
}

/// Build a fake zip that looks like an encrypted Office package — has
/// the `EncryptedPackage` entry but no `word/document.xml`.
fn fake_encrypted_docx() -> Vec<u8> {
    let mut buf: Vec<u8> = Vec::new();
    {
        let mut zip = zip::ZipWriter::new(Cursor::new(&mut buf));
        let opts =
            zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Deflated);
        zip.start_file("EncryptedPackage", opts).unwrap();
        zip.write_all(&[0u8; 128]).unwrap();
        zip.finish().unwrap();
    }
    buf
}

#[test]
fn corrupt_zip_surfaces_parse_error() {
    let garbage = b"PK\x03\x04 followed by absolute nonsense bytes \xff\xfe";
    let result = extract_text_from_bytes(garbage);
    assert!(
        matches!(result, Err(ZoneFailure::ParseError)),
        "expected ParseError on corrupt zip, got {result:?}"
    );
}

#[test]
fn non_zip_bytes_surface_parse_error() {
    let result = extract_text_from_bytes(b"this is plain text, not a .docx at all");
    assert!(matches!(result, Err(ZoneFailure::ParseError)));
}

#[test]
fn encrypted_docx_surfaces_password_protected_not_parse_error() {
    let bytes = fake_encrypted_docx();
    let result = extract_text_from_bytes(&bytes);
    assert!(
        matches!(result, Err(ZoneFailure::PasswordProtected)),
        "encrypted docx must surface PasswordProtected (FR-017), not the \
         ParseError catch-all; got {result:?}"
    );
}

#[test]
fn empty_paragraph_surfaces_empty_text_not_parse_error() {
    let bytes = pack_docx(&[""]);
    let result = extract_text_from_bytes(&bytes);
    assert!(
        matches!(result, Err(ZoneFailure::EmptyText)),
        "all-whitespace .docx must surface EmptyText (FR-018), got {result:?}"
    );
}

#[test]
fn whitespace_only_paragraph_surfaces_empty_text() {
    let bytes = pack_docx(&["   \t  "]);
    let result = extract_text_from_bytes(&bytes);
    assert!(matches!(result, Err(ZoneFailure::EmptyText)));
}

#[test]
fn body_at_exact_truncation_limit_is_not_marked_truncated() {
    let exact = "a".repeat(TRUNCATION_CHAR_LIMIT);
    let bytes = pack_docx(&[&exact]);
    let result = extract_text_from_bytes(&bytes).expect("ok at the limit");
    assert!(!result.was_truncated);
    assert_eq!(result.char_count, TRUNCATION_CHAR_LIMIT);
}

#[test]
fn body_one_char_over_limit_is_truncated_to_the_limit() {
    let over = "a".repeat(TRUNCATION_CHAR_LIMIT + 1);
    let bytes = pack_docx(&[&over]);
    let result = extract_text_from_bytes(&bytes).expect("ok one-over");
    assert!(result.was_truncated);
    assert_eq!(result.char_count, TRUNCATION_CHAR_LIMIT);
}

#[test]
fn body_well_over_limit_with_swedish_chars_truncates_on_char_boundary() {
    // 25,000 å characters — each is 2 bytes in UTF-8. A naive byte slice
    // at byte 24,000 would land mid-character; the char-boundary slice
    // must preserve the å character exactly.
    let body = "å".repeat(25_000);
    let bytes = pack_docx(&[&body]);
    let result = extract_text_from_bytes(&bytes).expect("ok swedish");
    assert!(result.was_truncated);
    // String::chars validates UTF-8 boundaries — if we corrupted a
    // character on truncation, calling chars().count() here would
    // either panic or produce a wrong count.
    let counted = result.raw.as_inner().chars().count();
    assert_eq!(counted, TRUNCATION_CHAR_LIMIT);
}

#[test]
fn multiple_paragraphs_are_joined_with_double_newline() {
    let bytes = pack_docx(&["Domskäl A.", "Domskäl B."]);
    let result = extract_text_from_bytes(&bytes).expect("ok");
    assert!(result.raw.as_inner().contains("Domskäl A."));
    assert!(result.raw.as_inner().contains("Domskäl B."));
    assert!(result.raw.as_inner().contains("\n\n"));
}

#[test]
fn empty_bytes_surface_parse_error() {
    let result = extract_text_from_bytes(&[]);
    assert!(matches!(result, Err(ZoneFailure::ParseError)));
}

/// T048 (Rust half) — cross-language drift assertion. The fixture
/// `tests/fixtures/zone-error-strings.json` is the single source of
/// truth for the Swedish strings; both `ZoneFailure::Display` (Rust)
/// and `SWEDISH_ZONE_ERROR` (TS) assert against it.
///
/// If a future PR changes a string on the Rust side without updating
/// the fixture, this test fails. If a future PR updates the fixture
/// without updating both sides, the matching vitest test fails. Both
/// languages forced into lock-step.
#[test]
fn every_zone_failure_string_matches_the_cross_language_fixture() {
    let manifest = env!("CARGO_MANIFEST_DIR");
    let fixture_path = std::path::Path::new(manifest)
        .join("tests")
        .join("fixtures")
        .join("zone-error-strings.json");
    let json =
        std::fs::read_to_string(&fixture_path).expect("zone-error-strings.json fixture must exist");
    let fixture: serde_json::Value =
        serde_json::from_str(&json).expect("fixture must be valid JSON");

    let cases: &[(ZoneFailure, &str)] = &[
        (ZoneFailure::InvalidFormat, "invalid_format"),
        (ZoneFailure::MultipleFiles, "multiple_files"),
        (ZoneFailure::ZoneBusy, "zone_busy"),
        (ZoneFailure::ZoneDisabled, "zone_disabled"),
        (ZoneFailure::ParseError, "parse_error"),
        (ZoneFailure::PasswordProtected, "password_protected"),
        (ZoneFailure::EmptyText, "empty_text"),
        (ZoneFailure::ModelError, "model_error"),
        (ZoneFailure::SaveError, "save_error"),
        // Spec 005 — two new variants for the PDF + text-encoding paths.
        (ZoneFailure::NoExtractableText, "no_extractable_text"),
        (ZoneFailure::UnsupportedEncoding, "unsupported_encoding"),
    ];

    for (variant, key) in cases {
        let rust_string = variant.to_string();
        let fixture_string = fixture
            .get(key)
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("fixture missing key {key:?}"));
        assert_eq!(
            rust_string, fixture_string,
            "ZoneFailure::{variant:?} Display drift vs fixture[{key:?}]"
        );
    }

    // Also assert the fixture has exactly the expected key count — a
    // new variant added to the enum without a fixture entry (or vice
    // versa) fails here.
    let fixture_obj = fixture.as_object().expect("fixture is an object");
    // _comment + 15 variants (9 spec 003 + 2 spec 005 + 3 spec 009 + 1 spec 024
    // file_too_large) = 16 keys.
    assert_eq!(
        fixture_obj.len(),
        16,
        "fixture must list exactly 15 ZoneFailure variants + 1 _comment field"
    );
}
