// Spec 011 / T010 — FR-015 telemetry-library denylist.
//
// No crash-reporting / analytics library may appear in the dependency
// tree. Scans exactly 4 manifest files. Case-insensitive matching with
// word-boundary detection — substring `segment` must NOT match inside
// `unicode-segmentation`, etc. A "word boundary" here means the char
// immediately before and after the match is not [a-z0-9_].

use std::path::Path;

const TELEMETRY_DENYLIST: &[&str] = &[
    "sentry",
    "plausible",
    "posthog",
    "mixpanel",
    "segment",
    "amplitude",
    "bugsnag",
    "rollbar",
    "crashlytics",
    "appcenter",
    "datadog",
    "firebase",
    "googleanalytics",
    "matomo",
    "fathom",
    "umami",
    "splitbee",
    "vercel-analytics",
];

#[test]
fn denylist_size_pinned() {
    // Cross-check against spec.allium config telemetry_denylist_size = 18.
    assert_eq!(TELEMETRY_DENYLIST.len(), 18);
}

#[test]
fn no_telemetry_libraries_in_dep_manifests() {
    let repo_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let manifests = [
        Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml"),
        Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.lock"),
        repo_root.join("package.json"),
        repo_root.join("package-lock.json"),
    ];

    let mut violations: Vec<String> = Vec::new();

    for manifest in &manifests {
        if !manifest.exists() {
            // package-lock.json may not exist on a fresh clone; tolerate.
            continue;
        }
        let contents = match std::fs::read_to_string(manifest) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let lower = contents.to_lowercase();
        for needle in TELEMETRY_DENYLIST {
            for (line_no, line) in lower.lines().enumerate() {
                if contains_with_word_boundary(line, needle) {
                    violations.push(format!(
                        "{}:{}: contains telemetry-denylist substring `{}`",
                        manifest.display(),
                        line_no + 1,
                        needle
                    ));
                }
            }
        }
    }

    assert!(
        violations.is_empty(),
        "telemetry-library denylist hit ({} violation{}):\n{}",
        violations.len(),
        if violations.len() == 1 { "" } else { "s" },
        violations.join("\n")
    );
}

/// Word-boundary substring check. Returns true iff `needle` appears in
/// `haystack` with non-alphanumeric, non-underscore characters (or
/// string boundaries) on both sides. Pure Rust, zero dependencies.
/// Both inputs are expected to be lowercase already.
fn contains_with_word_boundary(haystack: &str, needle: &str) -> bool {
    if needle.is_empty() || haystack.len() < needle.len() {
        return false;
    }
    let hb = haystack.as_bytes();
    let nb = needle.as_bytes();
    let mut i = 0usize;
    while i + nb.len() <= hb.len() {
        if &hb[i..i + nb.len()] == nb {
            let before_ok = i == 0 || !is_word_char(hb[i - 1]);
            let after_idx = i + nb.len();
            let after_ok = after_idx == hb.len() || !is_word_char(hb[after_idx]);
            if before_ok && after_ok {
                return true;
            }
        }
        i += 1;
    }
    false
}

fn is_word_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

#[cfg(test)]
mod boundary_self_tests {
    use super::contains_with_word_boundary;

    #[test]
    fn segment_does_not_match_inside_unicode_segmentation() {
        assert!(!contains_with_word_boundary(
            "\"unicode-segmentation\",",
            "segment"
        ));
    }

    #[test]
    fn segment_matches_a_bare_word() {
        assert!(contains_with_word_boundary("name = \"segment\"", "segment"));
    }

    #[test]
    fn segment_matches_with_hyphen_neighbor() {
        // `segment-analytics` should match — segment is a separate word
        // bounded by `-` on the right and `"` on the left.
        assert!(contains_with_word_boundary(
            "\"segment-analytics\":",
            "segment"
        ));
    }

    #[test]
    fn sentry_matches_at_string_start() {
        assert!(contains_with_word_boundary("sentry = \"1.0\"", "sentry"));
    }

    #[test]
    fn empty_haystack_no_match() {
        assert!(!contains_with_word_boundary("", "sentry"));
    }
}
