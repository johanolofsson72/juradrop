// Spec 018 — real-Ollama slow suite.
//
// Runs ONE real `gemma3:4b` inference per zone against a local Ollama on
// the committed spec-013 fixtures, asserting shape/presence (sidecar
// created, non-empty, source byte-identical, disclaimer present for
// disclaimer zones). Catches the regression class mocks can't: the Swedish
// system prompts drifting, or a model upgrade changing output shape.
//
// HARDWARE: needs a running Ollama with gemma3:4b on 127.0.0.1:11434.
// Skips cleanly (eprintln + return) when absent, so it never fails a run
// that lacks the model. Ignored by default; run explicitly:
//   cargo test --test real_ollama_zones -- --ignored --nocapture

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

const OLLAMA_URL: &str = "http://127.0.0.1:11434";
const MODEL: &str = "gemma3:4b";

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

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
// HARDWARE: requires a running Ollama + gemma3:4b on 127.0.0.1:11434.
// Skips cleanly when absent. Slow (real inference per zone).
#[ignore = "HARDWARE: requires running Ollama + gemma3:4b on 127.0.0.1:11434"]
async fn all_zones_real_inference_smoke() {
    let probe = OllamaClient::with_base_url(OLLAMA_URL.to_string());
    match probe.list_tags().await {
        Ok(tags) if tags.iter().any(|t| t.starts_with(MODEL)) => {}
        Ok(tags) => {
            eprintln!("[spec-018] skipping — {MODEL} not present (have: {tags:?}). Run `ollama pull {MODEL}`.");
            return;
        }
        Err(e) => {
            eprintln!("[spec-018] skipping — Ollama not responding at {OLLAMA_URL}: {e:?}");
            return;
        }
    }

    for (zone, fixture_name) in zone_cases() {
        let app = mock_builder()
            .plugin(tauri_plugin_shell::init())
            .build(mock_context(noop_assets()))
            .expect("build mock app");
        let handle = app.handle().clone();

        let dir = TempDir::new().expect("tempdir");
        let source = dir.path().join(fixture_name);
        std::fs::copy(fixture(fixture_name), &source).expect("copy fixture");
        let sha_before = sha256_of(&source);

        let client = Arc::new(OllamaClient::with_base_url(OLLAMA_URL.to_string()));
        DropZone::new(zone)
            .handle_drop(handle, client, true, MODEL, vec![source.clone()])
            .await;

        // Real inference can take tens of seconds — be generous.
        let needle = format!(".{}.", zone.sidecar_suffix());
        let deadline = std::time::Instant::now() + Duration::from_secs(120);
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
            tokio::time::sleep(Duration::from_millis(250)).await;
        }
        let sidecar =
            sidecar.unwrap_or_else(|| panic!("{zone:?}: no sidecar after 120s real inference"));

        let bytes = std::fs::read(&sidecar).expect("read sidecar");
        let text = extract_text_from_bytes(&bytes)
            .expect("sidecar parses")
            .raw
            .as_inner()
            .to_string();

        // Loose, non-deterministic-safe assertions.
        assert!(
            text.trim().len() > 20,
            "{zone:?}: real output suspiciously short: {text:?}"
        );
        assert_eq!(
            sha_before,
            sha256_of(&source),
            "{zone:?}: source must be byte-identical after real inference"
        );
        if let Some(d) = zone.disclaimer_paragraph() {
            assert!(
                text.contains(d),
                "{zone:?}: disclaimer paragraph missing from real-inference sidecar"
            );
        }
        eprintln!("[spec-018] {zone:?}: OK ({} chars)", text.len());
    }
}
