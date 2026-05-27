// Spec 005 — Markdown sidecar writer (FR-014).
//
// Layout:
//   [optional] <captured frontmatter block verbatim>
//   # <basename> — <zone_title>
//   > <YYYY-MM-DD>
//   (blank line)
//   [optional] > *Texten kortades av — modellen såg bara början av dokumentet.*
//   (blank line if truncation blockquote present)
//   <model body>
//   (blank line if disclaimer follows)
//   [Anonymisera/Förenkla only] > **OBS!** <disclaimer>
//
// UTF-8 LF output, no BOM.

use std::path::Path;

use chrono::Local;

use super::zone_id::ZoneId;

const TRUNCATION_NOTICE: &str = "> *Texten kortades av — modellen såg bara början av dokumentet.*";

/// Build the MD sidecar body. Frontmatter (if any) is prepended verbatim.
pub fn build_sidecar(
    zone_id: ZoneId,
    source: &Path,
    response: &str,
    frontmatter: Option<&str>,
    truncated: bool,
) -> Vec<u8> {
    let basename = source
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("(okänt dokument)");
    let date = Local::now().format("%Y-%m-%d");
    let title = zone_id.title();

    let mut out = String::new();

    if let Some(fm) = frontmatter {
        out.push_str(fm);
        if !fm.ends_with('\n') {
            out.push('\n');
        }
    }

    out.push_str(&format!("# {basename} — {title}\n"));
    out.push_str(&format!("> {date}\n\n"));

    if truncated {
        out.push_str(TRUNCATION_NOTICE);
        out.push_str("\n\n");
    }

    out.push_str(response.trim_end_matches('\n'));
    out.push('\n');

    if let Some(disclaimer) = zone_id.disclaimer_paragraph() {
        out.push_str(&format!("\n> **OBS!** {disclaimer}\n"));
    }

    out.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fake_source() -> PathBuf {
        PathBuf::from("/tmp/note.md")
    }

    fn body_to_str(bytes: &[u8]) -> &str {
        std::str::from_utf8(bytes).expect("UTF-8 output")
    }

    #[test]
    fn no_frontmatter_renders_header_first() {
        let bytes = build_sidecar(ZoneId::Sammanfatta, &fake_source(), "Body.", None, false);
        let body = body_to_str(&bytes);
        assert!(body.starts_with("# note.md — Sammanfatta\n> "));
    }

    #[test]
    fn yaml_frontmatter_prepended_verbatim() {
        let fm = "---\ntitle: Min studie\ntags: [juridik]\n---\n";
        let bytes = build_sidecar(ZoneId::Forenkla, &fake_source(), "Body.", Some(fm), false);
        let body = body_to_str(&bytes);
        assert!(body.starts_with(fm));
        assert!(body.contains("# note.md — Förenkla"));
    }

    #[test]
    fn toml_frontmatter_prepended_verbatim() {
        let fm = "+++\ntitle = \"x\"\n+++\n";
        let bytes = build_sidecar(
            ZoneId::Sammanfatta,
            &fake_source(),
            "Body.",
            Some(fm),
            false,
        );
        let body = body_to_str(&bytes);
        assert!(body.starts_with(fm));
    }

    #[test]
    fn truncation_blockquote_when_flag_set() {
        let bytes = build_sidecar(ZoneId::Sammanfatta, &fake_source(), "Body.", None, true);
        let body = body_to_str(&bytes);
        assert!(body.contains("> *Texten kortades av"));
    }

    #[test]
    fn anonymisera_appends_obs_blockquote() {
        let bytes = build_sidecar(ZoneId::Anonymisera, &fake_source(), "Body.", None, false);
        let body = body_to_str(&bytes);
        assert!(body.contains("> **OBS!**"));
        assert!(body.contains(ZoneId::Anonymisera.disclaimer_paragraph().unwrap()));
    }

    #[test]
    fn forenkla_appends_different_obs_blockquote() {
        let bytes = build_sidecar(ZoneId::Forenkla, &fake_source(), "Body.", None, false);
        let body = body_to_str(&bytes);
        assert!(body.contains("> **OBS!**"));
        assert!(body.contains(ZoneId::Forenkla.disclaimer_paragraph().unwrap()));
    }

    #[test]
    fn no_disclaimer_for_other_zones() {
        for z in [
            ZoneId::Sammanfatta,
            ZoneId::TillEngelska,
            ZoneId::TillSvenska,
            ZoneId::Punktlista,
        ] {
            let bytes = build_sidecar(z, &fake_source(), "Body.", None, false);
            let body = body_to_str(&bytes);
            assert!(!body.contains("OBS!"), "OBS!-blockquote leaked into {z:?}");
        }
    }
}
