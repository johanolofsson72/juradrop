// Spec 035 — panic-site ratchet (production code only; tests exempt via cfg_attr).
#![cfg_attr(
    not(test),
    deny(clippy::unwrap_used, clippy::expect_used, clippy::panic)
)]

// Spec 025 — Tauri commands for the diagnostics opt-in toggle.
//
// `get_diagnostics_status` returns the current consent + the local log
// path (shown in Settings so the user can inspect the file).
// `set_diagnostics_enabled` flips + persists the consent. Neither command
// touches document content or adds any outbound surface.

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct DiagnosticsStatus {
    pub enabled: bool,
    /// The local log path, shown to the user. `None` before init.
    pub log_path: Option<String>,
}

#[tauri::command]
pub async fn get_diagnostics_status() -> DiagnosticsStatus {
    DiagnosticsStatus {
        enabled: super::is_enabled(),
        log_path: super::log_path().map(|p| p.to_string_lossy().to_string()),
    }
}

#[tauri::command]
pub async fn set_diagnostics_enabled(enabled: bool) -> Result<DiagnosticsStatus, String> {
    super::set_enabled(enabled)?;
    Ok(DiagnosticsStatus {
        enabled: super::is_enabled(),
        log_path: super::log_path().map(|p| p.to_string_lossy().to_string()),
    })
}
