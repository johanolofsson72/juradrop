// Spec 004 / T028 + T035 — parametric tests across all six ZoneId
// variants, plus the cross-language identity drift assertion.
//
// One file iterating `ZoneId::ALL` covers what would otherwise be six
// near-identical test files. Drift between Rust and TS is detected
// via the shared `tests/fixtures/zone-identity.json` fixture.

use juradrop_lib::zones::sammanfatta::DropZone;
use juradrop_lib::zones::ZoneId;

/// Every ZoneId variant must produce a non-empty slug and the slug
/// must match its serde wire form (no underscores in multi-word slugs).
#[test]
fn every_zone_has_a_well_formed_slug() {
    for z in ZoneId::ALL {
        let slug = z.slug();
        assert!(!slug.is_empty(), "{z:?} has empty slug");
        assert!(
            slug.chars().all(|c| c.is_ascii_lowercase()),
            "{z:?} slug not lowercase: {slug:?}"
        );
        assert!(
            !slug.contains('_'),
            "{z:?} slug contains underscore — filesystem-suffix-unfriendly: {slug:?}"
        );
        // The serde form must match the slug exactly.
        let json = serde_json::to_string(&z).unwrap();
        assert_eq!(json, format!("\"{slug}\""));
    }
}

/// Every ZoneId variant must produce a non-empty Swedish title and
/// hint, and the strings must respect the same Allium SwedishCopy
/// invariants spec 003 codified (≤ 80 chars, no "Error:" prefix).
#[test]
fn every_zone_has_well_formed_swedish_copy() {
    for z in ZoneId::ALL {
        for (name, value) in [
            ("title", z.title()),
            ("hint_copy", z.hint_copy()),
            ("processing_hint", z.processing_hint()),
        ] {
            assert!(!value.is_empty(), "{z:?} {name} is empty");
            let len = value.chars().count();
            assert!(
                len <= 80,
                "{z:?} {name} is {len} chars; the SwedishCopy invariant caps at 80"
            );
            assert!(
                !value.starts_with("Error:"),
                "{z:?} {name} has English Error: prefix"
            );
        }
    }
}

/// Every ZoneId variant must have a unique sidecar suffix so two
/// zones never collide on the canonical sidecar filename.
#[test]
fn every_zone_has_a_unique_sidecar_suffix() {
    let suffixes: Vec<&str> = ZoneId::ALL.iter().map(|z| z.sidecar_suffix()).collect();
    let unique: std::collections::HashSet<_> = suffixes.iter().collect();
    assert_eq!(
        unique.len(),
        ZoneId::ALL.len(),
        "sidecar suffix duplicates: {suffixes:?}"
    );
}

/// Every ZoneId variant must produce a non-empty system prompt with
/// the no-greeting guardrail.
#[test]
fn every_zone_has_a_non_empty_system_prompt_with_guardrail() {
    for z in ZoneId::ALL {
        let prompt = z.system_prompt();
        assert!(!prompt.is_empty(), "{z:?} has empty system prompt");
        let lower = prompt.to_lowercase();
        assert!(
            lower.contains("bara") || lower.contains("only"),
            "{z:?} prompt missing the no-greeting guardrail ({{bara|only}}): {prompt:?}"
        );
    }
}

/// Header paragraph templates must contain the literal `{name}`
/// token so the writer can substitute the source basename.
#[test]
fn every_zone_header_template_has_the_name_token() {
    for z in ZoneId::ALL {
        let tmpl = z.header_paragraph_template();
        assert!(
            tmpl.contains("{name}"),
            "{z:?} header template missing the {{name}} token: {tmpl:?}"
        );
    }
}

/// Anonymisera, Förenkla, and (spec 013) Generera produce a
/// disclaimer paragraph (FR-013 + FR-014 + spec 013 Generera).
/// The other six return None.
#[test]
fn only_anonymisera_forenkla_and_generera_have_disclaimers() {
    for z in ZoneId::ALL {
        let expected_some = matches!(
            z,
            ZoneId::Anonymisera | ZoneId::Forenkla | ZoneId::Generera
        );
        assert_eq!(
            z.has_disclaimer(),
            expected_some,
            "{z:?} disclaimer presence drifted from FR-013/014 (+ spec 013 generera)"
        );
    }
}

/// Constructing a DropZone for each ZoneId must succeed and yield
/// the matching id back.
#[test]
fn every_zone_can_be_constructed_and_reads_back_its_id() {
    for z in ZoneId::ALL {
        let zone = DropZone::new(z);
        assert_eq!(zone.id(), z, "DropZone::new(id) lost its id");
    }
}

/// T035 — cross-language identity drift assertion. The Rust
/// `ZoneId::associated()` functions must match the
/// `tests/fixtures/zone-identity.json` fixture byte-for-byte. The
/// TypeScript side asserts the same in
/// `src/__tests__/DropZone.identity.test.tsx`.
#[test]
fn every_zone_identity_matches_the_cross_language_fixture() {
    let manifest = env!("CARGO_MANIFEST_DIR");
    let fixture_path = std::path::Path::new(manifest)
        .join("tests")
        .join("fixtures")
        .join("zone-identity.json");
    let json =
        std::fs::read_to_string(&fixture_path).expect("zone-identity.json fixture must exist");
    let fixture: serde_json::Value =
        serde_json::from_str(&json).expect("fixture must be valid JSON");

    for z in ZoneId::ALL {
        let key = z.slug();
        let entry = fixture
            .get(key)
            .unwrap_or_else(|| panic!("fixture missing key {key:?}"));

        let expect_str = |field: &str, actual: &str| {
            let expected = entry
                .get(field)
                .and_then(|v| v.as_str())
                .unwrap_or_else(|| panic!("fixture {key}/{field} missing"));
            assert_eq!(
                actual, expected,
                "ZoneId::{z:?} {field} drift vs fixture[{key}]"
            );
        };
        expect_str("slug", z.slug());
        expect_str("title", z.title());
        expect_str("hint_copy", z.hint_copy());
        expect_str("sidecar_suffix", z.sidecar_suffix());
        expect_str("processing_hint", z.processing_hint());

        let expected_has_disclaimer = entry
            .get("has_disclaimer")
            .and_then(|v| v.as_bool())
            .unwrap_or_else(|| panic!("fixture {key}/has_disclaimer missing"));
        assert_eq!(
            z.has_disclaimer(),
            expected_has_disclaimer,
            "ZoneId::{z:?} has_disclaimer drift vs fixture[{key}]"
        );
    }

    // Also assert key count — adding a tenth ZoneId variant without a
    // fixture entry (or vice versa) fails here. Spec 013 expanded to 9.
    let obj = fixture.as_object().expect("fixture root must be object");
    // 9 variants + 1 _comment = 10 keys.
    assert_eq!(
        obj.len(),
        10,
        "fixture must list exactly 9 ZoneIdentity rows + 1 _comment"
    );
}
