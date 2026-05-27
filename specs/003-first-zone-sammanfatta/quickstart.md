# Quickstart: First drop zone — Sammanfatta

How to exercise spec 003 end-to-end on a dev machine.

## Prerequisites

- Apple Silicon Mac, macOS 12+.
- Spec 002 verified (bundled Ollama spawn + consent flow works).
- `gemma3:4b` pulled locally (`ollama pull gemma3:4b` if needed; spec 002's first-launch flow does this automatically).
- A small `.docx` to test against — any Word document with text content.

## Smoke flow (US1 — happy path)

```bash
# From repo root
npm install                              # if first run
bash scripts/fetch-ollama.sh             # if first run (spec 002 prereq)
npm run tauri dev                        # opens the dev window
```

1. Wait for the welcome card to show `AI redo` (model loaded).
2. Drag a `.docx` from Finder onto the "Sammanfatta" zone.
3. Zone shows the dragover highlight (within 100 ms).
4. Release the file. Zone shows the spinner + Swedish "Sammanfattar…".
5. Within ~60 s, the sidecar `<original-stem>.sammanfatta.docx` appears next to the source on disk and opens automatically in Word / Pages / LibreOffice (whichever is the default).
6. Zone shows "Klar — öppnar fil…" briefly then returns to idle within 2 s.
7. Confirm via `sha256sum <original.docx>` (before and after) that the source is byte-identical.

## Cancel flow (US5)

1. Repeat steps 1–4 above with a larger `.docx` so inference takes ≥ 5 s.
2. While the zone is processing, click the Swedish "Avbryt" button.
3. Within 1 s the zone flashes "Sammanfattning avbruten" then returns to idle.
4. Confirm `ls <dir>` shows no `.sammanfatta.docx` was written.
5. Confirm the source `.docx` is byte-identical.

## Disabled-zone flow (US3)

1. Quit the app.
2. Delete `~/Library/Application Support/se.noisycricket.juradrop/consent.json` (spec 002 consent record).
3. Re-launch.
4. Welcome card shows the consent modal; do NOT click "Fortsätt" yet.
5. Drag a `.docx` over the zone — zone is visibly disabled and shows the Swedish hint matching the current sidecar status.
6. Click "Avbryt" on the modal. Zone hint updates to the cancelled-consent Swedish copy.

## Error-state flows (US4)

For each error, drop the offending input and verify the matching Swedish string appears:

| Trigger | Expected Swedish string |
|---|---|
| Drop a `.pdf` | `Endast .docx i denna version` |
| Drop two `.docx` at once | `Ett dokument i taget` |
| Drop a corrupt `.docx` (e.g. truncated zip) | `Kunde inte läsa dokumentet` |
| Drop a password-protected `.docx` | `Dokumentet är lösenordsskyddat` |
| Drop a `.docx` with only whitespace | `Dokumentet innehåller ingen text` |
| Drop a second `.docx` while one is processing | `Vänta tills föregående dokument är klart` |
| Force a model failure (e.g. kill Ollama mid-inference) | `AI-motorn svarade inte — försök igen` |

## Privacy verification (SC-003)

While a drop is in flight, in a separate terminal:

```bash
lsof -p $(pgrep -f juradrop | head -1) -i -n -P 2>/dev/null | grep -E '(ESTABLISHED|LISTEN)'
```

Confirm every line's remote endpoint is `127.0.0.1:*`. No `ollama.com`, no public IPs.

## Source-immutability verification (SC-004)

```bash
shasum -a 256 my-document.docx       # before drop
# ... do the drop ...
shasum -a 256 my-document.docx       # after drop
```

Both hashes must be identical.

## Running the test suites

```bash
cd src-tauri
cargo test                                                    # unit + integration tests
cargo test --test zone_sammanfatta_lifecycle -- --ignored     # full live-Ollama round-trip

cd ..
npm test                              # vitest (frontend)
npm run lint && npm run typecheck     # static checks
npm run test:e2e                      # Playwright smoke
```

## Common pitfalls

- **Port 11434 is busy** (Homebrew Ollama, Ollama.app, parallel `tauri dev`): the sidecar can't bind. Stop the foreign instance: `launchctl bootout gui/$(id -u)/se.noisycricket.ollama` if you're running the personal launch agent.
- **gemma3:4b not cached**: the round-trip test skips with a clear message. Pull via `ollama pull gemma3:4b`.
- **macOS Gatekeeper warning** on dev build: right-click → Open the first time. Signing arrives in spec 006.
