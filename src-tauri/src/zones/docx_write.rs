// Spec 003 / T015 + spec 004 / T015 — build the per-zone summary `.docx`.
//
// Output structure per `specs/004-all-six-zones/contracts/docx-format.md`:
//   paragraph 0  — per-zone header from ZoneId::header_paragraph_template() (bold)
//   paragraph 1  — "Genererad <ts> av JuraDrop med modellen gemma3:4b." (regular)
//   paragraph 2  — truncation notice                                    (italic, optional)
//   paragraph 3  — per-zone disclaimer (Anonymisera + Förenkla only)    (italic, conditional)
//   paragraph 4  — empty spacer                                          (always)
//   paragraph 5+ — model response, split on `\n\n`                       (1+)

use std::io::Cursor;
use std::path::Path;

use chrono::Local;
use docx_rs::{Docx, Paragraph, Run};

use super::zone_id::ZoneId;

const TRUNCATION_NOTICE: &str =
    "(Dokumentet förkortades innan sammanfattning — endast början är sammanfattad.)";

const MODEL_LABEL: &str = "gemma3:4b";

/// Construct a serialized per-zone `.docx`.
///
/// - `zone_id`     — selects the FR-009 header template + optional disclaimer.
/// - `source`      — used for the {name} substitution in the header.
/// - `response`    — the model output. Split on `\n\n` into body paragraphs.
/// - `truncated`   — toggles the FR-019 truncation notice paragraph.
pub fn build_summary_doc(
    zone_id: ZoneId,
    source: &Path,
    response: &str,
    truncated: bool,
) -> Vec<u8> {
    let basename = source
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("(okänt dokument)");
    let generated_at = Local::now().format("%Y-%m-%d %H:%M");

    let header_filename = zone_id
        .header_paragraph_template()
        .replace("{name}", basename);
    let header_meta = format!("Genererad {generated_at} av JuraDrop med modellen {MODEL_LABEL}.");

    let mut docx = Docx::new()
        .add_paragraph(Paragraph::new().add_run(Run::new().add_text(&header_filename).bold()))
        .add_paragraph(Paragraph::new().add_run(Run::new().add_text(&header_meta)));

    if truncated {
        docx = docx.add_paragraph(
            Paragraph::new().add_run(Run::new().add_text(TRUNCATION_NOTICE).italic()),
        );
    }

    // FR-013 + FR-014 — disclaimer paragraph for Anonymise + Förenkla only.
    if let Some(disclaimer) = zone_id.disclaimer_paragraph() {
        docx =
            docx.add_paragraph(Paragraph::new().add_run(Run::new().add_text(disclaimer).italic()));
    }

    // Spacer between header block and body.
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
    fn sammanfatta_header_uses_sammanfattning_template() {
        let bytes = build_summary_doc(
            ZoneId::Sammanfatta,
            &fake_source(),
            "En koncis sammanfattning.",
            false,
        );
        let extracted = extract_text_from_bytes(&bytes).expect("output must parse");
        assert!(extracted
            .raw
            .as_inner()
            .contains("Sammanfattning av 'my-ruling.docx'"));
    }

    #[test]
    fn tillengelska_header_uses_oversattning_template() {
        let bytes = build_summary_doc(ZoneId::TillEngelska, &fake_source(), "English text.", false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("Översättning till engelska av 'my-ruling.docx'"));
    }

    #[test]
    fn punktlista_header_uses_punktlista_template() {
        let bytes = build_summary_doc(ZoneId::Punktlista, &fake_source(), "- A\n- B", false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("Punktlista över 'my-ruling.docx'"));
    }

    #[test]
    fn anonymisera_includes_fr013_disclaimer_paragraph() {
        let bytes = build_summary_doc(ZoneId::Anonymisera, &fake_source(), "Person A...", false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("AI-anonymisering är inte hundra procent"));
    }

    #[test]
    fn forenkla_includes_fr014_disclaimer_paragraph() {
        let bytes = build_summary_doc(ZoneId::Forenkla, &fake_source(), "Förenklad…", false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("Förenklad version — granska att inga juridiska poänger"));
    }

    #[test]
    fn sammanfatta_has_no_disclaimer_paragraph() {
        let bytes = build_summary_doc(ZoneId::Sammanfatta, &fake_source(), "Text.", false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(!extracted
            .raw
            .as_inner()
            .contains("AI-anonymisering är inte hundra procent"));
        assert!(!extracted.raw.as_inner().contains("Förenklad version"));
    }

    #[test]
    fn meta_paragraph_includes_model_label() {
        let bytes = build_summary_doc(ZoneId::Sammanfatta, &fake_source(), "Hej.", false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted.raw.as_inner().contains("gemma3:4b"));
        assert!(extracted
            .raw
            .as_inner()
            .contains("av JuraDrop med modellen"));
    }

    #[test]
    fn truncation_notice_present_only_when_flag_set() {
        let with_notice =
            build_summary_doc(ZoneId::Sammanfatta, &fake_source(), "Kort text.", true);
        let extracted = extract_text_from_bytes(&with_notice).unwrap();
        assert!(extracted.raw.as_inner().contains("Dokumentet förkortades"));

        let without = build_summary_doc(ZoneId::Sammanfatta, &fake_source(), "Kort text.", false);
        let extracted2 = extract_text_from_bytes(&without).unwrap();
        assert!(!extracted2.raw.as_inner().contains("Dokumentet förkortades"));
    }

    #[test]
    fn body_paragraphs_split_on_double_newline() {
        let body = "Första.\n\nAndra.\n\nTredje.";
        let bytes = build_summary_doc(ZoneId::Sammanfatta, &fake_source(), body, false);
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        let raw = extracted.raw.as_inner();
        assert!(raw.contains("Första."));
        assert!(raw.contains("Andra."));
        assert!(raw.contains("Tredje."));
    }
}
