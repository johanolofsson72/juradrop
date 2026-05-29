# Tasks: Silence pdf-extract stdout noise (spec-only)

- [ ] T001 In `src-tauri/src/zones/pdf_extract.rs`, add a `with_stdout_silenced<T>(f)` helper: `#[cfg(unix)]` saves fd 1 (`libc::dup`), redirects `/dev/null` onto fd 1 (`libc::open` + `dup2`), runs `f`, and restores via an RAII `Drop` guard (covers panic/early-return); serialize the window with a `static Mutex<()>`; `std::io::stdout().flush()` before redirect and before restore. `#[cfg(not(unix))]` = transparent passthrough `f()`.
- [ ] T002 Wrap the `pdf_extract::extract_text_from_mem_by_pages(bytes)` call (line ~45) in `with_stdout_silenced(|| …)`. No other behavior change.
- [ ] T003 Unit test: `with_stdout_silenced(|| 42) == 42` (transparency) AND extracting the same bytes inside vs outside the wrapper yields identical `ExtractedText` (use a tiny in-memory or the committed `extraction-probe.pdf` fixture). FR-002/SC-001.
- [ ] T004 Verify: `cd src-tauri && cargo test` (existing `pdf_extract` + `extraction_probe` tests still green — proves transparency end-to-end), `cargo clippy -- -D warnings`, `cargo fmt --check`.
- [ ] T005 Manual dev check: `npm run tauri dev`, drop the Aptos-font PDF, confirm the terminal no longer shows the `missing char … falling back` lines and the output `.docx` is unchanged.
