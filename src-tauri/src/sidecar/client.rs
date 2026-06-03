// Ollama HTTP API client (loopback) + registry pull.
// Per spec 002 contracts/ollama-api-usage.md + research.md R-005.

use std::time::Duration;

use futures::StreamExt;
use serde::{Deserialize, Serialize};

use super::log_safe::Redacted;

const BASE_URL: &str = "http://127.0.0.1:11434";

/// Maximum tolerated SILENCE (no bytes received) on the `/api/pull` stream
/// before the pull is abandoned as a network failure (spec 034 — spec 027
/// `/tla` GAP-1). This is a per-read / inter-chunk bound that RESETS on every
/// received chunk — NOT a cap on total download duration. 90 s sits far above
/// any realistic inter-chunk gap (progress lines arrive sub-second while bytes
/// flow; even a `verifying sha256 digest` pause is seconds) and far below "the
/// user gave up". Same order of magnitude as the bundled path's 300 s TOTAL cap
/// (`MODEL_PULL_TIMEOUT_SECONDS`, sidecar/commands.rs), but it governs SILENCE,
/// so it cannot fire on a slow-but-progressing large-model pull.
const PULL_STREAM_IDLE_TIMEOUT: Duration = Duration::from_secs(90);

#[derive(Debug, thiserror::Error)]
pub enum ClientError {
    #[error("http error: {0}")]
    Http(String),
    #[error("json error: {0}")]
    Json(String),
    #[error("timeout")]
    Timeout,
    #[error("empty response")]
    EmptyResponse,
    #[error("disk full")]
    DiskFull,
}

#[derive(Debug, Clone)]
pub enum PullEvent {
    /// `completed`/`total` are the raw byte counts from the pull stream.
    /// Spec 008's bundled flow reads only `percent`; spec 027's tier
    /// download uses the bytes to render "5,0 / 8,1 GB". `total == 0`
    /// never reaches here (filtered in `into_event`).
    Progress {
        percent: u8,
        completed: u64,
        total: u64,
    },
    Completed,
    Failed(String),
}

impl From<reqwest::Error> for ClientError {
    fn from(value: reqwest::Error) -> Self {
        if value.is_timeout() {
            ClientError::Timeout
        } else {
            ClientError::Http(value.to_string())
        }
    }
}

impl From<serde_json::Error> for ClientError {
    fn from(value: serde_json::Error) -> Self {
        ClientError::Json(value.to_string())
    }
}

pub struct OllamaClient {
    http: reqwest::Client,
    base_url: String,
}

impl OllamaClient {
    /// Production constructor — targets the loopback Ollama at the
    /// project-wide `BASE_URL`. Principle I requires this to remain
    /// `127.0.0.1`; any change must be reviewed against `.specify/memory
    /// /constitution.md`.
    ///
    /// Spec 013 FR-015 — debug-only test seam: in debug builds ONLY, a
    /// non-empty `JURADROP_OLLAMA_URL` env var overrides the base URL so
    /// the e2e smoke test can point the live construction path at a mock.
    /// Release builds NEVER read the env var (Principle I /
    /// `ReleaseUsesLocalhostOnly`) — the loopback URL is hardcoded.
    pub fn new() -> Self {
        #[cfg(debug_assertions)]
        {
            if let Ok(url) = std::env::var("JURADROP_OLLAMA_URL") {
                if !url.is_empty() {
                    return Self::with_base_url(url);
                }
            }
        }
        Self::with_base_url(BASE_URL.to_string())
    }

    /// Test-only constructor for pointing the client at a mock HTTP server
    /// (e.g. `wiremock::MockServer`). Production code MUST use `new()` so
    /// the loopback invariant cannot be silently broken from a refactor.
    pub fn with_base_url(base_url: String) -> Self {
        let http = reqwest::Client::builder()
            // Spec 026 — 180 s, not 30 s. Local inference on a CPU/GPU-shared
            // Mac legitimately takes minutes for a long generation (Generera
            // produces a full legal text; a cold model adds load time). The
            // old 30 s ceiling surfaced as "AI-motorn svarade inte" on exactly
            // those longer jobs. A 5 s connect timeout still fails fast if the
            // sidecar is genuinely unreachable.
            .timeout(Duration::from_secs(180))
            .connect_timeout(Duration::from_secs(5))
            .build()
            .expect("failed to build reqwest client");
        Self { http, base_url }
    }

    pub async fn list_tags(&self) -> Result<Vec<String>, ClientError> {
        let url = format!("{}/api/tags", self.base_url);
        let resp = self.http.get(&url).send().await?;
        let body: ListTagsResponse = resp.json().await?;
        Ok(body.models.into_iter().map(|m| m.name).collect())
    }

    pub async fn generate(
        &self,
        model: &str,
        prompt: Redacted<String>,
    ) -> Result<Redacted<String>, ClientError> {
        let url = format!("{}/api/generate", self.base_url);
        let body = GenerateRequest {
            model: model.to_string(),
            prompt: prompt.into_inner(),
            stream: false,
        };
        let resp = self.http.post(&url).json(&body).send().await?;
        let parsed: GenerateResponse = resp.json().await?;
        if parsed.response.is_empty() {
            return Err(ClientError::EmptyResponse);
        }
        Ok(Redacted::new(parsed.response))
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    /// Stream `POST /api/pull` and invoke `on_event` for each meaningful
    /// status line (progress percent, completion, or failure).
    ///
    /// Thin delegate to [`OllamaClient::pull_with_idle_timeout`] with the
    /// production [`PULL_STREAM_IDLE_TIMEOUT`]. Both callers — the spec-008
    /// bundled first-run pull and the spec-027 on-demand tier pull — use this
    /// entry point and therefore both inherit the idle guard.
    pub async fn pull(
        &self,
        model: &str,
        on_event: impl FnMut(PullEvent) + Send,
    ) -> Result<(), ClientError> {
        self.pull_with_idle_timeout(model, PULL_STREAM_IDLE_TIMEOUT, on_event)
            .await
    }

    /// `pull` with an injectable idle (read) timeout — the inter-chunk SILENCE
    /// bound.
    ///
    /// Spec 034 (spec 027 `/tla` GAP-1): the registry stream had no read/idle
    /// timeout, so a silently half-open connection blocked `stream.next()`
    /// forever and left a tier download stuck in `downloading` (only Avbryt
    /// escaped). Each `stream.next().await` is now wrapped in
    /// `tokio::time::timeout(idle, …)`; the idle clock RESETS on every received
    /// chunk, so this bounds SILENCE — not total download duration — and a
    /// slow-but-progressing multi-GB pull is never strangled. On elapse we
    /// return [`ClientError::Timeout`], which the tier caller's
    /// `categorise_failure` maps to `DownloadFailure::Network`, handing off to
    /// the existing error → retry path. A 5 s connect timeout still covers the
    /// connect phase. `idle` is a parameter only so tests can inject a short
    /// window; production always passes the 90 s `PULL_STREAM_IDLE_TIMEOUT`.
    pub(crate) async fn pull_with_idle_timeout(
        &self,
        model: &str,
        idle: Duration,
        mut on_event: impl FnMut(PullEvent) + Send,
    ) -> Result<(), ClientError> {
        let url = format!("{}/api/pull", self.base_url);
        let body = PullRequest {
            name: model.to_string(),
            stream: true,
        };
        let http = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(5))
            .build()
            .map_err(ClientError::from)?;
        let resp = http.post(&url).json(&body).send().await?;
        if !resp.status().is_success() {
            return Err(ClientError::Http(format!("pull status {}", resp.status())));
        }
        let mut stream = resp.bytes_stream();
        let mut buf: Vec<u8> = Vec::with_capacity(8 * 1024);
        loop {
            // Idle guard (FR-001/FR-002): each chunk read waits at most `idle`.
            // A silent half-open connection trips this instead of hanging
            // forever; a healthy stream resets the window on every chunk.
            let next = match tokio::time::timeout(idle, stream.next()).await {
                Ok(item) => item,
                Err(_elapsed) => return Err(ClientError::Timeout),
            };
            let Some(chunk) = next else { break };
            let bytes = chunk.map_err(ClientError::from)?;
            buf.extend_from_slice(&bytes);
            while let Some(nl) = buf.iter().position(|b| *b == b'\n') {
                let line: Vec<u8> = buf.drain(..=nl).collect();
                let line_str = std::str::from_utf8(&line[..line.len() - 1])
                    .map_err(|e| ClientError::Json(e.to_string()))?
                    .trim();
                if line_str.is_empty() {
                    continue;
                }
                let parsed: PullLine = serde_json::from_str(line_str)?;
                match parsed.into_event() {
                    Some(PullEvent::Completed) => {
                        on_event(PullEvent::Completed);
                        return Ok(());
                    }
                    Some(PullEvent::Failed(msg)) => {
                        on_event(PullEvent::Failed(msg.clone()));
                        return Err(ClientError::Http(format!("pull failed: {msg}")));
                    }
                    Some(event) => on_event(event),
                    None => {} // Unrecognized / no-numeric-progress status — skip.
                }
            }
        }
        Err(ClientError::EmptyResponse)
    }
}

impl Default for OllamaClient {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Deserialize)]
struct ListTagsResponse {
    models: Vec<TagEntry>,
}

#[derive(Debug, Deserialize)]
struct TagEntry {
    name: String,
}

#[derive(Debug, Serialize)]
struct GenerateRequest {
    model: String,
    prompt: String,
    stream: bool,
}

#[derive(Debug, Deserialize)]
struct GenerateResponse {
    #[allow(dead_code)]
    model: String,
    response: String,
}

#[derive(Debug, Serialize)]
struct PullRequest {
    name: String,
    stream: bool,
}

#[derive(Debug, Deserialize)]
struct PullLine {
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    error: Option<String>,
    #[serde(default)]
    total: Option<u64>,
    #[serde(default)]
    completed: Option<u64>,
}

impl PullLine {
    fn into_event(self) -> Option<PullEvent> {
        // Error envelope wins — Ollama returns `{"error": "..."}` on
        // pull-time failures (e.g. model requires newer Ollama, registry
        // unreachable, manifest invalid).
        if let Some(err) = self.error {
            return Some(PullEvent::Failed(err));
        }
        if self.status.as_deref() == Some("success") {
            return Some(PullEvent::Completed);
        }
        // Numeric progress lines carry both `total` and `completed`. Other
        // status markers ("pulling manifest", "verifying sha256 digest",
        // "writing manifest", "removing any unused layers") are informational
        // and produce no percent — drop them.
        if let (Some(total), Some(done)) = (self.total, self.completed) {
            if total == 0 {
                return None;
            }
            let percent = ((done as u128 * 100) / total as u128).min(100) as u8;
            return Some(PullEvent::Progress {
                percent,
                completed: done,
                total,
            });
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // Env-var tests touch a process-global, so any test that calls
    // `new()` (which reads JURADROP_OLLAMA_URL in debug) must serialize
    // against the seam test. Shared lock; poisoning is irrelevant here.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn client_uses_loopback_base_url() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::remove_var("JURADROP_OLLAMA_URL");
        let c = OllamaClient::new();
        assert!(c.base_url().starts_with("http://127.0.0.1"));
    }

    // Spec 013 FR-015 — debug-only seam: a non-empty JURADROP_OLLAMA_URL
    // overrides the base URL in debug builds; an empty/unset var falls
    // back to the loopback default. (Release behavior — env var always
    // ignored — is asserted structurally by the source-grep invariant in
    // tests/ + the #[cfg(debug_assertions)] gate around the read.)
    #[test]
    fn debug_seam_overrides_base_url_when_env_set() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::set_var("JURADROP_OLLAMA_URL", "http://127.0.0.1:54321");
        let c = OllamaClient::new();
        // In debug builds (cargo test default profile) the seam is active.
        assert_eq!(c.base_url(), "http://127.0.0.1:54321");
        // Empty value must NOT override — falls back to loopback default.
        std::env::set_var("JURADROP_OLLAMA_URL", "");
        let c2 = OllamaClient::new();
        assert_eq!(c2.base_url(), BASE_URL);
        std::env::remove_var("JURADROP_OLLAMA_URL");
    }

    #[test]
    fn generate_only_accepts_redacted_prompt() {
        // Compile-time enforcement: the signature requires Redacted<String>.
        // This test documents the intent.
        fn _accepts(p: Redacted<String>) -> Redacted<String> {
            p
        }
        let _ = _accepts(Redacted::new("hello".into()));
    }

    #[test]
    fn pull_line_success_maps_to_completed() {
        let line: PullLine = serde_json::from_str(r#"{"status":"success"}"#).unwrap();
        assert!(matches!(line.into_event(), Some(PullEvent::Completed)));
    }

    #[test]
    fn pull_line_downloading_maps_to_progress() {
        let line: PullLine = serde_json::from_str(
            r#"{"status":"downloading","digest":"sha256:abc","total":1000,"completed":250}"#,
        )
        .unwrap();
        match line.into_event() {
            // Spec 027 — byte fields now ride along with the percent.
            Some(PullEvent::Progress {
                percent,
                completed,
                total,
            }) => {
                assert_eq!(percent, 25);
                assert_eq!(completed, 250);
                assert_eq!(total, 1000);
            }
            other => panic!("expected Progress(25), got {other:?}"),
        }
    }

    #[test]
    fn pull_line_clamps_overshoot_to_100() {
        let line: PullLine =
            serde_json::from_str(r#"{"status":"downloading","total":100,"completed":150}"#)
                .unwrap();
        match line.into_event() {
            Some(PullEvent::Progress {
                percent, completed, ..
            }) => {
                assert_eq!(percent, 100);
                assert_eq!(completed, 150); // raw bytes preserved even when clamped
            }
            other => panic!("expected Progress(100), got {other:?}"),
        }
    }

    #[test]
    fn pull_line_zero_total_yields_no_event() {
        let line: PullLine =
            serde_json::from_str(r#"{"status":"downloading","total":0,"completed":0}"#).unwrap();
        assert!(line.into_event().is_none());
    }

    #[test]
    fn pull_line_manifest_status_yields_no_event() {
        let line: PullLine = serde_json::from_str(r#"{"status":"pulling manifest"}"#).unwrap();
        assert!(line.into_event().is_none());
    }

    #[test]
    fn pull_line_error_envelope_yields_failed_event() {
        // Real failure mode observed against bundled Ollama 0.5.4 attempting
        // to pull gemma3 (which requires ≥ 0.5.13).
        let raw = r#"{"error":"pull model manifest: 412: \nThe model you are attempting to pull requires a newer version of Ollama.\n"}"#;
        let line: PullLine = serde_json::from_str(raw).unwrap();
        match line.into_event() {
            Some(PullEvent::Failed(msg)) => assert!(msg.contains("newer version of Ollama")),
            other => panic!("expected Failed(...), got {other:?}"),
        }
    }

    #[test]
    fn pull_line_without_status_or_error_yields_no_event() {
        let line: PullLine = serde_json::from_str(r#"{"digest":"sha256:abc"}"#).unwrap();
        assert!(line.into_event().is_none());
    }

    // T044 / FC-014 — design contract: OllamaClient's public API is exactly
    // three operations: list_tags (GET), pull (stream), generate (blocking).
    // The presence of these signatures is enforced by the type system. The
    // ABSENCE of a streaming-inference method (e.g. `generate_stream`,
    // `chat_stream`) is enforced by social contract — if you add one,
    // delete this test along with updating spec.allium FC-014.
    #[test]
    fn public_api_surface_is_blocking_inference_only() {
        // The three permitted methods, by signature. These compile iff the
        // type system allows the call — i.e. the methods exist and accept
        // the expected argument shapes.
        fn _list_tags_signature<'a>(
            c: &'a OllamaClient,
        ) -> impl std::future::Future<Output = Result<Vec<String>, ClientError>> + 'a {
            c.list_tags()
        }
        fn _generate_signature<'a>(
            c: &'a OllamaClient,
            model: &'a str,
            prompt: Redacted<String>,
        ) -> impl std::future::Future<Output = Result<Redacted<String>, ClientError>> + 'a {
            c.generate(model, prompt)
        }
        // pull is callback-driven; we can't take a generic FnMut by-value
        // in a function pointer, so just confirm it's callable here.
        // The returned future is dropped intentionally — this is a
        // compile-time signature check, not a runtime call.
        #[allow(clippy::let_underscore_future)]
        fn _pull_is_callable(c: &OllamaClient) {
            let _ = c.pull("x", |_| {});
        }
        let _ = _list_tags_signature;
        let _ = _generate_signature;
        let _ = _pull_is_callable;
    }

    // ===== Spec 034 — idle/read timeout on the pull stream (spec 027 /tla GAP-1).
    // A silently half-open registry connection used to hang `pull` forever; the
    // inter-chunk idle guard now settles a stalled pull into Err(Timeout) ->
    // DownloadFailure::Network with no user action, while timely chunks reset the
    // idle clock (the bound is SILENCE, not total duration).

    /// One-shot HTTP server: accept a connection, reply with a chunked 200,
    /// flush each NDJSON line in `chunks` spaced `gap` apart, then GO SILENT —
    /// hold the socket open forever without sending the terminating 0-chunk.
    /// Runs on a plain `std::thread` (no tokio `net` feature needed) so it stalls
    /// independently of the async runtime under test. Returns the base URL.
    fn spawn_stall_server(chunks: Vec<String>, gap: std::time::Duration) -> String {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        std::thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            // Drain the request head (small POST; one read is enough to proceed).
            let mut req = [0u8; 2048];
            let _ = sock.read(&mut req);
            sock.write_all(
                b"HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nTransfer-Encoding: chunked\r\n\r\n",
            )
            .unwrap();
            sock.flush().unwrap();
            for line in chunks {
                let payload = format!("{line}\n");
                // One HTTP/1.1 chunk frame: <hex len>CRLF<payload>CRLF.
                let frame = format!("{:x}\r\n{}\r\n", payload.len(), payload);
                if sock.write_all(frame.as_bytes()).is_err() {
                    return;
                }
                let _ = sock.flush();
                std::thread::sleep(gap);
            }
            // Stall: never send `0\r\n\r\n`, never close. Hold the socket open.
            loop {
                std::thread::sleep(std::time::Duration::from_secs(3600));
            }
        });
        format!("http://{addr}")
    }

    // T010 / contract C-1 / SC-001 — a stream that goes silent settles to
    // Err(Timeout) on its own, within a small bound of the idle window.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn idle_stall_returns_timeout() {
        let url = spawn_stall_server(
            vec![r#"{"status":"downloading","total":1000,"completed":100}"#.to_string()],
            std::time::Duration::from_millis(10),
        );
        let client = OllamaClient::with_base_url(url);
        let seen = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let seen_cb = seen.clone();
        let start = std::time::Instant::now();
        let res = client
            .pull_with_idle_timeout("stor", std::time::Duration::from_millis(200), move |_e| {
                seen_cb.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            })
            .await;
        let elapsed = start.elapsed();
        assert!(
            matches!(res, Err(ClientError::Timeout)),
            "expected Err(Timeout), got {res:?}"
        );
        // Self-settled well within a small multiple of the 200 ms idle window.
        assert!(
            elapsed < std::time::Duration::from_secs(2),
            "took {elapsed:?}"
        );
        // The live pre-stall progress line was delivered before the silence.
        assert_eq!(seen.load(std::sync::atomic::Ordering::SeqCst), 1);
    }

    // T011 / contract C-2 / SC-002 — timely chunks RESET the idle clock: nine
    // chunks at gap=100 ms with idle=700 ms. The LAST chunk lands at ~800 ms,
    // i.e. AFTER idle has elapsed in total — so a (hypothetical) total-duration
    // cap of 700 ms would have fired before the 9th chunk and seen ≤ 8. Per-chunk
    // reset means all nine arrive; the error only comes after the final silence.
    // Margins are wide (idle is 7× the gap) so a slow/contended CI runner can't
    // flake it — a single 100 ms server-sleep would have to inflate past 700 ms.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn timely_chunks_reset_idle_clock() {
        let chunks: Vec<String> = (1..=9)
            .map(|i| {
                format!(
                    r#"{{"status":"downloading","total":1000,"completed":{}}}"#,
                    i * 100
                )
            })
            .collect();
        let url = spawn_stall_server(chunks, std::time::Duration::from_millis(100));
        let client = OllamaClient::with_base_url(url);
        let seen = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let seen_cb = seen.clone();
        let res = client
            .pull_with_idle_timeout("stor", std::time::Duration::from_millis(700), move |_e| {
                seen_cb.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            })
            .await;
        // Did NOT time out mid-stream — every timely chunk reset the idle clock,
        // even though the stream ran longer (~800 ms) than the idle window.
        assert_eq!(
            seen.load(std::sync::atomic::Ordering::SeqCst),
            9,
            "idle clock failed to reset on a timely chunk"
        );
        // Then the post-chunk silence (> idle) settles it.
        assert!(
            matches!(res, Err(ClientError::Timeout)),
            "expected Err(Timeout) after final silence, got {res:?}"
        );
    }

    // T012 / contract C-3 / SC-003 — an idle Timeout maps to the EXISTING
    // network failure bucket, so the row shows the existing Swedish message +
    // Försök igen (no new state, no new copy).
    #[test]
    fn idle_timeout_categorises_as_network() {
        use crate::settings::tier_download::{categorise_failure, DownloadFailure};
        assert_eq!(
            categorise_failure(&ClientError::Timeout),
            DownloadFailure::Network
        );
    }
}
