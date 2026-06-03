// Spec 017 — concurrency stress.
//
// Fires all 9 zone pipelines concurrently (per-zone wiremock + mock app +
// fixture copy) via join_all, over 3 rounds, and asserts: every job
// completes correctly, NO cross-zone contamination (each sidecar carries
// only its own zone's unique marker + suffix), every source stays
// byte-identical, and the batch finishes in bounded time without deadlock.
//
// Each handle_drop spawns its own internal tokio task, so initiating all
// nine at once via join_all exercises real parallelism inside the dispatch
// while keeping the test free of Send bounds on the Tauri mock app.

use std::path::Path;
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

/// (zone, fixture filename). Each zone's mock response embeds a unique
/// `[[ZONE:<slug>]]` token so contamination across zones is detectable.
fn zone_cases() -> Vec<(ZoneId, &'static str)> {
    vec![
        (ZoneId::Sammanfatta, "sammanfatta-input.docx"),
        (ZoneId::TillEngelska, "tillengelska-input.docx"),
        (ZoneId::TillSvenska, "tillsvenska-input.docx"),
        (ZoneId::Punktlista, "punktlista-input.docx"),
        (ZoneId::Anonymisera, "anonymisera-input.docx"),
        (ZoneId::Forenkla, "forenkla-input.docx"),
        (ZoneId::Kontakter, "kontakter-input.docx"),
        (ZoneId::Generera, "generera-input.txt"),
        (ZoneId::Kallor, "kallor-input.docx"),
        // Spec 036 — study-method zones.
        (ZoneId::Identifiera, "identifiera-input.docx"),
        (ZoneId::Strukturera, "strukturera-input.docx"),
        (ZoneId::Forklara, "forklara-input.docx"),
    ]
}

fn fixture(name: &str) -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/documents")
        .join(name)
}

fn sha256_of(p: &Path) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(std::fs::read(p).expect("read"));
    h.finalize().into()
}

struct RunResult {
    zone: ZoneId,
    sidecar_text: String,
    source_unchanged: bool,
}

/// One full zone pipeline against its own mock; returns the sidecar text.
async fn run_one(zone: ZoneId, fixture_name: &'static str) -> RunResult {
    let marker = format!("[[ZONE:{}]]", zone.slug());
    let response = format!("Resultat {marker} för zonen.");

    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/generate"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "model": "gemma3:4b",
            "response": response,
            "done": true,
        })))
        .mount(&server)
        .await;

    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock app");
    let handle = app.handle().clone();

    let dir = TempDir::new().expect("tempdir");
    let source = dir.path().join(fixture_name);
    std::fs::copy(fixture(fixture_name), &source).expect("copy fixture");
    let sha_before = sha256_of(&source);

    let client = Arc::new(OllamaClient::with_base_url(server.uri()));
    DropZone::new(zone)
        .handle_drop(handle, client, true, "gemma3:4b", vec![source.clone()])
        .await;

    let suffix = zone.sidecar_suffix();
    let needle = format!(".{suffix}.");
    let deadline = std::time::Instant::now() + Duration::from_secs(20);
    let mut sidecar = None;
    while std::time::Instant::now() < deadline {
        if let Some(found) = std::fs::read_dir(dir.path())
            .unwrap()
            .flatten()
            .find(|e| e.file_name().to_string_lossy().contains(&needle))
        {
            sidecar = Some(found.path());
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let sidecar = sidecar.unwrap_or_else(|| panic!("{zone:?}: no sidecar appeared"));
    let bytes = std::fs::read(&sidecar).expect("read sidecar");
    let text = extract_text_from_bytes(&bytes)
        .expect("sidecar parses")
        .raw
        .as_inner()
        .to_string();

    // Compare source SHA while the file still exists (before `dir` drops).
    let source_unchanged = sha_before == sha256_of(&source);
    drop(dir);

    RunResult {
        zone,
        sidecar_text: text,
        source_unchanged,
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn twelve_zones_concurrent_no_contamination_three_rounds() {
    let cases = zone_cases();
    let all_slugs: Vec<String> = cases.iter().map(|(z, _)| z.slug().to_string()).collect();

    for round in 0..3 {
        let futures: Vec<_> = cases
            .iter()
            .map(|&(zone, fixture_name)| run_one(zone, fixture_name))
            .collect();
        let results = futures::future::join_all(futures).await;

        assert_eq!(results.len(), 12, "round {round}: expected 12 results");

        for r in &results {
            let own = format!("[[ZONE:{}]]", r.zone.slug());
            // Own marker present.
            assert!(
                r.sidecar_text.contains(&own),
                "round {round} {:?}: sidecar missing its own marker",
                r.zone
            );
            // No FOREIGN zone marker — isolation.
            for slug in &all_slugs {
                if *slug == r.zone.slug() {
                    continue;
                }
                let foreign = format!("[[ZONE:{slug}]]");
                assert!(
                    !r.sidecar_text.contains(&foreign),
                    "round {round} {:?}: CONTAMINATED with {foreign}",
                    r.zone
                );
            }
            assert!(
                r.source_unchanged,
                "round {round} {:?}: source changed",
                r.zone
            );
            // Disclaimer zones still carry their disclaimer under load.
            if let Some(d) = r.zone.disclaimer_paragraph() {
                assert!(
                    r.sidecar_text.contains(d),
                    "round {round} {:?}: disclaimer missing under concurrent load",
                    r.zone
                );
            }
        }
        println!("round {round}: 12 zones concurrent, 0 contamination");
    }
}
