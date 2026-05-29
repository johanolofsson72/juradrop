# Implementation Plan: Silence pdf-extract stdout noise

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: spec-only

## Summary

Wrap the single noisy call (`pdf_extract::extract_text_from_mem_by_pages`, `src-tauri/src/zones/pdf_extract.rs:45`) in a mutex-guarded stdout-silence helper: save fd 1, `dup2` `/dev/null` onto it, run the closure, restore fd 1 (RAII guard restores on drop, so panics/early-returns are covered). Unix-only via `libc` (already a dep); non-unix is a transparent passthrough.

## Constitution Check

- **I. Privacy** — ✅ no network, no content involved; only redirects a file descriptor.
- **VIII. Honest Failure** — ✅ stderr (where our honest Swedish errors and `eprintln!` diagnostics live) is untouched; only library stdout chatter is dropped.
- All others unaffected. Net new deps: 0. **PASS.**

## Approach

```rust
// pdf_extract.rs
#[cfg(unix)]
fn with_stdout_silenced<T>(f: impl FnOnce() -> T) -> T { /* mutex + dup/dup2/restore RAII */ }
#[cfg(not(unix))]
fn with_stdout_silenced<T>(f: impl FnOnce() -> T) -> T { f() }
```

A `Drop`-guard restores fd 1 so the redirect can never leak even if `f()` panics. A `static Mutex<()>` serializes the window so concurrent extractions don't race the saved fd. `std::io::stdout().flush()` before redirect + before restore keeps Rust's buffered stdout consistent.

## Structure Decision

One file: `src-tauri/src/zones/pdf_extract.rs` (the helper + wrapping the line-45 call). One added unit test (output transparency). No new files, no deps.
