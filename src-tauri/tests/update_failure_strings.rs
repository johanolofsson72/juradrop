// Spec 007 / T006 — cross-language drift assertion for the six
// Swedish UpdateFailure strings.

use juradrop_lib::updater::UpdateFailure;
use std::collections::HashMap;

#[test]
fn every_update_failure_string_matches_the_cross_language_fixture() {
    let manifest = env!("CARGO_MANIFEST_DIR");
    let fixture_path = std::path::Path::new(manifest)
        .join("tests")
        .join("fixtures")
        .join("update-failure-strings.json");
    let json = std::fs::read_to_string(&fixture_path)
        .expect("update-failure-strings.json fixture must exist");
    let fixture: HashMap<String, String> =
        serde_json::from_str(&json).expect("fixture must be valid JSON");

    let cases: &[(UpdateFailure, &str)] = &[
        (UpdateFailure::NoNetwork, "no_network"),
        (UpdateFailure::ManifestMalformed, "manifest_malformed"),
        (UpdateFailure::SignatureInvalid, "signature_invalid"),
        (UpdateFailure::DownloadInterrupted, "download_interrupted"),
        (UpdateFailure::InstallFailed, "install_failed"),
        (UpdateFailure::UnsupportedPlatform, "unsupported_platform"),
    ];

    for (variant, key) in cases {
        let rust_string = variant.to_string();
        let fixture_string = fixture
            .get(*key)
            .unwrap_or_else(|| panic!("fixture missing key {key:?}"));
        assert_eq!(
            &rust_string, fixture_string,
            "UpdateFailure::{variant:?} Display drift vs fixture[{key:?}]"
        );
    }

    // _comment + 6 variants = 7 keys.
    assert_eq!(
        fixture.len(),
        7,
        "fixture must list exactly 6 UpdateFailure variants + 1 _comment field"
    );
}
