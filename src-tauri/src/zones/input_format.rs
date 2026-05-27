// Spec 005 — InputFormat enum + extension-based detection (FR-009).
//
// The dispatcher resolves an `InputFormat` from the dropped file's
// lowercase extension. The choice drives which extractor module runs
// (docx_extract, pdf_extract, txt_extract, md_extract) and indirectly
// which writer runs (via OutputFormat::mirror_from).

use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InputFormat {
    Docx,
    Pdf,
    Txt,
    Md,
}

impl InputFormat {
    /// FR-009 — detect the format from a file path's lowercase extension.
    /// Returns `None` for any extension outside the supported set;
    /// the dispatch maps that to `ZoneFailure::UnsupportedFormat` (FR-010).
    pub fn detect_from_path(path: &Path) -> Option<Self> {
        let ext = path.extension()?.to_str()?.to_lowercase();
        match ext.as_str() {
            "docx" => Some(Self::Docx),
            "pdf" => Some(Self::Pdf),
            "txt" => Some(Self::Txt),
            "md" => Some(Self::Md),
            _ => None,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Docx => "docx",
            Self::Pdf => "pdf",
            Self::Txt => "txt",
            Self::Md => "md",
        }
    }

    pub const ALL: [Self; 4] = [Self::Docx, Self::Pdf, Self::Txt, Self::Md];
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn detects_each_supported_lowercase_extension() {
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("a.docx")),
            Some(InputFormat::Docx)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("b.pdf")),
            Some(InputFormat::Pdf)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("c.txt")),
            Some(InputFormat::Txt)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("d.md")),
            Some(InputFormat::Md)
        );
    }

    #[test]
    fn detects_uppercase_and_mixed_case_extensions() {
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("MYDOC.PDF")),
            Some(InputFormat::Pdf)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("notes.TxT")),
            Some(InputFormat::Txt)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("Brief.Md")),
            Some(InputFormat::Md)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("Case.DocX")),
            Some(InputFormat::Docx)
        );
    }

    #[test]
    fn rejects_unsupported_extensions() {
        for path in &["foo.rtf", "foo.pages", "foo.odt", "foo.html", "foo.tar.gz"] {
            assert_eq!(InputFormat::detect_from_path(&PathBuf::from(path)), None);
        }
    }

    #[test]
    fn rejects_no_extension() {
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("README")),
            None
        );
        assert_eq!(InputFormat::detect_from_path(&PathBuf::from("file.")), None);
    }

    #[test]
    fn double_extension_uses_only_the_last_part() {
        // "mydoc.tar.gz" → extension is "gz" → unsupported
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("mydoc.tar.gz")),
            None
        );
        // "mydoc.bak.pdf" → extension is "pdf" → supported
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("mydoc.bak.pdf")),
            Some(InputFormat::Pdf)
        );
    }

    #[test]
    fn as_str_matches_serde_lowercase_form() {
        for f in InputFormat::ALL {
            let json = serde_json::to_string(&f).unwrap();
            assert_eq!(json, format!("\"{}\"", f.as_str()));
        }
    }

    #[test]
    fn all_constant_lists_every_variant_exactly_once() {
        use std::collections::HashSet;
        let unique: HashSet<_> = InputFormat::ALL.iter().collect();
        assert_eq!(unique.len(), 4);
    }
}
