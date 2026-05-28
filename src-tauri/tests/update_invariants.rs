// Spec 007 / GAP-C + GAP-D + GAP-E — coverage tests for three invariants
// that previously had only source-review coverage.
//
//   GAP-C — NoModalDialog: `tauri.conf.json` plugins.updater.dialog == false
//   GAP-D — OnlyManifestAndDmgEndpoints: no new outbound surface in spec 007
//   GAP-E — SingleBackgroundTickTask: structural check that only one
//           `tauri::async_runtime::spawn(updater::tick::run_background_ticker(...))`
//           call exists in the codebase.

use std::path::Path;

fn manifest_dir() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn no_modal_dialog_in_tauri_config() {
    // GAP-D / spec.allium NoModalDialog invariant — the built-in
    // Tauri updater modal MUST NOT activate. If a future PR flips
    // `plugins.updater.dialog` back to `true`, this test fails.
    let config_path = manifest_dir().join("tauri.conf.json");
    let raw = std::fs::read_to_string(&config_path).expect("tauri.conf.json must exist");
    let cfg: serde_json::Value =
        serde_json::from_str(&raw).expect("tauri.conf.json must be valid JSON");

    let dialog = cfg
        .pointer("/plugins/updater/dialog")
        .and_then(|v| v.as_bool())
        .expect("plugins.updater.dialog must be set");
    assert!(
        !dialog,
        "spec 007 NoModalDialog invariant: plugins.updater.dialog MUST be false"
    );
}

#[test]
fn updater_introduces_no_new_outbound_surface() {
    // GAP-E / spec.allium OnlyManifestAndDmgEndpoints invariant —
    // spec 007 must not add a new outbound network call. Every match
    // for an HTTP client constructor in `src/` must live inside the
    // spec 002 sidecar files (`manager.rs`, `client.rs`); spec 007's
    // updater path goes through tauri-plugin-updater, which is not in
    // the grep surface.
    let src_root = manifest_dir().join("src");
    let mut offenders: Vec<String> = Vec::new();
    walk_rust_files(&src_root, &mut |path, contents| {
        let rel = path
            .strip_prefix(manifest_dir())
            .unwrap_or(path)
            .to_string_lossy()
            .to_string();

        // Whitelist: spec 002 sidecar files own every outbound call.
        let is_sidecar_surface =
            rel.contains("sidecar/manager.rs") || rel.contains("sidecar/client.rs");

        for (lineno, line) in contents.lines().enumerate() {
            // Skip comments + doc-comments to avoid false positives from
            // the from_plugin_error string-pattern matching in errors.rs.
            let trimmed = line.trim_start();
            if trimmed.starts_with("//") || trimmed.starts_with("/*") {
                continue;
            }

            let needles = [
                "reqwest::Client::",
                "reqwest::ClientBuilder",
                "hyper::Client",
                "isahc::",
                "tokio::net::TcpStream",
                "tokio::net::UdpSocket",
            ];
            for needle in needles {
                if line.contains(needle) && !is_sidecar_surface {
                    offenders.push(format!("{rel}:{}: {}", lineno + 1, line.trim()));
                }
            }
        }
    });

    assert!(
        offenders.is_empty(),
        "spec 007 OnlyManifestAndDmgEndpoints invariant: \
         new outbound network surface outside the sidecar:\n{}",
        offenders.join("\n")
    );
}

#[test]
fn exactly_one_background_ticker_spawn_in_lib() {
    // GAP-C / spec.allium SingleBackgroundTickTask invariant —
    // structural check that `lib.rs` spawns exactly one tick task.
    // A future refactor that fan-outs to multiple tasks would silently
    // multiply background checks; this test catches that at PR time.
    let lib_rs = manifest_dir().join("src").join("lib.rs");
    let raw = std::fs::read_to_string(&lib_rs).expect("src/lib.rs must exist");
    let occurrences = raw.matches("run_background_ticker(").count();
    assert_eq!(
        occurrences, 1,
        "spec 007 SingleBackgroundTickTask invariant: exactly one call \
         to run_background_ticker(...) must exist in lib.rs; found {occurrences}"
    );
}

/// Walk every `.rs` file under `root`, calling `f(path, contents)` for each.
fn walk_rust_files<F: FnMut(&Path, &str)>(root: &Path, f: &mut F) {
    let entries = match std::fs::read_dir(root) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk_rust_files(&path, f);
        } else if path.extension().and_then(|s| s.to_str()) == Some("rs") {
            if let Ok(contents) = std::fs::read_to_string(&path) {
                f(&path, &contents);
            }
        }
    }
}
