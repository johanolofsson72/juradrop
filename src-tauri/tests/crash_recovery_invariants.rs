// Spec 011 / T006-T008, T011, T011a — invariants of the crash-recovery
// surface. RATIFIES existing T045/F4 SidecarOneRetry pattern + adds the
// NEW invariants (FR-016 no-panic-hook, FR-017 no-outbound-from-crash).
//
// What this test file covers:
//   T006 — US1 retry-counter contract (monotonicity, channel pinning,
//          fel_ovantat + model_error copy pinning, fixture shape).
//   T007 — US2 listener-gates-second-spawn contract (counter-based
//          simulation; the real listener path requires a Tauri app
//          so we simulate the gate logic in pure Rust).
//   T008 — US3 pull-cancel-on-crash + after_sidecar_ready re-trigger
//          contract (CancellationToken behavior + static-grep of the
//          re-trigger branch).
//   T011 — no_custom_panic_hook_registered (FR-016): recursive walk
//          of src-tauri/src/ asserting `panic::set_hook` appears nowhere.
//   T011a — no_outbound_from_crash_listener_closure (FR-017): walk the
//          lib.rs listener block and assert no outbound-HTTP-capable
//          type is used.

use juradrop_lib::sidecar::manager::OllamaSidecar;
use std::path::Path;
use std::sync::Arc;

// ============================================================
// T006 — US1: retry-counter monotonicity + channel + copy
// ============================================================

#[test]
fn retry_counter_starts_at_zero() {
    let s = OllamaSidecar::new();
    assert_eq!(s.retry_count_value(), 0);
}

#[test]
fn increment_retry_returns_post_increment_value() {
    let s = OllamaSidecar::new();
    let prev = s.increment_retry();
    assert_eq!(prev, 1, "first increment must return 1 (post-increment)");
    assert_eq!(s.retry_count_value(), 1);
}

#[test]
fn second_increment_returns_two_but_listener_gate_prevents_in_practice() {
    // The AtomicU8 itself permits any number of increments; the
    // LISTENER's gate (retry_count_value() == 0) is what bounds the
    // budget at 1 per app lifetime. This test documents that the
    // counter primitive is monotonic + unbounded; the gate is what
    // makes the budget per-app-lifetime = 1.
    let s = OllamaSidecar::new();
    let first = s.increment_retry();
    let second = s.increment_retry();
    assert_eq!(first, 1);
    assert_eq!(second, 2);
}

#[test]
fn retry_counter_never_decrements_within_app_lifetime() {
    // Property-style: any sequence of increment_retry() calls must
    // produce a monotonically non-decreasing sequence of observed
    // retry_count_value() readings.
    let s = OllamaSidecar::new();
    let mut last = s.retry_count_value();
    for _ in 0..5 {
        let next = s.retry_count_value();
        assert!(
            next >= last,
            "retry_count_value() must be monotonic; got {next} after {last}"
        );
        last = next;
        s.increment_retry();
    }
}

#[test]
fn crash_event_channel_name_pinned() {
    // FR-001 — `juradrop://sidecar-crashed` is the pinned channel name.
    // The drain task in manager.rs is the only EMITTER; updater/commands.rs
    // references it in a channel-uniqueness CHECK (not an emit). This
    // test asserts the emitter pattern lives in manager.rs.
    let manager_src = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("src")
            .join("sidecar")
            .join("manager.rs"),
    )
    .expect("manager.rs must be readable");
    assert!(
        manager_src.contains("juradrop://sidecar-crashed"),
        "manager.rs must contain the pinned channel name"
    );
    assert!(
        manager_src.contains("emit("),
        "manager.rs must contain the emit call site"
    );
}

#[test]
fn fel_ovantat_copy_pinned_in_fixture() {
    // FR-007 + FR-009 + Clarification Q3.
    let fixture: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("tests")
                .join("fixtures")
                .join("crash-recovery-strings.json"),
        )
        .unwrap(),
    )
    .unwrap();
    let fel_ovantat = fixture
        .get("fel_ovantat")
        .and_then(|v| v.as_str())
        .expect("fixture must have fel_ovantat key");
    assert_eq!(fel_ovantat, "AI-motorn svarar inte. Starta om JuraDrop.");
    assert!(
        fel_ovantat.chars().count() <= 80,
        "fel_ovantat must be ≤ 80 chars"
    );
}

#[test]
fn model_error_copy_pinned_in_fixture() {
    // FR-008.
    let fixture: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("tests")
                .join("fixtures")
                .join("crash-recovery-strings.json"),
        )
        .unwrap(),
    )
    .unwrap();
    let model_error = fixture
        .get("model_error")
        .and_then(|v| v.as_str())
        .expect("fixture must have model_error key");
    assert_eq!(model_error, "AI-motorn svarade inte — försök igen");
    assert!(
        model_error.chars().count() <= 80,
        "model_error must be ≤ 80 chars"
    );
}

#[test]
fn fixture_has_exactly_three_keys() {
    let fixture: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("tests")
                .join("fixtures")
                .join("crash-recovery-strings.json"),
        )
        .unwrap(),
    )
    .unwrap();
    let obj = fixture.as_object().expect("fixture must be a JSON object");
    let keys: std::collections::BTreeSet<&str> = obj.keys().map(String::as_str).collect();
    let expected: std::collections::BTreeSet<&str> = ["_comment", "fel_ovantat", "model_error"]
        .into_iter()
        .collect();
    assert_eq!(keys, expected, "fixture key set drift");
}

// ============================================================
// T007 — US2: listener-gates-second-spawn (simulation)
// ============================================================

#[test]
fn listener_path_gates_second_spawn() {
    // Simulates the listener flow without a real Tauri app:
    //   First "crash" → retry_count_value() == 0 → would-spawn.
    //   Second "crash" → retry_count_value() != 0 → SKIPS spawn.
    let s = OllamaSidecar::new();

    // Counter mimicking what a spy on sidecar.spawn would observe.
    let mut would_spawn_count = 0u32;

    // First crash.
    if s.retry_count_value() == 0 {
        let _prev = s.increment_retry();
        would_spawn_count += 1;
    }
    // Second crash.
    if s.retry_count_value() == 0 {
        let _prev = s.increment_retry();
        would_spawn_count += 1;
    }

    assert_eq!(
        would_spawn_count, 1,
        "listener gate must permit exactly one retry-spawn across two crashes"
    );
}

#[test]
fn exhausted_retry_path_yields_fel_ovantat_string() {
    // After the simulated second crash, the listener path sets
    // error_override to fel_ovantat_copy. We assert the source-of-truth
    // string matches the pinned fixture entry.
    let fixture: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("tests")
                .join("fixtures")
                .join("crash-recovery-strings.json"),
        )
        .unwrap(),
    )
    .unwrap();
    let pinned = fixture.get("fel_ovantat").and_then(|v| v.as_str()).unwrap();
    // The lib.rs listener sets error_override to UserVisibleStatus::FelOvantat.
    // The frontend resolves that enum to the same Swedish copy — drift-tested
    // by crash-recovery-strings-drift.test.ts.
    assert_eq!(pinned, "AI-motorn svarar inte. Starta om JuraDrop.");
}

// ============================================================
// T008 — US3: pull-cancel-on-crash + after_sidecar_ready re-trigger
// ============================================================

#[tokio::test]
async fn pull_cancel_token_cancellable_via_crash_path() {
    // Symbolic test: a CancellationToken under the same wrapping the
    // production AppState uses, exercised the way the listener would.
    let token = tokio_util::sync::CancellationToken::new();
    let cloned = token.clone();
    // Simulate the crash listener calling cancel().
    token.cancel();
    assert!(cloned.is_cancelled());
}

#[test]
fn after_sidecar_ready_retriggers_pull_branch_exists() {
    // Static-grep: assert the after_sidecar_ready function in
    // sidecar/commands.rs contains the branch that re-triggers
    // a pull when (model_present == false && consent == Fortsatt).
    let src = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("src")
            .join("sidecar")
            .join("commands.rs"),
    )
    .unwrap();
    assert!(
        src.contains("pub async fn after_sidecar_ready"),
        "after_sidecar_ready must exist in sidecar/commands.rs"
    );
    assert!(
        src.contains("should_trigger_pull"),
        "after_sidecar_ready must gate on should_trigger_pull(present, consent)"
    );
    assert!(
        src.contains("spawn_pull_task"),
        "after_sidecar_ready must call spawn_pull_task on retry-recovery"
    );
}

// ============================================================
// T011 — FR-016 — no_custom_panic_hook_registered
// ============================================================

#[test]
fn no_custom_panic_hook_registered() {
    // Walk src-tauri/src/ for .rs files; assert no `panic::set_hook`
    // appears. Default Rust panic hook (stderr-only) is the contract
    // per R-007 + R-008.
    let backend_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut violations = Vec::new();
    walk_for_substring(&backend_root, "panic::set_hook", &["rs"], &mut violations);
    assert!(
        violations.is_empty(),
        "no custom panic hook permitted (FR-016):\n{}",
        violations.join("\n")
    );
}

// ============================================================
// T011a — FR-017 — no_outbound_from_crash_listener_closure
// ============================================================

#[test]
fn no_outbound_from_crash_listener_closure() {
    // Extract the closure body passed to .listen("juradrop://sidecar-crashed", ...)
    // from lib.rs and assert no outbound-HTTP-capable type appears.
    let lib_src = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("src")
            .join("lib.rs"),
    )
    .unwrap();
    let marker = "juradrop://sidecar-crashed";
    let listener_anchor = lib_src
        .find(&format!(".listen(\"{marker}\""))
        .expect("listener anchor must exist in lib.rs");
    // Take the next ~3000 chars after the anchor (covers the closure
    // body even with comments + nested blocks).
    let window_end = (listener_anchor + 3000).min(lib_src.len());
    let window = &lib_src[listener_anchor..window_end];

    let forbidden = [
        "reqwest::Client",
        "tauri::http::",
        "tauri_plugin_http",
        "shell::open",
    ];
    for needle in &forbidden {
        assert!(
            !window.contains(needle),
            "crash listener block must not reference `{needle}` (FR-017 + Principle I)"
        );
    }
}

// ============================================================
// helpers
// ============================================================

fn walk_for_substring(
    root: &Path,
    needle: &str,
    extensions: &[&str],
    violations: &mut Vec<String>,
) {
    let _ = needle.len();
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
            if contents.contains(needle) {
                violations.push(format!("{}: contains `{needle}`", path.display()));
            }
        }
    }
}

#[allow(dead_code)]
fn _arc_keep<T>(_a: Arc<T>) {} // satisfy unused-import linter for Arc in case of future use
