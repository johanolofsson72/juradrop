// Disk-space pre-check (F2/F3, T047, spec.allium `minimum_disk_free_gb: 4`).
//
// Calls `statvfs(2)` on the app data root to find the bytes available to the
// current user, then converts to GiB. The check is intentionally fail-open:
// if statvfs errors (path missing, permission denied, syscall fails) we
// return u64::MAX so the pull is NOT blocked on a measurement failure —
// Ollama's own disk-full surface still catches the real problem.

use std::ffi::CString;
use std::path::Path;

/// Sentinel returned when statvfs fails — interpreted as "plenty of space"
/// by the caller's `< MIN_FREE_GB` comparison (fail-open).
pub const UNKNOWN_OR_PLENTY: u64 = u64::MAX;

/// Returns the number of full GiB available to the current user at `path`,
/// or `UNKNOWN_OR_PLENTY` if the measurement couldn't be taken.
pub fn available_gb(path: &Path) -> u64 {
    let path_cstr = match CString::new(path.to_string_lossy().as_bytes()) {
        Ok(c) => c,
        Err(_) => return UNKNOWN_OR_PLENTY,
    };
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    let rc = unsafe { libc::statvfs(path_cstr.as_ptr(), &mut stat) };
    if rc != 0 {
        return UNKNOWN_OR_PLENTY;
    }
    let frsize: u64 = stat.f_frsize as u64;
    let bavail: u64 = stat.f_bavail as u64;
    let bytes = bavail.saturating_mul(frsize);
    bytes / (1024 * 1024 * 1024)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn root_path_returns_a_sensible_number() {
        // The CI machine should have at least 1 GiB free at "/" — sanity test.
        // If statvfs fails, UNKNOWN_OR_PLENTY (u64::MAX) is also acceptable.
        let v = available_gb(Path::new("/"));
        assert!(v > 0, "expected positive available_gb at /, got {v}");
    }

    #[test]
    fn nonexistent_path_fails_open() {
        // A path that doesn't exist should NOT block downloads — return the
        // sentinel so `< 4` comparisons treat it as "plenty".
        let v = available_gb(Path::new("/nonexistent/jura/drop/path"));
        assert_eq!(v, UNKNOWN_OR_PLENTY);
    }

    #[test]
    fn path_with_embedded_nul_fails_open() {
        // CString::new rejects strings with interior NUL bytes — verify we
        // don't panic, we just return the sentinel.
        let path = Path::new("/has\0null");
        let v = available_gb(path);
        assert_eq!(v, UNKNOWN_OR_PLENTY);
    }
}
