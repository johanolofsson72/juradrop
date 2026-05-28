// Spec 010 — settings panel. Single source of truth for user-tweakable
// preferences (currently just the active model tier). Privacy hard
// constraint: the on-disk file contains EXACTLY two keys
// (`schema_version`, `model_tier`) — never any user content, never any
// telemetry identifier. See contracts/settings-file-schema.md.

pub mod commands;
pub mod file_io;
pub mod snapshot;
pub mod tier_map;
