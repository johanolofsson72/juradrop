// Spec 027 / FR-015 (/tla GAP-1) — a tier download may run concurrently
// with document processing. There is no automated way to prove "runs at the
// same time" without a real Ollama, but the GUARANTEE is structural: the
// tier-download path shares NO lock or state with the document-generate
// path, so neither can block the other.
//
// This test pins that structural property by reading the module source and
// asserting it never reaches into the zone/dispatch/generate machinery — so
// a future refactor that introduced a shared mutex (and thus a cross-block)
// would trip immediately.

const TIER_DOWNLOAD_SRC: &str = include_str!("../src/settings/tier_download.rs");

#[test]
fn tier_download_does_not_couple_to_the_generate_path() {
    // It may use the Ollama client (to call /api/pull) and the tier map, but
    // it must NOT touch the zones/dispatch/DropZone state where document
    // generation holds its locks — that coupling would let one block the other.
    for forbidden in [
        "zones::",
        "DropZone",
        "dispatch_to_zone",
        "AppState", // the generate path's shared state; tier-download owns its own handle
        "model_status", // the spec-008 bundled-pull gate lives in AppState, not here
    ] {
        assert!(
            !TIER_DOWNLOAD_SRC.contains(forbidden),
            "tier_download.rs references `{forbidden}` — that couples it to the \
             document-generate path and could let a download block inference (FR-015)"
        );
    }
}

#[test]
fn tier_download_owns_its_own_lock_not_a_shared_one() {
    // The slot + cancel token are the ONLY shared mutable state, both local
    // to TierDownloadHandle. Confirm the handle holds its own RwLock rather
    // than borrowing one from elsewhere (so inference's locks are untouched).
    assert!(
        TIER_DOWNLOAD_SRC.contains("slot: RwLock<Option<TierDownloadState>>"),
        "the download slot must be the handle's OWN RwLock"
    );
    assert!(
        TIER_DOWNLOAD_SRC.contains("cancel: RwLock<CancellationToken>"),
        "the cancel token must be the handle's OWN RwLock"
    );
}
