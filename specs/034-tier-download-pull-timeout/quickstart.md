# Quickstart: Tier-download idle timeout

How to build, test, and manually verify the stalled-pull self-recovery.

## Automated verification (the source of truth)

```bash
# Rust unit + integration tests (includes the new idle-timeout suite)
cd src-tauri && cargo test

# Just the new idle-timeout tests
cd src-tauri && cargo test pull_idle_timeout
cd src-tauri && cargo test idle_stall_returns_timeout timely_chunks_reset_idle_clock idle_timeout_categorises_as_network

# Strict gate (must be clean before "done")
cd src-tauri && cargo clippy --all-targets -- -D warnings && cargo fmt --check
```

### New tests and what they prove

| Test | Proves | SC |
|---|---|---|
| `idle_stall_returns_timeout` | A stream that goes silent settles to `Err(ClientError::Timeout)` within ~the injected idle window — not a hang. | SC-001 |
| `timely_chunks_reset_idle_clock` | N chunks arriving faster than `idle`, then a stall → all N delivered to the callback, error only after the final silence (the clock resets per chunk; total runtime > idle does NOT trip it). | SC-002 |
| `idle_timeout_categorises_as_network` | `categorise_failure(&ClientError::Timeout) == DownloadFailure::Network` → existing network message + `Försök igen`. | SC-003 |

### Tests that must stay green (no regression)

```bash
cd src-tauri && cargo test                 # full suite
# specifically:
#  - the bundled pull total-timeout test (spec 008)          → SC-004
#  - spec-027 tier_download cancel + retry tests             → C-5 / C-7
#  - Principle-I no-outbound / localhost audit tests         → SC-005 / C-8
#  - cross-language string-drift tests (no new keys)         → SC-006
```

## The stall-server test helper

The new tests need a server that opens an HTTP stream and then goes silent mid-body (a half-open / stalled connection) — something `wiremock` cannot do. The helper (in the test module) is roughly:

```rust
async fn spawn_stall_server(chunks: Vec<&'static str>, gap: Duration) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        let (mut sock, _) = listener.accept().await.unwrap();
        // drain the request
        let mut req = [0u8; 1024];
        let _ = sock.read(&mut req).await;
        // status + chunked headers
        sock.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nTransfer-Encoding: chunked\r\n\r\n").await.unwrap();
        sock.flush().await.unwrap();
        for line in chunks {                      // timely chunks (gap < idle) prove reset
            let frame = format!("{:x}\r\n{}\r\n", line.len(), line);
            sock.write_all(frame.as_bytes()).await.unwrap();
            sock.flush().await.unwrap();
            tokio::time::sleep(gap).await;
        }
        // then GO SILENT — hold the socket open, send nothing more
        std::future::pending::<()>().await;
    });
    format!("http://{addr}")
}
```

Usage:

```rust
let url = spawn_stall_server(vec![
    r#"{"status":"pulling","total":100,"completed":10}"#,
], Duration::from_millis(50)).await;
let client = OllamaClient::with_base_url(url);
let mut seen = 0;
let res = client
    .pull_with_idle_timeout("stor", Duration::from_millis(200), |_e| seen += 1)
    .await;
assert!(matches!(res, Err(ClientError::Timeout)));        // C-1 / SC-001
assert_eq!(seen, 1);                                       // the timely chunk was delivered (reset)
```

## Manual verification (real app, optional — for the field)

Idle timeouts are hard to trigger by hand (you need a stalled-but-open connection). The honest manual path:

1. `npm run tauri dev`, open **Inställningar** (gear).
2. On a non-installed tier (e.g. **Stor**), click **Ladda ned**. The row shows progress.
3. Simulate a silent stall: with the registry connection live, drop the network in a way that does NOT reset the socket — e.g. enable a macOS Network Link Conditioner "100% loss" profile, or pull the Wi-Fi on a captive-portal network mid-download.
4. **Expected (after this feature):** within ~90 s the row flips on its own to the network-failure message with **Försök igen** — no Avbryt needed. **Before:** it sat at the last percentage forever.
5. Click **Försök igen** → the download restarts (status → downloading), confirming the existing retry path.

> Note: the 90 s production wait makes manual verification slow by design. The automated `pull_with_idle_timeout` tests (injected ~200 ms) are the authoritative, fast proof of the same behaviour.
