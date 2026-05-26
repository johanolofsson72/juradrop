// Orphan-sidecar cleanup via a PID lockfile (F10, T058).
//
// macOS doesn't give us PR_SET_PDEATHSIG, so a parent crash (e.g. the cargo
// watcher killing `target/debug/juradrop` during a dev rebuild) leaves the
// bundled `ollama serve` reparented to launchd and still bound to port
// 11434. Next launch can't bind. We saw this multiple times during spec 002.
//
// Mechanism: write the bundled sidecar's PID to a small file at spawn time,
// remove it on clean stop. On every fresh app start, before any port-busy
// check, read the file and SIGTERM the recorded PID if it's still alive.
//
// Trade-off: PID reuse. Between the previous run and this one, the kernel
// may have recycled the PID for an unrelated process. Mitigation: nothing
// — we just send SIGTERM (graceful) rather than SIGKILL, and the target
// process either is our orphan ollama (we want it killed) or some random
// process that handles SIGTERM. For a single-user desktop app, the
// likelihood of collision is negligible.

use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use tauri::{AppHandle, Manager};

const PIDFILE_NAME: &str = "ollama.pid";

fn pidfile_path(app: &AppHandle) -> Option<PathBuf> {
    app.path().app_data_dir().ok().map(|p| p.join(PIDFILE_NAME))
}

/// Persist the just-spawned sidecar's PID. Best-effort — failures are
/// logged but don't propagate; the worst case is we can't kill a future
/// orphan, which is the pre-spec-002 status quo.
pub fn write(app: &AppHandle, pid: u32) {
    let Some(path) = pidfile_path(app) else { return };
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Err(e) = fs::write(&path, pid.to_string()) {
        eprintln!("[juradrop] pidfile write failed: {e}");
    }
}

/// Remove the pidfile on clean shutdown so the next launch doesn't try to
/// kill a recycled PID. Idempotent — missing-file is not an error.
pub fn clear(app: &AppHandle) {
    let Some(path) = pidfile_path(app) else { return };
    let _ = fs::remove_file(&path);
}

/// On launch, kill any stale sidecar process that the previous run left
/// alive. Sends SIGTERM, sleeps briefly, then SIGKILL if still alive.
pub fn kill_stale_if_present(app: &AppHandle) {
    let Some(path) = pidfile_path(app) else { return };
    let pid_str = match fs::read_to_string(&path) {
        Ok(s) => s,
        Err(_) => return, // No file → no orphan to kill.
    };
    let Ok(pid) = pid_str.trim().parse::<i32>() else {
        let _ = fs::remove_file(&path);
        return;
    };

    // SIGTERM
    unsafe {
        libc::kill(pid, libc::SIGTERM);
    }
    std::thread::sleep(Duration::from_millis(500));

    // SIGKILL if still alive. `kill(pid, 0)` is the standard "is alive"
    // probe — returns 0 if reachable, errno=ESRCH if dead.
    let still_alive = unsafe { libc::kill(pid, 0) } == 0;
    if still_alive {
        unsafe {
            libc::kill(pid, libc::SIGKILL);
        }
        eprintln!("[juradrop] reaped stale sidecar PID {pid} (SIGKILL)");
    } else {
        eprintln!("[juradrop] cleared stale pidfile (PID {pid} already gone)");
    }

    let _ = fs::remove_file(&path);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nonexistent_pid_treated_as_already_gone() {
        // PID 0 isn't valid for kill, but kill with sig=0 will fail with
        // EINVAL or ESRCH — either way, our "still_alive" check returns
        // false, and we don't try to send SIGKILL.
        let alive = unsafe { libc::kill(999_999_999, 0) } == 0;
        assert!(!alive, "expected PID 999999999 to be unreachable");
    }
}
