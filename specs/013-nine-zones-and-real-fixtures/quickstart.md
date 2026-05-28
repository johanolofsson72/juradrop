# Quickstart — Spec 013 manual verification

Run after implementation. Automated coverage is the source of truth; these are the human spot-checks (SC wall-clock items need a real M-series Mac).

## Flow 1 — Nine zones render (SC-001, SC-006)

1. `npm run tauri dev`.
2. Complete/skip the first-run wizard so the zone grid shows.
3. Confirm **9** zone cards in a 3×3 grid (3 columns). The new cards: "Plocka ut kontaktuppgifter", "Generera juridisk text", "Källförteckning".
4. Resize the window narrow → grid collapses to 2-col then 1-col (breakpoints unchanged).

## Flow 2 — Per-zone help popover (FR-018)

1. Click the `(?)` at a card's top-right. A popover with the short Swedish help appears.
2. Press Esc → closes. Click `(?)` again → opens. Click outside → closes.
3. Confirm clicking `(?)` does NOT start a drop/dispatch.

## Flow 3 — Chrome help panel + mutual exclusion (FR-019, FR-020, FR-023)

1. Click the chrome-bar `(?)` (left of the gear). Panel slides in from the right listing all 9 zones with long explanations + format badges.
2. Esc / close-X / scrim click → slides out.
3. Open the help panel, then click the gear → help panel closes, settings opens (and vice versa). Never both open.

## Flow 4 — Modal gating (FR-022)

1. Trigger the first-run wizard (fresh profile) → the chrome `(?)` is disabled (dimmed, no-op).
2. Same while a restart-confirm dialog is up.

## Flow 5 — Real fixture round-trip (SC-002, US1)

1. Drag `src-tauri/tests/fixtures/documents/anonymisera-input.docx` onto Anonymisera.
2. A `anonymisera-input.anonymisera.docx` sidecar appears next to it and opens; names/personnummer/addresses are replaced with placeholders; the disclaimer paragraph is present.
3. Drag `kallor-input.docx` onto Källförteckning → numbered citation list sidecar.
4. Drag `generera-input.txt` onto Generera → generated legal text sidecar with the AI-disclaimer.

## Flow 6 — Cross-format probe (SC-003, US2)

1. `cd src-tauri && cargo test --test extraction_probe` → 6 format tests + 1 pages-failure test green.

## Flow 7 — Test suite budget (SC-008)

1. `cd src-tauri && time cargo test` → all zone-pipeline + probe tests run (no `--ignored` needed); total growth ≤ 30s vs baseline.
2. `grep -rE '#\[ignore\]' src-tauri/tests/` → every hit has a `// HARDWARE:` reason within 3 lines above (SC-004).

## Flow 8 — Constitution (SC-005)

1. `grep '\*\*Version\*\*' .specify/memory/constitution.md` → `1.1.0`. Sync Impact Report entry present at the top.
