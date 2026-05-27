// JuraDrop core — spec 002-ollama-sidecar-poc.
//
// Spec 001 wired the window + close-quits-app. Spec 002 adds the bundled
// Ollama sidecar, the first-launch consent flow, and the dev-only round-trip
// command. See specs/002-ollama-sidecar-poc/plan.md.

use std::time::Duration;

use tauri::{DragDropEvent, Emitter, Listener, Manager, RunEvent, WindowEvent};

pub mod sidecar;
pub mod zones;

use sidecar::commands::{
    after_sidecar_ready, cancel_consent, cancel_summary, get_status, give_consent,
    run_roundtrip_dev, AppState,
};
use sidecar::consent;
use sidecar::status::{SidecarStatus, UserVisibleStatus};

pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            get_status,
            give_consent,
            cancel_consent,
            run_roundtrip_dev,
            cancel_summary,
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
                                    eprintln!("[juradrop] sidecar crashed; attempting one retry");
                                    if let Err(e) = state.sidecar.spawn(&app).await {
                                        eprintln!("[juradrop] retry spawn failed: {e}");
                                        *state.error_override.write() =
                                            Some(UserVisibleStatus::from(&e));
                                        let _ = app.emit("juradrop://status", state.snapshot());
                                    } else if let Err(e) =
                                        state.sidecar.wait_ready(Duration::from_secs(10)).await
                                    {
                                        eprintln!("[juradrop] retry wait_ready failed: {e}");
                                        *state.error_override.write() =
                                            Some(UserVisibleStatus::from(&e));
                                        let _ = app.emit("juradrop://status", state.snapshot());
                                    } else {
                                        // GAP-4: re-run the full post-ready
                                        // bootstrap (list_tags → model check →
                                        // pull if needed). Without this, a
                                        // crash mid-pull plus a successful
                                        // retry would leave the app stuck in
                                        // LaddarNerModell with no pull
                                        // actually running.
                                        after_sidecar_ready(app.clone(), state.inner().clone())
                                            .await;
                                    }
                                }
                            } else {
                                eprintln!("[juradrop] retry budget exhausted; holding Crashed");
                            }
                        }
                    });
                });

            // Spec 003 / T038 — reactive zone-disabled gate. The
            // SammanfattaZone borrows the global sidecar status to
            // decide whether to accept drops. When `juradrop://status`
            // arrives (sidecar transitions to Ready / back to non-Ready),
            // re-emit a `juradrop://sammanfatta` snapshot so the React
            // layer's zone slice tracks the gate even when the zone
            // itself hasn't done anything.
            let status_listener_handle = app.handle().clone();
            app.handle().listen("juradrop://status", move |_event| {
                let app = status_listener_handle.clone();
                if let Some(state) = app.try_state::<AppState>() {
                    let ready = matches!(state.sidecar.status(), SidecarStatus::Ready);
                    state.sammanfatta.refresh_disabled(&app, ready);
                }
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
                            after_sidecar_ready(app_handle.clone(), state.inner().clone()).await;
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
        // Spec 003 — drag-and-drop entry point. WindowEvent::DragDrop
        // is the OS-level, sandbox-safe path that carries the actual
        // file path (HTML5 drag-and-drop only gives sandboxed blobs).
        if let RunEvent::WindowEvent {
            event: WindowEvent::DragDrop(drag),
            ..
        } = &event
        {
            handle_drag_drop_event(app_handle, drag.clone());
        }

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

/// Spec 003 / T018 — translate Tauri's `DragDropEvent` into zone-snapshot
/// emits or the dispatch pipeline call. Runs on the synchronous event
/// thread; any async work is spun out via `tauri::async_runtime::spawn`.
fn handle_drag_drop_event(app: &tauri::AppHandle, drag: DragDropEvent) {
    use zones::snapshot::{ZoneSnapshot, ZoneState};

    let Some(state) = app.try_state::<AppState>() else {
        return;
    };
    let sidecar_ready = matches!(state.sidecar.status(), SidecarStatus::Ready);

    match drag {
        DragDropEvent::Enter { .. } => {
            let _ = app.emit(
                "juradrop://sammanfatta",
                ZoneSnapshot {
                    state: ZoneState::Dragover,
                    disabled: !sidecar_ready,
                    failure: None,
                    job_id: None,
                    progress_hint: None,
                },
            );
        }
        DragDropEvent::Leave => {
            // Drag left the window without dropping — return to idle.
            let _ = app.emit("juradrop://sammanfatta", ZoneSnapshot::idle(!sidecar_ready));
        }
        DragDropEvent::Drop { paths, .. } => {
            let zone = state.sammanfatta.clone();
            let client = state.client.clone();
            let app_clone = app.clone();
            tauri::async_runtime::spawn(async move {
                zone.handle_drop(app_clone, client, sidecar_ready, paths)
                    .await;
            });
        }
        // Mouse position updates over the zone — not load-bearing for the
        // state machine, ignore.
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        assert_eq!(2 + 2, 4);
    }

    // GAP-9: `CapabilityAllowlistMinimal` invariant — the Tauri capabilities
    // file must contain exactly the spec.allium permissions and NOTHING
    // ELSE. A future PR that adds `fs:allow-read` or `http:*` silently
    // broadens our surface and breaks Principle I; this test catches it
    // at PR time.
    #[test]
    fn capabilities_allowlist_is_minimal_per_spec() {
        let manifest = env!("CARGO_MANIFEST_DIR");
        let path = std::path::Path::new(manifest).join("capabilities/default.json");
        let json = std::fs::read_to_string(&path).expect("capabilities/default.json must exist");
        let cap: serde_json::Value =
            serde_json::from_str(&json).expect("capabilities/default.json must be valid JSON");

        let perms = cap
            .get("permissions")
            .and_then(|v| v.as_array())
            .expect("permissions array missing");

        // String permissions, sorted for deterministic comparison.
        let mut string_perms: Vec<&str> = perms.iter().filter_map(|v| v.as_str()).collect();
        string_perms.sort();

        // Exactly these four core permissions — nothing more, nothing less.
        assert_eq!(
            string_perms,
            vec![
                "core:app:default",
                "core:default",
                "core:event:default",
                "shell:allow-kill",
            ],
            "capabilities allowlist drifted from spec.allium CapabilityAllowlistMinimal"
        );

        // Plus exactly one scoped object permission: shell:allow-spawn
        // limited to the bundled ollama binary. No other scoped permissions
        // are allowed.
        let object_perms: Vec<&serde_json::Value> =
            perms.iter().filter(|v| v.is_object()).collect();
        assert_eq!(
            object_perms.len(),
            1,
            "expected exactly one scoped permission (shell:allow-spawn for ollama)"
        );
        let spawn = object_perms[0];
        assert_eq!(
            spawn.get("identifier").and_then(|v| v.as_str()),
            Some("shell:allow-spawn"),
            "scoped permission must be shell:allow-spawn"
        );
        let allow = spawn
            .get("allow")
            .and_then(|v| v.as_array())
            .expect("shell:allow-spawn must have an allow array");
        assert_eq!(
            allow.len(),
            1,
            "shell:allow-spawn allow list must be a single entry (ollama only)"
        );
        let entry = &allow[0];
        assert_eq!(
            entry.get("name").and_then(|v| v.as_str()),
            Some("binaries/ollama"),
            "only the bundled ollama sidecar may be spawned"
        );
        assert_eq!(
            entry.get("sidecar").and_then(|v| v.as_bool()),
            Some(true),
            "ollama must be configured as a sidecar (not an arbitrary command)"
        );
    }
}
