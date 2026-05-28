# Contract: Zone pipeline integration tests (FR-011, FR-014)

## Per-zone test (`zone_pipeline_<zone>.rs`, 9 files)

Each test:

1. `let server = wiremock::MockServer::start().await;`
2. Mount `POST /api/generate` → `200` with a deterministic JSON body whose `response` field contains the zone's expected marker text (e.g. Anonymisera response contains `[Person 1]`; Kallor response contains a numbered citation list).
3. Build mock app: `mock_builder().plugin(tauri_plugin_shell::init()).build(mock_context(noop_assets()))`.
4. `let client = Arc::new(OllamaClient::with_base_url(server.uri()));`
5. Copy the committed fixture into a `TempDir` (so the committed file is never mutated).
6. `zone.handle_drop(handle, client, true, "gemma3:4b", vec![source]).await;`
7. Poll ≤ 10s for the sidecar at `<stem>.<suffix>.<ext>`.

Assertions:
- **(a)** source `TempDir` copy SHA-256 unchanged before vs after.
- **(b)** sidecar exists at canonical path with correct suffix + extension.
- **(c)** sidecar content non-empty.
- **(d)** sidecar content contains the zone-specific marker (per the mock response).
- Disclaimer zones (anonymisera, forenkla, generera): sidecar contains the disclaimer paragraph.

Output format: each test `println!`s its zone name + sidecar path (SC-002).

## E2E smoke (`zone_pipeline_e2e_smoke.rs`, FR-014)

- Sets `JURADROP_OLLAMA_URL` to a wiremock URL (exercises the FR-015 seam), constructs the client via the seam path (`OllamaClient::new()` in debug reads the env var), and drives one zone end-to-end through the same layers.
- Asserts the seam routed to the mock (request received by wiremock) and the sidecar landed.
- Cleans up the env var after (serialize via a mutex or `--test-threads` care — env vars are process-global; gate with a serial guard).

## Extraction probe (`extraction_probe.rs`, FR-012, FR-012a)

- `pub const CANONICAL_EXTRACTION_PROBE_TEXT: &str` (~200 chars, `å ä ö`).
- 6 tests `{docx, pdf, txt, md, rtf, odt}`: open `extraction-probe.<ext>`, run the format's extractor, assert returned text == canonical (after newline/whitespace normalization; `.md` after frontmatter strip).
- 1 `.pages` failure test: write a zero-byte `.pages` to a TempDir, run the pages extractor, assert `PagesParseError` (spec 009 FR-006). No successful extraction asserted (deferred).

## Runtime budget (SC-008)

Total `cargo test` growth ≤ 30s. Baseline: 6 existing zone tests run in 0.28s; 9 new zone tests + 7 probe tests are of the same shape → projected well under budget.
