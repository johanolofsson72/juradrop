// Spec 009 — cross-language drift test for the long-tail error
// strings (FR-013) and the no-path-leak invariant on the format-named
// Display impls (FR-017).
//
// This integration test is the Rust side of the long-tail drift
// contract. It loads `tests/fixtures/zone-error-strings.json` and
// asserts:
//   1. Each long-tail key exists in the fixture.
//   2. Each fixture value matches the corresponding `ZoneFailure`
//      variant's `Display` impl byte-for-byte.
//   3. The format-named Display values contain no `/`, no `\`, no `:`,
//      and no whitespace prefix — structurally impossible for any
//      `#[error("...")]` literal to have a leaked source path.
//   4. The updated `invalid_format` value lists all seven supported
//      extensions.
//
// Mirror test on the TS side lives in
// `src/__tests__/DropZone.longtail-formats.test.tsx`.

use juradrop_lib::zones::ZoneFailure;
use serde_json::Value;

const FIXTURE_PATH: &str = "tests/fixtures/zone-error-strings.json";

fn load_fixture() -> Value {
    let raw = std::fs::read_to_string(FIXTURE_PATH).expect("fixture present");
    serde_json::from_str(&raw).expect("fixture parses")
}

#[test]
fn long_tail_keys_present() {
    let fx = load_fixture();
    let obj = fx.as_object().expect("fixture is an object");
    for key in &["rtf_parse_error", "pages_parse_error", "odt_parse_error"] {
        assert!(
            obj.contains_key(*key),
            "fixture missing long-tail key {key:?}; spec 009 FR-013 requires it"
        );
    }
}

#[test]
fn rust_display_matches_fixture_for_long_tail() {
    let fx = load_fixture();
    let obj = fx.as_object().unwrap();
    let cases: &[(&str, ZoneFailure)] = &[
        ("rtf_parse_error", ZoneFailure::RtfParseError),
        ("pages_parse_error", ZoneFailure::PagesParseError),
        ("odt_parse_error", ZoneFailure::OdtParseError),
    ];
    for (key, variant) in cases {
        let fixture_value = obj
            .get(*key)
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("fixture missing string for {key}"));
        assert_eq!(
            variant.to_string(),
            fixture_value,
            "ZoneFailure::{variant:?} Display drifted from fixture[{key}]"
        );
    }
}

#[test]
fn no_format_named_error_leaks_path() {
    // FR-017 — the format-named errors must not include the source
    // file's name or path in their Display impl. Structurally
    // impossible for the literal `#[error("Kunde inte läsa .X-filen")]`
    // strings, but this test pins the contract so a future refactor
    // that adds `{file}` / `{path}` placeholders trips immediately.
    let variants = [
        ZoneFailure::RtfParseError,
        ZoneFailure::PagesParseError,
        ZoneFailure::OdtParseError,
    ];
    for v in variants {
        let s = v.to_string();
        assert!(
            !s.contains('/'),
            "ZoneFailure::{v:?} Display contains `/` — possible path leak: {s:?}"
        );
        assert!(
            !s.contains('\\'),
            "ZoneFailure::{v:?} Display contains backslash — possible path leak: {s:?}"
        );
        assert!(
            !s.contains(':'),
            "ZoneFailure::{v:?} Display contains `:` — possible path leak: {s:?}"
        );
        assert!(
            !s.starts_with(char::is_whitespace),
            "ZoneFailure::{v:?} Display has whitespace prefix: {s:?}"
        );
        assert!(
            s.starts_with("Kunde inte läsa ."),
            "ZoneFailure::{v:?} Display does not match the format-named pattern: {s:?}"
        );
        assert!(
            s.ends_with("-filen"),
            "ZoneFailure::{v:?} Display does not end with -filen: {s:?}"
        );
    }
}

#[test]
fn invalid_format_copy_lists_all_seven_formats() {
    let fx = load_fixture();
    let copy = fx["invalid_format"]
        .as_str()
        .expect("invalid_format is a string");
    for ext in &[".docx", ".pdf", ".txt", ".md", ".rtf", ".pages", ".odt"] {
        assert!(
            copy.contains(ext),
            "fixture invalid_format missing {ext}: {copy:?}"
        );
    }
    assert_eq!(
        copy, "Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt",
        "fixture invalid_format drifted from the spec 009 pinned copy"
    );
    assert!(
        copy.chars().count() <= 80,
        "fixture invalid_format > 80 chars: {} chars",
        copy.chars().count()
    );
}
