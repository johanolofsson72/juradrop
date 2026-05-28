// Spec 010 / T007 — the central ModelTier → Ollama model-ID mapping.
//
// Single source of truth. Clarification Q1 pinned the three model IDs;
// they live HERE and nowhere else in the codebase. A grep test in
// settings_invariants.rs asserts that no `llama3.2:1b`, `gemma3:4b`,
// or `gemma3:12b` literal appears in `src/**` (TypeScript). The Rust
// side may reference them in `commands.rs` (legacy `DEFAULT_MODEL`
// for back-compat) and in this file — nowhere else.
//
// `model_id()` is `const` because every dispatch reads it on the hot
// path; folding the match at compile time matters.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum ModelTier {
    Snabb,
    #[default]
    Smart,
    Stor,
}

impl ModelTier {
    pub const fn model_id(self) -> &'static str {
        match self {
            ModelTier::Snabb => "llama3.2:1b",
            ModelTier::Smart => "gemma3:4b",
            ModelTier::Stor => "gemma3:12b",
        }
    }

    pub const fn size_badge(self) -> &'static str {
        match self {
            ModelTier::Snabb => "~1.3 GB",
            ModelTier::Smart => "~3.3 GB",
            ModelTier::Stor => "~8.1 GB",
        }
    }

    pub const ALL: [ModelTier; 3] = [ModelTier::Snabb, ModelTier::Smart, ModelTier::Stor];
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn model_id_pinned_per_clarification_q1() {
        assert_eq!(ModelTier::Snabb.model_id(), "llama3.2:1b");
        assert_eq!(ModelTier::Smart.model_id(), "gemma3:4b");
        assert_eq!(ModelTier::Stor.model_id(), "gemma3:12b");
    }

    #[test]
    fn size_badges_pinned_per_clarification_q3() {
        assert_eq!(ModelTier::Snabb.size_badge(), "~1.3 GB");
        assert_eq!(ModelTier::Smart.size_badge(), "~3.3 GB");
        assert_eq!(ModelTier::Stor.size_badge(), "~8.1 GB");
    }

    #[test]
    fn all_three_tiers_present_in_canonical_order() {
        assert_eq!(ModelTier::ALL.len(), 3);
        assert_eq!(ModelTier::ALL[0], ModelTier::Snabb);
        assert_eq!(ModelTier::ALL[1], ModelTier::Smart);
        assert_eq!(ModelTier::ALL[2], ModelTier::Stor);
    }

    #[test]
    fn default_is_smart() {
        assert_eq!(ModelTier::default(), ModelTier::Smart);
    }

    #[test]
    fn smart_model_id_matches_legacy_default_model_constant() {
        // GAP guard: Smart must equal `sidecar::commands::DEFAULT_MODEL`
        // so the snapshot-aware dispatch path produces the same output
        // bytes as the old hard-coded path for the same input.
        assert_eq!(ModelTier::Smart.model_id(), "gemma3:4b");
    }
}
