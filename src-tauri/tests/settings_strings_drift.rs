// Spec 010 / T048 — cross-language drift test (Rust side).
//
// Asserts that every Swedish string the panel uses appears in the
// `settings-panel-strings.json` fixture AND matches the value the
// React layer reads. The TS counterpart lives in
// src/__tests__/settings-strings-drift.test.ts. Adding a string on
// one side without the other fails CI from both directions.
//
// The "Rust side" of this contract is the fixture itself — there is
// no Rust struct that needs to mirror the strings; the
// `get_app_version` command is the only Rust → TS data crossing for
// the panel, and version isn't a translated string.

use std::collections::BTreeMap;

#[test]
fn fixture_contains_exactly_the_expected_panel_keys() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("settings-panel-strings.json");
    let text = std::fs::read_to_string(&path).expect("fixture must exist");
    let parsed: BTreeMap<String, String> =
        serde_json::from_str(&text).expect("fixture must be JSON object of String→String");

    let expected: std::collections::BTreeSet<&str> = [
        "_comment",
        "gear_label",
        "panel_title",
        "close_label",
        "section_model_tier_title",
        "section_appearance_title",
        "section_about_title",
        "tier_snabb_label",
        "tier_smart_label",
        "tier_stor_label",
        "tier_snabb_helper",
        "tier_smart_helper",
        "tier_stor_helper",
        "tier_snabb_size",
        "tier_smart_size",
        "tier_stor_size",
        "tier_ladda_ned_button",
        "tier_not_downloaded_badge",
        "appearance_light",
        "appearance_dark",
        // Spec 026 — appearance picker option labels.
        "appearance_option_light",
        "appearance_option_dark",
        "appearance_option_system",
        "about_app_name",
        "about_license",
        "about_github_button",
        // Spec 025 — diagnostics opt-in section.
        "section_diagnostics_title",
        "diagnostics_toggle_label",
        "diagnostics_explanation",
        "diagnostics_path_label",
    ]
    .into_iter()
    .collect();

    let actual: std::collections::BTreeSet<&str> = parsed.keys().map(String::as_str).collect();

    let missing: Vec<_> = expected.difference(&actual).collect();
    let extra: Vec<_> = actual.difference(&expected).collect();

    assert!(missing.is_empty(), "fixture missing keys: {missing:?}",);
    assert!(extra.is_empty(), "fixture has unexpected keys: {extra:?}",);
}

#[test]
fn helper_sentences_within_80_char_cap() {
    // FR-011 + Clarification Q3 — each helper sentence ≤ 80 chars.
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("settings-panel-strings.json");
    let text = std::fs::read_to_string(&path).unwrap();
    let parsed: BTreeMap<String, String> = serde_json::from_str(&text).unwrap();
    for key in ["tier_snabb_helper", "tier_smart_helper", "tier_stor_helper"] {
        let v = parsed.get(key).unwrap_or_else(|| panic!("missing {key}"));
        assert!(
            v.chars().count() <= 80,
            "{key} = {v:?} is {}> chars (cap 80)",
            v.chars().count()
        );
    }
}

#[test]
fn helper_sentences_match_clarification_q3_pinned_values() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("settings-panel-strings.json");
    let text = std::fs::read_to_string(&path).unwrap();
    let parsed: BTreeMap<String, String> = serde_json::from_str(&text).unwrap();
    assert_eq!(
        parsed.get("tier_snabb_helper").map(String::as_str),
        Some("Snabbast och minst. Bra för korta texter.")
    );
    assert_eq!(
        parsed.get("tier_smart_helper").map(String::as_str),
        Some("Standardvalet. Bra balans mellan fart och kvalitet.")
    );
    assert_eq!(
        parsed.get("tier_stor_helper").map(String::as_str),
        Some("Bästa kvaliteten. Tar längre tid och mer plats på disken.")
    );
}
