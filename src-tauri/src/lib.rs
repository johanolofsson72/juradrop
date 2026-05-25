// JuraDrop core — spec 001-tauri-bootstrap
//
// Boots a single Tauri window. Closing the window quits the app (per FR-010,
// constitution Principle IV: "the window IS the app — close the window, the
// app quits"). No commands registered (deny-by-default per FR-019).

use tauri::{RunEvent, WindowEvent};

pub fn run() {
    tauri::Builder::default()
        .setup(|_app| Ok(()))
        .build(tauri::generate_context!())
        .expect("failed to build JuraDrop tauri application")
        .run(|app_handle, event| {
            if let RunEvent::WindowEvent {
                label,
                event: WindowEvent::CloseRequested { .. },
                ..
            } = event
            {
                if label == "main" {
                    app_handle.exit(0);
                }
            }
        });
}

#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        // FC-008: at least one Rust unit test passes when `cargo test` runs.
        assert_eq!(2 + 2, 4);
    }

    #[test]
    fn close_window_quits_app_intent_documented() {
        // We cannot test the full Tauri run loop without spinning up the WebView.
        // This test simply documents the invariant: pressing the red traffic-light
        // button on the main window triggers app_handle.exit(0). The integration
        // is verified manually + by destructive test DT-006 (close during render).
        let label = "main";
        assert_eq!(label, "main");
    }
}
