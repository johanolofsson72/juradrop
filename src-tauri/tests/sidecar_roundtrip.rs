// T042 — full sidecar → generate round-trip integration test
// (spec 002 / US3 / FC-008 / research.md R-009).
//
// Marked `#[ignore]` so `cargo test` stays fast — loading `gemma3:4b`
// takes 5–30 s even on warm cache, and the spec is explicit that
// normal test runs MUST not depend on the model being present. Run
// this test explicitly:
//
//     cargo test --test sidecar_roundtrip -- --ignored --nocapture
//
// Acceptance per T042: spawn the bundled Ollama, wait_ready, assert
// `gemma3:4b` is locally present (skip cleanly if not), send the
// hardcoded prompt "Säg hej.", assert a non-empty response within
// 30 s, tear the sidecar down.
//
// Privacy invariant per FR-012 / FR-021: the prompt is wrapped in
// `Redacted<String>` so accidental logging would print `<redacted>`;
// the response length is the only thing we ever assert on (never the
// content). `cargo test -- --ignored --nocapture | grep "hej\|hallå"`
// over the prompt string is expected to come back empty for the
// prompt itself (model output may include "hej" — that's not a
// logging leak, it's the model's emitted text via stdout from any
// caller that decides to print it; our test never prints it).

use std::time::Duration;

use juradrop_lib::sidecar::client::OllamaClient;
use juradrop_lib::sidecar::log_safe::Redacted;
use juradrop_lib::sidecar::manager::OllamaSidecar;
use juradrop_lib::sidecar::status::SidecarStatus;
use tauri::test::{mock_builder, mock_context, noop_assets};

const DEFAULT_MODEL: &str = "gemma3:4b";

/// Detect a pre-existing Ollama on 11434 — the round-trip test cannot
/// proceed if a foreign instance owns the port, because we'd be
/// asserting against its responses rather than the one our manager
/// spawned. Same probe as sidecar_lifecycle.rs.
async fn existing_ollama_responding() -> bool {
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_millis(500))
        .build()
    {
        Ok(c) => c,
        Err(_) => return false,
    };
    matches!(
        client
            .get("http://127.0.0.1:11434/api/tags")
            .send()
            .await
            .map(|r| r.status().is_success()),
        Ok(true)
    )
}

/// Stage the bundled ollama binary into `target/debug/` if it's
/// missing — same logic as sidecar_lifecycle.rs::stage_ollama_binary.
fn stage_ollama_binary() {
    let exe = std::env::current_exe().expect("current_exe");
    let exe_dir = exe.parent().expect("exe parent");
    let base = if exe_dir.ends_with("deps") {
        exe_dir.parent().expect("deps parent").to_path_buf()
    } else {
        exe_dir.to_path_buf()
    };
    let staged = base.join("ollama");
    if staged.exists() {
        return;
    }
    let manifest = env!("CARGO_MANIFEST_DIR");
    let source = std::path::PathBuf::from(manifest)
        .join("binaries")
        .join("ollama-aarch64-apple-darwin");
    assert!(
        source.exists(),
        "bundled ollama binary missing at {source:?} — run scripts/fetch-ollama.sh"
    );
    std::os::unix::fs::symlink(&source, &staged)
        .unwrap_or_else(|e| panic!("symlink {source:?} -> {staged:?} failed: {e}"));
}

/// FC-008 — full round-trip: spawn → wait_ready → generate → stop.
/// Asserts a non-empty Swedish-ish response from `gemma3:4b` within
/// 30 s of issuing the `generate` call. The wall-clock budget covers
/// model load (cold ≤ 30 s on M-series per spec SC-004).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires the bundled Ollama to spawn + gemma3:4b to be locally cached"]
async fn sidecar_roundtrip_gemma3_4b() {
    if existing_ollama_responding().await {
        eprintln!(
            "[T042] skipping sidecar_roundtrip_gemma3_4b — port 11434 is held by \
             another Ollama. Stop it and re-run; otherwise the round-trip would \
             hit that instance, not the one our manager spawned."
        );
        return;
    }

    stage_ollama_binary();

    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();

    let sidecar = OllamaSidecar::new();
    sidecar.spawn(&handle).await.expect("spawn sidecar");
    sidecar
        .wait_ready(Duration::from_secs(10))
        .await
        .expect("wait_ready");
    assert_eq!(sidecar.status(), SidecarStatus::Ready);

    let client = OllamaClient::new();

    // Presence check — skip with a clear message rather than failing
    // a missing-model run, per T042's "SKIP with clear message if not".
    let tags = client.list_tags().await.expect("list_tags");
    if !tags.iter().any(|t| t == DEFAULT_MODEL) {
        eprintln!(
            "[T042] skipping — {DEFAULT_MODEL} is not locally cached \
             (have: {tags:?}). Run `ollama pull {DEFAULT_MODEL}` and re-run."
        );
        sidecar.stop(Duration::from_secs(5)).await.ok();
        return;
    }

    // Round-trip — Swedish prompt per spec. Wrap in Redacted so
    // accidental logging surfaces `<redacted>` rather than the
    // privacy-relevant content.
    let prompt = Redacted::new("Säg hej.".to_string());
    let round_trip = tokio::time::timeout(
        Duration::from_secs(30),
        client.generate(DEFAULT_MODEL, prompt),
    )
    .await
    .expect("generate must complete within 30 s (SC-004 warm budget + cold-load headroom)");

    let response = round_trip.expect("generate ok");
    // Inspecting length is the only assertion — content stays inside
    // the Redacted wrapper. `into_inner` is the documented audit
    // boundary; we use it here once, never log the result.
    let len = response.into_inner().len();
    assert!(
        len > 0,
        "model must produce a non-empty response for a simple Swedish prompt"
    );
    eprintln!("[T042] round-trip ok — response length {len} bytes (content not printed)");

    sidecar.stop(Duration::from_secs(5)).await.expect("stop");
    assert_eq!(sidecar.status(), SidecarStatus::Stopped);
}
