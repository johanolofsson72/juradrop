// Spec 005 / 009 — InputFormat enum + extension-based detection (FR-009).
//
// The dispatcher resolves an `InputFormat` from the dropped file's
// lowercase extension. The choice drives which extractor module runs
// (docx_extract, pdf_extract, txt_extract, md_extract, rtf_extract,
// pages_extract, odt_extract) and indirectly which writer runs
// (via OutputFormat::mirror_from).
//
// Spec 009 added three long-tail variants (Rtf, Pages, Odt). Spec 028
// REMOVED Pages — modern Pages (v5+) stores text in Snappy+Protobuf `.iwa`
// blobs with no stable extraction path, so the app no longer claims to read
// it (a dropped `.pages` now routes to `ZoneFailure::PagesUnsupported`).
// Total variant count is pinned at 6.

use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InputFormat {
    Docx,
    Pdf,
    Txt,
    Md,
    // Spec 009 — long-tail formats (Pages removed in spec 028).
    Rtf,
    Odt,
}

impl InputFormat {
    /// FR-009 + FR-002 — detect the format from a file path's lowercase
    /// extension. Returns `None` for any extension outside the supported
    /// set; the dispatch maps that to `ZoneFailure::InvalidFormat` (FR-010).
    pub fn detect_from_path(path: &Path) -> Option<Self> {
        let ext = path.extension()?.to_str()?.to_lowercase();
        match ext.as_str() {
            "docx" => Some(Self::Docx),
            "pdf" => Some(Self::Pdf),
            "txt" => Some(Self::Txt),
            "md" => Some(Self::Md),
            "rtf" => Some(Self::Rtf),
            "odt" => Some(Self::Odt),
            _ => None,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Docx => "docx",
            Self::Pdf => "pdf",
            Self::Txt => "txt",
            Self::Md => "md",
            Self::Rtf => "rtf",
            Self::Odt => "odt",
        }
    }

    pub const ALL: [Self; 6] = [
        Self::Docx,
        Self::Pdf,
        Self::Txt,
        Self::Md,
        Self::Rtf,
        Self::Odt,
    ];
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
        // Spec 009 — long-tail formats.
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("e.rtf")),
            Some(InputFormat::Rtf)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("g.odt")),
            Some(InputFormat::Odt)
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
        // Spec 009 — long-tail formats.
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("File.RTF")),
            Some(InputFormat::Rtf)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("Notes.OdT")),
            Some(InputFormat::Odt)
        );
    }

    #[test]
    fn pages_is_no_longer_detected_any_case() {
        // Spec 028 — .pages was removed from the supported set; detection
        // returns None so the drop handler can route it to the explicit
        // PagesUnsupported message.
        for p in &["f.pages", "Letter.Pages", "X.PAGES", "project.old.pages"] {
            assert_eq!(
                InputFormat::detect_from_path(&PathBuf::from(*p)),
                None,
                "{p} must not detect as a supported format"
            );
        }
    }

    #[test]
    fn rejects_unsupported_extensions() {
        // Spec 009 removed .rtf, .pages, .odt from this list — they are
        // now supported. .doc (Word 97 binary), .epub, .html, .csv,
        // .eml, and the .tar.gz double-extension stay rejected.
        for path in &[
            "foo.doc",
            "foo.epub",
            "foo.html",
            "foo.csv",
            "foo.eml",
            "foo.tar.gz",
            "foo.pages", // spec 028 — Pages removed
        ] {
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
        // Spec 009 — analogous for the long-tail formats.
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("draft.bak.rtf")),
            Some(InputFormat::Rtf)
        );
        assert_eq!(
            InputFormat::detect_from_path(&PathBuf::from("notes.backup.odt")),
            Some(InputFormat::Odt)
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
        assert_eq!(unique.len(), 6);
    }
}
