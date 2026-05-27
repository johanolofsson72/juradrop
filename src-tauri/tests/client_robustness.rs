// Destructive robustness tests for the Ollama HTTP client (spec 002 / Phase 7).
//
// T056 (DT-001) — malformed JSON on /api/tags must not crash; it must
//                 surface a graceful `ClientError` that `status.rs` maps
//                 to `FelModellnedladdningAvbroten`.
// T057 (DT-002) — `OllamaClient::generate` must accept prompts and
//                 responses that contain XSS payloads, NUL/BEL control
//                 bytes, and emoji without panicking or corrupting state.
// T060 (DT-005) — calling `generate` against an Ollama that doesn't have
//                 the model loaded (HTTP 404) must return a graceful
//                 `ClientError`, never a panic.
//
// All three drive `OllamaClient` against a `wiremock` mock server on a
// random port, so the tests are independent of the real loopback Ollama
// — they run cleanly alongside Homebrew/Ollama.app holding 11434, and
// they don't need the bundled binary at all.

use juradrop_lib::sidecar::client::{ClientError, OllamaClient};
use juradrop_lib::sidecar::log_safe::Redacted;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

/// T056 (DT-001) — `/api/tags` returns malformed JSON. The client must
/// not panic; it must surface `ClientError::Http` (reqwest can't decode
/// the body) so the caller can map it to a Swedish error string.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn list_tags_with_malformed_json_returns_graceful_error() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/api/tags"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_string("{not valid json at all, missing braces and commas"),
        )
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let result = client.list_tags().await;

    match result {
        Err(ClientError::Http(_)) | Err(ClientError::Json(_)) => {}
        other => panic!("expected Err(Http|Json) on malformed JSON, got {other:?}"),
    }
}

/// T057 (DT-002) — `generate` must accept prompts and responses that
/// contain XSS-shaped strings, control bytes, and emoji without
/// panicking. The Redacted wrapper guarantees we never log the content,
/// but the request/response pipeline still has to handle every code
/// point cleanly.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn generate_round_trips_xss_control_bytes_and_emoji_without_panic() {
    // NUL is rejected by HTTP header validators, so we use it only in the
    // body. The script-tag is the actual XSS shape; the BEL byte (0x07)
    // and DEL (0x7F) are common control-char "smuggling" attempts.
    let evil_prompt = "<script>alert(1)</script>\u{0007}\u{007F}🎉 hej världen 🎉";
    let evil_response = "<img src=x onerror=alert(1)>\u{0001}🇸🇪 svar 🇸🇪";

    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "model": "gemma3:4b",
            "response": evil_response,
            "done": true,
        })))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let result = client
        .generate("gemma3:4b", Redacted::new(evil_prompt.to_string()))
        .await;

    let got = result.expect("generate should succeed for arbitrary text content");
    // `Redacted` enforces non-logging via Display/Debug; we still need to
    // verify the bytes round-tripped exactly. `into_inner` is the only
    // way to inspect the content and is intentionally gated.
    assert_eq!(got.into_inner(), evil_response);
}

/// T060 (DT-005) — Ollama returns HTTP 404 with `{"error": "model 'X'
/// not found"}` when the requested model isn't loaded. The client must
/// surface this as a graceful `ClientError`, never a panic. We accept
/// any of `Http`, `Json`, or `EmptyResponse` because the failure can
/// land at different layers (status check vs. body decode); the
/// behavioral guarantee is "no panic, error variant".
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn generate_against_missing_model_returns_graceful_error() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(404).set_body_json(serde_json::json!({
            "error": "model 'gemma3:4b' not found, try pulling it first",
        })))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let result = client
        .generate("gemma3:4b", Redacted::new("Säg hej.".to_string()))
        .await;

    match result {
        Err(ClientError::Http(_)) | Err(ClientError::Json(_)) | Err(ClientError::EmptyResponse) => {
        }
        other => panic!(
            "expected graceful Err(Http|Json|EmptyResponse) on 404-not-loaded, got {other:?}"
        ),
    }
}

/// Bonus: empty-but-valid response body must surface
/// `ClientError::EmptyResponse`, not a spurious success. This catches a
/// regression where a future refactor might accept `"response": ""` as
/// valid output and let the empty string bubble up to the UI.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn generate_with_empty_response_string_returns_empty_response_error() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "model": "gemma3:4b",
            "response": "",
            "done": true,
        })))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let result = client
        .generate("gemma3:4b", Redacted::new("Säg hej.".to_string()))
        .await;

    match result {
        Err(ClientError::EmptyResponse) => {}
        other => panic!("expected Err(EmptyResponse), got {other:?}"),
    }
}
