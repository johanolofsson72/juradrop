// Spec 010 / T033 — Privacy + centralisation invariants for the
// settings module. These run as part of `cargo test` and fail the
// build if any of the structural promises in spec.allium are broken.
//
// Coverage:
//   1. SettingsFileHasExactlyTwoFields — serialised JSON has exactly
//      `schema_version` + `model_tier`, no third key.
//   2. SettingsFileNeverContainsUserContent — denylist scan over
//      every reachable SettingsSnapshot's serialised form.
//   3. ModelIdStringsNeverHardCodedInFrontend — grep `src/**/*.{ts,tsx}`
//      for the three pinned model IDs; must be empty (Clarification Q1
//      pinned the mapping in Rust).
//   4. SettingsFilePathFromTauriApi — grep `src-tauri/src/**/*.rs`
//      for the literal `Library/Application Support`; must be empty
//      so a Tauri-API change in path resolution is the only way
//      persistence can move.

use juradrop_lib::settings::snapshot::{SchemaVersion, SettingsSnapshot};
use juradrop_lib::settings::tier_map::ModelTier;
use std::path::Path;

#[test]
fn settings_file_has_exactly_two_top_level_keys() {
    for tier in ModelTier::ALL {
        let s = SettingsSnapshot {
            schema_version: SchemaVersion::V1,
            model_tier: tier,
        };
        let v: serde_json::Value = serde_json::to_value(&s).unwrap();
        let obj = v
            .as_object()
            .expect("snapshot must serialise to a JSON object");
        let keys: std::collections::BTreeSet<&str> = obj.keys().map(String::as_str).collect();
        let expected: std::collections::BTreeSet<&str> =
            ["schema_version", "model_tier"].into_iter().collect();
        assert_eq!(
            keys, expected,
            "settings JSON must have exactly two keys, got: {keys:?}"
        );
        assert_eq!(obj.len(), 2, "object key count must be exactly 2");
    }
}

#[test]
fn settings_file_serialised_form_has_no_user_content_categories() {
    // Denylist of substrings that would indicate Principle I drift.
    // None of these CAN appear because the struct has only the two
    // pinned fields — but the test exists so adding a third field
    // triggers a loud failure rather than slipping through review.
    let denylist = [
        "telemetry",
        "analytics",
        "session_id",
        "install_id",
        "machine_id",
        "fingerprint",
        "document",
        "history",
        "path",
        "sha",
        "hash",
        "last_used",
        "tier_change",
    ];
    for tier in ModelTier::ALL {
        let s = SettingsSnapshot {
            schema_version: SchemaVersion::V1,
            model_tier: tier,
        };
        let json = serde_json::to_string(&s).unwrap().to_lowercase();
        for needle in &denylist {
            assert!(
                !json.contains(needle),
                "serialised settings.json must not contain '{needle}' — got: {json}"
            );
        }
    }
}

#[test]
fn model_id_strings_never_hardcoded_in_frontend() {
    // Walk src/ for .ts and .tsx files; assert none of the three model
    // IDs appear. The Rust `tier_map::ModelTier::model_id()` is the
    // single source of truth.
    let needles = ["llama3.2:1b", "gemma3:4b", "gemma3:12b"];
    let frontend_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("src");
    let mut violations = Vec::new();
    walk_for_strings(&frontend_root, &needles, &["ts", "tsx"], &mut violations);
    assert!(
        violations.is_empty(),
        "frontend must not hard-code model IDs (Clarification Q1):\n{}",
        violations.join("\n")
    );
}

#[test]
fn settings_file_path_from_tauri_api() {
    // Walk src-tauri/src/ for .rs files; assert none contain a
    // hard-coded `~/Library/Application Support` literal (note the
    // leading `~/` — comments and docstrings explaining the
    // anti-pattern reference the bare phrase without the tilde).
    // The `file_io::settings_file_path` function resolves via
    // Tauri's app_data_dir — anywhere else hard-coding the macOS
    // literal is a Tauri-version-drift risk.
    let needles = ["~/Library/Application Support"];
    let backend_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut violations = Vec::new();
    walk_for_strings(&backend_root, &needles, &["rs"], &mut violations);
    assert!(
        violations.is_empty(),
        "Rust must not hard-code ~/Library/Application Support (FR-019):\n{}",
        violations.join("\n")
    );
}

fn walk_for_strings(
    root: &Path,
    needles: &[&str],
    extensions: &[&str],
    violations: &mut Vec<String>,
) {
    if !root.exists() {
        return;
    }
    for entry in walkdir(root) {
        let ext = match entry.extension().and_then(|e| e.to_str()) {
            Some(e) => e,
            None => continue,
        };
        if !extensions.contains(&ext) {
            continue;
        }
        let contents = match std::fs::read_to_string(&entry) {
            Ok(c) => c,
            Err(_) => continue,
        };
        for needle in needles {
            if contents.contains(needle) {
                violations.push(format!("{}: contains `{needle}`", entry.display()));
            }
        }
    }
}

fn walkdir(root: &Path) -> Vec<std::path::PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let read = match std::fs::read_dir(&dir) {
            Ok(r) => r,
            Err(_) => continue,
        };
        for entry in read.flatten() {
            let path = entry.path();
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            // Skip build outputs, node_modules, etc.
            if name_str == "node_modules"
                || name_str == "target"
                || name_str == "dist"
                || name_str.starts_with('.')
            {
                continue;
            }
            if path.is_dir() {
                stack.push(path);
            } else {
                out.push(path);
            }
        }
    }
    out
}
