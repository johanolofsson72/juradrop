# Contract: JURADROP_OLLAMA_URL test seam (FR-015)

## Behavior

- `OllamaClient::new()`:
  - `#[cfg(debug_assertions)]`: if `std::env::var("JURADROP_OLLAMA_URL")` is `Ok(url)` and non-empty → `Self::with_base_url(url)`. Else → `Self::with_base_url(BASE_URL)`.
  - `#[cfg(not(debug_assertions))]`: always `Self::with_base_url(BASE_URL)`. The env var is NEVER read in release.
- `with_base_url` is unchanged (already exists, test-only constructor).

## Privacy invariant (Principle I / `ReleaseUsesLocalhostOnly`)

Release builds MUST resolve the base URL to `http://127.0.0.1:11434` regardless of environment. Verified by:
- A `#[cfg(not(debug_assertions))]`-gated unit test that sets the env var and asserts `OllamaClient::new().base_url() == BASE_URL`. (Runs only in release-profile test builds; documented if not run in default `cargo test`.)
- A source-grep invariant test (telemetry/immutability lineage): the env read is inside a `#[cfg(debug_assertions)]` block — assert no unconditional `env::var("JURADROP_OLLAMA_URL")` outside a debug-cfg gate.

## Test usage

- Integration tests inject directly via `with_base_url(server.uri())` — they do NOT set the env var (avoids process-global env races).
- Only `zone_pipeline_e2e_smoke.rs` sets the env var, guarded by a serial mutex, to exercise the `new()` seam path. It unsets the var on completion.
