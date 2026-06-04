// Spec 038 T018 / Principle I — the chunked path must not leak document
// content into any log sink. Two layers already hold structurally:
//   1. `OllamaClient::generate` takes `Redacted<String>` — the type system
//      forbids un-redacted prompt content reaching the HTTP layer's logs.
//   2. Chunk/partial strings live only in locals; the snapshot progress
//      hints are integer-only format strings (snapshot.rs contract).
// This test pins the remaining surface with the same static-grep
// discipline as seam_privacy_invariant.rs / telemetry_denylist.rs: no
// print/log macro in the chunked modules may reference document-derived
// bindings.

const CHUNKING_SRC: &str = include_str!("../src/zones/chunking.rs");
const DISPATCH_SRC: &str = include_str!("../src/zones/sammanfatta.rs");
const SCRUB_SRC: &str = include_str!("../src/zones/pii_scrub.rs");

fn production_region(src: &str) -> &str {
    match src.find("#[cfg(test)]") {
        Some(idx) => &src[..idx],
        None => src,
    }
}

#[test]
fn chunking_module_has_no_log_macros_at_all() {
    let prod = production_region(CHUNKING_SRC);
    for needle in ["println!", "eprintln!", "print!", "eprint!", "dbg!"] {
        assert!(
            !prod.contains(needle),
            "chunking.rs production code must not contain {needle} — \
             it handles raw document content (Principle I)"
        );
    }
}

// Spec 039 T003/A1 — the scrub handles RAW PII values; its production code
// must contain no log macro at all (FR-007: matched values never reach a
// log sink; the registry lives and dies on the function's stack).
#[test]
fn pii_scrub_module_has_no_log_macros_at_all() {
    let prod = production_region(SCRUB_SRC);
    for needle in ["println!", "eprintln!", "print!", "eprint!", "dbg!"] {
        assert!(
            !prod.contains(needle),
            "pii_scrub.rs production code must not contain {needle} — \
             it handles raw PII values (Principle I / FR-007)"
        );
    }
}

#[test]
fn dispatch_log_lines_never_reference_document_content_bindings() {
    let prod = production_region(DISPATCH_SRC);
    for (i, line) in prod.lines().enumerate() {
        let is_log = ["println!", "eprintln!", "print!(", "eprint!(", "dbg!"]
            .iter()
            .any(|m| line.contains(m));
        if !is_log {
            continue;
        }
        for banned in [
            "chunk",
            "partial",
            "response_text",
            "prompt",
            "extracted",
            "labeled",
        ] {
            assert!(
                !line.contains(banned),
                "sammanfatta.rs line {}: log macro references document-derived \
                 binding `{banned}` — Principle I violation: {line}",
                i + 1
            );
        }
    }
}

#[test]
fn progress_hints_are_integer_only_format_strings() {
    // The two spec-038 progress hints must not interpolate anything but the
    // loop integers — never a slice of document text.
    let prod = production_region(DISPATCH_SRC);
    assert!(
        prod.contains("\"Bearbetar del {} av {n}…\""),
        "per-part progress hint changed — re-verify it stays content-free"
    );
    assert!(
        prod.contains("\"Sammanställer…\""),
        "combine hint changed — re-verify it stays content-free"
    );
}
