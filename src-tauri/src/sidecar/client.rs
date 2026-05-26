// Ollama HTTP API client (loopback) + registry pull.
// Per spec 002 contracts/ollama-api-usage.md + research.md R-005.

use std::time::Duration;

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
}
