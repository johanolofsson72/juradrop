// Spec 050 FR-006 — the ONE frontend statement of how big the default
// (Smart tier) model download is. The Rust tier map owns the canonical
// badge ("~3.3 GB", src-tauri/src/settings/tier_map.rs); a Rust test reads
// this file and fails if the two disagree. Swedish decimal comma in the
// label. Used by the wizard copy, the consent modal and the progress ETA.
export const DEFAULT_MODEL_DOWNLOAD = {
  bytes: 3_300_000_000,
  label: '3,3 GB',
} as const;
