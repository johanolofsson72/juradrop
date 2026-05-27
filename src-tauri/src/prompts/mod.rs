// Spec 004 — per-zone Swedish system prompts.
//
// One file per zone so each prompt has its own commit history. The
// constants are re-exported here and consumed by
// `crate::zones::ZoneId::system_prompt()`.
//
// All prompts share the FR-021 "no greeting / no meta-commentary"
// guardrail because gemma3:4b without it loves to open with "Här är
// en sammanfattning:" — which then ends up at the top of the user's
// .docx output and looks AI-tinged.

pub mod anonymisera;
pub mod forenkla;
pub mod punktlista;
pub mod sammanfatta;
pub mod tillengelska;
pub mod tillsvenska;

pub use anonymisera::ANONYMISERA_SYSTEM_PROMPT;
pub use forenkla::FORENKLA_SYSTEM_PROMPT;
pub use punktlista::PUNKTLISTA_SYSTEM_PROMPT;
pub use sammanfatta::SAMMANFATTA_SYSTEM_PROMPT;
pub use tillengelska::TILLENGELSKA_SYSTEM_PROMPT;
pub use tillsvenska::TILLSVENSKA_SYSTEM_PROMPT;
