// Spec 015 — parser robustness battery.
//
// Feeds every extractor (docx/pdf/txt/md/rtf/odt) a deterministic battery
// of malformed inputs and asserts the universal invariant: NO PANIC, NO
// HANG. On failure an extractor must return the typed `ZoneFailure`, never
// unwind a stack trace into the UI (Principle VIII).
//
// Deterministic: seeded xorshift, fixed truncation points, static cases —
// identical bytes every run, so any failure is reproducible. No new deps,
// no nightly, runs on every `cargo test`. (cargo-fuzz coverage-guided
// fuzzing is a documented future enhancement, out of scope here.)

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};

use juradrop_lib::zones::extract::extract_text;
use juradrop_lib::zones::input_format::InputFormat;

const FORMATS: &[(InputFormat, &str)] = &[
    (InputFormat::Docx, "docx"),
    (InputFormat::Pdf, "pdf"),
    (InputFormat::Txt, "txt"),
    (InputFormat::Md, "md"),
    (InputFormat::Rtf, "rtf"),
    (InputFormat::Odt, "odt"),
];

/// Deterministic xorshift64 byte stream — no rng dependency.
fn seeded_bytes(seed: u64, len: usize) -> Vec<u8> {
    let mut x = seed | 1; // never zero
    let mut out = Vec::with_capacity(len);
    for _ in 0..len {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        out.push((x & 0xff) as u8);
    }
    out
}

fn probe_bytes(ext: &str) -> Option<Vec<u8>> {
    let p = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extraction-probe")
        .join(format!("extraction-probe.{ext}"));
    std::fs::read(p).ok()
}

/// The full malformed-input battery for one format. Each entry: (label, bytes).
fn battery(ext: &str) -> Vec<(String, Vec<u8>)> {
    let mut cases: Vec<(String, Vec<u8>)> = vec![
        ("empty".into(), Vec::new()),
        ("single-byte".into(), vec![0x00]),
        ("single-printable".into(), vec![b'A']),
        ("seed-1".into(), seeded_bytes(1, 4096)),
        ("seed-0xdead".into(), seeded_bytes(0xdead, 4096)),
        ("seed-0xffff".into(), seeded_bytes(0xffff, 65536)),
        ("all-null-1k".into(), vec![0u8; 1024]),
        (
            "invalid-utf8".into(),
            vec![0xff, 0xfe, 0xfd, 0xc0, 0x80, 0x80, 0xed, 0xa0, 0x80],
        ),
        ("oversized-bounded".into(), vec![b'x'; 256 * 1024]),
    ];

    // Valid magic header + garbage body (per-format magic bytes).
    let magic: &[u8] = match ext {
        "docx" | "odt" => b"PK\x03\x04", // zip
        "pdf" => b"%PDF-1.5",            // pdf
        "rtf" => b"{\\rtf1\\ansi",       // rtf
        _ => b"",
    };
    if !magic.is_empty() {
        let mut v = magic.to_vec();
        v.extend_from_slice(&seeded_bytes(7, 2048));
        cases.push(("magic+garbage".into(), v));
    }

    // Truncated valid fixtures — 1/4, 1/2, 3/4 of the committed probe.
    if let Some(valid) = probe_bytes(ext) {
        for (frac, denom) in [(1usize, 4usize), (1, 2), (3, 4)] {
            let cut = valid.len() * frac / denom;
            cases.push((format!("truncated-{frac}of{denom}"), valid[..cut].to_vec()));
        }
        // Valid file with a flipped byte in the middle.
        if !valid.is_empty() {
            let mut corrupted = valid.clone();
            let mid = corrupted.len() / 2;
            corrupted[mid] ^= 0xff;
            cases.push(("midbyte-flip".into(), corrupted));
        }
    }
    cases
}

fn write_temp(dir: &Path, ext: &str, bytes: &[u8]) -> PathBuf {
    let p = dir.join(format!("input.{ext}"));
    std::fs::write(&p, bytes).expect("write temp input");
    p
}

#[test]
fn no_extractor_panics_on_malformed_input() {
    let dir = tempfile::TempDir::new().expect("tempdir");
    let mut total = 0usize;
    let mut panicked: Vec<String> = Vec::new();

    for &(fmt, ext) in FORMATS {
        for (label, bytes) in battery(ext) {
            total += 1;
            let path = write_temp(dir.path(), ext, &bytes);
            // The inner Result (Ok best-effort | Err(ZoneFailure)) is BOTH
            // acceptable. The only failure is a panic — caught here.
            let outcome = catch_unwind(AssertUnwindSafe(|| {
                let _ = extract_text(&path, fmt);
            }));
            if outcome.is_err() {
                panicked.push(format!("{ext}/{label}"));
            }
        }
    }

    assert!(
        panicked.is_empty(),
        "extractors panicked on {} of {} inputs: {:?}",
        panicked.len(),
        total,
        panicked
    );
    // SC-002 — coverage sanity: 6 formats, each with ≥ 8 input classes.
    assert!(total >= 6 * 8, "battery too small: only {total} cases");
    println!("parser_robustness: {total} (format × malformed-input) pairs, 0 panics");
}

#[test]
fn failures_are_typed_zonefailure_not_panic() {
    // For the container formats, garbage MUST come back as a typed
    // ZoneFailure (the error path is wired), not Ok and not a panic.
    let dir = tempfile::TempDir::new().expect("tempdir");
    for &(fmt, ext) in &[
        (InputFormat::Docx, "docx"),
        (InputFormat::Odt, "odt"),
        (InputFormat::Pdf, "pdf"),
        (InputFormat::Rtf, "rtf"),
    ] {
        let path = write_temp(dir.path(), ext, &seeded_bytes(42, 4096));
        let result = extract_text(&path, fmt);
        assert!(
            result.is_err(),
            "{ext}: random garbage should be a typed ZoneFailure, got {result:?}"
        );
    }
}
