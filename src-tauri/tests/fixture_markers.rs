// Spec 013 SC-007 / FR-008 — every fixture document that contains
// fictitious personal data MUST carry the `[TESTDATA — fiktiva uppgifter]`
// marker, so no future contributor mistakes synthetic data for real data.
//
// The marker check extracts text from each fixture (docx via docx-rs,
// txt as UTF-8) and greps for the literal marker.

use std::path::{Path, PathBuf};

use juradrop_lib::zones::docx_extract::extract_text_from_bytes;

const MARKER: &str = "[TESTDATA — fiktiva uppgifter]";

fn doc(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/documents")
        .join(name)
}

fn docx_text(name: &str) -> String {
    let bytes = std::fs::read(doc(name)).unwrap_or_else(|e| panic!("read {name}: {e}"));
    extract_text_from_bytes(&bytes)
        .unwrap_or_else(|e| panic!("extract {name}: {e:?}"))
        .raw
        .as_inner()
        .to_string()
}

#[test]
fn personal_data_fixtures_carry_testdata_marker() {
    // The three fixtures whose content includes fictitious personal data.
    assert!(
        docx_text("anonymisera-input.docx").contains(MARKER),
        "anonymisera-input.docx missing TESTDATA marker"
    );
    assert!(
        docx_text("kontakter-input.docx").contains(MARKER),
        "kontakter-input.docx missing TESTDATA marker"
    );
    let generera = std::fs::read_to_string(doc("generera-input.txt")).expect("read generera txt");
    assert!(
        generera.contains(MARKER),
        "generera-input.txt missing TESTDATA marker"
    );
}

#[test]
fn anonymisera_fixture_uses_obviously_fake_personnummer() {
    // Edge case from spec.md — personnummer must be the reserved
    // 19010101-0101 / 19020202-0202 forms, never a plausible real number.
    let text = docx_text("anonymisera-input.docx");
    assert!(
        text.contains("19010101-0101") || text.contains("19020202-0202"),
        "anonymisera fixture must use the obviously-fake reserved personnummer forms"
    );
}
