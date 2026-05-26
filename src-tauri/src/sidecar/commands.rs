// Tauri command surface exposed to the WebView.
// Per spec 002 contracts/tauri-commands.md.

use std::sync::Arc;

use chrono::Utc;
use parking_lot::RwLock;
use tauri::{AppHandle, Emitter};

use super::client::OllamaClient;
use super::consent::{self, ConsentRecord};
use super::log_safe::Redacted;
use super::manager::OllamaSidecar;
use super::status::{AppStatus, ConsentChoice, ModelStatus, SidecarStatus};

#[derive(Clone)]
pub struct AppState {
    pub sidecar: Arc<OllamaSidecar>,
    pub client: Arc<OllamaClient>,
    pub model_status: Arc<RwLock<ModelStatus>>,
    pub progress: Arc<RwLock<Option<u8>>>,
    pub consent: Arc<RwLock<ConsentRecord>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            sidecar: Arc::new(OllamaSidecar::new()),
            client: Arc::new(OllamaClient::new()),
            model_status: Arc::new(RwLock::new(ModelStatus::NotPresent)),
            progress: Arc::new(RwLock::new(None)),
            consent: Arc::new(RwLock::new(ConsentRecord::default())),
        }
    }

    pub fn snapshot(&self) -> AppStatus {
        AppStatus::derive(
            self.sidecar.status(),
            *self.model_status.read(),
            *self.progress.read(),
            self.consent.read().choice,
        )
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

fn emit_status(app: &AppHandle, snapshot: &AppStatus) {
    let _ = app.emit("juradrop://status", snapshot);
}

#[tauri::command]
pub fn get_status(state: tauri::State<'_, AppState>) -> AppStatus {
    state.snapshot()
}

#[tauri::command]
pub async fn give_consent(app: AppHandle, state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut consent = state.consent.write().clone();
    consent.choice = ConsentChoice::Fortsatt;
    consent.asked_at = Some(Utc::now());
    consent.schema_version = 1;
    consent::save(&app, &consent)
        .await
        .map_err(|e| e.to_string())?;
    *state.consent.write() = consent;
    *state.model_status.write() = ModelStatus::Downloading;
    let snapshot = state.snapshot();
    emit_status(&app, &snapshot);
    // The actual pull stream is triggered by the lifecycle wiring in lib.rs;
    // this command persists consent + flips the model status so the welcome
    // card shows the progress placeholder immediately. The pull task is
    // spawned by the caller (lib.rs setup) when it observes the transition.
    Ok(())
}

#[tauri::command]
pub async fn cancel_consent(
    app: AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<(), String> {
    let mut consent = state.consent.write().clone();
    consent.choice = ConsentChoice::Avbryt;
    consent.asked_at = Some(Utc::now());
    consent.schema_version = 1;
    consent::save(&app, &consent)
        .await
        .map_err(|e| e.to_string())?;
    *state.consent.write() = consent;
    let snapshot = state.snapshot();
    emit_status(&app, &snapshot);
    Ok(())
}

#[tauri::command]
#[cfg(debug_assertions)]
pub async fn run_roundtrip_dev(state: tauri::State<'_, AppState>) -> Result<u64, String> {
    if state.sidecar.status() != SidecarStatus::Ready {
        return Err("sidecar not ready".into());
    }
    if *state.model_status.read() != ModelStatus::Ready {
        return Err("model not ready".into());
    }
    let prompt = Redacted::new(String::from("Säg hej."));
    let response = state
        .client
        .generate("gemma3:4b", prompt)
        .await
        .map_err(|e| e.to_string())?;
    Ok(response.len() as u64)
}

#[tauri::command]
#[cfg(not(debug_assertions))]
pub async fn run_roundtrip_dev(_state: tauri::State<'_, AppState>) -> Result<u64, String> {
    Err("not available in release build".into())
}
