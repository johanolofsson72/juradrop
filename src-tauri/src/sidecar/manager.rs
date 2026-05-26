// Ollama sidecar lifecycle manager.
// Per spec 002 spec.allium OllamaSidecar entity + manager rules.

use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Weak};
use std::time::Duration;

use parking_lot::RwLock;
use tauri::{AppHandle, Emitter};
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

pub struct OllamaSidecar {
    status: RwLock<SidecarStatus>,
    child: RwLock<Option<CommandChild>>,
    retry_count: AtomicU8,
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
            self_weak: weak.clone(),
        })
    }

    pub fn status(&self) -> SidecarStatus {
        *self.status.read()
    }

    fn set_status(&self, s: SidecarStatus) {
        *self.status.write() = s;
    }

    pub async fn spawn(&self, app: &AppHandle) -> Result<(), SidecarError> {
        // Pre-flight port check.
        if Self::port_busy(11434) {
            self.set_status(SidecarStatus::Crashed);
            return Err(SidecarError::PortBusy);
        }
        self.set_status(SidecarStatus::Starting);

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
                    let was_stopping =
                        sidecar_arc.status() == SidecarStatus::Stopping;
                    if was_stopping {
                        sidecar_arc.set_status(SidecarStatus::Stopped);
                        let _ = app_for_emit
                            .emit("juradrop://sidecar-terminated", payload.code);
                    } else {
                        sidecar_arc.set_status(SidecarStatus::Crashed);
                        let _ = app_for_emit
                            .emit("juradrop://sidecar-terminated", payload.code);
                        // Retry signal — the lib.rs listener picks this up
                        // and decides whether to call spawn() again based
                        // on `retry_count`.
                        let _ = app_for_emit.emit(
                            "juradrop://sidecar-crashed",
                            payload.code,
                        );
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
        Err(SidecarError::StartupTimeout)
    }

    pub async fn stop(&self, _grace: Duration) -> Result<(), SidecarError> {
        self.set_status(SidecarStatus::Stopping);
        if let Some(child) = self.child.write().take() {
            child
                .kill()
                .map_err(|e| SidecarError::Plugin(e.to_string()))?;
        }
        self.set_status(SidecarStatus::Stopped);
        Ok(())
    }

    pub fn retry_count(&self) -> u8 {
        self.retry_count.load(Ordering::Relaxed)
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
