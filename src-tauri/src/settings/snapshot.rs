// Spec 010 / T008-T009 — in-memory snapshot of the user's persisted
// preferences. Mirrors the on-disk JSON (see contracts/settings-file-schema.md).
//
// Tauri's managed state wraps a `RwLock<SettingsSnapshot>`; the
// dispatch path reads under a read lock at every dispatch, the
// `set_model_tier` command takes a write lock + persists to disk
// inside the same critical section.
//
// Privacy invariant: this struct has EXACTLY two fields. Adding a
// third is a Principle I review. See settings_invariants.rs.

use serde::{Deserialize, Serialize};

use super::tier_map::ModelTier;

/// Forward-compat sentinel. Current spec is V1. A future schema
/// migration bumps this; today, any other integer is treated as
/// malformed and triggers the load-default fallback.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(into = "u32", try_from = "u32")]
pub enum SchemaVersion {
    V1,
}

impl From<SchemaVersion> for u32 {
    fn from(v: SchemaVersion) -> Self {
        match v {
            SchemaVersion::V1 => 1,
        }
    }
}

impl TryFrom<u32> for SchemaVersion {
    type Error = String;
    fn try_from(value: u32) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(SchemaVersion::V1),
            other => Err(format!("unknown schema_version {other}")),
        }
    }
}

/// On-disk + in-memory shape. EXACTLY two fields. See
/// contracts/settings-file-schema.md § Strict schema.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SettingsSnapshot {
    pub schema_version: SchemaVersion,
    pub model_tier: ModelTier,
}

impl Default for SettingsSnapshot {
    fn default() -> Self {
        Self {
            schema_version: SchemaVersion::V1,
            model_tier: ModelTier::default(),
        }
    }
}

/// Tauri-managed state container. The dispatcher reads under a read
/// lock; `set_model_tier` takes a write lock + persists to disk
/// inside the critical section. `parking_lot::RwLock` matches the
/// pattern used by `AppState` in `sidecar/commands.rs`.
pub struct SettingsState {
    pub inner: parking_lot::RwLock<SettingsSnapshot>,
}

impl SettingsState {
    pub fn new(initial: SettingsSnapshot) -> Self {
        Self {
            inner: parking_lot::RwLock::new(initial),
        }
    }

    pub fn snapshot(&self) -> SettingsSnapshot {
        self.inner.read().clone()
    }

    /// Convenience: read the active model_id for the dispatch path.
    pub fn active_model_id(&self) -> &'static str {
        self.inner.read().model_tier.model_id()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_snapshot_is_v1_smart() {
        let s = SettingsSnapshot::default();
        assert_eq!(s.schema_version, SchemaVersion::V1);
        assert_eq!(s.model_tier, ModelTier::Smart);
    }

    #[test]
    fn schema_version_serialises_as_integer() {
        let s = SettingsSnapshot::default();
        let json = serde_json::to_string(&s).unwrap();
        assert!(
            json.contains(r#""schema_version":1"#),
            "schema_version must serialise as integer 1, got: {json}"
        );
    }

    #[test]
    fn unknown_schema_version_rejected_at_deserialise() {
        let json = r#"{"schema_version":2,"model_tier":"Smart"}"#;
        let result: Result<SettingsSnapshot, _> = serde_json::from_str(json);
        assert!(result.is_err(), "schema_version=2 must fail to deserialise");
    }

    #[test]
    fn unknown_model_tier_rejected_at_deserialise() {
        let json = r#"{"schema_version":1,"model_tier":"Mega"}"#;
        let result: Result<SettingsSnapshot, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "unknown model_tier must fail to deserialise"
        );
    }

    #[test]
    fn round_trip_all_three_tiers() {
        for tier in ModelTier::ALL {
            let s = SettingsSnapshot {
                schema_version: SchemaVersion::V1,
                model_tier: tier,
            };
            let json = serde_json::to_string(&s).unwrap();
            let back: SettingsSnapshot = serde_json::from_str(&json).unwrap();
            assert_eq!(back, s, "round-trip mismatch for {tier:?}");
        }
    }
}
