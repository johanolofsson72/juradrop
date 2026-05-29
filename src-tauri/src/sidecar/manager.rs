// Ollama sidecar lifecycle manager.
// Per spec 002 spec.allium OllamaSidecar entity + manager rules.

use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Weak};
use std::time::Duration;

use parking_lot::RwLock;
use tauri::{AppHandle, Emitter, Runtime};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;
use tokio::time::sleep;

use super::status::SidecarStatus;

#[derive(Debug, thiserror::Error)]
pub enum SidecarError {
    #[error("bundled binary missing or non-executable")]
    BundledBinaryMissing,
    #[error("port 11434 is busy")]
    PortBusy,
    #[error("sidecar did not become ready within timeout")]
    StartupTimeout,
    #[error("sidecar exited unexpectedly: {0:?}")]
    Crashed(Option<i32>),
    #[error("shell plugin error: {0}")]
    Plugin(String),
}

/// Spec 026 — did we start the AI, or are we reusing one the user already
/// had running on the loopback port? Decides shutdown behavior (never kill
/// what we did not start) and underpins the single readiness truth.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Ownership {
    None,
    ReusedExternal,
    WeStarted,
}

pub struct OllamaSidecar {
    status: RwLock<SidecarStatus>,
    child: RwLock<Option<CommandChild>>,
    retry_count: AtomicU8,
    /// Spec 026 — ownership of the AI process we are using.
    ownership: RwLock<Ownership>,
    /// F4 / T045: weak self-reference so the drain background task can
    /// re-spawn on first crash without holding a strong cycle.
    self_weak: Weak<Self>,
}

impl OllamaSidecar {
    pub fn new() -> Arc<Self> {
        Arc::new_cyclic(|weak| Self {
            status: RwLock::new(SidecarStatus::NotStarted),
            child: RwLock::new(None),
            retry_count: AtomicU8::new(0),
            ownership: RwLock::new(Ownership::None),
            self_weak: weak.clone(),
        })
    }

    pub fn status(&self) -> SidecarStatus {
        *self.status.read()
    }

    fn set_status(&self, s: SidecarStatus) {
        *self.status.write() = s;
    }

    /// Spec 026 — who started the AI we are using.
    pub fn ownership(&self) -> Ownership {
        *self.ownership.read()
    }

    /// Spec 026 — is a usable Ollama ALREADY serving on the loopback port
    /// (the user started their own, or one was left running)? Loopback-only
    /// (Principle I/III); reuses the same `/api/tags` 2xx signal `wait_ready`
    /// trusts. 2xx ⇒ reuse; anything else ⇒ not a usable external Ollama.
    pub async fn external_ollama_reachable(&self) -> bool {
        let Ok(client) = reqwest::Client::builder()
            .timeout(Duration::from_secs(2))
            .build()
        else {
            return false;
        };
        matches!(
            client
                .get("http://127.0.0.1:11434/api/tags")
                .send()
                .await
                .map(|r| r.status().is_success()),
            Ok(true)
        )
    }

    /// Spec 026 — adopt an already-running external Ollama: mark Ready WITHOUT
    /// spawning a bundled process that could not bind the busy port (and would
    /// die, clobbering readiness). `ownership = ReusedExternal` so shutdown
    /// never kills a process we did not start.
    pub fn mark_reused_ready(&self) {
        self.set_status(SidecarStatus::Ready);
        *self.ownership.write() = Ownership::ReusedExternal;
    }

    pub async fn spawn<R: Runtime>(&self, app: &AppHandle<R>) -> Result<(), SidecarError> {
        // Pre-flight port check.
        if Self::port_busy(11434) {
            self.set_status(SidecarStatus::Crashed);
            return Err(SidecarError::PortBusy);
        }
        self.set_status(SidecarStatus::Starting);
        // Spec 026 — we are starting the bundled process ourselves; we own it
        // and MUST stop it on shutdown.
        *self.ownership.write() = Ownership::WeStarted;

        let shell = app.shell();
        let cmd = shell
            .sidecar("ollama")
            .map_err(|e| {
                self.set_status(SidecarStatus::Crashed);
                SidecarError::Plugin(format!("sidecar lookup failed: {e}"))
            })?
            .args(["serve"])
            .env("OLLAMA_HOST", "127.0.0.1:11434")
            .env("OLLAMA_ORIGINS", "");

        let (mut rx, child) = cmd.spawn().map_err(|e| {
            self.set_status(SidecarStatus::Crashed);
            // Heuristic: a sidecar-missing error from shell typically surfaces here.
            let msg = e.to_string();
            if msg.contains("No such file") || msg.contains("not found") {
                SidecarError::BundledBinaryMissing
            } else {
                SidecarError::Plugin(msg)
            }
        })?;

        // F10 / T058 — record the child PID before stashing the handle so
        // the next launch can reap it if the parent dies before stop()
        // runs (e.g. cargo-watcher SIGTERM during dev rebuilds).
        super::pidfile::write(app, child.pid());

        *self.child.write() = Some(child);

        // Spawn a task to drain the sidecar's output (avoids pipe stalls) and
        // detect unexpected termination. We intentionally do NOT log the
        // output content — Ollama can include model identifiers in startup
        // logs.
        //
        // The drain task does NOT itself attempt retry (T045): calling
        // `sidecar.spawn()` from inside this Send-required task hits a Send
        // constraint on the spawn future. Instead, we emit
        // `juradrop://sidecar-crashed` and let a listener registered from
        // lib.rs::setup handle the retry — that call site has the exact
        // same pattern as the initial bootstrap call and is known to compile.
        let app_for_emit = app.clone();
        let self_weak = self.self_weak.clone();
        tauri::async_runtime::spawn(async move {
            while let Some(event) = rx.recv().await {
                if let CommandEvent::Terminated(payload) = event {
                    let Some(sidecar_arc) = self_weak.upgrade() else {
                        break; // Manager dropped — nothing to do.
                    };

                    // Distinguish orderly shutdown from a crash: if the manager
                    // had already entered Stopping, the exit is expected.
                    let was_stopping = sidecar_arc.status() == SidecarStatus::Stopping;
                    if was_stopping {
                        sidecar_arc.set_status(SidecarStatus::Stopped);
                        let _ = app_for_emit.emit("juradrop://sidecar-terminated", payload.code);
                    } else {
                        sidecar_arc.set_status(SidecarStatus::Crashed);
                        let _ = app_for_emit.emit("juradrop://sidecar-terminated", payload.code);
                        // Retry signal — the lib.rs listener picks this up
                        // and decides whether to call spawn() again based
                        // on `retry_count`.
                        let _ = app_for_emit.emit("juradrop://sidecar-crashed", payload.code);
                    }
                    break;
                }
                // Other event variants (Stdout/Stderr) are discarded — we
                // intentionally do not log sidecar output content.
            }
        });

        Ok(())
    }

    /// Returns the current retry counter without incrementing — for the
    /// lib.rs listener to gate at-most-one retry. The listener calls
    /// `increment_retry()` to actually consume one retry attempt.
    pub fn retry_count_value(&self) -> u8 {
        self.retry_count.load(Ordering::Relaxed)
    }

    /// Poll /api/tags until 2xx or timeout.
    pub async fn wait_ready(&self, timeout: Duration) -> Result<(), SidecarError> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(2))
            .build()
            .map_err(|e| SidecarError::Plugin(e.to_string()))?;
        let deadline = std::time::Instant::now() + timeout;
        while std::time::Instant::now() < deadline {
            if let Ok(resp) = client.get("http://127.0.0.1:11434/api/tags").send().await {
                if resp.status().is_success() {
                    self.set_status(SidecarStatus::Ready);
                    return Ok(());
                }
            }
            sleep(Duration::from_millis(200)).await;
        }
        self.set_status(SidecarStatus::Crashed);
        // GAP-2: kill the spawned child instead of leaking it. A child that's
        // slow to come up but eventually does would otherwise hold port 11434
        // for the rest of the session while the app sat in Crashed.
        if let Some(child) = self.child.write().take() {
            if let Err(e) = child.kill() {
                eprintln!("[juradrop] failed to kill timed-out sidecar: {e}");
            }
        }
        Err(SidecarError::StartupTimeout)
    }

    /// Graceful shutdown: SIGTERM first, poll for exit up to `grace`, then
    /// SIGKILL via the Tauri-owned child handle as a fallback. Ollama serve
    /// traps SIGTERM and shuts down cleanly (closes connections, releases
    /// the port) — SIGKILL alone leaves nothing on disk corrupted but skips
    /// any in-flight cleanup the runtime might want to do.
    pub async fn stop(&self, grace: Duration) -> Result<(), SidecarError> {
        self.set_status(SidecarStatus::Stopping);
        let Some(child) = self.child.write().take() else {
            // Nothing to stop — already gone (or never spawned). Idempotent.
            self.set_status(SidecarStatus::Stopped);
            return Ok(());
        };

        let pid = child.pid() as i32;

        // Phase 1 — SIGTERM. Best-effort: if delivery fails (e.g. the
        // process already exited between `take()` and now), the liveness
        // poll below will see that and return Ok immediately.
        unsafe {
            libc::kill(pid, libc::SIGTERM);
        }

        // Phase 2 — poll liveness. `kill(pid, 0)` is the POSIX "is it
        // alive?" probe; ESRCH (process gone) flips it to non-zero.
        let deadline = std::time::Instant::now() + grace;
        while std::time::Instant::now() < deadline {
            let alive = unsafe { libc::kill(pid, 0) } == 0;
            if !alive {
                self.set_status(SidecarStatus::Stopped);
                return Ok(());
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }

        // Phase 3 — fallback SIGKILL via the Tauri child handle. Reached
        // only when SIGTERM was either ignored or the process hung past
        // `grace`. Consumes `child`; the drain task's `rx` keeps receiving
        // until the kernel reports termination.
        child
            .kill()
            .map_err(|e| SidecarError::Plugin(e.to_string()))?;
        self.set_status(SidecarStatus::Stopped);
        Ok(())
    }

    pub fn retry_count(&self) -> u8 {
        self.retry_count.load(Ordering::Relaxed)
    }

    /// Returns the currently-spawned child's PID, or `None` if the
    /// sidecar isn't running. Used by integration tests to verify the
    /// process exits after `stop()` (T069 / SC-003); not load-bearing
    /// for production code paths.
    pub fn pid(&self) -> Option<u32> {
        self.child.read().as_ref().map(|c| c.pid())
    }

    pub fn increment_retry(&self) -> u8 {
        self.retry_count.fetch_add(1, Ordering::Relaxed) + 1
    }

    fn port_busy(port: u16) -> bool {
        std::net::TcpListener::bind(("127.0.0.1", port)).is_err()
    }
}

// No `Default` impl — `OllamaSidecar::new()` returns `Arc<Self>` (cyclic-weak
// pattern for the drain task), and the `Default` trait can't return `Arc<Self>`.

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_status_is_not_started() {
        let s = OllamaSidecar::new();
        assert_eq!(s.status(), SidecarStatus::NotStarted);
    }

    #[test]
    fn retry_counter_increments() {
        let s = OllamaSidecar::new();
        assert_eq!(s.retry_count(), 0);
        assert_eq!(s.increment_retry(), 1);
        assert_eq!(s.increment_retry(), 2);
    }
}
