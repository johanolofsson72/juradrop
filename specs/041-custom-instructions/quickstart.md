# Quickstart: manual real-model verification (spec 041)

Run after implementation, on a Mac with the bundled model available. The automated suites prove prompt assembly; this proves real-model behavior + the on-disk privacy claim.

## 1. Meja's case — steer a translation

1. `npm run tauri dev`
2. In the instruction field, type: `Behåll citerade stycken på svenska.`
3. Drop a Swedish .docx containing at least one quoted passage ("...") onto **Till engelska**.
4. **Expect**: sidecar `.tillengelska.docx` opens; prose translated to English; the quoted passage(s) remain in Swedish (4b-model best-effort — partial compliance is a model-quality note, not a bug, as long as the run visibly tried).

## 2. Long-document consistency

1. Keep the instruction `Fokusera på skadeståndsfrågan.`
2. Drop `juradrop-test/mycket-langt.txt` onto **Sammanfatta**.
3. **Expect**: per-part progress ("Bearbetar del i av n…"), final summary skews toward damages; no part of the summary obviously ignores the focus.

## 3. Dormant path

1. Clear the field (× button).
2. Drop the same document on **Sammanfatta**.
3. **Expect**: output indistinguishable in character from pre-041 behavior.

## 4. Privacy disk check (SC-004)

1. Use a unique sentinel instruction first: `zebrakvitto fokus` + one drop on Sammanfatta.
2. Quit the app.
3. Run:
   ```bash
   grep -ri "zebrakvitto" "$HOME/Library/Application Support/se.juradrop.app/" 2>/dev/null
   grep -ri "zebrakvitto" specs/../juradrop-test/ --include="*.docx" 2>/dev/null  # sidecar text check is automated too
   ```
4. **Expect**: zero hits anywhere (settings store, diagnostics log, caches). The sidecar may discuss damages but must not contain the sentinel.
5. Relaunch the app — **expect** the instruction field empty.

## 5. Field UX

- Type 500+ chars (paste a long text) → input stops at 500, counter shows `500/500`.
- Tab from app chrome → field reachable; Escape/clear behavior per design.
- Field text survives a cancelled run (drop + Avbryt → text still there).
