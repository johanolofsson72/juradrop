// Spec 024 — large-file guard.
//
// A pre-read metadata check rejects files over MAX_INPUT_FILE_BYTES (50 MB)
// with ZoneFailure::FileTooLarge, before any per-format extractor pulls the
// whole file into memory (OOM guard). Verified with a SPARSE file so the
// test doesn't actually write 50 MB to disk.

use std::io::{Seek, SeekFrom, Write};

use juradrop_lib::zones::extract::{extract_text, MAX_INPUT_FILE_BYTES};
use juradrop_lib::zones::input_format::InputFormat;
use juradrop_lib::zones::ZoneFailure;

/// Create a sparse file of `len` bytes (seek past the end + write one byte).
/// On macOS/APFS + Linux this allocates almost no real disk.
fn sparse_file(dir: &std::path::Path, name: &str, len: u64) -> std::path::PathBuf {
    let path = dir.join(name);
    let mut f = std::fs::File::create(&path).expect("create");
    f.seek(SeekFrom::Start(len - 1)).expect("seek");
    f.write_all(&[0]).expect("write last byte");
    f.flush().expect("flush");
    path
}

#[test]
fn oversized_file_is_rejected_with_file_too_large() {
    let dir = tempfile::TempDir::new().expect("tempdir");
    // One byte over the cap.
    let path = sparse_file(dir.path(), "huge.docx", MAX_INPUT_FILE_BYTES + 1);
    let result = extract_text(&path, InputFormat::Docx);
    assert!(
        matches!(result, Err(ZoneFailure::FileTooLarge)),
        "expected FileTooLarge for a {}-byte file, got {result:?}",
        MAX_INPUT_FILE_BYTES + 1
    );
}

#[test]
fn file_at_cap_passes_the_guard() {
    // Exactly at the cap must NOT trip the guard (`>` not `>=`). A sparse
    // .txt of all-zero bytes extracts (zeros decode to text; the guard is
    // the only thing under test here — it must let this through).
    let dir = tempfile::TempDir::new().expect("tempdir");
    let path = sparse_file(dir.path(), "atcap.txt", MAX_INPUT_FILE_BYTES);
    let result = extract_text(&path, InputFormat::Txt);
    assert!(
        !matches!(result, Err(ZoneFailure::FileTooLarge)),
        "a file exactly at the cap must pass the guard, got {result:?}"
    );
}

#[test]
fn small_file_is_not_blocked_by_the_guard() {
    let dir = tempfile::TempDir::new().expect("tempdir");
    let path = dir.path().join("small.txt");
    std::fs::write(&path, "Ett kort dokument.").expect("write");
    let result = extract_text(&path, InputFormat::Txt);
    assert!(
        !matches!(result, Err(ZoneFailure::FileTooLarge)),
        "a small file must not trip the size guard, got {result:?}"
    );
}
