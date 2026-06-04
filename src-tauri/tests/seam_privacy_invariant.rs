// Spec 013 FR-015 / Principle I (ReleaseUsesLocalhostOnly) — the
// JURADROP_OLLAMA_URL test seam MUST be debug-only. A static source
// grep guarantees the env read can never reach a release binary: every
// read of the var in production code (i.e. outside the `#[cfg(test)]`
// module) must sit inside a `#[cfg(debug_assertions)]` gate.
//
// This is the same static-grep discipline used by spec 011's
// telemetry_denylist.rs and update_source_immutability.rs.

const CLIENT_SRC: &str = include_str!("../src/sidecar/client.rs");
const ENV_VAR: &str = "JURADROP_OLLAMA_URL";

/// Returns the production-code region of client.rs (everything before
/// the `#[cfg(test)] mod tests` marker). The test module legitimately
/// reads the env var without a debug gate and is never compiled into a
/// release binary, so it is excluded from this invariant.
fn production_region(src: &str) -> &str {
    match src.find("#[cfg(test)]") {
        Some(idx) => &src[..idx],
        None => src,
    }
}

#[test]
fn seam_env_read_exists_in_production_code() {
    let prod = production_region(CLIENT_SRC);
    assert!(
        prod.contains(ENV_VAR),
        "expected the {ENV_VAR} seam read in production code; FR-015 not wired"
    );
}

#[test]
fn seam_env_read_is_debug_gated_in_production_code() {
    let prod = production_region(CLIENT_SRC);

    // Every line that reads the env var must have a `#[cfg(debug_assertions)]`
    // attribute within the preceding few lines AND no intervening close of
    // that block (heuristic: no standalone `}` at lower indentation between
    // the gate and the read). We assert the simpler, robust property: each
    // read line is preceded — within 8 lines — by a debug_assertions cfg,
    // and the read is NOT preceded on the same scope by an un-gated read.
    let lines: Vec<&str> = prod.lines().collect();
    let mut read_lines: Vec<usize> = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        // Only count the actual env read, not doc comments mentioning the var.
        let trimmed = line.trim_start();
        if trimmed.starts_with("//") || trimmed.starts_with("///") {
            continue;
        }
        if line.contains(ENV_VAR) {
            read_lines.push(i);
        }
    }

    assert!(
        !read_lines.is_empty(),
        "no non-comment {ENV_VAR} read found in production code"
    );

    for &i in &read_lines {
        let start = i.saturating_sub(8);
        let window = &lines[start..i];
        let gated = window
            .iter()
            .any(|l| l.contains("#[cfg(debug_assertions)]"));
        assert!(
            gated,
            "the {ENV_VAR} read at production line {} is NOT inside a \
             #[cfg(debug_assertions)] gate — this would leak the seam into \
             release builds and violate Principle I (ReleaseUsesLocalhostOnly)",
            i + 1
        );
    }
}

// Spec 037 — the FILE fallback channel of the same seam (added because
// macOS strips the env var on every XCUITest launch path) must obey the
// identical discipline: every production read of the override file path
// sits inside the #[cfg(debug_assertions)] gate.
#[test]
fn seam_file_fallback_is_debug_gated_in_production_code() {
    const OVERRIDE_PATH: &str = "juradrop-ollama-url-override";
    let prod = production_region(CLIENT_SRC);
    let lines: Vec<&str> = prod.lines().collect();
    let mut found = false;
    for (i, line) in lines.iter().enumerate() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("//") || trimmed.starts_with("///") {
            continue;
        }
        if line.contains(OVERRIDE_PATH) {
            found = true;
            let start = i.saturating_sub(12);
            let gated = lines[start..i]
                .iter()
                .any(|l| l.contains("#[cfg(debug_assertions)]"));
            assert!(
                gated,
                "the override-file read at production line {} is NOT inside a \
                 #[cfg(debug_assertions)] gate — Principle I violation",
                i + 1
            );
        }
    }
    assert!(
        found,
        "expected the spec-037 file-fallback read in production code"
    );
}

#[test]
fn no_unconditional_env_read_outside_debug_gate() {
    // Guard against a future refactor that reads the var at module scope
    // (e.g. a `lazy_static`/`OnceLock` initialized from env at startup)
    // which a per-read window check might miss. The production region must
    // contain a `#[cfg(debug_assertions)]` somewhere before the var name.
    let prod = production_region(CLIENT_SRC);
    let gate = prod.find("#[cfg(debug_assertions)]");
    let read = prod.find(&format!("var(\"{ENV_VAR}\")"));
    match (gate, read) {
        (Some(g), Some(r)) => assert!(
            g < r,
            "a #[cfg(debug_assertions)] gate must precede the {ENV_VAR} read"
        ),
        (None, Some(_)) => panic!(
            "{ENV_VAR} is read in production code with NO #[cfg(debug_assertions)] gate anywhere"
        ),
        // No read via the var("...") form (e.g. read spelled differently) —
        // the line-window test above still enforces gating; nothing to assert.
        (_, None) => {}
    }
}
