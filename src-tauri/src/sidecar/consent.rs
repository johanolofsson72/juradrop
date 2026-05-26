// First-launch consent persistence.
// Per spec 002 FR-019 + contracts/consent-store.md + research.md R-006.

use std::io;
use std::path::PathBuf;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use tokio::fs;
use tokio::io::AsyncWriteExt;

use super::status::ConsentChoice;

const SCHEMA_VERSION: u8 = 1;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsentRecord {
    #[serde(rename = "schemaVersion")]
    pub schema_version: u8,
    pub choice: ConsentChoice,
    #[serde(rename = "askedAt", skip_serializing_if = "Option::is_none")]
    pub asked_at: Option<DateTime<Utc>>,
}

impl Default for ConsentRecord {
    fn default() -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            choice: ConsentChoice::NotAsked,
            asked_at: None,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConsentError {
    #[error("future schema version {0}; this build is too old to read it")]
    UnsupportedSchemaVersion(u8),
    #[error("io error: {0}")]
    Io(#[from] io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
}

fn consent_file_path(app: &AppHandle) -> Result<PathBuf, ConsentError> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| ConsentError::Io(io::Error::new(io::ErrorKind::NotFound, e.to_string())))?;
    Ok(dir.join("consent.json"))
}

pub async fn load(app: &AppHandle) -> Result<ConsentRecord, ConsentError> {
    let path = consent_file_path(app)?;
    let bytes = match fs::read(&path).await {
        Ok(b) => b,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(ConsentRecord::default()),
        Err(e) => return Err(ConsentError::Io(e)),
    };
    let record: ConsentRecord = serde_json::from_slice(&bytes)?;
    if record.schema_version > SCHEMA_VERSION {
        return Err(ConsentError::UnsupportedSchemaVersion(
            record.schema_version,
        ));
    }
    Ok(record)
}

pub async fn save(app: &AppHandle, record: &ConsentRecord) -> Result<(), ConsentError> {
    let path = consent_file_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).await?;
    }
    let tmp_path = path.with_extension("json.tmp");
    let json = serde_json::to_vec_pretty(record)?;
    let mut tmp = fs::File::create(&tmp_path).await?;
    tmp.write_all(&json).await?;
    tmp.sync_all().await?;
    drop(tmp);
    fs::rename(&tmp_path, &path).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_record_is_not_asked() {
        let r = ConsentRecord::default();
        assert_eq!(r.choice, ConsentChoice::NotAsked);
        assert_eq!(r.schema_version, SCHEMA_VERSION);
        assert!(r.asked_at.is_none());
    }

    #[test]
    fn serialize_round_trip() {
        let r = ConsentRecord {
            schema_version: 1,
            choice: ConsentChoice::Fortsatt,
            asked_at: Some(Utc::now()),
        };
        let json = serde_json::to_string(&r).unwrap();
        let parsed: ConsentRecord = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.choice, ConsentChoice::Fortsatt);
        assert_eq!(parsed.schema_version, 1);
    }

    #[test]
    fn future_schema_version_is_rejected() {
        let json = r#"{"schemaVersion":99,"choice":"fortsatt"}"#;
        let parsed: Result<ConsentRecord, _> = serde_json::from_str(json);
        let r = parsed.unwrap();
        assert_eq!(r.schema_version, 99);
    }
}
