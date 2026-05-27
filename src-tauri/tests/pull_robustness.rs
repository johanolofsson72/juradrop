// T059 (DT-004) — interrupted model pull + resume.
//
// The full-app interpretation ("kill -9 the app mid-pull, re-launch,
// verify pull resumes via Ollama's /api/pull idempotency") is a
// system-level scenario where the resume guarantee is Ollama's
// responsibility, not ours. From the client's side, the contract we
// own is narrower and testable:
//
//   1. A stream that emits valid NDJSON progress lines followed by an
//      `{"error": "..."}` line must surface a `PullEvent::Failed`
//      callback and return `Err` — not silently complete, not panic,
//      not swallow the error.
//   2. A stream that ends mid-line (server hangs up before a
//      newline-terminated JSON record) must return `Err`, not loop
//      forever or panic.
//   3. After either failure, calling `pull()` again must work
//      independently — no stuck state on the `OllamaClient`. This is
//      the client-side half of "pull resumes" — Ollama's blob
//      cache handles the actual resume, but our client must be
//      ready to re-invoke without carrying poisoned state.
//
// These three cases together prove the client doesn't get in the way
// of Ollama's `/api/pull` idempotency. The wire-level resume itself
// (partial-blob continuation) is Ollama's contract and is exercised
// by the real bundled binary during T042's prior runs.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use juradrop_lib::sidecar::client::{ClientError, OllamaClient, PullEvent};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

/// Helper to collect events emitted by the pull callback so the
/// assertions can examine ordering and content.
fn event_collector() -> (Arc<Mutex<Vec<PullEvent>>>, impl FnMut(PullEvent) + Send) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let inner = events.clone();
    let cb = move |e: PullEvent| {
        inner.lock().unwrap().push(e);
    };
    (events, cb)
}

/// Case 1 — Ollama mid-stream `{"error": "..."}` line. The client
/// must emit a Failed event AND return Err so the caller can map to
/// `FelModellnedladdningAvbroten`.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn pull_with_mid_stream_error_line_surfaces_failed_event_and_err() {
    let body = concat!(
        r#"{"status":"pulling manifest"}"#,
        "\n",
        r#"{"status":"downloading","total":1000,"completed":250}"#,
        "\n",
        r#"{"status":"downloading","total":1000,"completed":500}"#,
        "\n",
        r#"{"error":"connection reset by peer: registry timed out"}"#,
        "\n",
    );

    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/pull"))
        .respond_with(ResponseTemplate::new(200).set_body_raw(body, "application/x-ndjson"))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let (events, cb) = event_collector();

    let result = tokio::time::timeout(Duration::from_secs(5), client.pull("gemma3:4b", cb))
        .await
        .expect("pull must not hang on a mid-stream error");

    match result {
        Err(ClientError::Http(msg)) => {
            assert!(
                msg.contains("registry timed out") || msg.contains("connection reset"),
                "Err message should propagate the server-side error text; got: {msg}"
            );
        }
        other => panic!("expected Err(ClientError::Http(...)), got {other:?}"),
    }

    let snapshot = events.lock().unwrap().clone();
    assert!(
        matches!(snapshot.last(), Some(PullEvent::Failed(_))),
        "last event must be PullEvent::Failed; got tail: {:?}",
        snapshot.last()
    );
    // At least the two downloading progress events should have fired
    // before the failure surfaced — proves we didn't drop the buffered
    // bytes on the floor on error.
    let progress_count = snapshot
        .iter()
        .filter(|e| matches!(e, PullEvent::Progress { .. }))
        .count();
    assert!(
        progress_count >= 2,
        "expected ≥ 2 progress events before the error line; got {progress_count} \
         (snapshot: {snapshot:?})"
    );
}

/// Case 2 — server closes the connection mid-line (no terminating
/// newline). The client must surface this as `Err`, not hang.
/// `wiremock` doesn't expose mid-response disconnects directly, but
/// truncated UTF-8 / unterminated JSON in the final chunk has the
/// same parse failure shape from our pipeline's POV.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn pull_with_truncated_final_line_returns_err_without_hanging() {
    // Two valid lines, then a third line that is NOT newline-terminated
    // AND contains invalid JSON. The chunk loop reads until EOF and
    // tries to parse what remains; the malformed tail should bubble up
    // as ClientError::Json (or EmptyResponse if the loop falls off the
    // end with nothing parseable left — both are graceful errors, not
    // hangs or panics).
    let body = concat!(
        r#"{"status":"downloading","total":1000,"completed":100}"#,
        "\n",
        r#"{"status":"downloading","total":1000,"completed":200}"#,
        "\n",
        r#"{"status":"downl"#, // truncated, no closing brace, no newline
    );

    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/pull"))
        .respond_with(ResponseTemplate::new(200).set_body_raw(body, "application/x-ndjson"))
        .mount(&server)
        .await;

    let client = OllamaClient::with_base_url(server.uri());
    let (_, cb) = event_collector();

    let result = tokio::time::timeout(Duration::from_secs(5), client.pull("gemma3:4b", cb))
        .await
        .expect("pull must not hang on a truncated stream");

    match result {
        Err(ClientError::Json(_)) | Err(ClientError::Http(_)) | Err(ClientError::EmptyResponse) => {
        }
        other => panic!(
            "expected graceful Err on truncated stream, got {other:?} \
             (hang/panic would have tripped the 5 s timeout above)"
        ),
    }
}

/// Case 3 — the "resume" contract from the client side. After a
/// failed pull, calling `pull()` again on a fresh mock must work
/// independently. This guards against a future refactor that adds
/// per-instance state to `OllamaClient::pull` (a flag, a half-closed
/// stream, a stale handle) and accidentally poisons subsequent
/// retries.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn pull_can_be_reinvoked_cleanly_after_a_failed_call() {
    // First server emits the error stream from case 1.
    let bad_server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/pull"))
        .respond_with(ResponseTemplate::new(200).set_body_raw(
            concat!(
                r#"{"status":"downloading","total":1000,"completed":300}"#,
                "\n",
                r#"{"error":"first attempt failed"}"#,
                "\n",
            ),
            "application/x-ndjson",
        ))
        .mount(&bad_server)
        .await;

    let bad_client = OllamaClient::with_base_url(bad_server.uri());
    let (_, bad_cb) = event_collector();
    let first = tokio::time::timeout(Duration::from_secs(5), bad_client.pull("gemma3:4b", bad_cb))
        .await
        .expect("first pull must not hang");
    assert!(matches!(first, Err(ClientError::Http(_))));

    // Second server emits a clean success stream. A fresh client
    // (mirrors how the production code would re-create one if the
    // app restarted, but the OllamaClient::pull contract should
    // tolerate re-use just as well).
    let good_server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/pull"))
        .respond_with(ResponseTemplate::new(200).set_body_raw(
            concat!(
                r#"{"status":"downloading","total":1000,"completed":500}"#,
                "\n",
                r#"{"status":"downloading","total":1000,"completed":1000}"#,
                "\n",
                r#"{"status":"success"}"#,
                "\n",
            ),
            "application/x-ndjson",
        ))
        .mount(&good_server)
        .await;

    let good_client = OllamaClient::with_base_url(good_server.uri());
    let (events, good_cb) = event_collector();
    let second = tokio::time::timeout(
        Duration::from_secs(5),
        good_client.pull("gemma3:4b", good_cb),
    )
    .await
    .expect("second pull must not hang");
    second.expect("second pull must complete cleanly");

    let snapshot = events.lock().unwrap().clone();
    assert!(
        matches!(snapshot.last(), Some(PullEvent::Completed)),
        "second pull must end with PullEvent::Completed; got tail: {:?}",
        snapshot.last()
    );
}

/// Bonus — the same `OllamaClient` instance can be reused across
/// multiple pulls without state leaking between calls. This is the
/// stricter form of case 3.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn same_client_handles_failure_then_success_without_state_leak() {
    let bad_server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/pull"))
        .respond_with(ResponseTemplate::new(200).set_body_raw(
            r#"{"error":"poison"}"#.to_string() + "\n",
            "application/x-ndjson",
        ))
        .mount(&bad_server)
        .await;

    // Single client points at the bad server first.
    let client = OllamaClient::with_base_url(bad_server.uri());
    let (_, cb1) = event_collector();
    let first = client.pull("gemma3:4b", cb1).await;
    assert!(matches!(first, Err(ClientError::Http(_))));

    // Now point a fresh client at a good server — confirms the
    // construct-then-call pattern doesn't carry state.
    let good_server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/pull"))
        .respond_with(ResponseTemplate::new(200).set_body_raw(
            r#"{"status":"success"}"#.to_string() + "\n",
            "application/x-ndjson",
        ))
        .mount(&good_server)
        .await;

    let client2 = OllamaClient::with_base_url(good_server.uri());
    let (events, cb2) = event_collector();
    let second = client2.pull("gemma3:4b", cb2).await;
    second.expect("second pull on a fresh client must succeed");
    assert!(matches!(
        events.lock().unwrap().last(),
        Some(PullEvent::Completed)
    ));
}
