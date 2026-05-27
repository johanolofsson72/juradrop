# Spec 005 quickstart — 12 smoke flows

Manual verification flows for spec 005. Run after implementation is complete; before ticking T-final in `tasks.md`.

## Prereqs

- `gemma3:4b` warm (run `ollama list` to confirm; if not, run `ollama pull gemma3:4b` once).
- `npm run tauri dev` launches the app to `Klar` state.
- Three test files prepared:
  - A 2-page text-based `.pdf` (any court judgment PDF works; `tingsrätt-dom-2024-001.pdf` from the Riksdagen archive is good).
  - A 100-line UTF-8 `.txt` with at least one Swedish name + personnummer.
  - A 50-line `.md` with: YAML frontmatter, an H1, a bullet list, an emphasised word, and a link.

## Flow 1 — PDF Sammanfatta (happy path)

1. Drop the 2-page `.pdf` on the Sammanfatta zone.
2. Zone enters Processing. Hint shows `Sammanfattar…`.
3. Within 60 s, a sidecar `<stem>.sammanfatta.docx` opens in Word.
4. Confirm the .docx contains a Swedish summary, no English fallback, no "Filen är lösenordsskyddad" notice.
5. Confirm the original `.pdf` is byte-identical (`shasum -a 256 <file>` matches pre-drop).

**Pass criterion:** SC-001 (≤ 60 s wall-clock) + SC-006 (no regression on .docx pipeline) + Source-immutability invariant.

## Flow 2 — PDF Anonymisera

1. Drop a `.pdf` containing the name "Anna Andersson" + personnummer "19890214-1234" on Anonymisera.
2. Sidecar `<stem>.anonymiserad.docx` appears within 60 s.
3. Confirm "Anna Andersson" appears as "Person A" (or similar placeholder).
4. Confirm the personnummer is anonymised.
5. Confirm the docx ends with the spec 004 disclaimer paragraph (italic, "AI-anonymisering är inte hundra procent").

## Flow 3 — Encrypted PDF (error path)

1. Create an encrypted PDF: open a PDF in macOS Preview → Export → Encrypt with password "test".
2. Drop the encrypted PDF on any zone.
3. Within 200 ms, the zone shows `Filen är lösenordsskyddad — öppna och spara om utan lösenord.`.
4. No sidecar is written.
5. The zone returns to idle when clicked.

## Flow 4 — Image-only PDF (NoExtractableText)

1. Create a PDF from a screenshot (Preview → File → Export as PDF).
2. Drop on any zone.
3. Within 500 ms, the zone shows `Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än.`.
4. No sidecar is written.

## Flow 5 — TXT Sammanfatta

1. Drop the 100-line UTF-8 `.txt` on Sammanfatta.
2. Sidecar `<stem>.sammanfatta.txt` appears within 30 s.
3. Open in TextEdit. First line is `# <basename> — Sammanfatta — <YYYY-MM-DD>`.
4. Body contains a Swedish summary.
5. File ends without a trailing newline (idiomatic Unix).

## Flow 6 — TXT Anonymisera (with disclaimer)

1. Drop a `.txt` containing a name + personnummer on Anonymisera.
2. Sidecar `<stem>.anonymiserad.txt` appears.
3. Open in TextEdit. Header line + body + final line: `# AI-anonymisering är inte hundra procent — granska resultatet innan du delar.`.

## Flow 7 — Windows-1252 TXT

1. Save a `.txt` from older TextEdit with "Always show file extensions" + a Swedish character ("å", "ö") in Windows-1252. Use `iconv -f utf-8 -t windows-1252 in.txt > out.txt` (system iconv is available on every macOS install). Fallback with Python if iconv ever goes missing: `python3 -c 'import sys; open(sys.argv[1],"wb").write(open(sys.argv[2]).read().encode("windows-1252"))' out.txt in.txt`.
2. Drop on any zone.
3. Sidecar appears within 30 s. Swedish characters render correctly in the output (UTF-8 on the way out).

## Flow 8 — UTF-16 TXT (error)

1. `iconv -f utf-8 -t utf-16 in.txt > out-utf16.txt`.
2. Drop on any zone.
3. Zone shows `Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen.` within 200 ms.
4. No sidecar is written.

## Flow 9 — MD Förenkla

1. Drop the 50-line `.md` (with YAML frontmatter) on Förenkla.
2. Sidecar `<stem>.forenkla.md` appears within 60 s.
3. Open in Obsidian / VS Code preview / GitHub.
4. Frontmatter at the top is byte-identical to the source (same keys, same order, same values).
5. Below the frontmatter: H1 `# <basename> — Förenkla`, blockquote subtitle `> <YYYY-MM-DD>`, simplified Swedish body, closing blockquote `> **OBS!** Förenklad version — granska att inga juridiska poänger gick förlorade.`.

## Flow 10 — MD Punktlista (no frontmatter)

1. Drop a `.md` without frontmatter on Punktlista.
2. Sidecar `<stem>.punktlista.md` appears.
3. No leading frontmatter block. Header `# <basename> — Punktlista`, subtitle blockquote, then a bulleted Markdown list (each bullet starts with `- `).
4. The list renders as a real bulleted list in Markdown preview.

## Flow 11 — Unsupported extension

1. Create `mydoc.rtf` (any RTF file).
2. Drop on any zone.
3. Zone shows `Filformatet stöds inte — dra ett .docx, .pdf, .txt eller .md.` within 100 ms.
4. No sidecar.

## Flow 12 — Mixed-case extension

1. Rename a `.pdf` to `MYDOC.PDF`.
2. Drop on any zone.
3. Same Flow 1 behaviour — extension matching is case-insensitive, sidecar appears within 60 s.

## Verification commands (between flows)

```bash
# Regression check — every previous spec's tests still green:
npm test
cd src-tauri && cargo test
npm run lint && npm run typecheck
npm run test:e2e

# Source immutability check after each flow:
shasum -a 256 path/to/source-file > /tmp/before
# ... run flow ...
shasum -a 256 path/to/source-file > /tmp/after
diff /tmp/before /tmp/after   # must be empty

# Outbound network audit (run once at end):
grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::Client|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/
# Every match must remain in spec 002's manager.rs + client.rs. Spec 005 introduces ZERO new outbound surface.
```
