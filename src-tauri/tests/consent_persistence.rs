// T035 — consent persistence integration test (spec 002 / US2 /
// FR-019 + FR-019b + research.md R-006).
//
// Drives `consent::save_at` and `consent::load_at` against a tempdir
// so the test never touches the real `~/Library/Application
// Support/se.noisycricket.juradrop/` path. The path-taking variants
// were added during this work specifically so the integration test
// could exercise the disk semantics without spinning up a Tauri app.
//
// The unit tests in `consent.rs` cover serde shape; this file covers
// the cross-FS semantics the unit tests can't reach:
//
//   - save → load round-trip preserves every field including the
//     UTC timestamp.
//   - the write goes via a `.json.tmp` staging file and the rename
//     leaves no `.tmp` lingering on success.
//   - a lingering `.tmp` (simulated mid-write crash) does NOT pollute
//     `load` — load sees only the canonical file.
//   - loading a record with `schemaVersion > 1` surfaces the typed
//     `ConsentError::UnsupportedSchemaVersion`, not a panic and not a
//     soft Default::default fallback.
//   - the missing-file case yields a `Default::default` record
//     (`ConsentChoice::NotAsked`) per the FR-019 first-launch contract.

use chrono::Utc;
use juradrop_lib::sidecar::consent::{load_at, save_at, ConsentError, ConsentRecord};
use juradrop_lib::sidecar::status::ConsentChoice;
use tempfile::TempDir;

#[tokio::test]
async fn save_then_load_round_trips_choice_and_timestamp() {
    let dir = TempDir::new().expect("tempdir");
    let path = dir.path().join("consent.json");

    let asked = Utc::now();
    let record = ConsentRecord {
        schema_version: 1,
        choice: ConsentChoice::Fortsatt,
        asked_at: Some(asked),
    };

    save_at(&path, &record).await.expect("save");
    let loaded = load_at(&path).await.expect("load");

    assert_eq!(loaded.choice, ConsentChoice::Fortsatt);
    assert_eq!(loaded.schema_version, 1);
    // Timestamp round-trips via chrono RFC3339 — re-compare via
    // formatted strings to avoid sub-microsecond drift across the
    // serde boundary on platforms that truncate.
    let original_ts = asked.to_rfc3339();
    let loaded_ts = loaded.asked_at.expect("asked_at").to_rfc3339();
    assert_eq!(loaded_ts, original_ts);
}

#[tokio::test]
async fn successful_save_leaves_no_tmp_file_behind() {
    let dir = TempDir::new().expect("tempdir");
    let path = dir.path().join("consent.json");
    let tmp_path = path.with_extension("json.tmp");

    let record = ConsentRecord {
        schema_version: 1,
        choice: ConsentChoice::Avbryt,
        asked_at: Some(Utc::now()),
    };
    save_at(&path, &record).await.expect("save");

    assert!(
        path.exists(),
        "canonical consent.json should exist after save"
    );
    assert!(
        !tmp_path.exists(),
        "consent.json.tmp must be renamed away on successful save (atomic-write invariant)"
    );
}

#[tokio::test]
async fn lingering_tmp_from_simulated_crash_does_not_pollute_load() {
    let dir = TempDir::new().expect("tempdir");
    let path = dir.path().join("consent.json");
    let tmp_path = path.with_extension("json.tmp");

    // Simulate a mid-write crash: a half-written record exists at
    // `.json.tmp` but the rename to `consent.json` never happened.
    let bogus = serde_json::json!({
        "schemaVersion": 1,
        "choice": "fortsatt",
    });
    tokio::fs::write(&tmp_path, serde_json::to_vec(&bogus).unwrap())
        .await
        .expect("write tmp");

    // `consent.json` itself doesn't exist yet. `load_at` must treat
    // that as a fresh-install (no record), NOT pick up the `.tmp`.
    let loaded = load_at(&path)
        .await
        .expect("load on missing canonical file");
    assert_eq!(
        loaded.choice,
        ConsentChoice::NotAsked,
        "load must ignore the .tmp staging file when the canonical file is absent"
    );
}

#[tokio::test]
async fn future_schema_version_surfaces_typed_error() {
    let dir = TempDir::new().expect("tempdir");
    let path = dir.path().join("consent.json");

    // Schema 99 — a future build wrote this; our schema-1 build must
    // refuse it (the alternative is misinterpreting fields and
    // making a privacy-critical decision on wrong data).
    let future_record = serde_json::json!({
        "schemaVersion": 99,
        "choice": "fortsatt",
    });
    tokio::fs::write(&path, serde_json::to_vec(&future_record).unwrap())
        .await
        .expect("write future record");

    let result = load_at(&path).await;
    match result {
        Err(ConsentError::UnsupportedSchemaVersion(v)) => assert_eq!(v, 99),
        other => panic!("expected Err(UnsupportedSchemaVersion(99)), got {other:?}"),
    }
}

#[tokio::test]
async fn missing_consent_file_yields_default_not_asked() {
    let dir = TempDir::new().expect("tempdir");
    let path = dir.path().join("consent.json"); // intentionally not created

    let loaded = load_at(&path).await.expect("load on absent file");
    assert_eq!(loaded.choice, ConsentChoice::NotAsked);
    assert_eq!(loaded.schema_version, 1);
    assert!(loaded.asked_at.is_none());
}
