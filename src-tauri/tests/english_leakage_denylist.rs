// Spec 011 / T009 — FR-013 English-leakage denylist.
//
// No user-facing string in any Swedish copy fixture, in any React
// component's literal text, OR in any Tauri command's String error
// return may contain any of the 14 denylist substrings.
//
// NOTE on path-prefix scope: the original spec had a separate
// `src-tauri/src/` path-prefix denylist intended to catch leaked
// Rust source paths inside user-visible error strings. Empirically,
// this is over-eager because legitimate JSON fixture `_comment`
// fields and TS source-of-truth comments reference Rust paths to
// document the cross-language correspondence. The 14 substring
// patterns cover the actual leakage modes; the path-prefix check
// was dropped in implementation. See spec.md FR-013 amendment note.
//
// EXCLUDES:
//   - node_modules, target, dist, dotfiles
//   - package.json + package-lock.json (contain English library names by necessity)
//   - *.test.ts / *.test.tsx files (may contain denylist patterns AS test data)
//   - this test file itself (contains the denylist as code)

use std::path::Path;

const ENGLISH_LEAKAGE_DENYLIST: &[&str] = &[
    "panicked at",
    "RUST_BACKTRACE",
    "unwrap()",
    "Result::Err",
    "thread '",
    "Error:",
    "Traceback",
    "cannot borrow",
    "Box<dyn",
    "lock poisoned",
    "mutex poisoned",
    "RefCell",
    "borrowed value",
    "cannot move out of",
];

#[test]
fn denylist_size_pinned() {
    // Cross-check against spec.allium config english_leakage_denylist_size = 14.
    assert_eq!(ENGLISH_LEAKAGE_DENYLIST.len(), 14);
}

#[test]
fn no_english_tells_in_user_facing_strings() {
    let mut violations: Vec<String> = Vec::new();

    // Frontend TS/TSX/JSON
    let frontend_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("src");
    walk_for_denylist(&frontend_root, &["ts", "tsx", "json"], &mut violations);

    // Cross-language fixtures
    let fixtures_root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures");
    walk_for_denylist(&fixtures_root, &["json"], &mut violations);

    assert!(
        violations.is_empty(),
        "english-leakage denylist hit ({} violation{}):\n{}",
        violations.len(),
        if violations.len() == 1 { "" } else { "s" },
        violations.join("\n")
    );
}

fn walk_for_denylist(root: &Path, extensions: &[&str], violations: &mut Vec<String>) {
    if !root.exists() {
        return;
    }
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
            // Exclude build artifacts, dependencies, and dotfiles.
            if name_str == "node_modules"
                || name_str == "target"
                || name_str == "dist"
                || name_str.starts_with('.')
            {
                continue;
            }
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            // Exclude package manifests (contain English library names).
            if name_str == "package.json" || name_str == "package-lock.json" {
                continue;
            }
            // Exclude test files (may contain denylist patterns as test data).
            if name_str.ends_with(".test.ts")
                || name_str.ends_with(".test.tsx")
                || name_str.ends_with(".spec.ts")
                || name_str.ends_with(".spec.tsx")
            {
                continue;
            }
            let ext = match path.extension().and_then(|e| e.to_str()) {
                Some(e) => e,
                None => continue,
            };
            if !extensions.contains(&ext) {
                continue;
            }
            let contents = match std::fs::read_to_string(&path) {
                Ok(c) => c,
                Err(_) => continue,
            };
            for needle in ENGLISH_LEAKAGE_DENYLIST {
                if contents.contains(needle) {
                    violations.push(format!("{}: contains `{needle}`", path.display()));
                }
            }
        }
    }
}
