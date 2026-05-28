// Spec 007 / T034 — mid-update source-immutability regression guard.
//
// Extends the spec 003 / 005 source-immutability contract with a
// "mid-update" scenario: while a fixture .docx sits on disk, drive
// the updater state machine through Unknown → Checking → Available
// and assert the document's SHA-256 is byte-identical before vs after.
// The updater path NEVER touches user file paths — this test exists
// so that contract stays a contract under future refactors.

use juradrop_lib::updater::lifecycle::{enter_checking, record_available, RemoteUpdate};
use juradrop_lib::updater::Updater;
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use tempfile::TempDir;

fn sha256_of(path: &std::path::Path) -> [u8; 32] {
    let bytes = std::fs::read(path).expect("read fixture");
    let mut h = Sha256::new();
    h.update(&bytes);
    h.finalize().into()
}

fn write_fixture_docx(dir: &std::path::Path) -> PathBuf {
    use docx_rs::{Docx, Paragraph, Run};
    let target = dir.join("dom-2026-04-29.docx");
    let mut bytes = Vec::new();
    Docx::new()
        .add_paragraph(
            Paragraph::new().add_run(Run::new().add_text("Sekretessbelagt — testdokument")),
        )
        .build()
        .pack(std::io::Cursor::new(&mut bytes))
        .expect("pack docx");
    std::fs::write(&target, &bytes).expect("write fixture");
    target
}

#[test]
fn update_check_does_not_touch_user_document_bytes() {
    let dir = TempDir::new().expect("tempdir");
    let source = write_fixture_docx(dir.path());
    let sha_before = sha256_of(&source);

    // Drive an entire update check through the lifecycle helpers — this
    // is exactly what `check_for_updates_now` does after the plugin
    // returns. None of these helpers should ever touch the filesystem.
    let mut u = Updater::new();
    assert!(enter_checking(&mut u));
    let remote = RemoteUpdate {
        version: "0.2.0".into(),
        notes: "Test release for immutability check".into(),
        download_url: "https://example.com/JuraDrop-0.2.0.dmg".into(),
    };
    assert!(record_available(&mut u, remote));

    let sha_after = sha256_of(&source);
    assert_eq!(
        sha_before, sha_after,
        "user document must be byte-identical across an update check"
    );

    // Also assert the tempdir itself didn't gain or lose entries.
    let entries: Vec<_> = std::fs::read_dir(dir.path())
        .expect("read tempdir")
        .map(|e| e.unwrap().file_name())
        .collect();
    assert_eq!(
        entries.len(),
        1,
        "update check should not have created or deleted files in the doc dir"
    );
}
