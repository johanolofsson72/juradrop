// Spec 005 / 009 — OutputFormat enum + mirror rule (FR-009/FR-011).
//
// The mirror rule has exceptions:
//   - PDF input → DOCX output (writing a polished PDF is out of scope).
//   - Pages input → DOCX output (Apple Pages bundles are proprietary;
//     JuraDrop never writes them back regardless of writer availability).
//   - RTF input → DOCX output (no pure-Rust RTF writer is selected;
//     see specs/009-long-tail-formats/research.md R-005).
//   - ODT input → DOCX output (no pure-Rust ODT writer is selected;
//     see specs/009-long-tail-formats/research.md R-005).
//
// The remaining variants (Docx, Txt, Md) mirror identity.

use serde::{Deserialize, Serialize};

use super::input_format::InputFormat;
use super::zone_id::ZoneId;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    Docx,
    Txt,
    Md,
    // No Rtf or Odt variants in spec 009 — the long-tail inputs all
    // mirror to .docx via the mirror_from fallback. A future spec that
    // adds pure-Rust RTF or ODT writers will add the variants and
    // adjust mirror_from to use them.
}

impl OutputFormat {
    /// FR-009 / FR-011 — output format mirrors input with four exceptions:
    /// PDF, Pages, RTF, and ODT all fall back to DOCX. The remaining
    /// three input formats (DOCX, TXT, MD) map identity.
    pub const fn mirror_from(input: InputFormat) -> Self {
        match input {
            InputFormat::Docx => Self::Docx,
            InputFormat::Pdf => Self::Docx,
            InputFormat::Txt => Self::Txt,
            InputFormat::Md => Self::Md,
            // Spec 009 — long-tail formats all fall back to .docx.
            InputFormat::Rtf => Self::Docx,
            InputFormat::Pages => Self::Docx,
            InputFormat::Odt => Self::Docx,
        }
    }

    /// Spec 013 FR-003 / analyze F2 — zone-aware output resolution.
    /// `Generera` produces a freshly generated legal *document*, so it
    /// ALWAYS writes a `.docx` sidecar regardless of the `.txt`/`.md`
    /// instruction-file input (the spec-005 input-mirror rule does not
    /// apply to a generation zone). Every other zone mirrors the input
    /// via `mirror_from`.
    pub const fn for_zone(zone: ZoneId, input: InputFormat) -> Self {
        match zone {
            ZoneId::Generera => Self::Docx,
            _ => Self::mirror_from(input),
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Docx => "docx",
            Self::Txt => "txt",
            Self::Md => "md",
        }
    }

    pub const ALL: [Self; 3] = [Self::Docx, Self::Txt, Self::Md];
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn docx_in_docx_out() {
        assert_eq!(
            OutputFormat::mirror_from(InputFormat::Docx),
            OutputFormat::Docx
        );
    }

    #[test]
    fn pdf_in_docx_out_is_the_one_exception() {
        // FR-011 — PDF → DOCX exception (inherited from spec 005).
        assert_eq!(
            OutputFormat::mirror_from(InputFormat::Pdf),
            OutputFormat::Docx
        );
    }

    #[test]
    fn txt_in_txt_out() {
        assert_eq!(
            OutputFormat::mirror_from(InputFormat::Txt),
            OutputFormat::Txt
        );
    }

    #[test]
    fn md_in_md_out() {
        assert_eq!(OutputFormat::mirror_from(InputFormat::Md), OutputFormat::Md);
    }

    #[test]
    fn rtf_in_docx_out_long_tail_fallback() {
        // Spec 009 FR-009 — no pure-Rust RTF writer selected, so
        // .rtf inputs fall back to .docx sidecar.
        assert_eq!(
            OutputFormat::mirror_from(InputFormat::Rtf),
            OutputFormat::Docx
        );
    }

    #[test]
    fn pages_in_docx_out_always() {
        // Spec 009 FR-009 — Apple Pages bundle is proprietary;
        // JuraDrop never writes it back regardless of writer availability.
        assert_eq!(
            OutputFormat::mirror_from(InputFormat::Pages),
            OutputFormat::Docx
        );
    }

    #[test]
    fn odt_in_docx_out_long_tail_fallback() {
        // Spec 009 FR-009 — no pure-Rust ODT writer selected, so
        // .odt inputs fall back to .docx sidecar.
        assert_eq!(
            OutputFormat::mirror_from(InputFormat::Odt),
            OutputFormat::Docx
        );
    }

    #[test]
    fn mirror_from_is_total() {
        // Spec 009 — iterate every InputFormat variant; mirror_from
        // must return a defined OutputFormat for each. The explicit
        // match arms (no `_ =>` catch-all) keep this total at compile
        // time; adding a future InputFormat variant is a compile error
        // until this match is updated.
        for input in InputFormat::ALL {
            let _ = OutputFormat::mirror_from(input);
        }
    }

    #[test]
    fn generera_always_outputs_docx_regardless_of_input() {
        // Spec 013 FR-003 / analyze F2 — generation zone ignores the
        // input-mirror rule; .txt/.md instructions still yield .docx.
        for input in InputFormat::ALL {
            assert_eq!(
                OutputFormat::for_zone(ZoneId::Generera, input),
                OutputFormat::Docx,
                "Generera must output docx for input {input:?}"
            );
        }
    }

    #[test]
    fn non_generera_zones_mirror_input() {
        // Every non-Generera zone defers to mirror_from.
        for zone in ZoneId::ALL {
            if zone == ZoneId::Generera {
                continue;
            }
            for input in InputFormat::ALL {
                assert_eq!(
                    OutputFormat::for_zone(zone, input),
                    OutputFormat::mirror_from(input),
                    "zone {zone:?} input {input:?} must mirror"
                );
            }
        }
    }

    #[test]
    fn as_str_matches_serde_lowercase_form() {
        for f in OutputFormat::ALL {
            let json = serde_json::to_string(&f).unwrap();
            assert_eq!(json, format!("\"{}\"", f.as_str()));
        }
    }
}
