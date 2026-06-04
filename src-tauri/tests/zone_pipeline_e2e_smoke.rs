// Spec 013 FR-014 — end-to-end smoke that exercises the FR-015 debug-only
// JURADROP_OLLAMA_URL seam. Instead of injecting the client directly, this
// test sets the env var and constructs the client via OllamaClient::new()
// (the production construction path), proving the seam routes to the mock.
//
// The env var is process-global, so this test serializes against itself via
// a static mutex and unsets the var on completion.

use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use juradrop_lib::sidecar::client::OllamaClient;
use juradrop_lib::zones::sammanfatta::DropZone;
use juradrop_lib::zones::ZoneId;
use tauri::test::{mock_builder, mock_context, noop_assets};
use tempfile::TempDir;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

static ENV_LOCK: Mutex<()> = Mutex::new(());

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn e2e_smoke_seam_routes_new_client_to_mock() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "model": "gemma3:4b",
            "response": "Sammanfattning: dokumentet rör ett hyresavtal.",
            "done": true,
        })))
        .mount(&server)
        .await;

    // Exercise the seam: OllamaClient::new() must pick up the env var in
    // this debug test build and target the mock. The std Mutex serializes
    // the env-var set + client construction (the only env-sensitive work);
    // it is intentionally NOT held across the awaits below, so the lock
    // never crosses an await point.
    let client = {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::set_var("JURADROP_OLLAMA_URL", server.uri());
        let client = Arc::new(OllamaClient::new());
        assert_eq!(
            client.base_url(),
            server.uri(),
            "FR-015 seam did not route new() to the mock URL"
        );
        client
    };

    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();

    let fixture = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/documents/sammanfatta-input.docx");
    let dir = TempDir::new().expect("tempdir");
    let source = dir.path().join("sammanfatta-input.docx");
    std::fs::copy(&fixture, &source).expect("copy fixture");

    DropZone::new(ZoneId::Sammanfatta)
        .handle_drop(
            handle,
            client,
            true,
            "gemma3:4b",
            vec![source.clone()],
            None,
        )
        .await;

    // The sidecar landing proves the whole pipeline ran against the mock
    // reached via the seam.
    let needle = ".sammanfatta.";
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    let mut found = false;
    while std::time::Instant::now() < deadline {
        if std::fs::read_dir(dir.path())
            .unwrap()
            .flatten()
            .any(|e| e.file_name().to_string_lossy().contains(needle))
        {
            found = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    std::env::remove_var("JURADROP_OLLAMA_URL");
    assert!(found, "e2e smoke: sidecar did not appear via the seam path");
}
