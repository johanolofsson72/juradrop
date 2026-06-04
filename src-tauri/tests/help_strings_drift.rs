// Spec 013 FR-021 / FR-016a — cross-language drift (Rust ↔ JSON).
//
// Asserts the Rust ZONE_HELP_STRINGS const matches the
// zone-help-strings.json fixture byte-for-byte, for all 9 zones, both
// short + long. The TS side (help-strings-drift) asserts TS ↔ JSON, so
// the three stay locked together from both directions.

use std::collections::BTreeMap;

use juradrop_lib::help::zone_help;
use juradrop_lib::zones::ZoneId;

#[derive(serde::Deserialize)]
struct Entry {
    short: String,
    long: String,
}

fn load_fixture() -> BTreeMap<String, serde_json::Value> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/zone-help-strings.json");
    let text = std::fs::read_to_string(&path).expect("fixture must exist");
    serde_json::from_str(&text).expect("fixture is a JSON object")
}

#[test]
fn rust_const_matches_json_fixture_for_every_zone() {
    let fixture = load_fixture();
    for zone in ZoneId::ALL {
        let slug = zone.slug();
        let raw = fixture
            .get(slug)
            .unwrap_or_else(|| panic!("fixture missing entry for slug {slug:?}"));
        let entry: Entry =
            serde_json::from_value(raw.clone()).expect("entry has short+long strings");
        let rust = zone_help(zone);
        assert_eq!(
            rust.short, entry.short,
            "{zone:?} short drifted: Rust {:?} vs JSON {:?}",
            rust.short, entry.short
        );
        assert_eq!(
            rust.long, entry.long,
            "{zone:?} long drifted: Rust {:?} vs JSON {:?}",
            rust.long, entry.long
        );
    }
}

#[test]
fn fixture_has_exactly_the_twelve_zone_slugs_plus_comment() {
    let fixture = load_fixture();
    let mut keys: Vec<&str> = fixture
        .keys()
        .map(String::as_str)
        .filter(|k| !k.starts_with('_'))
        .collect();
    keys.sort();
    let mut expected: Vec<&str> = ZoneId::ALL.iter().map(|z| z.slug()).collect();
    expected.sort();
    assert_eq!(
        keys, expected,
        "fixture zone slugs drifted from ZoneId::ALL"
    );
}

// Spec 041 — the chrome-level instruction-field entry is underscore-
// prefixed (skipped by the per-zone iterations above) and pinned here
// explicitly: Rust consts ↔ JSON. The TS side pins TS ↔ JSON.
#[test]
fn instruction_help_matches_fixture() {
    let fixture = load_fixture();
    let raw = fixture
        .get("_instruction_help")
        .expect("fixture has _instruction_help (spec 041)");
    assert_eq!(
        raw.get("title").and_then(|v| v.as_str()),
        Some(zone_help::INSTRUCTION_HELP_TITLE),
        "instruction help title drifted (Rust vs JSON)"
    );
    assert_eq!(
        raw.get("body").and_then(|v| v.as_str()),
        Some(zone_help::INSTRUCTION_HELP_BODY),
        "instruction help body drifted (Rust vs JSON)"
    );
}

#[test]
fn budgets_hold_in_fixture() {
    let fixture = load_fixture();
    for (k, v) in &fixture {
        if k.starts_with('_') {
            continue;
        }
        let entry: Entry = serde_json::from_value(v.clone()).unwrap();
        assert!(entry.short.chars().count() <= 80, "{k} short over 80 chars");
        assert!(entry.long.chars().count() <= 300, "{k} long over 300 chars");
    }
}
