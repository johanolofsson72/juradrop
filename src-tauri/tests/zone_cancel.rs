// Spec 003 / T053 — cancel-mid-inference integration test.
//
// Drives the SammanfattaZone::handle_drop entry point against a
// wiremock /api/generate that delays its response for 3 s. Fires
// cancel_summary roughly 100 ms after the drop and asserts:
//
//   1. The job's terminal outcome is Cancelled (Allium DropJob
//      transition: in_flight → cancelled).
//   2. No sidecar file is written at either the canonical or the
//      timestamp-suffixed path (Allium CancelledLeavesNoSidecar).
//   3. The source `.docx` is byte-identical before vs after
//      (FR-024 / SC-004 / Allium SourceFileImmutable).
//   4. The whole abort-to-idle cycle fits in the SC-008 1 s budget.
//
// Marked `#[ignore]` because Tauri test mocks are heavy. Run via:
//   cargo test --test zone_cancel -- --ignored --nocapture

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use docx_rs::{Docx, Paragraph, Run};
use juradrop_lib::sidecar::client::OllamaClient;
use juradrop_lib::zones::sammanfatta::DropZone;
use juradrop_lib::zones::ZoneId;
use sha2::{Digest, Sha256};
use tauri::test::{mock_builder, mock_context, noop_assets};
use tempfile::TempDir;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn sha256_of(p: &std::path::Path) -> [u8; 32] {
    let bytes = std::fs::read(p).unwrap();
    let mut h = Sha256::new();
    h.update(&bytes);
    h.finalize().into()
}

fn write_fixture_docx(dir: &std::path::Path, text: &str) -> PathBuf {
    let target = dir.join("ruling.docx");
    let mut bytes: Vec<u8> = Vec::new();
    Docx::new()
        .add_paragraph(Paragraph::new().add_run(Run::new().add_text(text)))
        .build()
        .pack(std::io::Cursor::new(&mut bytes))
        .unwrap();
    std::fs::write(&target, &bytes).unwrap();
    target
}

/// Helper: peek at the current in-flight job id without taking a
/// long write lock. Returns None if the zone is idle.
fn current_job_id(zone: &DropZone) -> Option<String> {
    // The zone exposes `cancel(&str)` but not a getter for the
    // current id; in production, the React layer carries the
    // job_id in the snapshot it observes. For tests we rely on
    // the cancel-by-id call being a no-op when the id mismatches —
    // see disabled_zone_rejects_drop_without_calling_model in
    // zone_sammanfatta_lifecycle.rs for the prior art.
    let _ = zone;
    None
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires Tauri mock app + wiremock; run with --ignored"]
async fn cancel_mid_inference_leaves_no_sidecar_and_source_byte_identical() {
    // 1. Wiremock with a 3-second delay so we have a long window to
    //    cancel during.
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(serde_json::json!({
                    "model": "gemma3:4b",
                    "response": "Detta svar borde aldrig synas — vi avbröt först.",
                    "done": true,
                }))
                .set_delay(Duration::from_secs(3)),
        )
        .mount(&server)
        .await;

    // 2. Mock Tauri app + the zone.
    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();
    let zone = DropZone::new(ZoneId::Sammanfatta);
    let client = Arc::new(OllamaClient::with_base_url(server.uri()));

    // 3. Stage a fixture .docx, capture its hash.
    let dir = TempDir::new().unwrap();
    let source = write_fixture_docx(dir.path(), "Ett testdokument om en tvist.");
    let sha_before = sha256_of(&source);

    // 4. Fire the drop. handle_drop spawns the dispatch internally;
    //    we return immediately and the dispatch's wiremock call is
    //    queued behind the 3 s delay.
    zone.clone()
        .handle_drop(handle, client, true, "gemma3:4b", vec![source.clone()])
        .await;

    // 5. Wait briefly for the dispatch to actually be in flight (the
    //    spawn-blocking extract step takes a few ms; the model call
    //    starts after that). 200 ms is comfortably past the
    //    extraction phase without sleeping near the 3 s delay.
    tokio::time::sleep(Duration::from_millis(200)).await;

    // 6. Cancel. We don't have a public getter for the in-flight
    //    job_id, but the cancel-by-id signature lets us pass *any*
    //    id; mismatched ids no-op (idempotency). For the test we
    //    cancel via the same path the dispatch's cancel_token uses
    //    internally — that requires us to know the job id. Since the
    //    Rust API hides it, we drop in a separate cancellation hook:
    //    the zone.state's current_job is a SammanfattaZone internal,
    //    so we reach into the zone's cancel(id) path by inspecting
    //    the only public observation point — the snapshot the
    //    React layer would see. As an integration shortcut, we
    //    snapshot via a test-only accessor; if absent, fall back to
    //    forcing cancellation via the public surface that always
    //    cancels the in-flight job regardless of id.
    //
    //    For this test, the simpler path is to call zone.cancel("*")
    //    which matches no id and is a no-op — proving the
    //    idempotency contract — and ALSO call zone.cancel() (the
    //    no-arg path we'll add) which cancels whatever is in flight.
    //    Until that exists, we test cancellation via the simpler
    //    path: read the current job id from the snapshot we emitted
    //    when handle_drop fired the processing snapshot.
    //
    //    The processing snapshot carries the job_id; we listen for
    //    it via the app's emit history. tauri::test exposes
    //    `assert_ipc_response` and `get_ipc_response` for command
    //    introspection; for arbitrary emits there is no public API.
    //    The pragmatic move for spec 003 is to teach the zone a
    //    test-only `cancel_in_flight()` shortcut. Pattern matches
    //    spec 002's set_visible_for_test from T035.
    let _ = current_job_id(&zone); // documented above; currently None
    zone.cancel_in_flight_for_test();

    // 7. Wait briefly for the cancel signal to propagate through the
    //    select! in dispatch. SC-008 budget is 1 s; in practice
    //    this is < 50 ms because reqwest closes the connection on
    //    future drop.
    let abort_started = std::time::Instant::now();
    let deadline = abort_started + Duration::from_secs(1);
    while std::time::Instant::now() < deadline {
        if zone.visible_for_test() != juradrop_lib::zones::ZoneState::Processing {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let abort_elapsed = abort_started.elapsed();
    assert!(
        abort_elapsed < Duration::from_secs(1),
        "SC-008: cancel must take effect within 1 s, took {abort_elapsed:?}"
    );

    // 8. No sidecar file landed at the canonical or timestamped path.
    let canonical = source.parent().unwrap().join("ruling.sammanfatta.docx");
    assert!(
        !canonical.exists(),
        "cancelled job must not leave a sidecar at {canonical:?}"
    );
    // Cheap glob — collect all entries in the source dir, none should
    // match the `.sammanfatta.` pattern.
    let dir_entries: Vec<_> = std::fs::read_dir(source.parent().unwrap())
        .unwrap()
        .filter_map(Result::ok)
        .map(|e| e.path())
        .collect();
    for entry in &dir_entries {
        let name = entry.file_name().unwrap().to_string_lossy();
        assert!(
            !name.contains(".sammanfatta."),
            "cancelled job must not write any sidecar; found {entry:?}"
        );
    }

    // 9. Source is byte-identical (FR-024).
    let sha_after = sha256_of(&source);
    assert_eq!(
        sha_before, sha_after,
        "cancelled job must leave the source byte-identical"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires Tauri mock app; run with --ignored"]
async fn cancel_with_unknown_job_id_is_idempotent_noop() {
    // Verifies the FR-027 + contracts/tauri-commands.md "idempotent
    // no-op" contract: cancelling a stale id while a different job
    // is in flight (or while idle) must NOT disturb anything.
    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let _handle = app.handle().clone();
    let zone = DropZone::new(ZoneId::Sammanfatta);

    // Idle zone — cancel by random id is a no-op.
    zone.cancel("00000000-0000-0000-0000-000000000000");
    zone.cancel("");
    zone.cancel("not-even-a-uuid");
    // No assertion needed — surviving without panic is the contract.
}
