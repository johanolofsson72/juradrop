# Phase 0 — Research: Ollama Sidecar PoC

## R-001 — Where does the bundled Ollama binary come from, and which version?

**Decision**: Pin to **Ollama v0.24.0**. Fetch via `scripts/fetch-ollama.sh`, which:
1. Downloads `Ollama-darwin.zip` from `https://github.com/ollama/ollama/releases/download/v0.24.0/Ollama-darwin.zip` over HTTPS.
2. Extracts the inner `Ollama.app/Contents/Resources/ollama` server binary.
3. Verifies SHA-256 against a pinned hash committed in `scripts/fetch-ollama.sh`.
4. Places the binary at `src-tauri/binaries/ollama-aarch64-apple-darwin` (Tauri's sidecar naming convention).
5. Runs `chmod +x` on the binary.

**Rationale**: Building Ollama from Go source would be reproducible but adds a Go toolchain prerequisite that contradicts spec 001's "Node + Rust only" stack. The upstream release is signed by the Ollama project; we re-sign at spec 006 under our Developer ID. The hash pin gives supply-chain integrity at this spec without needing a vendored Go build.

**Version history**:
- Originally pinned to v0.5.4 during initial spec drafting. v0.5.4 returned HTTP 412 on `POST /api/pull` for `gemma3:*` with body `"requires a newer version of Ollama"`, blocking model pull. Bumped to v0.24.0 (2026-05-26) which supports the full current model catalogue including gemma3.

**Alternatives considered**:
- *Build from source* — reproducible, adds Go toolchain to prerequisites. Rejected to keep dev setup small.
- *Use the Homebrew binary* — violates Principle II (zero-CLI install) and ties dev to brew. Rejected.
- *Use a forked / minimal Ollama* — engineering effort with no spec-002 benefit. Rejected.

## R-002 — Tauri sidecar configuration shape

**Decision**: Use the official `tauri-plugin-shell` plugin (v2.x) with `externalBin` declared in `tauri.conf.json`.

`tauri.conf.json` gets:
```jsonc
{
  "bundle": {
    "externalBin": ["binaries/ollama"]
  },
  "plugins": {
    "shell": {
      "open": false,
      "scope": []
    }
  }
}
```

The `externalBin` entry tells Tauri to bundle `src-tauri/binaries/ollama-<target-triple>` and Tauri 2.x resolves the right one at build time. In code we spawn via `app.shell().sidecar("ollama")`.

The empty `scope: []` for the shell plugin means: only the bundled sidecar can be spawned. Arbitrary shell commands stay denied.

**Rationale**: Tauri's sidecar API is the canonical way to handle a bundled binary; it integrates with code signing, capability gating, and quit-on-close lifecycle. Hand-rolling with `std::process::Command` would lose the signing tie-in and require manual capability config.

**Alternatives considered**:
- *Use `std::process::Command` directly* — works but bypasses capabilities; rejected.
- *Run Ollama as a launchd agent that JuraDrop pings* — violates Principle IV (no daemon). Rejected hard.

## R-003 — Sidecar startup signal — how do we know Ollama is "ready"?

**Decision**: Poll `GET http://127.0.0.1:11434/api/tags` every 200 ms with a 10-second timeout (SC-001). The first 2xx response means Ollama's HTTP server is up. The endpoint is cheap, always available, and doubles as the model-presence check we need next.

**Rationale**: Ollama doesn't write a `ready` signal to stderr or stdout reliably across versions. Polling the health surface is the version-agnostic way. 200 ms keeps total polling overhead under 50 polls.

**Alternatives considered**:
- *Parse stdout for `Listening on …`* — fragile across Ollama versions.
- *Read a Unix-domain socket signal* — Ollama doesn't expose one.

## R-004 — Loopback-only binding enforcement

**Decision**: Set `OLLAMA_HOST=127.0.0.1:11434` as a child-process environment variable when spawning the sidecar. Also set `OLLAMA_ORIGINS=` (empty) to deny browser-origin CORS just in case. Verify at runtime by snapshotting the sidecar's listening sockets via `lsof -p <pid> -i -P -n` (in the destructive test DT-010 equivalent).

**Rationale**: `OLLAMA_HOST` is the official Ollama env var for bind address; honoring it is documented. Snapshot verification gives us a test path that doesn't rely on inspecting Ollama internals.

**Alternatives considered**:
- *Firewall rule (pf.conf)* — requires sudo; nope.
- *Trust Ollama's default* — defaults are not contractual; pin explicitly.

## R-005 — Model presence check & pull API

**Decision**: Use Ollama's HTTP API:
- `GET /api/tags` — returns `{ models: [{ name: "gemma3:4b", ... }, ...] }`. Presence = the default tag appears in `name`.
- `POST /api/pull` with `{ name: "gemma3:4b", stream: true }` — emits a stream of `{ status, total, completed }` lines as NDJSON. We parse the stream, report progress, terminate on `{ status: "success" }`.

**Rationale**: These are the documented Ollama endpoints. NDJSON streaming for `/api/pull` is the only sensible way to get progress updates; "blocking" (per FR-021) refers to *inference*, not to *pull*. The pull endpoint inherently streams progress and that's not what FR-021 was carving out.

**Clarification of FR-021 scope**: FR-021 says "inference calls" use blocking `/api/generate`. The pull stream is a different API surface (download progress, not token generation) and is allowed to be NDJSON-streamed. This nuance is captured here so the implementer doesn't try to apply "blocking" to `/api/pull` and end up with a broken progress UI.

**Alternatives considered**:
- *Use `/api/show` instead of `/api/tags`* — also works but `/api/tags` is the lightest call.

## R-006 — Consent persistence shape

**Decision**: A JSON file at `app_data_dir()/consent.json`:
```json
{
  "schemaVersion": 1,
  "choice": "fortsatt" | "avbryt",
  "askedAt": "2026-05-26T12:34:56Z"
}
```

Written atomically (write to `consent.json.tmp`, fsync, rename). Read on launch. Absent file → consent state `not_asked`.

**Rationale**: One field per row, human-inspectable, version-tagged so spec 010 (settings) can extend without breaking. Atomic write avoids partial-state corruption on power loss / crash mid-write.

**Alternatives considered**:
- *macOS `UserDefaults` via Tauri plugin* — adds a plugin dependency for one bool+timestamp. Overkill.
- *Sqlite* — same; overkill.

## R-007 — Log redaction for prompts and responses (FR-012 enforcement)

**Decision**: All inference paths (the `client.rs` module) route prompt/response strings through `log_safe::Redacted<T>` — a newtype wrapper whose `Debug` and `Display` impls return `"<redacted>"` regardless of content. The reqwest call wraps prompt and response in this newtype before any `tracing::info!` / `tracing::debug!` / `eprintln!` call. The compiler enforces it: there's no path that prints raw prompt/response because the function signature returns `Redacted<String>`.

Additionally, in dev profile only, a single `tracing::trace!` line MAY log the **length** of prompt/response (no content) to aid debugging.

**Rationale**: Static enforcement (newtype around the value) is stronger than convention. The compiler refuses to log content because the type itself prints redacted.

**Alternatives considered**:
- *Manual redaction at each log site* — works only if every developer remembers; rejected.
- *Strip via log filter at the slog/tracing layer* — works at runtime but is bypassed by `println!` / `eprintln!`; rejected.

## R-008 — Capability allowlist additions

**Decision**: `src-tauri/capabilities/default.json` gets exactly these new permissions (additive to spec 001's empty allowlist):

```json
{
  "permissions": [
    "shell:allow-execute",
    "shell:allow-kill",
    {
      "identifier": "shell:allow-spawn",
      "allow": [{ "name": "ollama", "sidecar": true }]
    },
    "event:default",
    "core:app:default"
  ]
}
```

Plus the four custom Tauri commands the WebView invokes (`get_status`, `give_consent`, `cancel_consent`, `run_roundtrip_dev`) which Tauri 2.x auto-grants to capabilities targeting the main window unless an explicit deny rule exists.

The `shell:*` permissions are SCOPED to the `ollama` sidecar binary — they grant nothing else. The WebView cannot use these to spawn arbitrary processes.

**Rationale**: Minimal additive surface. No filesystem capability granted (Ollama manages its own storage). No HTTP capability granted to the WebView (Rust core does HTTP, not the WebView).

**Alternatives considered**:
- *Grant `http:default`* — would let the WebView fetch arbitrary URLs. Violates Principle I; rejected.

## R-009 — Round-trip integration test design

**Decision**: A Rust integration test at `src-tauri/tests/sidecar_roundtrip.rs`, marked `#[ignore]`, that:
1. Spawns the sidecar (sharing the `manager.rs` lifecycle code).
2. Waits up to 10 s for `/api/tags` to return 2xx.
3. Asserts `gemma3:4b` is in `tags.models` (test SKIPs with a clear message if not — the test environment is expected to have the model present).
4. Sends `POST /api/generate` with prompt `"Säg hej."` and `stream: false`.
5. Asserts the response body's `response` field is non-empty.
6. Tears down the sidecar.

Total runtime with warm model: < 30 s (SC-004). With cold model: < 60 s. The `#[ignore]` flag keeps `cargo test` fast for normal dev work; CI runs `cargo test -- --ignored` separately when the model is provisioned.

**Rationale**: Integration tests fit Rust's `tests/` convention. `#[ignore]` is the standard way to mark "expensive opt-in" tests.

**Alternatives considered**:
- *Dev-only Tauri command exposed in the UI* — would require user interaction to verify; less reproducible. Rejected.

## R-010 — Failure paths and one-retry semantics

**Decision**: When the sidecar exits unexpectedly (RunEvent indicates child terminated while we expected `ready`), the manager:
1. Captures `crashed` state, surfaces `fel_ovantat` user-visible status.
2. Increments a per-app-session retry counter.
3. If `retry_count == 0`, attempts one re-spawn (SidecarOneRetry rule).
4. If retry also fails, holds the error status until next app launch. No further automatic retries — that's spec 011's full recovery logic.

The retry counter is per-app-session (not persisted) so quitting and re-launching gets a fresh retry budget.

**Rationale**: One retry handles transient failures (e.g., the sidecar lost a port race with another short-lived process) without becoming a fork-bomb. Persisting retry counts would create a "stuck" state requiring user intervention.

## R-011 — Bundling considerations: signing, notarization, Gatekeeper

**Decision**: At this spec the bundled binary is **unsigned**. Spec 006 introduces the signing pipeline. Until then:
- The dev `tauri dev` flow runs the binary directly — no Gatekeeper involvement.
- The release `tauri build` flow bundles the unsigned binary inside the unsigned `.app` — Gatekeeper warns and requires right-click → Open on the outer `.app` (spec 001 DT-003).
- Once inside the `.app`, the unsigned sidecar runs without further Gatekeeper friction (macOS trusts child processes of a user-approved app within the same bundle).

**Rationale**: Splitting signing into a separate spec (006) avoids dragging Apple Developer enrollment into the PoC scope. The PoC works locally and on developer machines today.

## R-012 — Default model choice: `gemma3:4b`

**Decision**: Default model is `gemma3:4b` (already chosen in `project_juradrop` memory and spec.md FR-006). ~3.3 GB on disk, ~5-6 GB RAM during inference, instruction-tuned, decent on Swedish out of the box.

**Rationale**: Best Swedish quality in the small-model class. `llama3.2:3b` is comparable but slightly weaker on Swedish per quick spot-checks during project inception. Model swap to `llama3.2:3b` (or another) is a one-line change in `config.default_model_tag`.

**Alternatives considered**:
- *`llama3.2:3b`* — fallback if `gemma3:4b` shows worse Swedish quality on the drop-zone tasks in spec 003. The config is structured so the swap is trivial.
- *`mistral:7b-instruct`* — too heavy on 8 GB RAM; rejected.
