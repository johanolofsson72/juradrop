// JuraDrop core — spec 002-ollama-sidecar-poc.
//
// Spec 001 wired the window + close-quits-app. Spec 002 adds the bundled
// Ollama sidecar, the first-launch consent flow, and the dev-only round-trip
// command. See specs/002-ollama-sidecar-poc/plan.md.

use std::time::Duration;

use tauri::{Emitter, Manager, RunEvent, WindowEvent};

pub mod sidecar;

use sidecar::commands::{
    cancel_consent, get_status, give_consent, run_roundtrip_dev, spawn_pull_task, AppState,
};
use sidecar::consent;
use sidecar::status::{ConsentChoice, ModelStatus};

pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            get_status,
            give_consent,
            cancel_consent,
            run_roundtrip_dev,
        ])
        .setup(|app| {
            let state = AppState::new();
            app.manage(state.clone());

            // Boot the sidecar + initial status sync in a background task so
            // the WebView mounts quickly. The welcome card initially shows
            // "Startar AI..." (UserVisibleStatus::Startar) which matches the
            // initial NotStarted -> Starting transition.
            let app_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                // Load consent first so the modal-vs-no-modal decision is
                // ready by the time the sidecar reaches ready state.
                match consent::load(&app_handle).await {
                    Ok(record) => {
                        if let Some(state) = app_handle.try_state::<AppState>() {
                            *state.consent.write() = record;
                        }
                    }
                    Err(e) => {
                        eprintln!("[juradrop] consent load failed: {e}");
                    }
                }

                if let Some(state) = app_handle.try_state::<AppState>() {
                    if let Err(e) = state.sidecar.spawn(&app_handle).await {
                        eprintln!("[juradrop] sidecar spawn failed: {e}");
                        let _ = app_handle.emit("juradrop://status", state.snapshot());
                        return;
                    }
                    let _ = app_handle.emit("juradrop://status", state.snapshot());

                    match state.sidecar.wait_ready(Duration::from_secs(10)).await {
                        Ok(()) => {
                            // Sidecar ready — check model presence.
                            match state.client.list_tags().await {
                                Ok(tags) => {
                                    let present = tags.iter().any(|t| t == "gemma3:4b");
                                    *state.model_status.write() = if present {
                                        ModelStatus::Ready
                                    } else {
                                        ModelStatus::NotPresent
                                    };
                                    let _ = app_handle.emit("juradrop://status", state.snapshot());

                                    // FR-020: if the model is absent on launch and the user has
                                    // previously consented, re-trigger the pull idempotently.
                                    if !present
                                        && state.consent.read().choice == ConsentChoice::Fortsatt
                                    {
                                        *state.model_status.write() = ModelStatus::Downloading;
                                        *state.progress.write() = Some(0);
                                        let _ = app_handle
                                            .emit("juradrop://status", state.snapshot());
                                        spawn_pull_task(app_handle.clone(), state.inner().clone());
                                    }
                                }
                                Err(e) => {
                                    eprintln!("[juradrop] /api/tags failed: {e}");
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("[juradrop] sidecar wait_ready failed: {e}");
                            let _ = app_handle.emit("juradrop://status", state.snapshot());
                        }
                    }
                }
            });

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("failed to build JuraDrop tauri application");

    app.run(|app_handle, event| {
        if let RunEvent::WindowEvent {
            label,
            event: WindowEvent::CloseRequested { .. },
            ..
        } = event
        {
            if label == "main" {
                // Stop the sidecar synchronously before the process exits.
                if let Some(state) = app_handle.try_state::<AppState>() {
                    let sidecar = state.sidecar.clone();
                    tauri::async_runtime::block_on(async move {
                        let _ = sidecar.stop(Duration::from_secs(5)).await;
                    });
                }
                app_handle.exit(0);
            }
        }
    });
}

#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        assert_eq!(2 + 2, 4);
    }
}
