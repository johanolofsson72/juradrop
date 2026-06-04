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
    let _ = run_zone_pipeline_checked(zone, fixture_name, mock_response, markers, &[]).await;
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
) -> String {
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
        .handle_drop(
            handle,
            client,
            true,
            "gemma3:4b",
            vec![source.clone()],
            None,
        )
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

    // Returned so callers can assert ORDER properties the contains-checks
    // above cannot (spec 040 T005: single-part pass-through section order).
    text.to_string()
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

// ===== Spec 038 — chunked-run harness =====================================
//
// Drives a generated .txt document (mirror-output → .txt sidecar, trivially
// inspectable) through the full pipeline against a SEQUENCED wiremock
// responder: the i-th /api/generate request receives the i-th template.
// Records every request body and every ZoneSnapshot emitted on the zone's
// channel so tests can assert request counts, num_ctx, framing, progress
// hints, and all-or-nothing failure semantics.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

use juradrop_lib::zones::{ZoneSnapshot, ZoneState};
use tauri::Listener;
use wiremock::{Request, Respond};

/// Returns the i-th template per request, clamping to the last.
pub struct SeqResponder {
    templates: Vec<ResponseTemplate>,
    counter: AtomicUsize,
}

impl SeqResponder {
    pub fn new(templates: Vec<ResponseTemplate>) -> Self {
        assert!(!templates.is_empty(), "SeqResponder needs >= 1 template");
        Self {
            templates,
            counter: AtomicUsize::new(0),
        }
    }
}

impl Respond for SeqResponder {
    fn respond(&self, _req: &Request) -> ResponseTemplate {
        let i = self.counter.fetch_add(1, Ordering::SeqCst);
        self.templates
            .get(i)
            .or_else(|| self.templates.last())
            .cloned()
            .expect("non-empty templates")
    }
}

/// 200 OK /api/generate body with the given model response text.
pub fn ok_generate(response: &str) -> ResponseTemplate {
    ResponseTemplate::new(200).set_body_json(serde_json::json!({
        "model": "gemma3:4b",
        "response": response,
        "done": true,
    }))
}

pub struct ChunkedSetup {
    pub server: MockServer,
    pub app: tauri::App<tauri::test::MockRuntime>,
    pub dir: TempDir,
    pub source: PathBuf,
    pub zone_obj: Arc<DropZone>,
    pub client: Arc<OllamaClient>,
    pub snapshots: Arc<Mutex<Vec<ZoneSnapshot>>>,
}

impl ChunkedSetup {
    /// Build the harness: temp .txt source with `doc_text`, sequenced
    /// responder, snapshot listener on the zone channel.
    pub async fn new(zone: ZoneId, doc_text: &str, templates: Vec<ResponseTemplate>) -> Self {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/api/generate"))
            .respond_with(SeqResponder::new(templates))
            .mount(&server)
            .await;

        let app = mock_builder()
            .plugin(tauri_plugin_shell::init())
            .build(mock_context(noop_assets()))
            .expect("build mock tauri app");

        let dir = TempDir::new().expect("tempdir");
        let source = dir.path().join("dokument.txt");
        std::fs::write(&source, doc_text).expect("write source txt");

        let zone_obj = DropZone::new(zone);
        let client = Arc::new(OllamaClient::with_base_url(server.uri()));

        let snapshots: Arc<Mutex<Vec<ZoneSnapshot>>> = Arc::new(Mutex::new(Vec::new()));
        let sink = snapshots.clone();
        let channel = format!("juradrop://zone/{}", zone.slug());
        app.handle().listen(channel, move |event| {
            if let Ok(snap) = serde_json::from_str::<ZoneSnapshot>(event.payload()) {
                sink.lock().expect("snapshot sink lock").push(snap);
            }
        });

        Self {
            server,
            app,
            dir,
            source,
            zone_obj,
            client,
            snapshots,
        }
    }

    /// Dispatch the source file onto the zone (sidecar_ready = true).
    pub async fn drop_file(&self) {
        self.drop_file_with_instruction(None).await;
    }

    /// Spec 041 — dispatch with a pinned user instruction (already
    /// normalized; production normalization lives in `dispatch_to_zone`).
    pub async fn drop_file_with_instruction(&self, instruction: Option<String>) {
        self.zone_obj
            .clone()
            .handle_drop(
                self.app.handle().clone(),
                self.client.clone(),
                true,
                "gemma3:4b",
                vec![self.source.clone()],
                instruction,
            )
            .await;
    }

    /// Poll until a sidecar appears OR the zone settles in Error OR the
    /// timeout passes. Returns the sidecar text if one was written.
    pub async fn wait_settled(&self, timeout: Duration) -> Option<String> {
        let needle = format!(".{}.", self.zone_obj.id().sidecar_suffix());
        let deadline = std::time::Instant::now() + timeout;
        while std::time::Instant::now() < deadline {
            if let Some(p) = find_sidecar(self.dir.path(), &needle) {
                return Some(std::fs::read_to_string(p).expect("read txt sidecar"));
            }
            if matches!(self.zone_obj.visible_for_test(), ZoneState::Error) {
                return None;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        None
    }

    /// Spec 041 — like `wait_settled`, but for zones whose .txt input maps
    /// to a .docx sidecar (Generera per spec 013 FR-003): extracts the
    /// document text from the docx bytes instead of reading raw UTF-8.
    pub async fn wait_settled_docx(&self, timeout: Duration) -> Option<String> {
        let needle = format!(".{}.", self.zone_obj.id().sidecar_suffix());
        let deadline = std::time::Instant::now() + timeout;
        while std::time::Instant::now() < deadline {
            if let Some(p) = find_sidecar(self.dir.path(), &needle) {
                let bytes = std::fs::read(p).expect("read docx sidecar");
                let extracted = extract_text_from_bytes(&bytes).expect("sidecar parses as docx");
                return Some(extracted.raw.as_inner().to_string());
            }
            if matches!(self.zone_obj.visible_for_test(), ZoneState::Error) {
                return None;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        None
    }

    /// True iff any sidecar file exists next to the source.
    pub fn sidecar_exists(&self) -> bool {
        let needle = format!(".{}.", self.zone_obj.id().sidecar_suffix());
        find_sidecar(self.dir.path(), &needle).is_some()
    }

    /// Parsed /api/generate request bodies, in arrival order.
    pub async fn generate_bodies(&self) -> Vec<serde_json::Value> {
        self.server
            .received_requests()
            .await
            .unwrap_or_default()
            .iter()
            .filter(|r| r.url.path() == "/api/generate")
            .map(|r| serde_json::from_slice(&r.body).expect("json body"))
            .collect()
    }

    /// Progress hints observed so far, in emission order.
    pub fn progress_hints(&self) -> Vec<String> {
        self.snapshots
            .lock()
            .expect("snapshot lock")
            .iter()
            .filter_map(|s| s.progress_hint.clone())
            .collect()
    }
}

/// A multi-paragraph Swedish-ish document of roughly `target_chars` chars
/// with `sentinels` planted at evenly spread positions (start of evenly
/// spaced paragraphs), so chunk i is guaranteed to contain sentinel i for
/// suitable chunk counts.
pub fn long_doc_with_sentinels(target_chars: usize, sentinels: &[&str]) -> String {
    let para = format!(
        "{} domslutet vann laga kraft.",
        "rättegångsord ".repeat(140)
    );
    let mut paragraphs: Vec<String> = Vec::new();
    let mut chars = 0usize;
    while chars < target_chars {
        paragraphs.push(para.clone());
        chars += para.chars().count() + 2;
    }
    // Plant sentinels at evenly spread paragraph indices; the LAST sentinel
    // goes in the LAST paragraph so end-coverage is directly assertable.
    let n = paragraphs.len();
    for (i, s) in sentinels.iter().enumerate() {
        let idx = if i + 1 == sentinels.len() {
            n - 1
        } else {
            (i * n) / sentinels.len().max(1)
        };
        paragraphs[idx] = format!("{s} {para}");
    }
    paragraphs.join("\n\n")
}
