# Quickstart: verifying chunked long-document processing (038)

## Automated (CI-equivalent, run locally)

```bash
cd src-tauri && cargo test                 # unit (chunking) + integration (zone_pipeline_chunked)
cd src-tauri && cargo clippy --all-targets -- -D warnings && cargo fmt --check
npm test                                   # vitest (unchanged surface must stay green)
npm run lint && npm run typecheck
npm run test:e2e                           # Playwright incl. progress-hint assertion
```

Key automated checks and where they live:
- chunk boundary cascade + Swedish abbreviations + UTF-8 safety → zones/chunking.rs unit tests
- request count + num_ctx=8192 + DOKUMENT framing per chunk → tests/zone_pipeline_chunked.rs
- sentinel coverage beginning/middle/end (SC-001-003 analog with mock model) → zone_pipeline_chunked.rs
- mid-chunk failure ⇒ no sidecar file (SC-005) → zone_pipeline_chunked.rs
- single-chunk path = exactly 1 generate request (SC-004) → zone_pipeline_chunked.rs
- anonymisera: sweep on combined output + multi-chunk disclaimer (FR-010/FR-014) → zone_pipeline_chunked.rs

## Manual (real model, `npm run tauri dev` on a Mac with the model pulled)

1. Generate a long test document (the gen_testdocs example produces a corpus in
   ~/Desktop/juradrop-test, or any ~50-page .docx/.txt):
   plant three sentinel facts — one on page 1, one in the middle, one on the last page
   (e.g. "Käranden yrkar 417 250 kr", "Vittnet Karin Holm hörd 12 mars",
   "Hovrätten fastställer domslutet i punkt 9").
2. Drop it on **Sammanfatta**:
   - zone shows "Bearbetar del 1 av N…" advancing, then "Sammanställer…"
   - sidecar opens; summary references material from beginning, middle AND end
   - NO "texten kortades av" disclaimer
3. Drop a short (1-page) doc on Sammanfatta — behavior identical to before (no "del 1 av 1"
   text, just the normal processing hint).
4. Drop the long doc on **Till svenska** (if source is English) or **Förenkla**:
   output contains the final sections of the document, in order.
5. Drop a long doc with a phone number planted on the last page on **Kontakter**:
   the number appears in the output exactly once.
6. Drop the long doc on **Anonymisera**: output is anonymized through the end and carries
   the multi-chunk review disclaimer near the top.
7. (Patience test) Drop a ~300-page document: processes 12 parts, output carries the
   truncation disclaimer (content above ~240 pages genuinely skipped).
