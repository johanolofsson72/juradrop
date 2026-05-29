// Spec 009 — output mirror rule parametric coverage for the long-tail
// input formats × zones. Spec 028 removed Pages, leaving {Rtf, Odt}.
//
// Asserts: for every (InputFormat ∈ {Rtf, Odt}, ZoneId) pair,
// OutputFormat::mirror_from returns Docx, and the resulting sidecar
// filename ends with the canonical `<stem>.<zone_suffix>.docx` form.
// This pins FR-009 (long-tail fallback) and C-013 (sidecar filename
// construction from the plan).

use std::path::PathBuf;

use juradrop_lib::zones::sidecar_path::canonical_for_format;
use juradrop_lib::zones::{InputFormat, OutputFormat, ZoneId};

fn long_tail_inputs() -> &'static [InputFormat] {
    &[InputFormat::Rtf, InputFormat::Odt]
}

#[test]
fn long_tail_inputs_all_mirror_to_docx() {
    for input in long_tail_inputs() {
        assert_eq!(
            OutputFormat::mirror_from(*input),
            OutputFormat::Docx,
            "InputFormat::{input:?} should mirror to Docx per spec 009 FR-009"
        );
    }
}

#[test]
fn long_tail_sidecars_end_with_docx_extension() {
    for input in long_tail_inputs() {
        let output_format = OutputFormat::mirror_from(*input);
        for zone in ZoneId::ALL {
            let source = PathBuf::from(format!("/tmp/sample.{}", input.as_str()));
            let sidecar = canonical_for_format(&source, zone, output_format);
            let sidecar_str = sidecar.to_string_lossy().into_owned();
            assert!(
                sidecar_str.ends_with(".docx"),
                "sidecar for (input={input:?}, zone={zone:?}) should end with .docx, got {sidecar_str:?}"
            );
            let expected_suffix = format!(".{}.docx", zone.sidecar_suffix());
            assert!(
                sidecar_str.ends_with(&expected_suffix),
                "sidecar for (input={input:?}, zone={zone:?}) should end with {expected_suffix:?}, got {sidecar_str:?}"
            );
        }
    }
}

#[test]
fn long_tail_sidecars_preserve_source_stem() {
    for input in long_tail_inputs() {
        let output_format = OutputFormat::mirror_from(*input);
        let source = PathBuf::from(format!("/tmp/kursplan.{}", input.as_str()));
        let sidecar = canonical_for_format(&source, ZoneId::Sammanfatta, output_format);
        let name = sidecar.file_name().unwrap().to_string_lossy().into_owned();
        assert!(
            name.starts_with("kursplan."),
            "sidecar for {input:?} should preserve source stem 'kursplan', got {name:?}"
        );
    }
}
