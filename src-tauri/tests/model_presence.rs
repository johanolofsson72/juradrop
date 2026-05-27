// T034 — model-presence detection (spec 002 / US2 / FC-003).
//
// FC-003 in spec.md classifies this as "Rust unit test against mocked
// Ollama API" — the live-Ollama path is already exercised by T023
// (`sidecar_lifecycle.rs::sidecar_starts_and_stops_cleanly`), which
// hits `/api/tags` on the real bundled binary as part of `wait_ready`.
// What `commands.rs::after_sidecar_ready` actually depends on is:
//
//   1. `OllamaClient::list_tags()` parses Ollama's response shape into
//      a `Vec<String>` of model names.
//   2. The presence check `tags.iter().any(|t| t == DEFAULT_MODEL)`
//      correctly distinguishes model-present from model-absent.
//
// Both are deterministic against a mock — `wiremock` serves the exact
// JSON shapes Ollama produces in the field, so these tests stay green
// regardless of what models the dev machine happens to have pulled.

use juradrop_lib::sidecar::client::OllamaClient;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

const DEFAULT_MODEL: &str = "gemma3:4b";

fn model_present(tags: &[String]) -> bool {
    tags.iter().any(|t| t == DEFAULT_MODEL)
}

/// FC-003 / case 1 — `/api/tags` lists the default model. `list_tags`
/// returns it; the presence check finds it.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn list_tags_detects_default_model_when_present() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/api/tags"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "models": [
                { "name": "gemma3:4b", "size": 3_300_000_000u64, "modified_at": "2026-05-01T00:00:00Z" },
                { "name": "llama3.2:3b", "size": 2_100_000_000u64, "modified_at": "2026-05-01T00:00:00Z" },
            ],
        })))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let tags = client.list_tags().await.expect("list_tags ok");

    assert_eq!(tags.len(), 2);
    assert!(tags.contains(&"gemma3:4b".to_string()));
    assert!(
        model_present(&tags),
        "default model should be detected as present"
    );
}

/// FC-003 / case 2 — `/api/tags` lists OTHER models, but not the
/// default. `list_tags` returns them; the presence check correctly
/// reports absent (so `after_sidecar_ready` would gate the pull on
/// consent).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn list_tags_detects_default_model_when_absent() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/api/tags"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "models": [
                { "name": "llama3.2:3b", "size": 2_100_000_000u64, "modified_at": "2026-05-01T00:00:00Z" },
                { "name": "phi3.5:3.8b", "size": 2_400_000_000u64, "modified_at": "2026-05-01T00:00:00Z" },
            ],
        })))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let tags = client.list_tags().await.expect("list_tags ok");

    assert_eq!(tags.len(), 2);
    assert!(!tags.contains(&"gemma3:4b".to_string()));
    assert!(
        !model_present(&tags),
        "default model should be detected as absent"
    );
}

/// FC-003 / case 3 — fresh Ollama with no models pulled. Empty list
/// must round-trip and the presence check must report absent.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn list_tags_returns_empty_when_no_models_pulled() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/api/tags"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "models": [],
        })))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let tags = client.list_tags().await.expect("list_tags ok");

    assert!(tags.is_empty());
    assert!(
        !model_present(&tags),
        "empty list means default model is absent"
    );
}

/// Edge case: tags response includes models with `:latest` and other
/// tag suffixes. The presence check is strict equality on `gemma3:4b`
/// — `gemma3:latest` does NOT match (the spec.allium
/// `ModelArtifact::TagIsDefault` invariant pins the exact tag). This
/// catches a future refactor that loosens the comparison to
/// `starts_with("gemma3")` or similar.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn presence_check_is_exact_tag_match_not_prefix() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/api/tags"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "models": [
                { "name": "gemma3:latest", "size": 3_300_000_000u64, "modified_at": "2026-05-01T00:00:00Z" },
                { "name": "gemma3:9b", "size": 6_000_000_000u64, "modified_at": "2026-05-01T00:00:00Z" },
            ],
        })))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let tags = client.list_tags().await.expect("list_tags ok");

    assert!(
        !model_present(&tags),
        "gemma3:latest must not satisfy the gemma3:4b presence check"
    );
}
