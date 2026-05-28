// Spec 013 US2 / FR-010, FR-012, FR-012a — cross-format extraction probe.
//
// The 6 committed `extraction-probe.<ext>` fixtures (docx/pdf/txt/md/rtf/odt)
// all carry the SAME canonical Swedish paragraph. Each format extracts back
// to that paragraph (modulo per-format whitespace normalization). `.pages`
// is excluded from the probe set (FR-009a) and has a dedicated failure-mode
// test (FR-012a) since Apple IWA extraction is deferred.
//
// These run on every `cargo test` — no `--ignored`, no network, no Ollama.

use std::path::{Path, PathBuf};

use juradrop_lib::zones::extract::extract_text;
use juradrop_lib::zones::input_format::InputFormat;
use juradrop_lib::zones::ZoneFailure;

// FR-010 — the canonical paragraph, byte-pinned to the committed .txt
// fixture (single source of truth, shared with the generator).
pub const CANONICAL_EXTRACTION_PROBE_TEXT: &str =
    include_str!("fixtures/extraction-probe/extraction-probe.txt");

fn probe(ext: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extraction-probe")
        .join(format!("extraction-probe.{ext}"))
}

/// Whitespace-insensitive compare — PDF/RTF extraction introduces spacing
/// variation (US2 acceptance scenario 2 permits a normalized comparison).
fn normalize(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn assert_extracts_canonical(ext: &str, fmt: InputFormat) {
    let extracted = extract_text(&probe(ext), fmt)
        .unwrap_or_else(|e| panic!("{ext}: extraction failed: {e:?}"));
    let got = normalize(extracted.raw.as_inner());
    let want = normalize(CANONICAL_EXTRACTION_PROBE_TEXT);
    assert!(
        got == want || got.contains(&want),
        "{ext}: extracted text does not match canonical.\n got: {got:?}\nwant: {want:?}"
    );
    println!("extraction-probe.{ext}: OK ({} chars)", got.chars().count());
}

#[test]
fn probe_docx_extracts_canonical() {
    assert_extracts_canonical("docx", InputFormat::Docx);
}

#[test]
fn probe_pdf_extracts_canonical() {
    assert_extracts_canonical("pdf", InputFormat::Pdf);
}

#[test]
fn probe_txt_extracts_canonical() {
    assert_extracts_canonical("txt", InputFormat::Txt);
}

#[test]
fn probe_md_extracts_canonical() {
    // FR-009 — the .md probe carries YAML frontmatter; md_extract strips it,
    // so the extracted body equals the canonical paragraph.
    assert_extracts_canonical("md", InputFormat::Md);
}

#[test]
fn probe_rtf_extracts_canonical() {
    assert_extracts_canonical("rtf", InputFormat::Rtf);
}

#[test]
fn probe_odt_extracts_canonical() {
    assert_extracts_canonical("odt", InputFormat::Odt);
}

/// FR-012a — `.pages` failure-mode: a malformed (zero-byte) `.pages` file
/// must surface `PagesParseError` (spec 009 FR-006), proving the
/// named-format-error path stays wired even though full `.pages` extraction
/// is deferred (Apple IWA proprietary).
#[test]
fn probe_pages_malformed_yields_pages_parse_error() {
    let dir = tempfile::TempDir::new().expect("tempdir");
    let pages = dir.path().join("broken.pages");
    std::fs::write(&pages, b"").expect("write zero-byte .pages");
    let result = extract_text(&pages, InputFormat::Pages);
    assert!(
        matches!(result, Err(ZoneFailure::PagesParseError)),
        "expected PagesParseError for malformed .pages, got {result:?}"
    );
}

/// FR-010 — the canonical text is non-trivial and contains the Swedish
/// characters that exercise UTF-8 round-tripping across formats.
#[test]
fn canonical_text_has_swedish_characters() {
    let t = CANONICAL_EXTRACTION_PROBE_TEXT;
    assert!(t.contains('å') && t.contains('ä') && t.contains('ö'));
    assert!(t.chars().count() > 150, "canonical paragraph too short");
}
