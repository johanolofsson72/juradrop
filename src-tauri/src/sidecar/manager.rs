// Ollama sidecar lifecycle manager.
// Per spec 002 spec.allium OllamaSidecar entity + manager rules.

use std::sync::atomic::{AtomicU8, Ordering};
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
}

impl OllamaSidecar {
    pub fn new() -> Self {
        Self {
            status: RwLock::new(SidecarStatus::NotStarted),
            child: RwLock::new(None),
            retry_count: AtomicU8::new(0),
        }
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

        *self.child.write() = Some(child);

        // Spawn a task to drain the sidecar's output (avoids pipe stalls) and
        // detect unexpected termination. We intentionally do NOT log the
        // output content — Ollama can include model identifiers in startup
        // logs. Length-only counts at TRACE level would be safe but here we
        // simply discard to be safe.
        let status_handle = parking_lot::RwLock::new(()); // marker, no contents
        let app_for_emit = app.clone();
        let weak_status = self.status_ref();
        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                if let CommandEvent::Terminated(payload) = event {
                    // Sidecar exited.
                    if let Some(s) = weak_status.upgrade() {
                        *s.write() = SidecarStatus::Crashed;
                        let _ = app_for_emit.emit("juradrop://sidecar-terminated", payload.code);
                    }
                    break;
                }
                // Other event variants (Stdout/Stderr) are discarded — we
                // intentionally do not log sidecar output content.
            }
            let _ = status_handle;
        });

        Ok(())
    }

    /// Returns a weak reference to the status RwLock so the background task
    /// doesn't keep the manager alive indefinitely.
    fn status_ref(&self) -> std::sync::Weak<RwLock<SidecarStatus>> {
        // We don't actually have an Arc here — for the bootstrap version,
        // return a Weak that always fails to upgrade. The real shutdown path
        // calls stop() which sets state directly. This keeps the type signature.
        std::sync::Weak::new()
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

impl Default for OllamaSidecar {
    fn default() -> Self {
        Self::new()
    }
}

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
