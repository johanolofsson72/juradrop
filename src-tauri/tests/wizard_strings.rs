// Spec 008 / T004 — cross-language drift assertion + SwedishCopy invariants
// for the 12 wizard strings.

use std::collections::HashMap;
use std::path::Path;

fn load_fixture() -> HashMap<String, String> {
    let manifest = env!("CARGO_MANIFEST_DIR");
    let path = Path::new(manifest)
        .join("tests")
        .join("fixtures")
        .join("wizard-strings.json");
    let json = std::fs::read_to_string(&path).expect("wizard-strings.json fixture must exist");
    serde_json::from_str(&json).expect("fixture must be valid JSON")
}

/// Long-form welcome strings — capped at 200 chars (refined per
/// /speckit.analyze C1 finding 2026-05-28).
const LONG_FORM_KEYS: [&str; 2] = ["welcome_paragraph", "welcome_download_note"];

const ALL_KEYS: [&str; 12] = [
    "welcome_title",
    "welcome_paragraph",
    "welcome_privacy_line",
    "welcome_download_note",
    "welcome_cta_primary",
    "welcome_cta_secondary",
    "welcome_sidecar_helper",
    "progress_label_downloading",
    "progress_label_waiting",
    "progress_cancel_button",
    "progress_eta_unknown",
    "progress_error_retry",
];

#[test]
fn fixture_has_exactly_13_keys() {
    // 12 strings + 1 _comment.
    let f = load_fixture();
    assert_eq!(
        f.len(),
        13,
        "wizard-strings.json must have exactly 12 strings + _comment, got {}",
        f.len()
    );
    assert!(f.contains_key("_comment"));
    for key in ALL_KEYS {
        assert!(f.contains_key(key), "fixture missing key {key:?}");
    }
}

#[test]
fn every_string_is_non_empty() {
    let f = load_fixture();
    for key in ALL_KEYS {
        let s = f.get(key).unwrap();
        assert!(!s.is_empty(), "{key} is empty");
    }
}

#[test]
fn no_string_starts_with_english_error_prefix() {
    let f = load_fixture();
    for key in ALL_KEYS {
        let s = f.get(key).unwrap();
        assert!(
            !s.starts_with("Error:"),
            "{key} has English `Error:` prefix"
        );
    }
}

#[test]
fn long_form_strings_within_200_chars() {
    let f = load_fixture();
    for key in LONG_FORM_KEYS {
        let s = f.get(key).unwrap();
        let len = s.chars().count();
        assert!(len <= 200, "{key} is {len} chars; long-form cap is 200");
    }
}

#[test]
fn short_form_strings_within_80_chars() {
    let f = load_fixture();
    for key in ALL_KEYS {
        if LONG_FORM_KEYS.contains(&key) {
            continue;
        }
        let s = f.get(key).unwrap();
        let len = s.chars().count();
        assert!(len <= 80, "{key} is {len} chars; short-form cap is 80");
    }
}

#[test]
fn welcome_paragraph_names_all_six_zones() {
    // Clarification 1 — the welcome paragraph doubles as a feature
    // preview by naming each of the six zone verbs.
    let f = load_fixture();
    let para = f.get("welcome_paragraph").unwrap();
    for verb in [
        "sammanfatta",
        "översätta",
        "anonymisera",
        "punktlista",
        "förenkla",
    ] {
        assert!(
            para.to_lowercase().contains(verb),
            "welcome paragraph missing the verb {verb:?}"
        );
    }
}

#[test]
fn privacy_line_mentions_mac() {
    // FR-014 — privacy reassurance is meaningful only if it names the
    // user's machine. "Inget dokumentinnehåll lämnar din Mac." is the
    // canonical wording.
    let f = load_fixture();
    let s = f.get("welcome_privacy_line").unwrap();
    assert!(s.contains("Mac"));
    assert!(s.to_lowercase().contains("dokumentinnehåll"));
}
