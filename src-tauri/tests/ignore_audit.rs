// Spec 013 SC-004 / FR-013 — every remaining `#[ignore]` attribute in
// the integration test suite MUST carry a `// HARDWARE:` reason comment
// within the 4 lines preceding it. This keeps the un-ignore audit honest:
// a future test cannot be silently `#[ignore]`'d to make CI green without
// declaring WHY it can't run unattended.

use std::fs;
use std::path::Path;

#[test]
fn every_ignored_test_has_a_hardware_reason() {
    let tests_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests");
    let mut offenders: Vec<String> = Vec::new();
    let mut ignore_count = 0usize;

    for entry in fs::read_dir(&tests_dir).expect("read tests dir").flatten() {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("rs") {
            continue;
        }
        let src = fs::read_to_string(&path).expect("read test file");
        let lines: Vec<&str> = src.lines().collect();
        for (i, line) in lines.iter().enumerate() {
            // Only the ATTRIBUTE form (line starts with `#[ignore`), not
            // doc/comment mentions of the word.
            if line.trim_start().starts_with("#[ignore") {
                ignore_count += 1;
                let start = i.saturating_sub(4);
                let window = &lines[start..i];
                let has_reason = window.iter().any(|l| l.contains("// HARDWARE:"));
                if !has_reason {
                    offenders.push(format!(
                        "{}:{} — #[ignore] without a `// HARDWARE:` reason within 4 lines above",
                        path.file_name().unwrap().to_string_lossy(),
                        i + 1
                    ));
                }
            }
        }
    }

    assert!(
        offenders.is_empty(),
        "SC-004 violated — un-justified #[ignore] attributes:\n{}",
        offenders.join("\n")
    );
    // Sanity: after the spec-013 audit exactly one hardware-bound test
    // remains (sidecar_roundtrip). If this drifts, re-run the audit.
    assert_eq!(
        ignore_count, 1,
        "expected exactly 1 #[ignore]'d test after the spec-013 audit, found {ignore_count}"
    );
}
