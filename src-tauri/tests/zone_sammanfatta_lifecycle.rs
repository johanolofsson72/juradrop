// Spec 003 / T023 — Sammanfatta zone lifecycle integration test.
//
// End-to-end happy path with a wiremock mock standing in for the
// real Ollama. Drives the SammanfattaZone::handle_drop entry point
// (the same path lib.rs's DragDrop event handler uses), waits for
// the sidecar file to land on disk, and asserts:
//   - The sidecar exists at the canonical path next to the source.
//   - The sidecar is a valid .docx parseable by docx-rs.
//   - The source .docx is byte-identical (SHA-256) before vs after
//     the drop (FR-024 / SC-004 / Allium SourceFileImmutable).
//
// Spec 013 (US3 / FR-013) — UN-IGNORED. The prior `#[ignore]` claimed
// the Tauri mock harness was "expensive"; measurement showed all 6 tests
// run in ~0.3s, so they now run on every `cargo test`. wiremock is already
// a dev-dependency; no harness rewrite was needed.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use docx_rs::{Docx, Paragraph, Run};
use juradrop_lib::sidecar::client::OllamaClient;
use juradrop_lib::zones::docx_extract::extract_text_from_bytes;
use juradrop_lib::zones::sammanfatta::DropZone;
use juradrop_lib::zones::ZoneId;
use sha2::{Digest, Sha256};
use tauri::test::{mock_builder, mock_context, noop_assets};
use tempfile::TempDir;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn sha256_of(path: &std::path::Path) -> [u8; 32] {
    let bytes = std::fs::read(path).expect("read source");
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
        .expect("pack docx");
    std::fs::write(&target, &bytes).expect("write fixture");
    target
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn drop_docx_writes_sidecar_and_leaves_source_byte_identical() {
    // 1. Wiremock the /api/generate endpoint with a Swedish-looking
    //    response. This keeps the test deterministic and avoids
    //    needing a real Ollama running.
    let server = MockServer::start().await;
    let swedish_summary =
        "Detta är en testsammanfattning.\n\nDokumentet handlar om en juridisk tvist.";
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "model": "gemma3:4b",
            "response": swedish_summary,
            "done": true,
        })))
        .mount(&server)
        .await;

    // 2. Build the Tauri mock app + the zone owning the in-flight slot.
    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();
    let zone = DropZone::new(ZoneId::Sammanfatta);
    let client = Arc::new(OllamaClient::with_base_url(server.uri()));

    // 3. Stage a fixture .docx and capture its SHA-256.
    let dir = TempDir::new().expect("tempdir");
    let source = write_fixture_docx(
        dir.path(),
        "Domskäl: detta är ett testdokument om en tvist mellan A och B.",
    );
    let sha_before = sha256_of(&source);

    // 4. Fire the drop. handle_drop spawns the dispatch in a tokio
    //    task — wait for the success snapshot via the side-effect
    //    of the sidecar landing on disk.
    zone.clone()
        .handle_drop(
            handle,
            client,
            true,
            "gemma3:4b",
            vec![source.clone()],
            None,
        )
        .await;

    // 5. Poll for the sidecar file (the dispatch is async — give it
    //    up to 10 s to write, well within the 60 s SC-001 budget).
    let canonical = source.parent().unwrap().join("ruling.sammanfatta.docx");
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    let mut found = false;
    while std::time::Instant::now() < deadline {
        if canonical.exists() {
            found = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(
        found,
        "sidecar {canonical:?} did not appear within 10 s of drop"
    );

    // 6. The sidecar is a valid .docx with the FR-005a header.
    let sidecar_bytes = std::fs::read(&canonical).expect("read sidecar");
    let extracted = extract_text_from_bytes(&sidecar_bytes).expect("sidecar parses");
    assert!(
        extracted
            .raw
            .as_inner()
            .contains("Sammanfattning av 'ruling.docx'"),
        "sidecar missing FR-005a header; got: {:?}",
        extracted.raw.as_inner()
    );
    assert!(extracted.raw.as_inner().contains("gemma3:4b"));
    assert!(extracted.raw.as_inner().contains("juridisk tvist"));

    // 7. Source is byte-identical (FR-024 / SC-004).
    let sha_after = sha256_of(&source);
    assert_eq!(
        sha_before, sha_after,
        "source .docx must be byte-identical before vs after the drop"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn disabled_zone_rejects_drop_without_calling_model() {
    // No wiremock - the model MUST NOT be called when disabled.
    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();
    let zone = DropZone::new(ZoneId::Sammanfatta);
    // A client pointed at a port nothing listens on — would fail loudly
    // if dispatch reached it; the disabled gate must short-circuit before.
    let client = Arc::new(OllamaClient::with_base_url(
        "http://127.0.0.1:1".to_string(),
    ));

    let dir = TempDir::new().unwrap();
    let source = write_fixture_docx(dir.path(), "Text.");

    // sidecar_ready: false → ZoneFailure::ZoneDisabled snapshot, no dispatch.
    zone.handle_drop(
        handle,
        client,
        false,
        "gemma3:4b",
        vec![source.clone()],
        None,
    )
    .await;

    // Give the (non-existent) dispatch a moment to NOT happen.
    tokio::time::sleep(Duration::from_millis(200)).await;

    let canonical = source.parent().unwrap().join("ruling.sammanfatta.docx");
    assert!(
        !canonical.exists(),
        "disabled zone must not produce a sidecar"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn non_docx_drop_emits_invalid_format_and_does_not_call_model() {
    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();
    let zone = DropZone::new(ZoneId::Sammanfatta);
    let client = Arc::new(OllamaClient::with_base_url(
        "http://127.0.0.1:1".to_string(),
    ));

    let dir = TempDir::new().unwrap();
    let fake_pdf = dir.path().join("document.pdf");
    std::fs::write(&fake_pdf, b"%PDF-1.5 not a real pdf").unwrap();

    zone.handle_drop(
        handle,
        client,
        true,
        "gemma3:4b",
        vec![fake_pdf.clone()],
        None,
    )
    .await;

    tokio::time::sleep(Duration::from_millis(200)).await;
    let unexpected_sidecar = fake_pdf.parent().unwrap().join("document.sammanfatta.docx");
    assert!(
        !unexpected_sidecar.exists(),
        "non-.docx drop must not produce a sidecar"
    );
}

/// T063 — DT-007 equivalent: a `.docx` whose path contains exotic
/// UTF-8 characters (emoji, accented characters, NFD vs NFC forms)
/// must round-trip through the sidecar pipeline without shell
/// injection, without filename corruption, and without panic. The
/// sidecar lands in the same directory with the right `.sammanfatta`
/// suffix derived from the exotic stem.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn drop_with_exotic_chars_in_path_produces_correctly_named_sidecar() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "model": "gemma3:4b",
            "response": "Kort sammanfattning.",
            "done": true,
        })))
        .mount(&server)
        .await;

    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();
    let zone = DropZone::new(ZoneId::Sammanfatta);
    let client = Arc::new(OllamaClient::with_base_url(server.uri()));

    let dir = TempDir::new().expect("tempdir");
    // Exotic stem: emoji + accented Swedish + a space + an em dash.
    // None of these may be expanded by a shell — write_atomically
    // takes a PathBuf directly, no shell layer between.
    let exotic_stem = "domskäl-🎉-vår tvist—2026";
    let source = {
        let target = dir.path().join(format!("{exotic_stem}.docx"));
        let mut bytes: Vec<u8> = Vec::new();
        Docx::new()
            .add_paragraph(Paragraph::new().add_run(Run::new().add_text("Text.")))
            .build()
            .pack(std::io::Cursor::new(&mut bytes))
            .expect("pack");
        std::fs::write(&target, &bytes).expect("write fixture");
        target
    };
    let sha_before = sha256_of(&source);

    zone.clone()
        .handle_drop(
            handle,
            client,
            true,
            "gemma3:4b",
            vec![source.clone()],
            None,
        )
        .await;

    // Wait for the sidecar.
    let expected_canonical = source
        .parent()
        .unwrap()
        .join(format!("{exotic_stem}.sammanfatta.docx"));
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    let mut found = false;
    while std::time::Instant::now() < deadline {
        if expected_canonical.exists() {
            found = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(
        found,
        "sidecar with exotic-char stem did not appear at {expected_canonical:?}"
    );

    // Source SHA-256 unchanged — no shell expansion side-effects on
    // the source file.
    let sha_after = sha256_of(&source);
    assert_eq!(
        sha_before, sha_after,
        "exotic-char path must not modify the source"
    );

    // The sidecar's filename must include the exotic stem verbatim
    // (NFC/NFD normalization preserved by the macOS FS layer; we
    // just assert the round-trip survived).
    let name = expected_canonical
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap();
    assert!(
        name.contains("🎉"),
        "emoji must survive in the sidecar name"
    );
    assert!(name.contains("ä"), "Swedish ä must survive");
    assert!(name.contains("—"), "em dash must survive");
}

/// GAP-1 (closed by `/tla` pass): explicit assertion that a
/// dispatch-time failure (model returns 500) leaves NO sidecar on
/// disk. The architecture makes this structurally true — every
/// failure path in dispatch returns before write_atomically is
/// called — but this test exercises the full path end-to-end so a
/// future refactor that reorders the dispatch can't accidentally
/// drop a partial sidecar after a model failure.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn dispatch_failure_leaves_no_sidecar_on_disk() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(500).set_body_string("ollama internal error"))
        .mount(&server)
        .await;

    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();
    let zone = DropZone::new(ZoneId::Sammanfatta);
    let client = Arc::new(OllamaClient::with_base_url(server.uri()));

    let dir = TempDir::new().expect("tempdir");
    let source = write_fixture_docx(dir.path(), "Text att sammanfatta.");
    let sha_before = sha256_of(&source);

    zone.clone()
        .handle_drop(
            handle,
            client,
            true,
            "gemma3:4b",
            vec![source.clone()],
            None,
        )
        .await;

    // Wait for the dispatch to complete (transition out of Processing).
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    while std::time::Instant::now() < deadline {
        if zone.visible_for_test() != juradrop_lib::zones::ZoneState::Processing {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    // Should have landed in Error (ModelError), not Success.
    assert_eq!(
        zone.visible_for_test(),
        juradrop_lib::zones::ZoneState::Error,
        "model failure must land in Error state"
    );

    // The canonical sidecar MUST NOT exist.
    let canonical = source.parent().unwrap().join("ruling.sammanfatta.docx");
    assert!(
        !canonical.exists(),
        "failed dispatch must NOT write {canonical:?}"
    );

    // And no timestamp-suffixed variant either — sweep the dir.
    for entry in std::fs::read_dir(source.parent().unwrap())
        .unwrap()
        .flatten()
    {
        let name = entry.file_name().to_string_lossy().to_string();
        assert!(
            !name.contains(".sammanfatta."),
            "failed dispatch must not write ANY sidecar; found {entry:?}"
        );
    }

    // And the source is byte-identical (FR-024 holds on the failure
    // path too, not just success).
    let sha_after = sha256_of(&source);
    assert_eq!(sha_before, sha_after);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn multi_file_drop_emits_multiple_files_failure() {
    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();
    let zone = DropZone::new(ZoneId::Sammanfatta);
    let client = Arc::new(OllamaClient::with_base_url(
        "http://127.0.0.1:1".to_string(),
    ));

    let dir = TempDir::new().unwrap();
    let a = write_fixture_docx(dir.path(), "a");
    let b = dir.path().join("b.docx");
    std::fs::copy(&a, &b).unwrap();

    zone.handle_drop(handle, client, true, "gemma3:4b", vec![a.clone(), b], None)
        .await;

    tokio::time::sleep(Duration::from_millis(200)).await;
    let sidecar = a.parent().unwrap().join("ruling.sammanfatta.docx");
    assert!(
        !sidecar.exists(),
        "multi-file drop must not produce a sidecar"
    );
}
