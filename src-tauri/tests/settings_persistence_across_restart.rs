// Spec 010 / T032a (per analyze C3 / SC-002) — settings persist
// across simulated app restarts. Round-trip alone covers serde
// symmetry; this test additionally drops the snapshot, reloads
// from disk, and asserts equality — matching the "100% of clean
// app restarts" promise.

use juradrop_lib::settings::file_io::{load_or_default, save};
use juradrop_lib::settings::snapshot::{SchemaVersion, SettingsSnapshot};
use juradrop_lib::settings::tier_map::ModelTier;

#[test]
fn each_tier_survives_simulated_restart() {
    for tier in ModelTier::ALL {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");

        // 1. Write via save() — same code path the set_model_tier
        //    command uses. The snapshot value is bound inside a
        //    block so it goes out of scope on block exit —
        //    simulating the process ending with no in-memory state.
        {
            let to_write = SettingsSnapshot {
                schema_version: SchemaVersion::V1,
                model_tier: tier,
            };
            save(&path, &to_write).unwrap();
        }

        // 2. Reload via load_or_default() — same code path
        //    init_settings_state uses on app boot.
        let restored = load_or_default(&path);

        // 3. Bit-equivalence guarantee.
        assert_eq!(
            restored,
            SettingsSnapshot {
                schema_version: SchemaVersion::V1,
                model_tier: tier
            },
            "{tier:?} did not survive simulated restart"
        );
    }
}

#[test]
fn missing_file_after_restart_yields_default_with_no_error() {
    // Fresh install scenario: no settings file exists yet on the
    // first launch.  The "restart" of a default-bearing snapshot
    // must equal the in-memory default.
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("settings.json");
    let restored = load_or_default(&path);
    assert_eq!(restored, SettingsSnapshot::default());
    assert_eq!(restored.model_tier, ModelTier::Smart);
}
