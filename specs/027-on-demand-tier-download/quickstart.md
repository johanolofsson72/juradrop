# Quickstart: On-demand tier download — manual verification

Run in `npm run tauri dev` (or the built DMG). These mirror the acceptance scenarios + edge cases.

## Flow 1 — Happy path (User Story 1, SC-001)

1. Open **Inställningar → Modell**. Confirm **Snabb** and **Stor** show **Ladda ned** + size; **Smart** is the selected radio.
2. Click **Ladda ned** on **Snabb** (smallest, ~1.3 GB — fastest to verify).
3. The row switches to a progress state: a percentage advances and a byte figure ("… / 1,3 GB") updates at least once a second. The **Stor** Ladda-ned button is now disabled (FR-009).
4. Wait for completion. The Snabb row becomes a **selectable radio** without reloading the panel (FR-005).
5. Select **Snabb**. It becomes the active model (the spec-010 `set_model_tier` gate now accepts it).

## Flow 2 — Cancel (User Story 3, SC-004)

1. Click **Ladda ned** on **Stor** (~8 GB — long enough to cancel mid-way).
2. While progress is moving, click **Avbryt**.
3. The download stops; the row returns to **Ladda ned** (not_pulled). The **Stor** radio does NOT appear. Re-open the panel — Stor is still **Ladda ned** (cancel left it uninstalled).

## Flow 3 — Honest failure + retry (User Story 2, SC-003)

Simulate failures (dev: point the seam at a mock, or pull a deliberately bad tag; disk-full needs a constrained volume):

1. **Network drop**: start a download, disable wifi mid-stream → row shows `tier_download_err_network` (Swedish, no stack trace) + **Försök igen**.
2. Click **Försök igen** → row re-enters downloading (FR-007). With wifi back, it completes.
3. **Not ready**: quit/restart so Ollama is still starting, immediately click **Ladda ned** → `tier_download_err_not_ready`, no pull starts, row stays Ladda ned (FR-010).

## Flow 4 — Survives panel close (FR-011)

1. Start a **Stor** download.
2. Close the settings panel (✕), do something else, reopen it.
3. The Stor row still shows the in-progress download with current progress — the pull was not aborted by closing the panel.

## Flow 5 — Concurrent with document processing (FR-015)

1. Start a **Stor** download.
2. While it downloads, drop a `.docx` on **Sammanfatta**.
3. Both proceed: the summary completes (perhaps a little slower) and the download keeps advancing. Neither blocks the other.

## Flow 6 — Contrast / readability (regression of the bug that started this)

1. In light mode AND dark mode, confirm the **Ladda ned** button text and the selected-tier border are clearly visible (blue `#007aff` / `#0a84ff`), not white-on-white. (Fixed in commit 71d9b66; verify it stuck.)

## Automated coverage to run before "done"

- `npm test -- --run` (vitest): tier-download store + row sub-states + strings drift.
- `cd src-tauri && cargo test` : tier_download state machine, concurrency guard, failure categorisation, model-id mapping, no-content-leak grep.
- `cargo clippy -- -D warnings && cargo fmt --check`; `npm run lint && npm run typecheck`.
- `/tla` after browser tests (per pipeline) — the per-tier download state machine is non-trivial (4 states, async boundaries, concurrency guard).
