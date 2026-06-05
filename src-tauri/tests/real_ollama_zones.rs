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
        // Spec 043-followup — the suite predated spec 036; all twelve now.
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

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
// HARDWARE: requires a running Ollama + gemma3:4b on 127.0.0.1:11434.
// Skips cleanly when absent. Slow (real inference per zone).
#[ignore = "HARDWARE: requires running Ollama + gemma3:4b on 127.0.0.1:11434"]
async fn all_zones_real_inference_smoke() {
    std::env::set_var("JURADROP_SUPPRESS_OPEN", "1");
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
            .handle_drop(handle, client, true, MODEL, vec![source.clone()], None)
            .await;

        // Real inference can take tens of seconds — be generous. Poll until
        // the sidecar both EXISTS and fully PARSES (the concurrency_stress
        // discipline): accepting it on existence alone races a still-in-
        // flight flush and panics at "sidecar parses" — the exact flake
        // that bit this suite at Anonymisera on 2026-06-05.
        // 300s hang-guard (not a perf bound): a cold/evicted model reload
        // plus real generation legitimately exceeds 120s when other models
        // were recently used on the same machine.
        let needle = format!(".{}.", zone.sidecar_suffix());
        let deadline = std::time::Instant::now() + Duration::from_secs(300);
        let mut text = None;
        let mut last_seen: Option<std::path::PathBuf> = None;
        while std::time::Instant::now() < deadline {
            if let Some(found) = std::fs::read_dir(dir.path()).unwrap().flatten().find(|e| {
                let n = e.file_name().to_string_lossy().to_string();
                !n.starts_with("~$") && !n.starts_with("._") && n.contains(&needle)
            }) {
                last_seen = Some(found.path());
                if let Ok(bytes) = std::fs::read(found.path()) {
                    if let Ok(extracted) = extract_text_from_bytes(&bytes) {
                        text = Some(extracted.raw.as_inner().to_string());
                        break;
                    }
                }
            }
            tokio::time::sleep(Duration::from_millis(250)).await;
        }
        let text = text.unwrap_or_else(|| match last_seen {
            // Distinguish the two failure classes — they have different fixes.
            Some(p) => {
                let keep =
                    std::env::temp_dir().join(format!("juradrop-unparseable-{}.docx", zone.slug()));
                let _ = std::fs::copy(&p, &keep);
                panic!(
                    "{zone:?}: sidecar EXISTS but never parsed within deadline — \
                     PERMANENTLY unparseable output? Copy kept at {keep:?}"
                )
            }
            None => panic!(
                "{zone:?}: NO sidecar appeared within 300s — inference hang or \
                 pipeline failure (check the zone state/error)"
            ),
        });

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

/// Manus validation (2026-06-05, user directive: "validera att allt i
/// testdokumentet verkligen fungerar") — real-model twins of TESTMANUS
/// steps 1–4: chunked long-doc processing, deterministic Anonymisera
/// PII replacement, per-person Kontakter grouping, and instruction
/// threading. Hard assertions only where the guarantee is deterministic;
/// model-quality outcomes are shape-checked.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
// HARDWARE: requires a running Ollama + gemma3:4b on 127.0.0.1:11434.
// Skips cleanly when absent. Slow (multiple real inferences).
#[ignore = "HARDWARE: requires running Ollama + gemma3:4b on 127.0.0.1:11434"]
async fn manus_validation_real_model() {
    std::env::set_var("JURADROP_SUPPRESS_OPEN", "1");
    let probe = OllamaClient::with_base_url(OLLAMA_URL.to_string());
    match probe.list_tags().await {
        Ok(tags) if tags.iter().any(|t| t.starts_with(MODEL)) => {}
        _ => {
            eprintln!("[manus] skipping — Ollama/{MODEL} not available");
            return;
        }
    }

    // ── Steg 1: chunked long doc — parts progress + no truncation note ──
    {
        let app = mock_builder()
            .plugin(tauri_plugin_shell::init())
            .build(mock_context(noop_assets()))
            .expect("build mock app");
        let handle = app.handle().clone();

        // ~50k chars of varied Swedish-ish sections → 3 chunks.
        let mut doc = String::new();
        for i in 0..120 {
            doc.push_str(&format!(
                "Avsnitt {i}. Hovrätten prövar frågan om ersättning för fuktskador i \
                 bjälklaget och huruvida entreprenören förfarit vårdslöst vid utförandet. \
                 Vittnet uppgav att avvikelserapporter upprättades veckovis men inte \
                 alltid distribuerades till beställarens ombud.\n\n"
            ));
        }
        let dir = TempDir::new().expect("tempdir");
        let source = dir.path().join("langt-dokument.txt");
        std::fs::write(&source, &doc).expect("write long doc");

        let hints: Arc<std::sync::Mutex<Vec<String>>> = Arc::new(std::sync::Mutex::new(Vec::new()));
        let sink = hints.clone();
        use tauri::Listener;
        handle.listen("juradrop://zone/sammanfatta", move |event| {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(event.payload()) {
                if let Some(h) = v["progress_hint"].as_str() {
                    sink.lock().expect("hint lock").push(h.to_string());
                }
            }
        });

        let client = Arc::new(OllamaClient::with_base_url(OLLAMA_URL.to_string()));
        DropZone::new(ZoneId::Sammanfatta)
            .handle_drop(handle, client, true, MODEL, vec![source.clone()], None)
            .await;

        let deadline = std::time::Instant::now() + Duration::from_secs(600);
        let sidecar_path = dir.path().join("langt-dokument.sammanfatta.txt");
        while std::time::Instant::now() < deadline && !sidecar_path.exists() {
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
        assert!(sidecar_path.exists(), "steg 1: no sidecar after 600s");
        let text = std::fs::read_to_string(&sidecar_path).expect("read sidecar");
        assert!(
            !text.contains("kortades"),
            "steg 1: truncation note must NOT appear — chunking covers everything"
        );
        let hints = hints.lock().expect("hints").clone();
        assert!(
            hints.iter().any(|h| h.contains("Bearbetar del 1 av")),
            "steg 1: per-part progress missing: {hints:?}"
        );
        assert!(
            hints.iter().any(|h| h.contains("Sammanställer")),
            "steg 1: combine progress missing: {hints:?}"
        );
        eprintln!("[manus] steg 1 (chunked long doc): OK — hints {hints:?}");
    }

    // ── Steg 3: Anonymisera — DETERMINISTIC structured-PII replacement ──
    {
        let app = mock_builder()
            .plugin(tauri_plugin_shell::init())
            .build(mock_context(noop_assets()))
            .expect("build mock app");
        let handle = app.handle().clone();
        let dir = TempDir::new().expect("tempdir");
        let source = dir.path().join("pii.txt");
        std::fs::write(
            &source,
            "Käranden Anna Ek, personnummer 19850312-1234, nås på telefon \
             070-123 45 67 eller via e-post anna.ek@example.se. Hon bor på \
             Storgatan 12 i Lund och yrkar ersättning för utebliven vinst.",
        )
        .expect("write pii doc");

        let client = Arc::new(OllamaClient::with_base_url(OLLAMA_URL.to_string()));
        DropZone::new(ZoneId::Anonymisera)
            .handle_drop(handle, client, true, MODEL, vec![source.clone()], None)
            .await;

        let sidecar_path = dir.path().join("pii.anonymiserad.txt");
        let deadline = std::time::Instant::now() + Duration::from_secs(180);
        while std::time::Instant::now() < deadline && !sidecar_path.exists() {
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
        assert!(sidecar_path.exists(), "steg 3: no sidecar after 180s");
        let text = std::fs::read_to_string(&sidecar_path).expect("read sidecar");
        // DETERMINISTIC (spec 039): raw structured PII is structurally
        // impossible — these are hard assertions, not model hopes.
        assert!(
            !text.contains("19850312-1234"),
            "steg 3: RAW PERSONNUMMER LEAKED"
        );
        assert!(
            !text.contains("070-123 45 67"),
            "steg 3: RAW TELEFON LEAKED"
        );
        assert!(
            !text.contains("anna.ek@example.se"),
            "steg 3: RAW E-POST LEAKED"
        );
        eprintln!("[manus] steg 3 (anonymisera deterministisk): OK");
    }

    // ── Steg 4: Kontakter — per-PERSON grouping shape ────────────────────
    {
        let app = mock_builder()
            .plugin(tauri_plugin_shell::init())
            .build(mock_context(noop_assets()))
            .expect("build mock app");
        let handle = app.handle().clone();
        let dir = TempDir::new().expect("tempdir");
        let source = dir.path().join("kontakter.txt");
        std::fs::write(
            &source,
            "Ombud för käranden är advokat David Dahl, Storgatan 1, 222 22 Lund, \
             telefon 046-12 34 56, e-post david.dahl@example.se. Motpartens ombud \
             är jur.kand. Eva Ek, Lillgatan 9, 211 11 Malmö, telefon 040-98 76 54, \
             e-post eva.ek@example.se.",
        )
        .expect("write kontakter doc");

        let client = Arc::new(OllamaClient::with_base_url(OLLAMA_URL.to_string()));
        DropZone::new(ZoneId::Kontakter)
            .handle_drop(handle, client, true, MODEL, vec![source.clone()], None)
            .await;

        let sidecar_path = dir.path().join("kontakter.kontakter.txt");
        let deadline = std::time::Instant::now() + Duration::from_secs(180);
        while std::time::Instant::now() < deadline && !sidecar_path.exists() {
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
        assert!(sidecar_path.exists(), "steg 4: no sidecar after 180s");
        let text = std::fs::read_to_string(&sidecar_path).expect("read sidecar");
        assert!(
            text.contains("## "),
            "steg 4: expected per-person '## ' headings, got: {text:?}"
        );
        assert!(
            !text.contains("## Namn") && !text.contains("## Adresser"),
            "steg 4: CATEGORY grouping detected — spec 040 regression: {text:?}"
        );
        eprintln!("[manus] steg 4 (kontakter per person): OK");
    }

    // ── Steg 2 (omskrivet): instruction threading on a real run ─────────
    {
        let app = mock_builder()
            .plugin(tauri_plugin_shell::init())
            .build(mock_context(noop_assets()))
            .expect("build mock app");
        let handle = app.handle().clone();
        let dir = TempDir::new().expect("tempdir");
        let source = dir.path().join("fokus.txt");
        std::fs::write(
            &source,
            "Domstolen behandlade tre frågor: preskription av fordran, \
             skadestånd för utebliven vinst om 1 450 000 kr på grund av \
             vårdslös projektering, samt rättegångskostnadernas fördelning. \
             Skadeståndsfrågan avgjordes till kärandens fördel sedan \
             vårdslöshet styrkts genom teknisk bevisning.",
        )
        .expect("write fokus doc");

        let client = Arc::new(OllamaClient::with_base_url(OLLAMA_URL.to_string()));
        DropZone::new(ZoneId::Sammanfatta)
            .handle_drop(
                handle,
                client,
                true,
                MODEL,
                vec![source.clone()],
                Some("fokusera på skadeståndsfrågan".to_string()),
            )
            .await;

        let sidecar_path = dir.path().join("fokus.sammanfatta.txt");
        let deadline = std::time::Instant::now() + Duration::from_secs(180);
        while std::time::Instant::now() < deadline && !sidecar_path.exists() {
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
        assert!(sidecar_path.exists(), "steg 2: no sidecar after 180s");
        let text = std::fs::read_to_string(&sidecar_path)
            .expect("read sidecar")
            .to_lowercase();
        // Shape assertion: the steered topic is present (obedience is
        // best-effort by contract; total absence would be suspicious).
        assert!(
            text.contains("skadestånd") || text.contains("ersättning"),
            "steg 2: focus topic absent from steered summary: {text:?}"
        );
        eprintln!("[manus] steg 2 (instruction threading): OK");
    }
}
