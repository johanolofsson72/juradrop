# Quickstart: manual verification (spec 042)

1. `npm run tauri dev` (ready state, model present).
2. **Badge**: under the zone grid, one muted Swedish line states documents are processed on din dator and never leave it. Drop a file → badge unchanged during processing/success/error. Switch macOS light/dark → legible in both.
3. **Window fit**: at the default window size, the fourth zone row AND the badge are visible without scrolling.
4. **Wizard** (fresh install or reset app data): welcome screen says processing is local ("din dator"); the download step's note explains the one-time model download and offline-after. No screen claims "no internet ever".
5. **Help**: open the help panel → "Så skyddas dina dokument"-style entry (final title per humanizer) lists what never leaves AND names the two network uses (model download, update check).
6. **README**: Privacy guarantees section matches the in-app facts.
7. **Consistency spot-check**: grep the app strings — `grep -rn "din Mac" src/` returns nothing for in-app copy.
