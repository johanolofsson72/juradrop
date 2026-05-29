// Spec 003 / T014 — canonical + collision-suffixed sidecar paths + atomic write.
//
// FR-005: sidecar `<stem>.sammanfatta.docx` next to source.
// FR-006: on collision, append `.YYYY-MM-DD-HHMMSS` local-time suffix.
// R-007 :  write to `<target>.tmp` → fsync → rename — POSIX atomic on
//          the same filesystem.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use chrono::Local;
use tokio::fs;
use tokio::io::AsyncWriteExt;

/// Spec 026 — monotonic counter so concurrent writes in the same directory
/// pick distinct temp names (combined with the pid).
static WRITE_TMP_COUNTER: AtomicU64 = AtomicU64::new(0);

use super::errors::ZoneFailure;
use super::output_format::OutputFormat;
use super::zone_id::ZoneId;

/// FR-005 + FR-007 — canonical sidecar path for a given source file
/// and ZoneId. The suffix is per-zone (`sammanfatta`, `tillengelska`,
/// `anonymiserad`, …) and the extension comes from the mirrored
/// OutputFormat (spec 005 FR-011). Pure path computation.
pub fn canonical_for_format(source: &Path, zone_id: ZoneId, ext: OutputFormat) -> PathBuf {
    let dir = source.parent().unwrap_or_else(|| Path::new(""));
    let stem = source
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("dokument");
    let suffix = zone_id.sidecar_suffix();
    dir.join(format!("{stem}.{suffix}.{ext}", ext = ext.as_str()))
}

/// Spec 003 compat shim — same as the spec-005 form with `OutputFormat::Docx`.
pub fn canonical_for(source: &Path, zone_id: ZoneId) -> PathBuf {
    canonical_for_format(source, zone_id, OutputFormat::Docx)
}

/// FR-006 — sidecar path with a local-time timestamp suffix appended
/// before the extension. Used when `canonical_for_format` already exists.
pub fn with_collision_suffix_format(source: &Path, zone_id: ZoneId, ext: OutputFormat) -> PathBuf {
    let dir = source.parent().unwrap_or_else(|| Path::new(""));
    let stem = source
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("dokument");
    let suffix = zone_id.sidecar_suffix();
    let ts = Local::now().format("%Y-%m-%d-%H%M%S");
    dir.join(format!("{stem}.{suffix}.{ts}.{ext}", ext = ext.as_str()))
}

/// Spec 003 compat shim — same as the spec-005 form with `OutputFormat::Docx`.
pub fn with_collision_suffix(source: &Path, zone_id: ZoneId) -> PathBuf {
    with_collision_suffix_format(source, zone_id, OutputFormat::Docx)
}

/// FR-006 — resolve a free per-zone sidecar path for a specific output
/// format: canonical if available, otherwise the timestamped variant.
pub fn resolve_target_format(source: &Path, zone_id: ZoneId, ext: OutputFormat) -> PathBuf {
    let canonical = canonical_for_format(source, zone_id, ext);
    if canonical.exists() {
        with_collision_suffix_format(source, zone_id, ext)
    } else {
        canonical
    }
}

/// Spec 003 compat shim — same as the spec-005 form with `OutputFormat::Docx`.
pub fn resolve_target(source: &Path, zone_id: ZoneId) -> PathBuf {
    resolve_target_format(source, zone_id, OutputFormat::Docx)
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

    // Spec 026 — write to a GENERIC hidden temp name in the same directory,
    // NOT `<final>.tmp`. A `<final>.tmp` sibling carries the output's
    // identifying suffix, so a directory scan for the result (a Finder
    // watcher, or the test harness globbing the zone suffix) can catch the
    // half-written temp and mistake it for the finished file — that is the
    // `.docx.tmp` flake. A neutral `.juradrop-write-<pid>-<n>.tmp` name can't
    // be confused with the output. Same directory → the rename stays
    // POSIX-atomic on one filesystem.
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let n = WRITE_TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    let tmp = parent.join(format!(".juradrop-write-{}-{n}.tmp", std::process::id()));

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

    // Rename phase — atomic replace of the final path.
    if fs::rename(&tmp, path).await.is_err() {
        let _ = fs::remove_file(&tmp).await;
        return Err(ZoneFailure::SaveError);
    }

    // Spec 026 — strip `com.apple.quarantine` so the auto-open (and any app
    // the user opens the result with) can read it. An unsigned/dev build
    // stamps files it writes with quarantine, which Word refuses to open with
    // a misleading "no access permission" error. Best-effort, no shell
    // (respects the sidecar capability sandbox).
    strip_quarantine(path);

    Ok(())
}

/// Spec 026 — remove the macOS quarantine xattr from a finished output file.
/// Best-effort: a missing attribute (ENOATTR) or any failure is ignored.
#[cfg(target_os = "macos")]
fn strip_quarantine(path: &Path) {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    if let (Ok(c_path), Ok(c_name)) = (
        CString::new(path.as_os_str().as_bytes()),
        CString::new("com.apple.quarantine"),
    ) {
        // SAFETY: both are valid NUL-terminated C strings live for the call;
        // removexattr does not retain them. Errors are intentionally ignored.
        unsafe {
            libc::removexattr(c_path.as_ptr(), c_name.as_ptr(), 0);
        }
    }
}

#[cfg(not(target_os = "macos"))]
fn strip_quarantine(_path: &Path) {}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn canonical_appends_sammanfatta_docx_in_same_dir() {
        let p = canonical_for(Path::new("/tmp/some/dir/ruling.docx"), ZoneId::Sammanfatta);
        assert_eq!(p.to_string_lossy(), "/tmp/some/dir/ruling.sammanfatta.docx");
    }

    #[test]
    fn canonical_handles_stem_with_dots() {
        // file_stem strips only the LAST extension; "v2.final.docx" → "v2.final".
        let p = canonical_for(Path::new("/tmp/v2.final.docx"), ZoneId::Sammanfatta);
        assert_eq!(p.to_string_lossy(), "/tmp/v2.final.sammanfatta.docx");
    }

    #[test]
    fn collision_suffix_is_iso_local_time() {
        let p = with_collision_suffix(Path::new("/tmp/a.docx"), ZoneId::Sammanfatta);
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
        // Spec 026 — NO temp file of any name may linger, and the temp must
        // not carry the output's suffix (so a dir scan for the result can't
        // catch it mid-write — the `.docx.tmp` flake).
        let leftovers: Vec<String> = std::fs::read_dir(dir.path())
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|n| n.ends_with(".tmp") || n.contains("sammanfatta.docx.tmp"))
            .collect();
        assert!(
            leftovers.is_empty(),
            "no .tmp file may remain: {leftovers:?}"
        );
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
            let target = resolve_target(&source, ZoneId::Sammanfatta);
            write_atomically(&target, format!("body {i}").as_bytes())
                .await
                .unwrap();
            // If the timestamp suffix collides with a previously-written
            // file in the same second, sleep and re-pick.
            if paths.contains(&target) {
                tokio::time::sleep(std::time::Duration::from_millis(1_100)).await;
                let retry = resolve_target(&source, ZoneId::Sammanfatta);
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
