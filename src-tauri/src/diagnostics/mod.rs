// Spec 025 — opt-in local crash diagnostics.
//
// A consent-gated (default OFF), local-only, content-scrubbed diagnostics
// log the user can turn on in Settings and inspect. Content-safety is
// STRUCTURAL: `log_event` takes a `DiagnosticEvent` enum of fixed
// categories — there is no free-text/String parameter that could carry
// document content, prompts, model output, or file paths. The log is
// NEVER sent anywhere (Principle I — no network added by this module).
//
// Consent lives in this module's OWN file (`<dir>/consent.json`), NOT in
// SettingsSnapshot, so that struct keeps its test-enforced 2-field privacy
// invariant. A failed write silently no-ops — diagnostics must never crash
// or degrade the app.

pub mod commands;

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};

/// ~64 KB cap; the log is trimmed (oldest lines first) when it grows past.
pub const LOG_SIZE_CAP_BYTES: usize = 64 * 1024;

const CONSENT_FILE: &str = "consent.json";
const LOG_FILE: &str = "diagnostics.log";

/// Content-free event categories. NO variant carries free text or content.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiagnosticEvent {
    SidecarCrash,
    SidecarRestart {
        attempt: u8,
    },
    /// `category` is a closed-set ZoneFailure serde tag (e.g. `model_error`),
    /// never document content.
    ZoneFailureLogged {
        category: &'static str,
    },
}

impl DiagnosticEvent {
    /// The fixed, content-free token written to the log for this event.
    fn category_token(&self) -> String {
        match self {
            DiagnosticEvent::SidecarCrash => "sidecar_crash".to_string(),
            DiagnosticEvent::SidecarRestart { attempt } => {
                format!("sidecar_restart attempt={attempt}")
            }
            DiagnosticEvent::ZoneFailureLogged { category } => {
                format!("zone_failure category={category}")
            }
        }
    }
}

/// A diagnostics instance bound to a directory. Fully testable without the
/// process global (construct one with a tempdir).
pub struct Diagnostics {
    enabled: AtomicBool,
    dir: PathBuf,
    write_lock: Mutex<()>,
}

impl Diagnostics {
    /// Build for `dir`, loading any persisted consent (default OFF).
    pub fn new(dir: PathBuf) -> Self {
        let enabled = load_consent(&dir);
        Self {
            enabled: AtomicBool::new(enabled),
            dir,
            write_lock: Mutex::new(()),
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    pub fn log_path(&self) -> PathBuf {
        self.dir.join(LOG_FILE)
    }

    /// Set + persist consent. A persistence failure is reported but the
    /// in-memory flag is still updated (the user's choice takes effect this
    /// session even if the disk write fails).
    pub fn set_enabled(&self, value: bool) -> Result<(), String> {
        self.enabled.store(value, Ordering::Relaxed);
        persist_consent(&self.dir, value)
    }

    /// Append a content-free line IF enabled. No-op when disabled (default)
    /// or on any write error (FR-006 — never crash the app).
    pub fn log_event(&self, event: DiagnosticEvent) {
        if !self.enabled.load(Ordering::Relaxed) {
            return;
        }
        let _guard = self.write_lock.lock().unwrap_or_else(|e| e.into_inner());
        let _ = self.append_line(&event); // best-effort; errors swallowed
    }

    fn append_line(&self, event: &DiagnosticEvent) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.dir)?;
        let line = format!(
            "{} {} v{} {}\n",
            chrono::Utc::now().to_rfc3339(),
            event.category_token(),
            env!("CARGO_PKG_VERSION"),
            std::env::consts::OS,
        );
        let path = self.log_path();
        let mut existing = std::fs::read_to_string(&path).unwrap_or_default();
        existing.push_str(&line);
        if existing.len() > LOG_SIZE_CAP_BYTES {
            existing = trim_to_cap(&existing, LOG_SIZE_CAP_BYTES);
        }
        std::fs::write(&path, existing)
    }
}

/// Keep the most recent whole lines that fit under `cap` bytes.
fn trim_to_cap(content: &str, cap: usize) -> String {
    if content.len() <= cap {
        return content.to_string();
    }
    let mut start = content.len() - cap;
    // Advance to the next line boundary so we keep whole lines.
    if let Some(nl) = content[start..].find('\n') {
        start += nl + 1;
    }
    content[start..].to_string()
}

fn consent_path(dir: &Path) -> PathBuf {
    dir.join(CONSENT_FILE)
}

/// Load persisted consent. Missing / malformed → false (default OFF).
fn load_consent(dir: &Path) -> bool {
    let path = consent_path(dir);
    let Ok(text) = std::fs::read_to_string(&path) else {
        return false;
    };
    serde_json::from_str::<ConsentFile>(&text)
        .map(|c| c.enabled)
        .unwrap_or(false)
}

fn persist_consent(dir: &Path, enabled: bool) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("diagnostics dir: {e}"))?;
    let json = serde_json::to_string(&ConsentFile { enabled })
        .map_err(|e| format!("serialize consent: {e}"))?;
    std::fs::write(consent_path(dir), json).map_err(|e| format!("write consent: {e}"))
}

#[derive(serde::Serialize, serde::Deserialize)]
struct ConsentFile {
    enabled: bool,
}

// ---- Process-global wrapper (used by runtime call sites) ----

static DIAG: OnceLock<Diagnostics> = OnceLock::new();

/// Initialize the global diagnostics instance for `dir`. Call once at
/// startup. Subsequent calls are ignored.
pub fn init(dir: PathBuf) {
    let _ = DIAG.set(Diagnostics::new(dir));
}

pub fn is_enabled() -> bool {
    DIAG.get().map(Diagnostics::is_enabled).unwrap_or(false)
}

pub fn set_enabled(value: bool) -> Result<(), String> {
    DIAG.get()
        .ok_or_else(|| "diagnostics not initialized".to_string())?
        .set_enabled(value)
}

pub fn log_path() -> Option<PathBuf> {
    DIAG.get().map(Diagnostics::log_path)
}

/// Log an event via the global instance. No-op if uninitialized or disabled.
pub fn log_event(event: DiagnosticEvent) {
    if let Some(d) = DIAG.get() {
        d.log_event(event);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp() -> tempfile::TempDir {
        tempfile::TempDir::new().expect("tempdir")
    }

    #[test]
    fn disabled_by_default_writes_nothing() {
        let dir = tmp();
        let d = Diagnostics::new(dir.path().join("diag"));
        assert!(!d.is_enabled());
        d.log_event(DiagnosticEvent::SidecarCrash);
        assert!(!d.log_path().exists(), "no log file when disabled");
    }

    #[test]
    fn enabled_writes_content_free_line() {
        let dir = tmp();
        let d = Diagnostics::new(dir.path().join("diag"));
        d.set_enabled(true).unwrap();
        d.log_event(DiagnosticEvent::ZoneFailureLogged {
            category: "model_error",
        });
        let log = std::fs::read_to_string(d.log_path()).expect("log exists");
        assert!(log.contains("zone_failure category=model_error"));
        assert!(log.contains(&format!("v{}", env!("CARGO_PKG_VERSION"))));
        assert!(log.contains(std::env::consts::OS));
    }

    #[test]
    fn log_never_contains_document_content() {
        // Structural: the API can't even accept content. This asserts the
        // rendered lines only carry category tokens + metadata.
        let dir = tmp();
        let d = Diagnostics::new(dir.path().join("diag"));
        d.set_enabled(true).unwrap();
        d.log_event(DiagnosticEvent::SidecarCrash);
        d.log_event(DiagnosticEvent::SidecarRestart { attempt: 2 });
        d.log_event(DiagnosticEvent::ZoneFailureLogged {
            category: "parse_error",
        });
        let log = std::fs::read_to_string(d.log_path()).unwrap();
        // No path separators that would indicate a leaked user file path
        // (the app_data temp dir path is never written into the log lines).
        for line in log.lines() {
            assert!(
                !line.contains('/') || line.contains("category="),
                "log line looks like it leaked a path: {line}"
            );
        }
        assert!(log.contains("sidecar_crash"));
        assert!(log.contains("sidecar_restart attempt=2"));
    }

    #[test]
    fn consent_persists_and_reloads() {
        let dir = tmp();
        let p = dir.path().join("diag");
        {
            let d = Diagnostics::new(p.clone());
            d.set_enabled(true).unwrap();
        }
        // A fresh instance over the same dir loads the persisted consent.
        let d2 = Diagnostics::new(p);
        assert!(d2.is_enabled(), "consent must persist across instances");
    }

    #[test]
    fn size_cap_trims_oldest_lines() {
        let dir = tmp();
        let d = Diagnostics::new(dir.path().join("diag"));
        d.set_enabled(true).unwrap();
        for _ in 0..5000 {
            d.log_event(DiagnosticEvent::SidecarCrash);
        }
        let size = std::fs::metadata(d.log_path()).unwrap().len() as usize;
        assert!(
            size <= LOG_SIZE_CAP_BYTES,
            "log {size} exceeds cap {LOG_SIZE_CAP_BYTES}"
        );
    }

    #[test]
    fn failed_write_is_noop_not_panic() {
        // Point the dir at a path whose parent is a FILE, so create_dir_all
        // fails — log_event must swallow the error.
        let dir = tmp();
        let blocker = dir.path().join("blocker");
        std::fs::write(&blocker, b"x").unwrap();
        let d = Diagnostics::new(blocker.join("diag")); // parent is a file
        d.enabled.store(true, Ordering::Relaxed); // force-enable without persisting
        d.log_event(DiagnosticEvent::SidecarCrash); // must not panic
        assert!(!d.log_path().exists());
    }

    #[test]
    fn trim_keeps_whole_lines() {
        let content = "aaaa\nbbbb\ncccc\ndddd\n";
        let trimmed = trim_to_cap(content, 10);
        assert!(trimmed.len() <= 10);
        // Must start at a line boundary (no partial leading line).
        assert!(!trimmed.starts_with('a') || trimmed.starts_with("aaaa"));
        assert!(trimmed.ends_with('\n'));
    }
}
