// Spec 005 — TXT sidecar writer (FR-013).
//
// Layout:
//   # <basename> — <zone_title> — <YYYY-MM-DD>
//   (blank line)
//   [optional] # Texten kortades av — modellen såg bara början av dokumentet.
//   (blank line if truncation comment present)
//   <model body>
//   (blank line if disclaimer follows)
//   [Anonymisera/Förenkla only] # <disclaimer>
//
// UTF-8 LF output, no BOM, no trailing newline.

use std::path::Path;

use chrono::Local;

use super::zone_id::ZoneId;

const TRUNCATION_NOTICE: &str = "# Texten kortades av — modellen såg bara början av dokumentet.";

/// Build the TXT sidecar body. Returns the bytes ready to write
/// atomically.
pub fn build_sidecar(zone_id: ZoneId, source: &Path, response: &str, truncated: bool) -> Vec<u8> {
    let basename = source
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("(okänt dokument)");
    let date = Local::now().format("%Y-%m-%d");
    let title = zone_id.title();

    let mut out = String::new();
    out.push_str(&format!("# {basename} — {title} — {date}"));
    out.push_str("\n\n");

    if truncated {
        out.push_str(TRUNCATION_NOTICE);
        out.push_str("\n\n");
    }

    out.push_str(response.trim_end_matches('\n'));

    if let Some(disclaimer) = zone_id.disclaimer_paragraph() {
        out.push_str("\n\n# ");
        out.push_str(disclaimer);
    }

    out.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fake_source() -> PathBuf {
        PathBuf::from("/tmp/notes.txt")
    }

    fn body_to_str(bytes: &[u8]) -> &str {
        std::str::from_utf8(bytes).expect("UTF-8 output")
    }

    #[test]
    fn header_contains_basename_title_and_date() {
        let bytes = build_sidecar(ZoneId::Sammanfatta, &fake_source(), "Body text.", false);
        let body = body_to_str(&bytes);
        assert!(body.starts_with("# notes.txt — Sammanfatta — "));
        assert!(body.contains("Body text."));
    }

    #[test]
    fn truncation_comment_present_when_flag_set() {
        let bytes = build_sidecar(ZoneId::Sammanfatta, &fake_source(), "Body.", true);
        let body = body_to_str(&bytes);
        assert!(body.contains("Texten kortades av"));
    }

    #[test]
    fn truncation_comment_absent_when_flag_unset() {
        let bytes = build_sidecar(ZoneId::Sammanfatta, &fake_source(), "Body.", false);
        let body = body_to_str(&bytes);
        assert!(!body.contains("Texten kortades av"));
    }

    #[test]
    fn anonymisera_zone_appends_disclaimer_comment() {
        let bytes = build_sidecar(ZoneId::Anonymisera, &fake_source(), "Person A...", false);
        let body = body_to_str(&bytes);
        assert!(body.ends_with(&format!(
            "\n\n# {}",
            ZoneId::Anonymisera.disclaimer_paragraph().unwrap()
        )));
    }

    #[test]
    fn forenkla_zone_appends_disclaimer_comment() {
        let bytes = build_sidecar(ZoneId::Forenkla, &fake_source(), "Förenklat.", false);
        let body = body_to_str(&bytes);
        assert!(body.ends_with(&format!(
            "\n\n# {}",
            ZoneId::Forenkla.disclaimer_paragraph().unwrap()
        )));
    }

    #[test]
    fn no_disclaimer_for_non_anonymisera_forenkla_zones() {
        for z in [
            ZoneId::Sammanfatta,
            ZoneId::TillEngelska,
            ZoneId::TillSvenska,
            ZoneId::Punktlista,
        ] {
            let bytes = build_sidecar(z, &fake_source(), "Body.", false);
            let body = body_to_str(&bytes);
            assert!(!body.contains("granska"), "disclaimer leaked into {z:?}");
        }
    }

    #[test]
    fn output_is_utf8_with_lf_line_endings() {
        let bytes = build_sidecar(ZoneId::Sammanfatta, &fake_source(), "Hej.", false);
        assert!(std::str::from_utf8(&bytes).is_ok());
        assert!(!bytes.contains(&b'\r'));
    }

    #[test]
    fn output_has_no_trailing_newline() {
        let bytes = build_sidecar(ZoneId::Sammanfatta, &fake_source(), "Hej.", false);
        let body = body_to_str(&bytes);
        assert!(!body.ends_with('\n'));
    }
}
