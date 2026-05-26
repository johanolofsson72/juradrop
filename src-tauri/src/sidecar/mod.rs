// JuraDrop sidecar module — spec 002-ollama-sidecar-poc.
//
// Owns the bundled Ollama process lifecycle, the local HTTP client wrapping
// the Ollama API, the user-visible status derivation, the first-launch
// consent persistence, the Tauri command surface exposed to the WebView,
// and the log-safe redaction newtype that enforces FR-012.

pub mod client;
pub mod commands;
pub mod consent;
pub mod disk_space;
pub mod log_safe;
pub mod manager;
pub mod status;

pub use status::{AppStatus, ConsentChoice, ModelStatus, SidecarStatus, UserVisibleStatus};
