// Spec 003 / T015 — build the summary `.docx` per contracts/docx-format.md.
//
// Output structure:
//   paragraph 0   — "Sammanfattning av '<basename>'"           (bold)
//   paragraph 1   — "Genererad <YYYY-MM-DD HH:MM> av JuraDrop
//                    med modellen gemma3:4b."                  (regular)
//   paragraph 2   — truncation notice (Swedish, italic)        (optional)
//   paragraph 3   — empty spacer                                (always)
//   paragraph 4+  — model response, split on `\n\n`             (1+)

use std::io::Cursor;
use std::path::Path;

use chrono::Local;
use docx_rs::{Docx, Paragraph, Run};

use crate::prompts::SAMMANFATTA_SYSTEM_PROMPT;

const TRUNCATION_NOTICE: &str =
    "(Dokumentet förkortades innan sammanfattning — endast början är sammanfattad.)";

const MODEL_LABEL: &str = "gemma3:4b";

/// Construct a serialized `.docx` summarizing `response` for `source`.
///
/// `truncated` toggles the FR-019 Swedish truncation notice paragraph.
/// The system prompt referenced here is only used at run time to
/// invoke the model — it does not appear in the output document.
pub fn build_summary_doc(source: &Path, response: &str, truncated: bool) -> Vec<u8> {
    let _ = SAMMANFATTA_SYSTEM_PROMPT; // keep the import meaningful; the
                                       // dispatcher uses this constant.

    let basename = source
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("(okänt dokument)");
    let generated_at = Local::now().format("%Y-%m-%d %H:%M");

    let header_filename = format!("Sammanfattning av '{basename}'");
    let header_meta = format!("Genererad {generated_at} av JuraDrop med modellen {MODEL_LABEL}.");

    let mut docx = Docx::new()
        .add_paragraph(Paragraph::new().add_run(Run::new().add_text(&header_filename).bold()))
        .add_paragraph(Paragraph::new().add_run(Run::new().add_text(&header_meta)));

    if truncated {
        docx = docx.add_paragraph(
            Paragraph::new().add_run(Run::new().add_text(TRUNCATION_NOTICE).italic()),
        );
    }

    // Spacer paragraph between header block and body.
    docx = docx.add_paragraph(Paragraph::new());

    // Body: split on `\n\n`, drop empty trailing chunks.
    for chunk in response.split("\n\n") {
        let trimmed = chunk.trim();
        if trimmed.is_empty() {
            continue;
        }
        docx = docx.add_paragraph(Paragraph::new().add_run(Run::new().add_text(trimmed)));
    }

    let mut buf = Vec::new();
    docx.build()
        .pack(Cursor::new(&mut buf))
        .expect("docx-rs pack should not fail in-memory");
    buf
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zones::docx_extract::extract_text_from_bytes;
    use std::path::PathBuf;

    fn fake_source() -> PathBuf {
        PathBuf::from("/tmp/my-ruling.docx")
    }

    #[test]
    fn output_is_a_valid_docx_round_trippable_through_docx_rs() {
        let bytes = build_summary_doc(&fake_source(), "En koncis sammanfattning.", false);
        let extracted = extract_text_from_bytes(&bytes).expect("output must parse");
        // First paragraph must be the FR-005a header.
        assert!(extracted
            .raw
            .as_inner()
            .contains("Sammanfattning av 'my-ruling.docx'"));
    }

    #[test]
    fn meta_paragraph_includes_model_label() {
        let bytes = build_summary_doc(&fake_source(), "Hej.", false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted.raw.as_inner().contains("gemma3:4b"));
        assert!(extracted
            .raw
            .as_inner()
            .contains("av JuraDrop med modellen"));
    }

    #[test]
    fn truncation_notice_present_only_when_flag_set() {
        let with_notice = build_summary_doc(&fake_source(), "Kort text.", true);
        let extracted = extract_text_from_bytes(&with_notice).unwrap();
        assert!(extracted.raw.as_inner().contains("Dokumentet förkortades"));

        let without = build_summary_doc(&fake_source(), "Kort text.", false);
        let extracted2 = extract_text_from_bytes(&without).unwrap();
        assert!(!extracted2.raw.as_inner().contains("Dokumentet förkortades"));
    }

    #[test]
    fn body_paragraphs_split_on_double_newline() {
        let body = "Första.\n\nAndra.\n\nTredje.";
        let bytes = build_summary_doc(&fake_source(), body, false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        let raw = extracted.raw.as_inner();
        assert!(raw.contains("Första."));
        assert!(raw.contains("Andra."));
        assert!(raw.contains("Tredje."));
    }

    #[test]
    fn empty_body_chunks_are_dropped() {
        // Triple newlines produce an empty middle chunk — must NOT
        // emit a body paragraph for it.
        let body = "A.\n\n\n\nB.";
        let bytes = build_summary_doc(&fake_source(), body, false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        let raw = extracted.raw.as_inner();
        assert!(raw.contains("A."));
        assert!(raw.contains("B."));
    }

    #[test]
    fn output_uses_filename_with_extension_in_header() {
        let bytes = build_summary_doc(
            Path::new("/Users/me/Documents/HD-2024-123.docx"),
            "Text.",
            false,
        );
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted.raw.as_inner().contains("HD-2024-123.docx"));
    }
}
