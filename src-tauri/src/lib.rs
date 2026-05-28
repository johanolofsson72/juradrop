// JuraDrop core — spec 002-ollama-sidecar-poc.
//
// Spec 001 wired the window + close-quits-app. Spec 002 adds the bundled
// Ollama sidecar, the first-launch consent flow, and the dev-only round-trip
// command. See specs/002-ollama-sidecar-poc/plan.md.

use std::time::Duration;

use tauri::{DragDropEvent, Emitter, Listener, Manager, RunEvent, WindowEvent};

pub mod prompts;
pub mod settings;
pub mod sidecar;
pub mod updater;
pub mod zones;

use settings::commands::{
    get_app_version, get_settings, get_tier_pull_state, init_settings_state, set_model_tier,
    trigger_tier_download,
};
use sidecar::commands::{
    after_sidecar_ready, cancel_consent, cancel_model_pull, cancel_summary, dispatch_to_zone,
    get_status, give_consent, run_roundtrip_dev, AppState,
};
use sidecar::consent;
use sidecar::status::{SidecarStatus, UserVisibleStatus};
use updater::commands::{
    cancel_deferred_restart, check_for_updates_now, confirm_restart_install,
    dismiss_update_indicator, install_update_now,
};

pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        // Spec 006 — auto-updater plugin. Reads its endpoint + pubkey
        // from tauri.conf.json's plugins.updater block. Verifies the
        // .sig signature against the embedded pubkey before installing
        // any downloaded update (FR-015).
        .plugin(tauri_plugin_updater::Builder::new().build())
        .invoke_handler(tauri::generate_handler![
            get_status,
            give_consent,
            cancel_consent,
            run_roundtrip_dev,
            cancel_summary,
            dispatch_to_zone,
            // Spec 007 — auto-updater commands.
            check_for_updates_now,
            install_update_now,
            confirm_restart_install,
            cancel_deferred_restart,
            dismiss_update_indicator,
            // Spec 008 — first-run-wizard Cancel-button command.
            cancel_model_pull,
            // Spec 010 — settings panel.
            get_settings,
            set_model_tier,
            get_tier_pull_state,
            trigger_tier_download,
            get_app_version,
        ])
        .setup(|app| {
            let state = AppState::new();
            app.manage(state.clone());

            // Spec 010 / T002 — load persisted settings + manage state.
            // Done BEFORE the sidecar bootstrap so the dispatch path can
            // read the active tier from frame zero.
            init_settings_state(app.handle());

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
                    // Spec 004 — fan out to all six zones so the disabled
                    // gate flips in lock-step (FR-012 + DisabledGateAppliesToAllZones).
                    for zone in state.zones.values() {
                        zone.refresh_disabled(&app, ready);
                    }
                }
            });

            // Spec 007 / GAP-A — DeferredRestartAutoFires actuator.
            // Every per-zone channel emits a fresh snapshot on every
            // state-machine transition; we listen on all six and ask
            // the updater to fire a deferred restart if (a) consent is
            // parked and (b) no zone is processing. The check is cheap
            // and idempotent, so we don't try to filter for "transitions
            // to idle" specifically — every snapshot is a re-check.
            // Spec 013 — iterate over ZoneId::ALL instead of a hardcoded
            // 6-slug array so future zone-set expansions are picked up
            // automatically (e.g., the 9 zones from spec 013).
            for zone in zones::ZoneId::ALL {
                let channel = format!("juradrop://zone/{}", zone.slug());
                let deferred_handle = app.handle().clone();
                app.handle().listen(&channel, move |_event| {
                    let app = deferred_handle.clone();
                    if let Some(state) = app.try_state::<AppState>() {
                        if let Some(bytes) =
                            updater::deferral::try_fire_deferred_restart(&app, &state)
                        {
                            // We've transitioned ReadyToInstall → Restarting.
                            // The install() call may take time + exits the
                            // process on success; do it in an async task so
                            // the listener returns immediately.
                            let install_app = app.clone();
                            tauri::async_runtime::spawn(async move {
                                updater::commands::run_deferred_install(&install_app, bytes).await;
                            });
                        }
                    }
                });
            }

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

            // Spec 007 / T018-T019 — spawn the 4-hour background tick.
            // First fire is `LAUNCH_CHECK_DELAY` (5s) after app boot;
            // subsequent fires every 4 hours. The cancellation token
            // lives on the Updater entity; we abort on app shutdown via
            // its `cancel()`.
            let tick_handle = app.handle().clone();
            let tick_cancel = {
                if let Some(state) = tick_handle.try_state::<AppState>() {
                    state.updater.read().cancel_token.clone()
                } else {
                    tokio_util::sync::CancellationToken::new()
                }
            };
            tauri::async_runtime::spawn(async move {
                updater::tick::run_background_ticker(tick_cancel, move || {
                    let app = tick_handle.clone();
                    tauri::async_runtime::spawn(async move {
                        // Gating predicate — only fire when the state
                        // allows a fresh check.
                        let allowed = if let Some(state) = app.try_state::<AppState>() {
                            updater::tick::is_check_allowed(state.updater.read().state)
                        } else {
                            false
                        };
                        if allowed {
                            let _ = updater::commands::check_for_updates_now(app.clone()).await;
                        }
                    });
                })
                .await;
            });

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
                    // Spec 007 / T019 — cancel the 4-hour ticker so its
                    // task stops sleeping and returns cleanly.
                    state.updater.read().cancel_token.cancel();

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

/// Spec 004 / T018 — translate Tauri's `DragDropEvent` into the
/// `juradrop://file-dropped` event the WebView consumes. The
/// elementFromPoint resolution lives in JS; this Rust handler is
/// purely an OS-level → bridge-level translator.
///
/// Position semantics: Tauri 2.x on macOS delivers `position` in
/// LOGICAL pixels (despite the type being `PhysicalPosition<f64>`,
/// the values match what `document.elementFromPoint(x, y)` expects
/// in the WebView). Dividing by `scale_factor` here would
/// double-shrink the coordinates and route the drop to the wrong
/// zone (typically above the zone grid). Verified empirically on
/// macOS 26 with a Retina display (scale=2); the unmodified
/// position lands on the visually-targeted zone. The earlier
/// divide-by-scale was inherited from the Tauri 1.x convention
/// and the bug went unnoticed because no spec ever exercised a
/// real drag-drop against a built `.app` until the post-spec-012
/// hardware test.
fn handle_drag_drop_event(app: &tauri::AppHandle, drag: DragDropEvent) {
    // Enter / Over / Leave are routed by the WebView's own
    // drag-tracking layer (set per-zone via React onDragOver +
    // data-zone-id). Rust only needs to fan out the Drop event with
    // the OS file paths + the position.
    if let DragDropEvent::Drop { paths, position } = drag {
        #[derive(serde::Serialize, Clone)]
        struct FileDroppedPayload {
            paths: Vec<std::path::PathBuf>,
            position: CssPosition,
        }
        #[derive(serde::Serialize, Clone)]
        struct CssPosition {
            x: f64,
            y: f64,
        }
        let payload = FileDroppedPayload {
            paths,
            position: CssPosition {
                x: position.x,
                y: position.y,
            },
        };
        let _ = app.emit("juradrop://file-dropped", payload);
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

        // Plus exactly two scoped object permissions:
        //   1. shell:allow-spawn — limited to the bundled ollama binary
        //      (spec 002).
        //   2. shell:allow-open — limited to the single GitHub Releases
        //      URL the spec 010 About-section button uses.
        // No other scoped permissions are allowed.
        let object_perms: Vec<&serde_json::Value> =
            perms.iter().filter(|v| v.is_object()).collect();
        assert_eq!(
            object_perms.len(),
            2,
            "expected exactly two scoped permissions (shell:allow-spawn for ollama, shell:allow-open for GitHub Releases URL)"
        );

        // First scoped permission: spec 002 — shell:allow-spawn for ollama.
        let spawn = object_perms
            .iter()
            .find(|v| v.get("identifier").and_then(|i| i.as_str()) == Some("shell:allow-spawn"))
            .expect("shell:allow-spawn entry must exist");
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

        // Second scoped permission: spec 010 — shell:allow-open for the
        // pinned GitHub Releases URL only.
        let open = object_perms
            .iter()
            .find(|v| v.get("identifier").and_then(|i| i.as_str()) == Some("shell:allow-open"))
            .expect("shell:allow-open entry must exist (spec 010 About link)");
        let open_allow = open
            .get("allow")
            .and_then(|v| v.as_array())
            .expect("shell:allow-open must have an allow array");
        assert_eq!(
            open_allow.len(),
            1,
            "shell:allow-open allow list must be a single entry (GitHub Releases URL only)"
        );
        let open_entry = &open_allow[0];
        assert_eq!(
            open_entry.get("url").and_then(|v| v.as_str()),
            Some("https://github.com/johanolofsson72/juradrop/releases"),
            "shell:allow-open URL must match the pinned spec 010 constant"
        );
    }
}
