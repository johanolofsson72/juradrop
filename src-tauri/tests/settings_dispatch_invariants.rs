// Spec 010 / T034 — invariants about the snapshot-aware dispatch
// path. These cover what unit tests in `settings/tier_map.rs` and
// `settings/snapshot.rs` cannot: the contract that the Rust dispatch
// reads the CURRENT snapshot at the moment of dispatch, and that
// in-flight runs are immune to tier switches that fire mid-flight.
//
// We cannot drive `dispatch_to_zone` end-to-end without a real Tauri
// AppState (which needs a Tauri mock app + wiremock — same reason
// the lifecycle tests are marked `#[ignore]`). What we CAN do is
// assert the contract at the SettingsState boundary: the value
// returned by `active_model_id()` matches `TierMappingLookup` of the
// snapshot's tier, and mutating the snapshot AFTER capturing
// active_model_id() does NOT change the captured string.

use juradrop_lib::settings::snapshot::{SchemaVersion, SettingsSnapshot, SettingsState};
use juradrop_lib::settings::tier_map::ModelTier;

#[test]
fn active_model_id_matches_snapshot_tier_at_call_time() {
    for tier in ModelTier::ALL {
        let state = SettingsState::new(SettingsSnapshot {
            schema_version: SchemaVersion::V1,
            model_tier: tier,
        });
        assert_eq!(state.active_model_id(), tier.model_id());
    }
}

#[test]
fn dispatch_capture_is_immune_to_subsequent_tier_switch() {
    // Mimics the dispatch_to_zone code path: read active_model_id()
    // INSIDE the dispatch, then mutate the snapshot from another
    // "caller". The captured string must not change — strings are
    // 'static, the snapshot is behind a RwLock; once captured the
    // dispatch task holds its own copy.
    let state = SettingsState::new(SettingsSnapshot {
        schema_version: SchemaVersion::V1,
        model_tier: ModelTier::Smart,
    });
    let captured: &'static str = state.active_model_id();
    assert_eq!(captured, "gemma3:4b");

    // Mutate the snapshot — simulates a tier switch via set_model_tier.
    {
        let mut w = state.inner.write();
        w.model_tier = ModelTier::Stor;
    }

    // The dispatcher's captured pointer is unchanged.
    assert_eq!(captured, "gemma3:4b");
    // But a fresh read sees the new tier (the NEXT dispatch boundary).
    assert_eq!(state.active_model_id(), "gemma3:12b");
}

#[test]
fn snapshot_roundtrip_preserves_dispatch_lookup() {
    // FR-008 + FR-009 — a tier persisted via the file_io path and
    // restored on launch produces the same active_model_id().
    for tier in ModelTier::ALL {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        let to_save = SettingsSnapshot {
            schema_version: SchemaVersion::V1,
            model_tier: tier,
        };
        juradrop_lib::settings::file_io::save(&path, &to_save).unwrap();

        let restored = juradrop_lib::settings::file_io::load_or_default(&path);
        let state = SettingsState::new(restored);
        assert_eq!(state.active_model_id(), tier.model_id());
    }
}
