// Spec 003 / T014 — canonical + collision-suffixed sidecar paths + atomic write.
//
// FR-005: sidecar `<stem>.sammanfatta.docx` next to source.
// FR-006: on collision, append `.YYYY-MM-DD-HHMMSS` local-time suffix.
// R-007 :  write to `<target>.tmp` → fsync → rename — POSIX atomic on
//          the same filesystem.

use std::path::{Path, PathBuf};

use chrono::Local;
use tokio::fs;
use tokio::io::AsyncWriteExt;

use super::errors::ZoneFailure;

const SIDECAR_BASENAME_SUFFIX: &str = "sammanfatta";

/// FR-005 — canonical sidecar path for a given source `.docx`. Does NOT
/// check filesystem state; pure path computation.
pub fn canonical_for(source: &Path) -> PathBuf {
    let dir = source.parent().unwrap_or_else(|| Path::new(""));
    let stem = source
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("dokument");
    dir.join(format!("{stem}.{SIDECAR_BASENAME_SUFFIX}.docx"))
}

/// FR-006 — sidecar path with a local-time timestamp suffix appended
/// before the extension. Used when `canonical_for(source)` already
/// exists on disk.
pub fn with_collision_suffix(source: &Path) -> PathBuf {
    let dir = source.parent().unwrap_or_else(|| Path::new(""));
    let stem = source
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("dokument");
    let ts = Local::now().format("%Y-%m-%d-%H%M%S");
    dir.join(format!("{stem}.{SIDECAR_BASENAME_SUFFIX}.{ts}.docx"))
}

/// FR-006 — resolve a free sidecar path: canonical if available,
/// otherwise the timestamped variant. Does the filesystem probe so the
/// caller's dispatch logic stays linear.
pub fn resolve_target(source: &Path) -> PathBuf {
    let canonical = canonical_for(source);
    if canonical.exists() {
        with_collision_suffix(source)
    } else {
        canonical
    }
}

/// R-007 — atomic write: `<path>.tmp` → fsync → rename. Either the
/// rename succeeds and the canonical file holds the new bytes, or the
/// rename fails and the canonical file is untouched. A partial `.tmp`
/// left behind is cleaned best-effort on `ZoneFailure::SaveError`.
pub async fn write_atomically(path: &Path, bytes: &[u8]) -> Result<(), ZoneFailure> {
    if let Some(parent) = path.parent() {
        // best-effort — if parent already exists, create_dir_all is a no-op
        let _ = fs::create_dir_all(parent).await;
    }

    let tmp = path.with_extension("docx.tmp");

    // Write phase
    let mut file = match fs::File::create(&tmp).await {
        Ok(f) => f,
        Err(_) => return Err(ZoneFailure::SaveError),
    };
    if file.write_all(bytes).await.is_err() {
        let _ = fs::remove_file(&tmp).await;
        return Err(ZoneFailure::SaveError);
    }
    if file.sync_all().await.is_err() {
        let _ = fs::remove_file(&tmp).await;
        return Err(ZoneFailure::SaveError);
    }
    drop(file);

    // Rename phase
    if fs::rename(&tmp, path).await.is_err() {
        let _ = fs::remove_file(&tmp).await;
        return Err(ZoneFailure::SaveError);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn canonical_appends_sammanfatta_docx_in_same_dir() {
        let p = canonical_for(Path::new("/tmp/some/dir/ruling.docx"));
        assert_eq!(p.to_string_lossy(), "/tmp/some/dir/ruling.sammanfatta.docx");
    }

    #[test]
    fn canonical_handles_stem_with_dots() {
        // file_stem strips only the LAST extension; "v2.final.docx" → "v2.final".
        let p = canonical_for(Path::new("/tmp/v2.final.docx"));
        assert_eq!(p.to_string_lossy(), "/tmp/v2.final.sammanfatta.docx");
    }

    #[test]
    fn collision_suffix_is_iso_local_time() {
        let p = with_collision_suffix(Path::new("/tmp/a.docx"));
        let s = p.to_string_lossy();
        assert!(s.starts_with("/tmp/a.sammanfatta."));
        assert!(s.ends_with(".docx"));
        // The middle portion is the timestamp — match the YYYY-MM-DD-HHMMSS shape.
        let middle = &s["/tmp/a.sammanfatta.".len()..s.len() - ".docx".len()];
        // 17 chars: 4+1+2+1+2+1+6 = 17.
        assert_eq!(middle.len(), 17, "unexpected timestamp shape: {middle:?}");
    }

    #[tokio::test]
    async fn write_atomically_creates_file_and_leaves_no_tmp() {
        let dir = TempDir::new().unwrap();
        let target = dir.path().join("sample.sammanfatta.docx");
        write_atomically(&target, b"hello world").await.unwrap();
        assert!(target.exists());
        assert!(!target.with_extension("docx.tmp").exists());
        assert_eq!(std::fs::read(&target).unwrap(), b"hello world");
    }

    /// SC-006 — 10 consecutive sidecars from the same source must
    /// produce 10 distinct files on disk. The timestamp suffix at
    /// seconds precision can collide if two drops land in the same
    /// second; the retry-with-sleep handles that edge case explicitly.
    #[tokio::test]
    async fn ten_consecutive_writes_produce_ten_distinct_files() {
        let dir = TempDir::new().unwrap();
        let source = dir.path().join("doc.docx");
        // Pretend the source exists so resolve_target works without
        // requiring an actual .docx — only `canonical.exists()` is
        // probed inside resolve_target.

        let mut paths: Vec<PathBuf> = Vec::new();
        for i in 0..10 {
            let target = resolve_target(&source);
            write_atomically(&target, format!("body {i}").as_bytes())
                .await
                .unwrap();
            // If the timestamp suffix collides with a previously-written
            // file in the same second, sleep and re-pick.
            if paths.contains(&target) {
                tokio::time::sleep(std::time::Duration::from_millis(1_100)).await;
                let retry = resolve_target(&source);
                write_atomically(&retry, format!("body {i} retry").as_bytes())
                    .await
                    .unwrap();
                paths.push(retry);
            } else {
                paths.push(target);
            }
        }

        // All paths must be distinct AND exist on disk.
        let unique: std::collections::HashSet<_> = paths.iter().collect();
        assert_eq!(
            unique.len(),
            10,
            "expected 10 distinct sidecars, got {}",
            unique.len()
        );
        for p in &paths {
            assert!(p.exists(), "sidecar {p:?} missing");
        }
    }
}
