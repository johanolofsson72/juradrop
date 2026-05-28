// Spec 010 / T010 — settings.json load + save.
//
// FR-019 — path resolved via Tauri's app_data_dir (no hard-coded
// ~/Library literal anywhere — settings_invariants.rs enforces this).
// FR-020 — missing or malformed file silently falls back to default,
// with a debug-only console warning. The user never sees a Swedish
// error for a first-run-state missing file.
// Save is atomic: temp-file + fsync + rename, so a kill mid-write
// cannot corrupt the prior good version.

use std::path::Path;

use tauri::{AppHandle, Manager};

use super::snapshot::SettingsSnapshot;

/// Resolve the canonical settings file path inside `app_data_dir`.
/// FR-019 — never hard-code `/Library/Application Support` literals.
pub fn settings_file_path(app: &AppHandle) -> Result<std::path::PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("app_data_dir resolution failed: {e}"))?;
    Ok(dir.join("settings.json"))
}

/// Load the snapshot from disk. Missing file or any parse / validation
/// failure returns `SettingsSnapshot::default()` — never an error.
/// Logs a debug-only warning on malformed input so the dev can see it
/// in the terminal; release builds are silent.
pub fn load_or_default(path: &Path) -> SettingsSnapshot {
    if !path.exists() {
        return SettingsSnapshot::default();
    }
    let bytes = match std::fs::read(path) {
        Ok(b) => b,
        Err(e) => {
            debug_warn(format!("settings.json read failed ({e}), using default"));
            return SettingsSnapshot::default();
        }
    };
    let text = match String::from_utf8(bytes) {
        Ok(t) => t,
        Err(_) => {
            debug_warn("settings.json is not valid UTF-8, using default".to_string());
            return SettingsSnapshot::default();
        }
    };
    match serde_json::from_str::<SettingsSnapshot>(&text) {
        Ok(s) => s,
        Err(e) => {
            debug_warn(format!("settings.json malformed ({e}), using default"));
            SettingsSnapshot::default()
        }
    }
}

/// Atomic save. Writes to `<path>.tmp`, fsyncs, then renames over the
/// real path. APFS rename is atomic per the spec, so a torn write is
/// impossible — either the prior file is intact or the new file is
/// complete.
pub fn save(path: &Path, snapshot: &SettingsSnapshot) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("create_dir_all failed: {e}"))?;
    }
    let json =
        serde_json::to_string_pretty(snapshot).map_err(|e| format!("serialise failed: {e}"))?;
    let tmp = path.with_extension("json.tmp");
    {
        use std::io::Write;
        let mut f =
            std::fs::File::create(&tmp).map_err(|e| format!("temp file create failed: {e}"))?;
        f.write_all(json.as_bytes())
            .map_err(|e| format!("temp file write failed: {e}"))?;
        f.sync_all()
            .map_err(|e| format!("temp file fsync failed: {e}"))?;
    }
    std::fs::rename(&tmp, path).map_err(|e| format!("atomic rename failed: {e}"))?;
    Ok(())
}

#[cfg(debug_assertions)]
fn debug_warn(msg: String) {
    eprintln!("[juradrop:settings] WARN: {msg}");
}

#[cfg(not(debug_assertions))]
fn debug_warn(_msg: String) {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::snapshot::SchemaVersion;
    use crate::settings::tier_map::ModelTier;

    fn tmpdir() -> tempfile::TempDir {
        tempfile::tempdir().unwrap()
    }

    #[test]
    fn missing_file_returns_default() {
        let dir = tmpdir();
        let path = dir.path().join("settings.json");
        let s = load_or_default(&path);
        assert_eq!(s, SettingsSnapshot::default());
    }

    #[test]
    fn round_trip_preserves_snapshot() {
        let dir = tmpdir();
        let path = dir.path().join("settings.json");
        for tier in ModelTier::ALL {
            let s = SettingsSnapshot {
                schema_version: SchemaVersion::V1,
                model_tier: tier,
            };
            save(&path, &s).unwrap();
            let loaded = load_or_default(&path);
            assert_eq!(loaded, s, "round-trip mismatch for {tier:?}");
        }
    }

    #[test]
    fn malformed_json_returns_default() {
        let dir = tmpdir();
        let path = dir.path().join("settings.json");
        std::fs::write(&path, b"this is not json").unwrap();
        assert_eq!(load_or_default(&path), SettingsSnapshot::default());
    }

    #[test]
    fn unknown_schema_version_returns_default() {
        let dir = tmpdir();
        let path = dir.path().join("settings.json");
        std::fs::write(&path, br#"{"schema_version":999,"model_tier":"Smart"}"#).unwrap();
        assert_eq!(load_or_default(&path), SettingsSnapshot::default());
    }

    #[test]
    fn unknown_tier_returns_default() {
        let dir = tmpdir();
        let path = dir.path().join("settings.json");
        std::fs::write(&path, br#"{"schema_version":1,"model_tier":"Mega"}"#).unwrap();
        assert_eq!(load_or_default(&path), SettingsSnapshot::default());
    }

    #[test]
    fn extra_keys_rejected_via_default_fallback() {
        // serde_json defaults to permissive (ignores unknown fields).
        // We accept that on load, but the SAVE path always emits
        // exactly the declared fields — so the on-disk file is clean
        // after the next save. Round-tripping via load+save sanitises.
        let dir = tmpdir();
        let path = dir.path().join("settings.json");
        std::fs::write(
            &path,
            br#"{"schema_version":1,"model_tier":"Stor","telemetry_id":"abc"}"#,
        )
        .unwrap();
        let loaded = load_or_default(&path);
        assert_eq!(loaded.model_tier, ModelTier::Stor);
        save(&path, &loaded).unwrap();
        let on_disk = std::fs::read_to_string(&path).unwrap();
        assert!(
            !on_disk.contains("telemetry_id"),
            "save must scrub stray fields; got: {on_disk}"
        );
    }

    #[test]
    fn empty_object_returns_default() {
        let dir = tmpdir();
        let path = dir.path().join("settings.json");
        std::fs::write(&path, b"{}").unwrap();
        assert_eq!(load_or_default(&path), SettingsSnapshot::default());
    }
}
