// Sidecar lifecycle integration tests (spec 002 / US1 + US4).
//
// T023 (FC-001 / FC-002) — happy-path spawn → wait_ready → stop.
// T049 (US4 / FR-015)   — missing-binary spawn returns BundledBinaryMissing.
// T050 (US4)            — busy-port spawn returns PortBusy.
//
// All three tests drive the public `OllamaSidecar` API against the bundled
// `ollama` binary that `npm run tauri dev` (or `cargo build`) has staged at
// `target/debug/ollama`. The shell plugin's relative-command-path resolver
// detects `deps/` and climbs one level up — so for `cargo test --test
// sidecar_lifecycle`, `current_exe()` lives in `target/debug/deps/` and the
// binary lookup lands at `target/debug/ollama`. If that file is missing
// (fresh clone, `cargo clean`), `stage_ollama_binary` symlinks the
// repository's `src-tauri/binaries/ollama-<triple>` into place rather than
// burning a confusing `BundledBinaryMissing` error on the user.
//
// Port 11434 is a shared resource: only one test may be poking at it at a
// time, otherwise the spawn / port-busy / port-released assertions race.
// The `PORT_11434_LOCK` static serializes the three tests across tokio's
// multi-threaded test runtime.
//
// Tests skip with a clear log line when 11434 is already busy with a
// foreign Ollama (Homebrew, Ollama.app, parallel `tauri dev`) so the
// developer isn't punished for having the app open while they iterate.

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use juradrop_lib::sidecar::manager::{OllamaSidecar, SidecarError};
use juradrop_lib::sidecar::status::SidecarStatus;
use tauri::test::{mock_builder, mock_context, noop_assets};
use tokio::sync::Mutex;

/// Process-wide serializer for tests that touch port 11434. tokio's test
/// runtime is multi-threaded by default; without this guard, the lifecycle
/// test and the port-busy test would race for the port and produce
/// confusing failures. `tokio::sync::Mutex` (rather than `std::sync` /
/// `parking_lot`) — its guard is safe to hold across `.await`, which the
/// tests below do.
static PORT_11434_LOCK: Mutex<()> = Mutex::const_new(());

/// Ensure the bundled sidecar binary is reachable from the test executable.
/// Returns the resolved binary path for diagnostic logging.
fn stage_ollama_binary() -> PathBuf {
    // tauri-plugin-shell's relative_command_path: if the test exe lives in
    // a `deps/` dir, the base dir climbs one level — so we stage at
    // `target/debug/ollama`, not `target/debug/deps/ollama`.
    let exe = std::env::current_exe().expect("current_exe");
    let exe_dir = exe.parent().expect("exe parent");
    let base = if exe_dir.ends_with("deps") {
        exe_dir.parent().expect("deps parent").to_path_buf()
    } else {
        exe_dir.to_path_buf()
    };
    let staged = base.join("ollama");

    if staged.exists() {
        return staged;
    }

    let manifest = env!("CARGO_MANIFEST_DIR");
    let source = PathBuf::from(manifest)
        .join("binaries")
        .join("ollama-aarch64-apple-darwin");
    assert!(
        source.exists(),
        "bundled ollama binary missing at {source:?} — run scripts/fetch-ollama.sh"
    );

    // Symlink keeps the 75 MB binary out of the test deps dir while still
    // letting the plugin resolve it.
    std::os::unix::fs::symlink(&source, &staged)
        .unwrap_or_else(|e| panic!("symlink {source:?} -> {staged:?} failed: {e}"));
    staged
}

/// Detect any pre-existing Ollama on port 11434. The TCP bind probe alone
/// misses a Homebrew/Ollama.app instance bound to IPv6 `*:11434` because
/// macOS lets us bind IPv4 127.0.0.1:11434 alongside it — and then
/// `wait_ready` would happily reach the *other* process. We probe
/// `/api/tags` over HTTP instead, which catches both stacks.
async fn existing_ollama_responding() -> bool {
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_millis(500))
        .build()
    {
        Ok(c) => c,
        Err(_) => return false,
    };
    matches!(
        client
            .get("http://127.0.0.1:11434/api/tags")
            .send()
            .await
            .map(|r| r.status().is_success()),
        Ok(true)
    )
}

/// FC-001 + FC-002 — spawn → wait_ready → stop, asserting the post-stop
/// invariant that `/api/tags` becomes unreachable within the 5 s grace.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn sidecar_starts_and_stops_cleanly() {
    let _port_guard = PORT_11434_LOCK.lock().await;
    if existing_ollama_responding().await {
        eprintln!(
            "[T023] skipping sidecar_starts_and_stops_cleanly — another Ollama is \
             already serving 127.0.0.1:11434 (likely `npm run tauri dev`, \
             Ollama.app, or `brew services start ollama`). Stop it and re-run \
             to actually exercise the lifecycle."
        );
        return;
    }

    let binary = stage_ollama_binary();
    eprintln!("[T023] staged ollama binary at {binary:?}");

    // MockRuntime app with the shell plugin registered — same plugin path
    // as production lib.rs, just running over the test runtime.
    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();

    let sidecar = OllamaSidecar::new();
    assert_eq!(sidecar.status(), SidecarStatus::NotStarted);

    // FC-001 — spawn + wait_ready(10s).
    sidecar
        .spawn(&handle)
        .await
        .expect("sidecar spawn should succeed when port is free and binary present");
    sidecar
        .wait_ready(Duration::from_secs(10))
        .await
        .expect("sidecar should reach Ready within 10 s");
    assert_eq!(sidecar.status(), SidecarStatus::Ready);

    // Sanity check: /api/tags must be 2xx now (wait_ready already proved
    // this, but we re-probe to anchor the post-stop assertion below).
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(2))
        .build()
        .expect("reqwest client");
    let pre = client
        .get("http://127.0.0.1:11434/api/tags")
        .send()
        .await
        .expect("pre-stop /api/tags reachable");
    assert!(
        pre.status().is_success(),
        "pre-stop /api/tags should be 2xx"
    );

    // FC-002 — stop(5s) and verify the port is released.
    sidecar
        .stop(Duration::from_secs(5))
        .await
        .expect("sidecar stop should succeed");
    assert_eq!(sidecar.status(), SidecarStatus::Stopped);

    let deadline = Instant::now() + Duration::from_secs(5);
    let mut last_err: Option<String> = None;
    let mut released = false;
    while Instant::now() < deadline {
        match client.get("http://127.0.0.1:11434/api/tags").send().await {
            Ok(resp) => {
                last_err = Some(format!("got HTTP {} after stop", resp.status()));
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
            Err(e) => {
                if e.is_connect() || e.is_timeout() {
                    released = true;
                    break;
                }
                last_err = Some(e.to_string());
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }
    assert!(
        released,
        "sidecar port should be released within 5 s of stop \
         (last probe: {last_err:?})"
    );
}

/// Smoke-test the `OllamaSidecar::new` constructor invariants without
/// spawning anything — protects the rest of the file from a regression in
/// the cyclic-weak Arc setup.
#[test]
fn new_returns_arc_with_not_started_status() {
    let sidecar = OllamaSidecar::new();
    assert_eq!(sidecar.status(), SidecarStatus::NotStarted);
    assert_eq!(sidecar.retry_count(), 0);
}

/// RAII helper for T049: rename the staged binary out of the way, restore
/// it on drop so a panicking assertion can't leave the dev tree wedged.
struct BinaryHidden {
    staged: PathBuf,
    backup: PathBuf,
}

impl BinaryHidden {
    fn hide(staged: &Path) -> std::io::Result<Self> {
        let backup = staged.with_extension("bak.t049");
        // Best-effort cleanup of a stale backup from an earlier crashed run.
        let _ = std::fs::remove_file(&backup);
        std::fs::rename(staged, &backup)?;
        Ok(Self {
            staged: staged.to_path_buf(),
            backup,
        })
    }
}

impl Drop for BinaryHidden {
    fn drop(&mut self) {
        if let Err(e) = std::fs::rename(&self.backup, &self.staged) {
            eprintln!(
                "[T049] WARNING: failed to restore staged binary {:?} <- {:?}: {e}",
                self.staged, self.backup
            );
        }
    }
}

/// T049 (US4 / FR-015) — spawning with the bundled binary moved out of the
/// way must surface `SidecarError::BundledBinaryMissing`. The RAII guard
/// restores the file even when the assertion panics, so a failing run
/// doesn't break the next `cargo test` invocation.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn spawn_with_missing_binary_returns_bundled_binary_missing() {
    let _port_guard = PORT_11434_LOCK.lock().await;
    if existing_ollama_responding().await {
        eprintln!(
            "[T049] skipping spawn_with_missing_binary_returns_bundled_binary_missing \
             — port 11434 is held by another Ollama; spawn would short-circuit on \
             PortBusy before reaching the missing-binary code path. Stop it and re-run."
        );
        return;
    }

    let binary = stage_ollama_binary();
    let hidden = BinaryHidden::hide(&binary)
        .unwrap_or_else(|e| panic!("hide staged binary {binary:?}: {e}"));

    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();

    let sidecar = OllamaSidecar::new();
    let result = sidecar.spawn(&handle).await;

    drop(hidden); // Restore before the assertion so a panic still leaves the tree intact.

    match result {
        Err(SidecarError::BundledBinaryMissing) => {}
        other => panic!("expected Err(BundledBinaryMissing), got {other:?}"),
    }
    assert_eq!(sidecar.status(), SidecarStatus::Crashed);
}

/// T050 (US4) — pre-flight port-busy detection. Bind the loopback port
/// ourselves and verify `spawn` returns `PortBusy` without launching a
/// child. The bind may fail if a foreign Ollama already owns the port —
/// that's fine, the manager will still see the port as busy and the
/// assertion holds.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn spawn_when_port_11434_busy_returns_port_busy() {
    let _port_guard = PORT_11434_LOCK.lock().await;
    // Try to own the port for the duration of the test. If something else
    // already has it, that's also a valid PortBusy scenario for the manager.
    let listener = std::net::TcpListener::bind(("127.0.0.1", 11434)).ok();

    if listener.is_none() && !existing_ollama_responding().await {
        // Neither we nor a foreign Ollama hold the port — the manager will
        // see it as free and (correctly) try to spawn. That's not what this
        // test is verifying; skip with context.
        eprintln!(
            "[T050] skipping spawn_when_port_11434_busy_returns_port_busy \
             — couldn't bind 11434 and no foreign Ollama is responding; \
             a non-Ollama TCP listener may be holding the port without \
             answering /api/tags."
        );
        return;
    }

    let app = mock_builder()
        .plugin(tauri_plugin_shell::init())
        .build(mock_context(noop_assets()))
        .expect("build mock tauri app");
    let handle = app.handle().clone();

    let sidecar = OllamaSidecar::new();
    let result = sidecar.spawn(&handle).await;

    drop(listener);

    match result {
        Err(SidecarError::PortBusy) => {}
        other => panic!("expected Err(PortBusy), got {other:?}"),
    }
    assert_eq!(sidecar.status(), SidecarStatus::Crashed);
}
