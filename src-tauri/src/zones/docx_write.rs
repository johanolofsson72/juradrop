// Spec 003 / T015 + spec 004 / T015 — build the per-zone summary `.docx`.
// Spec 036 follow-up — typography pass for a print-ready result.
//
// Output structure:
//   title    — per-zone header from ZoneId::header_paragraph_template() (bold, 16 pt)
//   meta     — "Genererad <ts> av JuraDrop med modellen gemma3:4b."     (italic grey, 10 pt)
//   notices  — partial-PDF + truncation notices                          (italic grey, optional)
//   disclaim — per-zone disclaimer                                       (italic grey, conditional)
//   spacer   — empty paragraph                                           (always)
//   body     — model response, ONE paragraph per non-empty line:
//                · `- ` lines      → real indented Word bullets
//                · heading lines   → bold 14 pt with air above (IRAC labels / lines ending `:`)
//                · everything else → 12 pt Times New Roman body
//   Document-wide: Times New Roman 12 pt, 1.15 line height, 8 pt after each paragraph.

use std::io::Cursor;
use std::path::Path;

use chrono::Local;
use docx_rs::{
    AbstractNumbering, Docx, IndentLevel, Level, LevelJc, LevelText, LineSpacing, LineSpacingType,
    NumberFormat, Numbering, NumberingId, Paragraph, Run, RunFonts, SpecialIndentType, Start,
};

use super::errors::ZoneFailure;
use super::zone_id::ZoneId;

// Spec 036 follow-up — output typography. The finished `.docx` should be usable
// without editing: a classic serif (Times New Roman, the Swedish legal
// standard), 1.15 line height, 8 pt of air after every paragraph so list items
// and text blocks breathe, bold headings, and real indented Word bullets.
const BODY_FONT: &str = "Times New Roman";
const BODY_SIZE: usize = 24; // half-points → 12 pt (legal standard)
const TITLE_SIZE: usize = 32; // 16 pt
const META_SIZE: usize = 20; // 10 pt
const HEADING_SIZE: usize = 28; // 14 pt
const META_COLOR: &str = "595959"; // muted grey for meta + notices
const SPACE_AFTER: u32 = 160; // twips → 8 pt air after each paragraph
const LINE_HEIGHT: i32 = 276; // 1.15× line spacing (276 / 240)
const BULLET_NUM_ID: usize = 1; // Word numbering id for the bullet list

/// Body line spacing: 1.15× with 8 pt after — the document-wide default.
fn body_line_spacing() -> LineSpacing {
    LineSpacing::new()
        .line_rule(LineSpacingType::Auto)
        .line(LINE_HEIGHT)
        .after(SPACE_AFTER)
}

/// Does this body line start with a list-item marker?
fn is_bullet(line: &str) -> bool {
    let l = line.trim_start();
    l.starts_with("- ") || l.starts_with("* ") || l.starts_with("• ") || l.starts_with("– ")
}

/// Strip a leading list-item marker so the text rides under a real Word bullet.
fn strip_bullet_marker(line: &str) -> &str {
    let l = line.trim_start();
    for m in ["- ", "* ", "• ", "– "] {
        if let Some(rest) = l.strip_prefix(m) {
            return rest.trim_start();
        }
    }
    l
}

/// A real Word bullet list: 0.5" left indent with a 0.25" hanging indent so the
/// "•" glyph hangs and wrapped lines align under the text (not the bullet).
fn bullet_numbering() -> AbstractNumbering {
    AbstractNumbering::new(BULLET_NUM_ID).add_level(
        Level::new(
            0,
            Start::new(1),
            NumberFormat::new("bullet"),
            LevelText::new("•"),
            LevelJc::new("left"),
        )
        .indent(Some(720), Some(SpecialIndentType::Hanging(360)), None, None),
    )
}

/// A heading-style body line: a known IRAC / structural label, or a short line
/// that ends with a colon (and is not a list item). Rendered bold with extra
/// air above so sections stand out.
fn looks_like_heading(line: &str) -> bool {
    const LABELS: [&str; 4] = ["Rättsfråga", "Gällande rätt", "Subsumtion", "Slutsats"];
    let l = line.trim();
    if LABELS.iter().any(|h| l.eq_ignore_ascii_case(h)) {
        return true;
    }
    l.ends_with(':') && l.chars().count() <= 60 && !is_bullet(l)
}

const TRUNCATION_NOTICE: &str =
    "(Dokumentet förkortades innan sammanfattning — endast början är sammanfattad.)";

// Spec 005 / FR-002a — Swedish partial-extraction notice for PDFs
// where pdf-extract recovered text from fewer than 100% of pages.
pub const PARTIAL_EXTRACTION_NOTICE: &str =
    "(Delar av PDF-filen kunde inte läsas — resultatet kan vara ofullständigt.)";

const MODEL_LABEL: &str = "gemma3:4b";

/// Construct a serialized per-zone `.docx`.
///
/// - `zone_id`     — selects the FR-009 header template + optional disclaimer.
/// - `source`      — used for the {name} substitution in the header.
/// - `response`    — the model output. One paragraph per non-empty line, with
///   heading-style lines bolded; the whole document uses a clean font + air.
/// - `truncated`   — toggles the FR-019 truncation notice paragraph.
/// - `was_partial` — (spec 005 FR-002a) toggles the Swedish partial-PDF notice.
pub fn build_summary_doc(
    zone_id: ZoneId,
    source: &Path,
    response: &str,
    truncated: bool,
    was_partial: bool,
) -> Result<Vec<u8>, ZoneFailure> {
    let basename = source
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("(okänt dokument)");
    let generated_at = Local::now().format("%Y-%m-%d %H:%M");

    let header_filename = zone_id
        .header_paragraph_template()
        .replace("{name}", basename);
    let header_meta = format!("Genererad {generated_at} av JuraDrop med modellen {MODEL_LABEL}.");

    // Muted-grey italic styling shared by the meta line + the notices.
    let meta_run = |text: &str| {
        Run::new()
            .add_text(text)
            .italic()
            .size(META_SIZE)
            .color(META_COLOR)
    };

    let mut docx = Docx::new()
        // Document-wide typography defaults: classic serif, 12 pt, 1.15 line
        // height + 8 pt after every paragraph (the "air").
        .default_fonts(RunFonts::new().ascii(BODY_FONT).hi_ansi(BODY_FONT))
        .default_size(BODY_SIZE)
        .default_line_spacing(body_line_spacing())
        // Real Word bullet list definition (used by `- ` lines below).
        .add_abstract_numbering(bullet_numbering())
        .add_numbering(Numbering::new(BULLET_NUM_ID, BULLET_NUM_ID))
        // Title — bold, larger.
        .add_paragraph(
            Paragraph::new().add_run(
                Run::new()
                    .add_text(&header_filename)
                    .bold()
                    .size(TITLE_SIZE),
            ),
        )
        // Meta — small, muted, italic.
        .add_paragraph(Paragraph::new().add_run(meta_run(&header_meta)));

    // Spec 005 FR-002a — partial PDF notice comes BEFORE the truncation
    // notice (root-cause before symptom).
    if was_partial {
        docx = docx.add_paragraph(Paragraph::new().add_run(meta_run(PARTIAL_EXTRACTION_NOTICE)));
    }

    if truncated {
        docx = docx.add_paragraph(Paragraph::new().add_run(meta_run(TRUNCATION_NOTICE)));
    }

    // FR-013 + FR-014 — disclaimer paragraph (Anonymisera/Förenkla/Generera +
    // the spec 036 study-method zones).
    if let Some(disclaimer) = zone_id.disclaimer_paragraph() {
        docx = docx.add_paragraph(Paragraph::new().add_run(meta_run(disclaimer)));
    }

    // Spacer between the header block and the body.
    docx = docx.add_paragraph(Paragraph::new());

    // Body: one paragraph per non-empty line, so list items, IRAC headings, and
    // term→definition pairs keep their structure (the model separates them with
    // SINGLE newlines — splitting only on `\n\n` collapsed them into a wall of
    // text). Blank lines are skipped, so flowing prose with `\n\n` between
    // paragraphs renders one paragraph each, as before. Heading-style lines are
    // bolded with extra air above so sections stand out (every paragraph already
    // carries 8 pt of air after it via the document default).
    for line in response.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if is_bullet(trimmed) {
            // Real indented Word bullet — the "•" + indent come from the
            // numbering definition, so only the text rides in the run.
            docx = docx.add_paragraph(
                Paragraph::new()
                    .numbering(NumberingId::new(BULLET_NUM_ID), IndentLevel::new(0))
                    .add_run(Run::new().add_text(strip_bullet_marker(trimmed))),
            );
        } else if looks_like_heading(trimmed) {
            let heading = trimmed.trim_end_matches(':').trim();
            docx = docx.add_paragraph(
                Paragraph::new()
                    .line_spacing(
                        LineSpacing::new()
                            .line_rule(LineSpacingType::Auto)
                            .line(LINE_HEIGHT)
                            .before(240) // 12 pt air above a heading
                            .after(80), // 4 pt below
                    )
                    .add_run(Run::new().add_text(heading).bold().size(HEADING_SIZE)),
            );
        } else {
            docx = docx.add_paragraph(Paragraph::new().add_run(Run::new().add_text(trimmed)));
        }
    }

    let mut buf = Vec::new();
    // Packing into an in-memory Vec is effectively infallible, but the output
    // pipeline must never panic (Principle VIII) — a pack failure surfaces as
    // the existing honest "Kunde inte spara…" SaveError instead of a crash.
    docx.build()
        .pack(Cursor::new(&mut buf))
        .map_err(|_| ZoneFailure::SaveError)?;
    Ok(buf)
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
            false,
        )
        .unwrap();
        let extracted = extract_text_from_bytes(&bytes).expect("output must parse");
        assert!(extracted
            .raw
            .as_inner()
            .contains("Sammanfattning av 'my-ruling.docx'"));
    }

    #[test]
    fn tillengelska_header_uses_oversattning_template() {
        let bytes = build_summary_doc(
            ZoneId::TillEngelska,
            &fake_source(),
            "English text.",
            false,
            false,
        )
        .unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("Översättning till engelska av 'my-ruling.docx'"));
    }

    #[test]
    fn punktlista_header_uses_punktlista_template() {
        let bytes = build_summary_doc(ZoneId::Punktlista, &fake_source(), "- A\n- B", false, false)
            .unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("Punktlista över 'my-ruling.docx'"));
    }

    #[test]
    fn anonymisera_includes_fr013_disclaimer_paragraph() {
        let bytes = build_summary_doc(
            ZoneId::Anonymisera,
            &fake_source(),
            "Person A...",
            false,
            false,
        )
        .unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("AI-anonymisering är inte hundra procent"));
    }

    #[test]
    fn forenkla_includes_fr014_disclaimer_paragraph() {
        let bytes = build_summary_doc(ZoneId::Forenkla, &fake_source(), "Förenklad…", false, false)
            .unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("Förenklad version — granska att inga juridiska poänger"));
    }

    #[test]
    fn sammanfatta_has_no_disclaimer_paragraph() {
        let bytes =
            build_summary_doc(ZoneId::Sammanfatta, &fake_source(), "Text.", false, false).unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(!extracted
            .raw
            .as_inner()
            .contains("AI-anonymisering är inte hundra procent"));
        assert!(!extracted.raw.as_inner().contains("Förenklad version"));
    }

    #[test]
    fn meta_paragraph_includes_model_label() {
        let bytes =
            build_summary_doc(ZoneId::Sammanfatta, &fake_source(), "Hej.", false, false).unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted.raw.as_inner().contains("gemma3:4b"));
        assert!(extracted
            .raw
            .as_inner()
            .contains("av JuraDrop med modellen"));
    }

    #[test]
    fn truncation_notice_present_only_when_flag_set() {
        let with_notice = build_summary_doc(
            ZoneId::Sammanfatta,
            &fake_source(),
            "Kort text.",
            true,
            false,
        )
        .unwrap();
        let extracted = extract_text_from_bytes(&with_notice).unwrap();
        assert!(extracted.raw.as_inner().contains("Dokumentet förkortades"));

        let without = build_summary_doc(
            ZoneId::Sammanfatta,
            &fake_source(),
            "Kort text.",
            false,
            false,
        )
        .unwrap();
        let extracted2 = extract_text_from_bytes(&without).unwrap();
        assert!(!extracted2.raw.as_inner().contains("Dokumentet förkortades"));
    }

    #[test]
    fn body_paragraphs_split_on_double_newline() {
        let body = "Första.\n\nAndra.\n\nTredje.";
        let bytes =
            build_summary_doc(ZoneId::Sammanfatta, &fake_source(), body, false, false).unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        let raw = extracted.raw.as_inner();
        assert!(raw.contains("Första."));
        assert!(raw.contains("Andra."));
        assert!(raw.contains("Tredje."));
    }

    // Spec 036 follow-up — output formatting.

    #[test]
    fn bullet_lines_become_real_word_bullets_without_the_text_marker() {
        let body = "- Första punkten\n- Andra punkten";
        let bytes =
            build_summary_doc(ZoneId::Punktlista, &fake_source(), body, false, false).unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        let raw = extracted.raw.as_inner();
        // Content is preserved...
        assert!(raw.contains("Första punkten"));
        assert!(raw.contains("Andra punkten"));
        // ...but the "- " marker is gone — the bullet is a Word numbering glyph
        // (a paragraph property), not run text.
        assert!(!raw.contains("- Första"));
    }

    #[test]
    fn heading_like_lines_keep_their_text_and_body_follows() {
        let body = "Rättsfråga\nHar köparen rätt att häva?\n\nSlutsats\nSannolikt prisavdrag.";
        let bytes =
            build_summary_doc(ZoneId::Strukturera, &fake_source(), body, false, false).unwrap();
        let raw = extract_text_from_bytes(&bytes).unwrap();
        let raw = raw.raw.as_inner();
        assert!(raw.contains("Rättsfråga"));
        assert!(raw.contains("Slutsats"));
        assert!(raw.contains("Har köparen rätt att häva?"));
        assert!(raw.contains("Sannolikt prisavdrag."));
    }

    // ============================================================
    // Spec 005 / T018 — partial-PDF notice rendering tests.
    // ============================================================

    #[test]
    fn partial_pdf_flag_inserts_swedish_partial_notice() {
        let bytes = build_summary_doc(
            ZoneId::Sammanfatta,
            &fake_source(),
            "Body text.",
            false,
            true, // was_partial
        )
        .unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(extracted
            .raw
            .as_inner()
            .contains("Delar av PDF-filen kunde inte läsas"));
    }

    #[test]
    fn partial_notice_appears_when_both_partial_and_truncated_are_set() {
        let bytes = build_summary_doc(
            ZoneId::Sammanfatta,
            &fake_source(),
            "Body text.",
            true, // truncated
            true, // was_partial
        )
        .unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        let raw = extracted.raw.as_inner();
        assert!(raw.contains("Delar av PDF-filen kunde inte läsas"));
        assert!(raw.contains("Dokumentet förkortades"));
        // Partial notice must precede the truncation notice (root cause
        // before the symptom). Find both occurrences and check order.
        let partial_idx = raw
            .find("Delar av PDF-filen")
            .expect("partial notice present");
        let truncation_idx = raw
            .find("Dokumentet förkortades")
            .expect("truncation notice present");
        assert!(
            partial_idx < truncation_idx,
            "partial notice must precede truncation notice"
        );
    }

    #[test]
    fn no_partial_notice_when_flag_unset() {
        let bytes = build_summary_doc(
            ZoneId::Sammanfatta,
            &fake_source(),
            "Body text.",
            false,
            false,
        )
        .unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        assert!(!extracted.raw.as_inner().contains("Delar av PDF-filen"));
    }

    #[test]
    fn partial_notice_and_disclaimer_both_present_on_anonymisera() {
        let bytes = build_summary_doc(
            ZoneId::Anonymisera,
            &fake_source(),
            "Person A...",
            false,
            true,
        )
        .unwrap();
        let extracted = extract_text_from_bytes(&bytes).unwrap();
        let raw = extracted.raw.as_inner();
        assert!(raw.contains("Delar av PDF-filen kunde inte läsas"));
        assert!(raw.contains("AI-anonymisering är inte hundra procent"));
    }
}
