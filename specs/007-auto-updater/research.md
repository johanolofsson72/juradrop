# Phase 0 Research — Spec 007 (auto-updater)

Date: 2026-05-27

## R-001 — Tauri updater plugin 2.x API surface

**Decision**: Use the existing `tauri-plugin-updater = "2"` (added in spec 006) and drive it from Rust via three calls:

- `app.updater()?.check().await` — fetches the manifest, returns `Option<Update>`. `Some(update)` means a newer version is available.
- `update.download_and_install(on_chunk, on_done).await` — downloads, verifies signature, replaces the running .app, exits the current process. Streams progress via the `on_chunk` callback.
- For the staged-install pattern (download → wait for restart consent → restart), use the lower-level pair `update.download(on_chunk, on_done).await` followed by `update.install(bytes)?` — these are separate in plugin 2.10+.

**Rationale**:
- Single-step `download_and_install` doesn't fit the FR-008/FR-009 deferral gate (it restarts immediately on success). The two-step `download` then `install` lets us hold the downloaded bytes in memory until consent + zone idleness.
- Signature verification happens inside `download` (the plugin verifies the `.sig` against the embedded pubkey before returning success). FR-012 is satisfied by relying on this built-in path — we do NOT reimplement signature checks.
- The plugin's `Update` struct exposes `.version`, `.body` (release notes), and `.date` — exactly the fields the React indicator panel needs.

**Alternatives considered**:
- Hand-roll the HTTP fetch + minisign verification: rejected — the plugin already does it correctly and shipping a second verifier doubles the attack surface.
- `app.updater()?.check_and_install_if_available().await` (if it existed): no such single-call exists in plugin 2.x; the two-step approach is the documented one.

**Implementation notes**:
- `app.updater()` requires the plugin to be registered (spec 006 already did this in `src-tauri/src/lib.rs`).
- The `on_chunk` callback fires per byte block; we emit a fresh `juradrop://update-status` event at most once per integer percent (FR-007) — debounced via a `last_emitted_pct: u8` field on the `Updater` entity.
- `update.install(bytes)` consumes the downloaded buffer and the process exits inside the call; the running app sees the function not return.

## R-002 — State-machine ownership in Rust

**Decision**: The `Updater` entity lives in a new field on the existing `AppState` (which already holds `OllamaSidecar`, `zones: HashMap<ZoneId, Arc<DropZone>>`, and `OllamaClient`). Wrapped in `Arc<RwLock<Updater>>` for the same reasons spec 003 wraps `ZoneInternalState`: cheap clones for the tokio tasks + the Tauri command handlers.

**Rationale**:
- Co-locating with the existing single source-of-truth state (`AppState`) means every Tauri command, every tokio task, and every event handler has a consistent path to read/write the updater state.
- `parking_lot::RwLock` is already a dep; the project uses it everywhere (zones, sidecar). Drop-in fit.
- Arc-wrapping makes the 4-hour background task own a clone without lifetime gymnastics.

**Alternatives considered**:
- A separate global static (`once_cell::Lazy`): rejected — splits the source of truth, makes shutdown harder.
- Tokio's `Mutex`: rejected — async-mutex contention is unnecessary; the state mutations are short and synchronous.

## R-003 — Background 4-hour tick implementation

**Decision**: Single `tokio::spawn`-ed task launched from `setup()` in `src-tauri/src/lib.rs`. The task body is `loop { sleep(4h); check_if_state_allows().await; }`. Cancellation via a `CancellationToken` stored on the `Updater` entity; flipped during app shutdown.

**Rationale**:
- `tokio::time::sleep` is suspended cheaply during sleep; the task uses negligible resources between ticks.
- A single task keeps the timer math simple — no per-event-handler scheduling, no priority inversion.
- The `CancellationToken` pattern is already used in spec 003's per-zone cancel; reusing it keeps the codebase consistent.

**Alternatives considered**:
- `tokio::time::interval` (rather than `sleep`): rejected — interval ticks fire even if a previous tick is still running, which could double-trigger a check. `sleep` in a loop is safer for low-frequency cadence.
- A wall-clock cron-style timer (e.g. via `cron` crate): rejected — overkill for "tick every 4 hours from app launch", and would bring a new dep.

**Implementation notes**:
- The first tick is `sleep(launch_check_delay_secs)` (5 s) — the launch-time check.
- Subsequent ticks are `sleep(4h)`.
- On wake, the task acquires a read lock on `Updater`, checks the state predicate, then acquires a write lock to transition if allowed. Lock granularity is small — no other path is starved.

## R-004 — React state mirror via Zustand

**Decision**: New Zustand slice `useUpdateStore` at `src/lib/update-store.ts`. Subscribes to the `juradrop://update-status` Tauri event on mount; populates the store from each event payload. The `UpdateIndicator.tsx` component reads from this store.

**Rationale**:
- Zustand is already used for the status store (`src/lib/status-store.ts`); a parallel slice keeps the React-side state model consistent.
- Single subscription per app instance — the React tree never re-subscribes on remount because the listener is attached at the bridge layer (`src/lib/tauri-bridge.ts`).
- The slice is a single object matching the `UpdateStatus` shape, so React components get cheap shallow-equality re-renders.

**Alternatives considered**:
- React context: rejected — re-renders all consumers on every transition, which is overkill for a low-frequency channel.
- TanStack Query: rejected — wrong tool; the updater isn't a query/cache problem.

## R-005 — `wiremock` integration-test stubbing

**Decision**: Use the existing `wiremock = "0.6"` dev-dep (added in spec 002 for client robustness tests). Stub the manifest endpoint via:

```rust
let server = wiremock::MockServer::start().await;
let manifest_url = format!("{}/latest.json", server.uri());
let manifest_body = serde_json::json!({
    "version": "0.2.0",
    "notes": "Test release notes",
    "pub_date": "2026-05-27T00:00:00Z",
    "platforms": {
        "darwin-x86_64": {
            "signature": "<base64 minisign signature of the binary>",
            "url": format!("{}/JuraDrop_0.2.0_universal.dmg", server.uri())
        },
        "darwin-aarch64": { "signature": "...", "url": "..." }
    }
});
wiremock::Mock::given(wiremock::matchers::method("GET"))
    .and(wiremock::matchers::path("/latest.json"))
    .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(manifest_body))
    .mount(&server).await;
```

**Rationale**:
- `wiremock` is already linked into the dev-test binary; no new dep.
- The mock server binds to a random `localhost:NNNN` port — works on all CI runners without prior config.
- The test can override the updater's endpoint URL via a `cfg(test)` field on the `Updater` entity, OR via a dedicated `tauri-plugin-updater` Builder customization point (`.endpoints(...)`).

**Alternatives considered**:
- `httpmock` (alternative HTTP mock): rejected — `wiremock` is already in.
- Real HTTP server bound to a static port: rejected — flaky on shared CI runners.

**Implementation notes**:
- The test does NOT actually call `update.install(bytes)` — that would write to the running .app on the test runner, which is a destructive side-effect.
- The test asserts the state machine reaches `ReadyToInstall` and stops. Real install verification lives in the spec 006 quickstart's "smoke-test the draft DMG" manual step.

## R-006 — Manifest schema (what the GitHub Releases manifest looks like)

**Decision**: Inherit the Tauri 2.x updater manifest format byte-for-byte. The plugin generates this format from `tauri-action` during the spec 006 release workflow. Spec 007 consumes it; we don't modify the schema.

Reference shape:
```json
{
  "version": "0.2.0",
  "notes": "## What's new\n\n- New zone for ...",
  "pub_date": "2026-05-27T15:30:00Z",
  "platforms": {
    "darwin-x86_64": {
      "signature": "<minisign signature>",
      "url": "https://github.com/.../JuraDrop_0.2.0_universal.dmg"
    },
    "darwin-aarch64": {
      "signature": "...",
      "url": "..."
    }
  }
}
```

**Rationale**: This is the format `tauri-action` produces; the plugin expects it. Deviating breaks the spec 006 → spec 007 pipeline.

**Implementation notes**:
- The `notes` field is consumed as plain text by spec 007 (FR-019). The "## What's new" markdown header renders as a literal `## What's new` line in the indicator panel — the user understands.
- Empty `notes` → indicator panel shows "Inga noteringar för denna version." per FR-019.

## R-007 — Mapping plugin errors to `UpdateFailure` variants

**Decision**: A single `From<tauri_plugin_updater::Error>` impl on `UpdateFailure` performs the variant mapping. Concrete rules:

| Plugin error | UpdateFailure |
|---|---|
| `Reqwest(reqwest::Error)` where `.is_connect() \|\| .is_timeout()` | `NoNetwork` |
| `Reqwest` other (4xx/5xx body) | `ManifestMalformed` |
| `Serialization(_)` / `JsonError` | `ManifestMalformed` |
| `Minisign(_)` (signature verification failure) | `SignatureInvalid` |
| `Io(_)` during download | `DownloadInterrupted` |
| `Io(_)` during install | `InstallFailed` |
| `MinimumSystemVersion` (the updater carries this) | `UnsupportedPlatform` |

**Rationale**:
- The plugin's internal `Error` enum has variants in roughly the same shape as our `UpdateFailure`. The mapping is one-to-one for most cases.
- Centralising the mapping in one `impl From` makes the conversion testable in isolation.

**Alternatives considered**:
- Catch-all `From<E>` returning `UpdateFailure::DownloadInterrupted` for everything we don't recognise: rejected — violates Principle VIII ("Honest failure states"). Specific is better than generic.

**Implementation notes**:
- The minisign error variant comes from the plugin's bundled `minisign-verify` crate. The plugin propagates it transparently.
- "macOS too old" detection: the plugin compares the manifest's `minimumSystemVersion` against the running system. If mismatched, it returns a specific error variant. If that variant doesn't exist in plugin 2.10 (TBD at code-time), we fall back to inspecting the manifest body ourselves before calling `install`.

## R-008 — `tauri.conf.json` change

**Decision**: Single one-line edit — flip `plugins.updater.dialog` from `true` to `false`. The pubkey + endpoint stay where spec 006 put them.

```json
"plugins": {
  "shell": { "open": false },
  "updater": {
    "active": true,
    "dialog": false,                              // ← spec 007 (was true)
    "endpoints": ["https://github.com/.../latest.json"],
    "pubkey": "<spec 006 pubkey>"
  }
}
```

**Rationale**: With `dialog: false`, the plugin never renders its built-in modal. The check + the UI are entirely Rust-driven.

## R-009 — Why no new outbound network surface

**Decision**: Codified as Allium invariant `OnlyManifestAndDmgEndpoints` + the existing static network audit grep (spec 002 T053).

The updater's only network calls:
1. `GET <update_endpoint>/latest.json` — the manifest fetch (existing surface, unchanged from spec 006).
2. `GET <DMG URL from manifest>` — the DMG download (existing surface, unchanged from spec 006).

Both are already permitted by Principle I as the "app updater" channel. Spec 007 introduces ZERO new surfaces — it just consumes the existing endpoints more thoroughly than spec 006's "dialog: true" mode did.

The Rust integration test uses `wiremock` (in-process; localhost only) — no real network.

## R-010 — Cargo.toml unchanged

**Decision**: Spec 007 adds NO new dependencies. Everything is built on what's already in the tree:

- `tauri-plugin-updater = "2"` (spec 006)
- `tokio` with the `time` feature (spec 002)
- `parking_lot::RwLock` (spec 003)
- `serde` + `serde_json` (existing)
- `wiremock` dev-dep (spec 002)
- `chrono` for the `last_fired_at` timestamp (existing)

Rationale: a feature like this should not require new third-party code. Tauri's updater plugin is the only third-party piece, and it's been in the tree since spec 006.
