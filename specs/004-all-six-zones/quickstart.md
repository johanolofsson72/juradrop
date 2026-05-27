# Quickstart: All six drop zones

How to exercise spec 004 end-to-end on a dev machine.

## Prerequisites

- Spec 003 verified (single Sammanfatta zone works end-to-end).
- `gemma3:4b` pulled locally.
- A small `.docx` to test against.

## Six smoke flows (one per zone)

```bash
# From repo root
npm install                              # if first run
bash scripts/fetch-ollama.sh             # if first run
npm run tauri dev                        # opens the dev window with the 2×3 grid
```

Wait for the welcome card to show `AI redo`, then for each zone in turn:

### Sammanfatta (already shipped)

Drag a `.docx`. Verify `<stem>.sammanfatta.docx` appears next to the source within 60 s.

### TillEngelska (US1)

Drag a Swedish `.docx`. Verify `<stem>.tillengelska.docx` opens with English content preserving the source structure.

### TillSvenska (US5)

Drag an English `.docx`. Verify `<stem>.tillsvenska.docx` opens with Swedish content. If you accidentally drag a Swedish `.docx`, the sidecar body opens with the Swedish notice "(Dokumentet är redan på svenska — endast lätt korrigerad.)" prepended.

### Punktlista (US2)

Drag a `.docx`. Verify `<stem>.punktlista.docx` opens as a bulleted Swedish list (Word "List Bullet" style or similar).

### Anonymisera (US3)

Drag a `.docx` with known personal names. Verify `<stem>.anonymiserad.docx` contains "Person A", "Företag X" placeholders consistently. The header carries the FR-013 disclaimer "AI-anonymisering är inte hundra procent — granska resultatet innan du delar.".

### Förenkla (US4)

Drag a `.docx` containing legal jargon. Verify `<stem>.forenkla.docx` rewrites in plain Swedish with parenthetical jargon explanations. The header carries the FR-014 disclaimer "Förenklad version — granska att inga juridiska poänger gick förlorade.".

## Parallel-zones flow (US6)

1. Drag a `.docx` onto Sammanfatta.
2. Within 1 second, drag the same `.docx` onto Anonymisera.
3. Verify both zones show Processing simultaneously (two spinners visible).
4. Verify both sidecars eventually appear (`<stem>.sammanfatta.docx` AND `<stem>.anonymiserad.docx`); the second arrives after the first completes (Ollama serialises inference).
5. Confirm cancelling Sammanfatta does NOT cancel Anonymisera.

## Disabled-state flow

Quit the app. Delete `~/Library/Application Support/se.noisycricket.juradrop/consent.json`. Re-launch. All six zones are visibly disabled with the same status hint borrowed from the WelcomeCard. Drag a `.docx` on any zone — drop is rejected; no sidecar lands.

## Privacy verification (SC-003)

While any zone is in flight, run in a separate terminal:

```bash
lsof -p $(pgrep -f juradrop | head -1) -i -n -P 2>/dev/null | grep -E '(ESTABLISHED|LISTEN)'
```

Confirm every line's remote endpoint is `127.0.0.1:*`. No outbound traffic from any zone.

## Source-immutability verification (SC-003 across zones)

```bash
shasum -a 256 my-document.docx
# Run through all six zones, sequentially or in parallel
shasum -a 256 my-document.docx
# Both hashes MUST be identical
```

## Running the test suites

```bash
cd src-tauri
cargo test                                                         # unit + parametric + ignored-by-default integration
cargo test --test zone_sammanfatta_lifecycle -- --ignored          # full live-Ollama happy path (spec 003 path)
cargo test --test zone_parametric -- --ignored                     # NEW — six-zone table tests

cd ..
npm test                                # vitest
npm run lint && npm run typecheck
npm run test:e2e                        # Playwright stub
```

## Common pitfalls

- **Drop misses the zone**: the drop position is in CSS pixels. If you drop on a zone seam, the `elementFromPoint` resolution picks whichever zone the centre of the drop landed on. A drop outside any zone (e.g. on the WelcomeCard) is silently ignored.
- **gemma3:4b missing**: spec 002's first-launch flow downloads it. Otherwise `ollama pull gemma3:4b`.
- **Port 11434 busy**: spec 002 surfaces this as `FelPortenUpptagen`; all six zones are disabled with the matching Swedish hint.
