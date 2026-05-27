// Spec 005 — OutputFormat enum + mirror rule (FR-011).
//
// The mirror rule has one exception: PDF input maps to DOCX output
// because writing a polished PDF (font embedding, page layout) is
// out of scope. The other three formats map identity.

use serde::{Deserialize, Serialize};

use super::input_format::InputFormat;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    Docx,
    Txt,
    Md,
}

impl OutputFormat {
    /// FR-011 — output format mirrors input with one exception: PDF → DOCX.
    pub const fn mirror_from(input: InputFormat) -> Self {
        match input {
            InputFormat::Docx => Self::Docx,
            InputFormat::Pdf => Self::Docx,
            InputFormat::Txt => Self::Txt,
            InputFormat::Md => Self::Md,
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
        // FR-011 — the only non-identity mapping.
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
    fn as_str_matches_serde_lowercase_form() {
        for f in OutputFormat::ALL {
            let json = serde_json::to_string(&f).unwrap();
            assert_eq!(json, format!("\"{}\"", f.as_str()));
        }
    }
}
