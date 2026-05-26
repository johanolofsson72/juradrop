// JuraDrop core — spec 002-ollama-sidecar-poc.
//
// Spec 001 wired the window + close-quits-app. Spec 002 adds the bundled
// Ollama sidecar, the first-launch consent flow, and the dev-only round-trip
// command. See specs/002-ollama-sidecar-poc/plan.md.

use std::time::Duration;

use tauri::{Emitter, Listener, Manager, RunEvent, WindowEvent};

pub mod sidecar;

use sidecar::commands::{
    cancel_consent, get_status, give_consent, has_sufficient_disk_for_pull, run_roundtrip_dev,
    spawn_pull_task, AppState,
};
use sidecar::consent;
use sidecar::status::{ConsentChoice, ModelStatus, UserVisibleStatus};

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

            // T045 / F4 — SidecarOneRetry. The drain task in manager.rs emits
            // `juradrop://sidecar-crashed` on unexpected exit; this listener
            // attempts exactly one re-spawn on the first crash. Subsequent
            // crashes hold `FelOvantat` until next launch. Reusing the same
            // `state.sidecar.spawn(&app).await` call pattern as the initial
            // bootstrap below — that pattern is already Send-clean here.
            let listener_handle = app.handle().clone();
            app.handle()
                .listen("juradrop://sidecar-crashed", move |_event| {
                    let app = listener_handle.clone();
                    tauri::async_runtime::spawn(async move {
                        if let Some(state) = app.try_state::<AppState>() {
                            if state.sidecar.retry_count_value() == 0 {
                                let prev = state.sidecar.increment_retry();
                                if prev == 1 {
                                    eprintln!(
                                        "[juradrop] sidecar crashed; attempting one retry"
                                    );
                                    if let Err(e) =
                                        state.sidecar.spawn(&app).await
                                    {
                                        eprintln!(
                                            "[juradrop] retry spawn failed: {e}"
                                        );
                                        *state.error_override.write() =
                                            Some(UserVisibleStatus::from(&e));
                                        let _ = app.emit(
                                            "juradrop://status",
                                            state.snapshot(),
                                        );
                                    } else if let Err(e) = state
                                        .sidecar
                                        .wait_ready(Duration::from_secs(10))
                                        .await
                                    {
                                        eprintln!(
                                            "[juradrop] retry wait_ready failed: {e}"
                                        );
                                        *state.error_override.write() =
                                            Some(UserVisibleStatus::from(&e));
                                        let _ = app.emit(
                                            "juradrop://status",
                                            state.snapshot(),
                                        );
                                    } else {
                                        let _ = app.emit(
                                            "juradrop://status",
                                            state.snapshot(),
                                        );
                                    }
                                }
                            } else {
                                eprintln!(
                                    "[juradrop] retry budget exhausted; holding Crashed"
                                );
                            }
                        }
                    });
                });

            // Boot the sidecar + initial status sync in a background task so
            // the WebView mounts quickly. The welcome card initially shows
            // "Startar AI..." (UserVisibleStatus::Startar) which matches the
            // initial NotStarted -> Starting transition.
            let app_handle = app.handle().clone();

            // F10 / T058 — reap any orphan sidecar from a previous run that
            // didn't get a chance to clean up (cargo-watcher SIGTERM, kill -9,
            // OS-level force-quit). Runs synchronously before the spawn task
            // so the port-busy check below has a clear field.
            sidecar::pidfile::kill_stale_if_present(&app_handle);

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
                        *state.error_override.write() = Some(UserVisibleStatus::from(&e));
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
                                    // previously consented, re-trigger the pull idempotently —
                                    // unless we don't have the disk to honour it (F2/F3).
                                    if !present
                                        && state.consent.read().choice == ConsentChoice::Fortsatt
                                    {
                                        if !has_sufficient_disk_for_pull(&app_handle) {
                                            *state.error_override.write() =
                                                Some(UserVisibleStatus::FelDiskFull);
                                            let _ = app_handle
                                                .emit("juradrop://status", state.snapshot());
                                        } else {
                                            *state.model_status.write() =
                                                ModelStatus::Downloading;
                                            *state.progress.write() = Some(0);
                                            let _ = app_handle
                                                .emit("juradrop://status", state.snapshot());
                                            spawn_pull_task(
                                                app_handle.clone(),
                                                state.inner().clone(),
                                            );
                                        }
                                    }
                                }
                                Err(e) => {
                                    eprintln!("[juradrop] /api/tags failed: {e}");
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("[juradrop] sidecar wait_ready failed: {e}");
                            *state.error_override.write() = Some(UserVisibleStatus::from(&e));
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
                // Stop the sidecar synchronously before the process exits,
                // then clear the pidfile so the next launch doesn't try to
                // reap a now-dead PID.
                if let Some(state) = app_handle.try_state::<AppState>() {
                    let sidecar = state.sidecar.clone();
                    tauri::async_runtime::block_on(async move {
                        let _ = sidecar.stop(Duration::from_secs(5)).await;
                    });
                }
                sidecar::pidfile::clear(app_handle);
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
