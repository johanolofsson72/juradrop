// Ollama HTTP API client (loopback) + registry pull.
// Per spec 002 contracts/ollama-api-usage.md + research.md R-005.

use std::time::Duration;

use futures::StreamExt;
use serde::{Deserialize, Serialize};

use super::log_safe::Redacted;

const BASE_URL: &str = "http://127.0.0.1:11434";

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
    Progress { percent: u8 },
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
}

impl OllamaClient {
    pub fn new() -> Self {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(5))
            .build()
            .expect("failed to build reqwest client");
        Self { http }
    }

    pub async fn list_tags(&self) -> Result<Vec<String>, ClientError> {
        let url = format!("{}/api/tags", BASE_URL);
        let resp = self.http.get(&url).send().await?;
        let body: ListTagsResponse = resp.json().await?;
        Ok(body.models.into_iter().map(|m| m.name).collect())
    }

    pub async fn generate(
        &self,
        model: &str,
        prompt: Redacted<String>,
    ) -> Result<Redacted<String>, ClientError> {
        let url = format!("{}/api/generate", BASE_URL);
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

    pub fn base_url(&self) -> &'static str {
        BASE_URL
    }

    /// Stream `POST /api/pull` and invoke `on_event` for each meaningful
    /// status line (progress percent, completion, or failure).
    ///
    /// Uses a fresh `reqwest::Client` without the 30 s default timeout, since
    /// registry pulls can take minutes. A 5 s connect timeout still applies so
    /// a missing sidecar fails fast. The per-chunk read inherits Tokio's
    /// blocking semantics — a stalled connection will surface via the
    /// `bytes_stream()` adapter rather than a hard timer.
    pub async fn pull(
        &self,
        model: &str,
        mut on_event: impl FnMut(PullEvent) + Send,
    ) -> Result<(), ClientError> {
        let url = format!("{}/api/pull", BASE_URL);
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
        while let Some(chunk) = stream.next().await {
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
            return Some(PullEvent::Progress { percent });
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_uses_loopback_base_url() {
        let c = OllamaClient::new();
        assert!(c.base_url().starts_with("http://127.0.0.1"));
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
            Some(PullEvent::Progress { percent }) => assert_eq!(percent, 25),
            other => panic!("expected Progress(25), got {other:?}"),
        }
    }

    #[test]
    fn pull_line_clamps_overshoot_to_100() {
        let line: PullLine = serde_json::from_str(
            r#"{"status":"downloading","total":100,"completed":150}"#,
        )
        .unwrap();
        match line.into_event() {
            Some(PullEvent::Progress { percent }) => assert_eq!(percent, 100),
            other => panic!("expected Progress(100), got {other:?}"),
        }
    }

    #[test]
    fn pull_line_zero_total_yields_no_event() {
        let line: PullLine = serde_json::from_str(
            r#"{"status":"downloading","total":0,"completed":0}"#,
        )
        .unwrap();
        assert!(line.into_event().is_none());
    }

    #[test]
    fn pull_line_manifest_status_yields_no_event() {
        let line: PullLine =
            serde_json::from_str(r#"{"status":"pulling manifest"}"#).unwrap();
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
}
