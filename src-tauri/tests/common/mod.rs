// Spec 013 — shared harness for the 9 zone-pipeline integration tests
// (FR-011) and the e2e smoke (FR-014). Reuses the proven spec-003
// wiremock + tauri::test::mock_builder pattern.
//
// Not a test binary itself (lives under tests/common/), so it carries no
// #[test] fns — it is `mod common;`-included by each zone_pipeline_*.rs.

#![allow(dead_code)]

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use juradrop_lib::sidecar::client::OllamaClient;
use juradrop_lib::zones::docx_extract::extract_text_from_bytes;
use juradrop_lib::zones::sammanfatta::DropZone;
use juradrop_lib::zones::ZoneId;
use sha2::{Digest, Sha256};
use tauri::test::{mock_builder, mock_context, noop_assets};
use tempfile::TempDir;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

pub fn fixture_path(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/documents")
        .join(name)
}

pub fn sha256_of(p: &Path) -> [u8; 32] {
    let bytes = std::fs::read(p).expect("read for sha");
    let mut h = Sha256::new();
    h.update(&bytes);
    h.finalize().into()
}

/// Drive a real fixture through the full zone pipeline against a wiremock
/// `/api/generate` returning `mock_response`. Asserts:
///   (a) source SHA-256 unchanged, (b) sidecar created with the zone's
///   suffix, (c) sidecar content non-empty, (d) sidecar contains each
///   marker, (e) disclaimer present iff the zone declares one.
pub async fn run_zone_pipeline(
    zone: ZoneId,
    fixture_name: &str,
    mock_response: &str,
    markers: &[&str],
) {
    run_zone_pipeline_checked(zone, fixture_name, mock_response, markers, &[]).await;
}

/// As `run_zone_pipeline`, plus (f) the sidecar MUST NOT contain any of the
/// `forbidden` substrings. Spec 036 SC-002 uses this to assert a study-method
/// zone's citation-free mock output stays citation-free (no fabricated
/// `§`/`SFS`/`NJA`/`kap.` tokens) — exercising the Principle-VIII guard as a
/// property of the produced sidecar, not just a prose claim.
pub async fn run_zone_pipeline_checked(
    zone: ZoneId,
    fixture_name: &str,
    mock_response: &str,
    markers: &[&str],
    forbidden: &[&str],
) {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "model": "gemma3:4b",
            "response": mock_response,
            "done": true,
        })))
        .mount(&server)
        .await;

    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();

    // Copy the committed fixture into a TempDir so the committed file is
    // NEVER mutated by the test (and the sidecar lands in the temp dir).
    let dir = TempDir::new().expect("tempdir");
    let source = dir.path().join(fixture_name);
    std::fs::copy(fixture_path(fixture_name), &source).expect("copy fixture");
    let sha_before = sha256_of(&source);

    let zone_obj = DropZone::new(zone);
    let client = Arc::new(OllamaClient::with_base_url(server.uri()));
    zone_obj
        .clone()
        .handle_drop(handle, client, true, "gemma3:4b", vec![source.clone()])
        .await;

    // Poll for a sidecar named `*.<sidecar_suffix>.*` next to the source.
    // Note: the suffix is NOT always the slug — Anonymisera writes the
    // past-participle "anonymiserad" (zone_id.rs sidecar_suffix()).
    let suffix = zone.sidecar_suffix();
    let needle = format!(".{suffix}.");
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    let mut sidecar: Option<PathBuf> = None;
    while std::time::Instant::now() < deadline {
        if let Some(found) = find_sidecar(dir.path(), &needle) {
            sidecar = Some(found);
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let sidecar = sidecar.unwrap_or_else(|| {
        let listing: Vec<String> = std::fs::read_dir(dir.path())
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_string())
            .collect();
        panic!(
            "{zone:?}: no sidecar matching '*{needle}*' appeared in 10s. \
             tempdir contents: {listing:?}; zone state: {:?}",
            zone_obj.visible_for_test()
        )
    });

    // (a) source byte-identical.
    assert_eq!(
        sha_before,
        sha256_of(&source),
        "{zone:?}: source must be byte-identical after dispatch"
    );

    // All 9 zones write a .docx sidecar (every fixture is .docx input, and
    // Generera's .txt input maps to .docx per FR-003).
    assert_eq!(
        sidecar.extension().and_then(|s| s.to_str()),
        Some("docx"),
        "{zone:?}: expected a .docx sidecar, got {sidecar:?}"
    );

    let bytes = std::fs::read(&sidecar).expect("read sidecar");
    let extracted = extract_text_from_bytes(&bytes).expect("sidecar parses as docx");
    let text = extracted.raw.as_inner();

    // (c) non-empty.
    assert!(
        !text.trim().is_empty(),
        "{zone:?}: sidecar content is empty"
    );

    // (d) zone-specific markers (sourced from the mock response).
    for m in markers {
        assert!(
            text.contains(m),
            "{zone:?}: sidecar missing marker {m:?}\nfull text: {text}"
        );
    }

    // (e) disclaimer present iff the zone declares one.
    if let Some(disclaimer) = zone.disclaimer_paragraph() {
        assert!(
            text.contains(disclaimer),
            "{zone:?}: disclaimer paragraph missing from sidecar"
        );
    }

    // (f) forbidden substrings absent (spec 036 SC-002 — citation-free).
    // The disclaimer text itself is excluded so a zone whose disclaimer happens
    // to mention a forbidden token can't false-positive (none currently do).
    let body_only = zone
        .disclaimer_paragraph()
        .map(|d| text.replace(d, ""))
        .unwrap_or_else(|| text.to_string());
    for f in forbidden {
        assert!(
            !body_only.contains(f),
            "{zone:?}: sidecar unexpectedly contains forbidden token {f:?}\nfull text: {text}"
        );
    }

    println!("{zone:?}: sidecar {sidecar:?} OK ({} chars)", text.len());
}

fn find_sidecar(dir: &Path, needle: &str) -> Option<PathBuf> {
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.contains(needle) {
            return Some(entry.path());
        }
    }
    None
}
