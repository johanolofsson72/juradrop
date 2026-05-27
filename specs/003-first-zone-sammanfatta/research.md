# Research: First drop zone — Sammanfatta

**Phase 0 output** for `/speckit-plan`. Each decision below resolves a candidate "NEEDS CLARIFICATION" from the plan's Technical Context section into a concrete pick with rationale.

## R-001: `.docx` extraction crate

**Decision**: `docx-rs = "0.4"` (the maintained docx-rs fork, crate name `docx-rs` on crates.io).

**Rationale**: The constitution names `docx-rs` as the project default for both reading and writing `.docx`. Pure-Rust (no native deps), maintained, supports both extraction and writing. Spec 002 already pulled it transitively via the workspace Cargo.lock — adding it as a direct dep is mechanical.

**Alternatives considered**:
- Custom zip + XML walker (`zip` + `quick-xml`): more code, more bugs, no win over the maintained crate.
- `docx-rust` (a different crate): unmaintained for 18 months as of 2026-05.
- `office-cleaner`: too narrow (only sanitization).

## R-002: Password-protected `.docx` detection

**Decision**: Detect at the zip-archive layer. Password-protected `.docx` files have an `EncryptedPackage` OLE stream rather than the standard `word/document.xml`; opening the archive and looking for `[Content_Types].xml` is the canonical detection. If the archive opens but `word/document.xml` is missing AND an `EncryptedPackage` blob is present, surface `password_protected`.

**Rationale**: `docx-rs` will fail with a generic "missing document.xml" error on password-protected files; the discriminator above lets us emit the FR-017 Swedish string instead of the FR-016 "Kunde inte läsa dokumentet" catch-all.

**Alternatives considered**:
- `office-crypto-rs`: depends on `RustCrypto/aes`; adds attack surface for a feature we don't need (decrypting — we just want to detect).
- Catch the generic parse error and assume password: false positives on actually-corrupt files.

## R-003: Truncation boundary (FR-019)

**Decision**: Truncate extracted text at the first 24,000 UTF-8 characters. Implementation: take a UTF-8 char-iterator, count, slice on a char boundary (NOT a byte boundary — Swedish characters are multi-byte in UTF-8).

**Rationale**: Per the clarification round, 24,000 chars approximates 6,000 English tokens with headroom for Swedish's slightly higher chars-per-token ratio. Deterministic, testable, no tokenizer coupling.

**Alternatives considered**:
- Real tokenization (e.g. `tiktoken-rs`): couples us to a tokenizer that doesn't even match `gemma3:4b`'s tokenizer. Heavy dep for marginal accuracy gain.
- Word count: cross-language inconsistency; "ord" vs "word" yields different counts on near-identical text.

## R-004: OS default-handler invocation

**Decision**: `open = "5"` (the `open` crate on crates.io, by Sven-Hendrik Haase). On macOS it shells out to `/usr/bin/open` under the hood; we never construct shell strings with user input — we pass the `PathBuf` directly.

**Rationale**: Standard, audited crate. Tauri's `shell::open` is deprecated as of plugin-shell 2.1 (per its source code in `~/.cargo/registry/src/.../tauri-plugin-shell-2.3.5/src/lib.rs` line 75). The `opener` crate is also viable but `open` has wider adoption and the same surface.

**Alternatives considered**:
- `tauri_plugin_opener`: a near-identical replacement Tauri now points to. Acceptable alternative; pick whichever has cleaner API at implementation time. Either way the capabilities file gains no new permission because `open` shells out via `std::process::Command` directly, not through the Tauri shell plugin.
- Raw `std::process::Command::new("open").arg(&path)`: same effect, more boilerplate, no audit boundary.

## R-005: Cancellation mechanism

**Decision**: Use `tokio_util::sync::CancellationToken` (or hand-roll an `Arc<AtomicBool>` + `select!` with a `cancel_rx`). The `OllamaClient::generate` call gets a borrowed `&CancellationToken` (or a `select!` on the cancel future) so the in-flight HTTP request can be cancelled by dropping the future.

**Rationale**: `reqwest::Response::bytes` is cancellation-safe when awaited inside `tokio::select!` — dropping the future closes the underlying connection. No new external dep if we hand-roll; `tokio-util` adds a small dep but provides the ergonomics. Pick `tokio-util` (already in the workspace via `parking_lot` transitive? — verify at implementation time; if not, add as a direct dep).

**Alternatives considered**:
- `futures::future::Abortable`: deprecated for this purpose; doesn't propagate to reqwest cleanly.
- A manual flag checked between chunks: works for streaming pulls but `generate` is non-streaming. `select!` is the right pattern.

## R-006: Drag-and-drop event handling on macOS

**Decision**: Use Tauri 2's `WindowEvent::DragDrop` event variants (`DragDropEvent::Enter`, `::Over`, `::Drop`, `::Leave`) at the Rust layer; relay them to the WebView via `emit("juradrop://drag-event", payload)`. The React drop zone listens to those events rather than reimplementing HTML5 drag-drop (which doesn't expose the real file path on macOS — only sandboxed blobs).

**Rationale**: HTML5 drag-and-drop in a WebView gives you a synthetic `File` object without the OS path. Spec 003's pipeline needs the path to (a) compute the sidecar location, (b) write atomically, (c) leave the source untouched. Tauri's native drag-drop events carry `paths: Vec<PathBuf>` — exactly what we need.

**Alternatives considered**:
- HTML5 drag-and-drop API only: would force us to write the file via `tauri::api::dialog::FileDialog` or `WebView`'s synthetic-blob handle — neither preserves the user's actual path. Privacy posture stays fine but the UX breaks (sidecar would land in the user's Downloads folder, not next to the source).

## R-007: Atomic sidecar write

**Decision**: Write to `<target>.tmp`, `fsync`, then rename to `<target>`. The existing `consent::save_at` from spec 002 already proved this pattern works on macOS; reuse the helper shape in `zones::sidecar_path::write_atomically`.

**Rationale**: POSIX `rename(2)` is atomic on the same filesystem. The `fsync` is belt-and-braces — guarantees the bytes hit disk before the rename swap. Matches the spec 002 consent persistence pattern, so reviewers already know the shape.

**Alternatives considered**:
- Write directly to the canonical path: if the process crashes mid-write, the file is half-written and any later read sees garbage.
- `tempfile::NamedTempFile::persist`: equivalent semantics, adds the `tempfile` crate dep (already a dev-dep from spec 002; adding as a regular dep is fine but bigger surface than needed).

## R-008: Sidecar name collision strategy

**Decision**: Per spec FR-006, the canonical name is `<stem>.sammanfatta.docx`. On collision, append `.YYYY-MM-DD-HHMMSS` in local timezone before the extension. Use `chrono::Local::now().format("%Y-%m-%d-%H%M%S")` to produce the suffix.

**Rationale**: Local time matches the user's clock (resolved in clarification). `chrono` is already a workspace dep (spec 002 used it for `ConsentRecord.asked_at`).

**Alternatives considered**:
- Increment suffix (`-2`, `-3`): readable but order-ambiguous if files arrive out-of-order from external tools.
- UTC timestamp: would feel "off by hours" to the Swedish user.

## R-009: Source-file SHA-256 invariant verification (test-only)

**Decision**: Add `sha2 = "0.10"` as a dev-dep (NOT a runtime dep — the constitution favors minimal dependencies). Integration tests compute SHA-256 of the source `.docx` before and after every drop scenario and assert equality.

**Rationale**: The constitution-level invariant "source file is byte-identical after a drop" needs to be tested; a hash comparison is the only honest way. Runtime code does not compute the hash — it just opens the file read-only and never writes to it. The dev-dep boundary keeps the runtime closure small.

**Alternatives considered**:
- `md5`: cryptographically weak, but tests don't need cryptographic strength. `sha2` is already in the workspace via `reqwest`'s TLS chain — no new closure entry.
- File-mtime comparison: macOS updates atime on read; mtime is what we actually want, but it's less robust than a content hash (renames within same dir don't bump mtime).

## R-010: Swedish system prompt for summarization

**Decision**: The prompt is a fixed Swedish instruction stored as a const string in `src-tauri/src/zones/prompts.rs`. Initial text:

```
Du är en svensk juriststudent som hjälper en annan student. Skriv en saklig, koncis sammanfattning på svenska av följande dokument. Behåll juridiska termer på svenska där det är möjligt. Skriv 2–6 stycken; börja inte med en hälsning eller meta-kommentar; skriv bara själva sammanfattningen.
```

**Rationale**: Fixed prompt at v1 — spec 010 (settings panel) will eventually expose model + prompt customization. Constraining to 2–6 paragraphs keeps the output bounded; the "no greeting / no meta-commentary" instruction prevents the common `gemma3:4b` opening of "Här är en sammanfattning:" which would degrade the SummaryDoc's quality.

**Alternatives considered**:
- Per-zone prompts (sammanfatta vs tillengelska vs anonymisera): yes, but spec 003 only ships one zone. Spec 004 adds the others.
- User-configurable: deferred to spec 010 (settings panel).

## R-011: Live-runtime network audit during a drop

**Decision**: Add a Playwright test (or a manual quickstart step — TBD at /tasks time) that captures `lsof -p $(pgrep -f juradrop) -i -n -P` mid-drop and asserts every entry's remote endpoint matches `127.0.0.1:*`. Pattern reused from spec 002's T054.

**Rationale**: This is the SC-003 verification — proves at runtime that no document content leaks. Encoding it as a test (vs a manual check) catches future regressions cheaply.

**Alternatives considered**:
- Static grep only: spec 002's T053 already grep-audits the source tree. A grep can't catch a future transitive dep that introduces an outbound call; the live `lsof` does.

## R-012: WebView drag-handler installation point

**Decision**: Wire the Tauri `WindowEvent::DragDrop` listener inside `lib.rs`'s `setup` callback, alongside the existing spec 002 sidecar-lifecycle wiring. Emit `juradrop://drop-file` carrying the resolved paths to the WebView. React drop zone subscribes via the same `tauri-bridge.ts` pattern as `juradrop://status`.

**Rationale**: Centralises the drag-drop entry point; the React layer stays declarative and reuses the existing event subscription infrastructure.

**Alternatives considered**:
- Install a drag handler per-component on the React side using `window.addEventListener('drop', ...)`: works in Safari/WKWebView but doesn't carry the file path (sandboxed). Already rejected in R-006.
