// Spec 004 / T003 — ZoneId discriminator + associated identity functions.
// Spec 013 — expanded from 6 to 9 variants (added Kontakter, Generera, Kallor).
//
// Nine unit variants, one per drop zone. Associated functions return
// the per-zone slug, title, hint copy, sidecar suffix, header
// paragraph template, system prompt, and optional disclaimer. Using
// `match` on the enum makes every callsite exhaustive at compile time
// — adding a tenth variant lights up every call site until handled.

use serde::{Deserialize, Serialize};

use crate::prompts::{
    ANONYMISERA_SYSTEM_PROMPT, FORENKLA_SYSTEM_PROMPT, GENERERA_SYSTEM_PROMPT,
    KALLOR_SYSTEM_PROMPT, KONTAKTER_SYSTEM_PROMPT, PUNKTLISTA_SYSTEM_PROMPT,
    SAMMANFATTA_SYSTEM_PROMPT, TILLENGELSKA_SYSTEM_PROMPT, TILLSVENSKA_SYSTEM_PROMPT,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ZoneId {
    // Per-variant renames so the JSON / URL wire form matches `slug()`
    // exactly (no underscores in the multi-word variants — they're
    // filesystem-suffix-friendly).
    #[serde(rename = "sammanfatta")]
    Sammanfatta,
    #[serde(rename = "tillengelska")]
    TillEngelska,
    #[serde(rename = "tillsvenska")]
    TillSvenska,
    #[serde(rename = "punktlista")]
    Punktlista,
    #[serde(rename = "anonymisera")]
    Anonymisera,
    #[serde(rename = "forenkla")]
    Forenkla,
    // Spec 013 — three new zones expanding from 2×3 to 3×3 grid.
    // Identifier uses ASCII-only Rust convention (Kallor not Källor).
    #[serde(rename = "kontakter")]
    Kontakter,
    #[serde(rename = "generera")]
    Generera,
    #[serde(rename = "kallor")]
    Kallor,
}

impl ZoneId {
    pub const ALL: [ZoneId; 9] = [
        ZoneId::Sammanfatta,
        ZoneId::TillEngelska,
        ZoneId::TillSvenska,
        ZoneId::Punktlista,
        ZoneId::Anonymisera,
        ZoneId::Forenkla,
        ZoneId::Kontakter,
        ZoneId::Generera,
        ZoneId::Kallor,
    ];

    /// FR-003 — URL slug + filesystem-visible suffix base + module name.
    pub fn slug(self) -> &'static str {
        match self {
            ZoneId::Sammanfatta => "sammanfatta",
            ZoneId::TillEngelska => "tillengelska",
            ZoneId::TillSvenska => "tillsvenska",
            ZoneId::Punktlista => "punktlista",
            ZoneId::Anonymisera => "anonymisera",
            ZoneId::Forenkla => "forenkla",
            ZoneId::Kontakter => "kontakter",
            ZoneId::Generera => "generera",
            ZoneId::Kallor => "kallor",
        }
    }

    /// FR-004 — Swedish title shown in the zone header.
    pub fn title(self) -> &'static str {
        match self {
            ZoneId::Sammanfatta => "Sammanfatta",
            ZoneId::TillEngelska => "Till engelska",
            ZoneId::TillSvenska => "Till svenska",
            ZoneId::Punktlista => "Punktlista",
            ZoneId::Anonymisera => "Anonymisera",
            ZoneId::Forenkla => "Förenkla",
            ZoneId::Kontakter => "Plocka ut kontaktuppgifter",
            ZoneId::Generera => "Generera juridisk text",
            ZoneId::Kallor => "Källförteckning",
        }
    }

    /// FR-005 + spec 005 FR-017 + spec 009 FR-011 — per-zone Swedish
    /// hint copy. Spec 009 extended the format list; spec 028 removed
    /// .pages, leaving six entries (.docx, .pdf, .txt, .md, .rtf, .odt)
    /// in a slash-separated presentation with the `ett` article dropped.
    /// Spec 013 — Generera takes only .txt/.md instructions.
    pub fn hint_copy(self) -> &'static str {
        match self {
            ZoneId::Sammanfatta => "Släpp .docx/.pdf/.txt/.md/.rtf/.odt för sammanfattning",
            ZoneId::TillEngelska => {
                "Släpp .docx/.pdf/.txt/.md/.rtf/.odt för engelsk översättning"
            }
            ZoneId::TillSvenska => {
                "Släpp .docx/.pdf/.txt/.md/.rtf/.odt för svensk översättning"
            }
            ZoneId::Punktlista => "Släpp .docx/.pdf/.txt/.md/.rtf/.odt för punktlista",
            ZoneId::Anonymisera => "Släpp .docx/.pdf/.txt/.md/.rtf/.odt för anonymisering",
            ZoneId::Forenkla => "Släpp .docx/.pdf/.txt/.md/.rtf/.odt för klarspråk",
            ZoneId::Kontakter => "Släpp .docx/.pdf/.txt/.md/.rtf/.odt för kontaktuppgifter",
            ZoneId::Generera => "Släpp .txt eller .md med instruktioner för juridisk text",
            ZoneId::Kallor => "Släpp .docx/.pdf/.txt/.md/.rtf/.odt för källförteckning",
        }
    }

    /// Per-zone Swedish present-tense verb shown during Processing.
    pub fn processing_hint(self) -> &'static str {
        match self {
            ZoneId::Sammanfatta => "Sammanfattar…",
            ZoneId::TillEngelska => "Översätter…",
            ZoneId::TillSvenska => "Översätter…",
            ZoneId::Punktlista => "Listar…",
            ZoneId::Anonymisera => "Anonymiserar…",
            ZoneId::Forenkla => "Förenklar…",
            ZoneId::Kontakter => "Plockar ut kontaktuppgifter…",
            ZoneId::Generera => "Genererar juridisk text…",
            ZoneId::Kallor => "Bygger källförteckning…",
        }
    }

    /// FR-007 — sidecar filename suffix. Note the past-participle
    /// "anonymiserad" for the noun-form filename (reads better than
    /// the verb stem on disk).
    pub fn sidecar_suffix(self) -> &'static str {
        match self {
            ZoneId::Sammanfatta => "sammanfatta",
            ZoneId::TillEngelska => "tillengelska",
            ZoneId::TillSvenska => "tillsvenska",
            ZoneId::Punktlista => "punktlista",
            ZoneId::Anonymisera => "anonymiserad",
            ZoneId::Forenkla => "forenkla",
            ZoneId::Kontakter => "kontakter",
            ZoneId::Generera => "generera",
            ZoneId::Kallor => "kallor",
        }
    }

    /// FR-009 — first-header-paragraph template. The literal `{name}`
    /// token is replaced with the source filename + extension at write
    /// time.
    pub fn header_paragraph_template(self) -> &'static str {
        match self {
            ZoneId::Sammanfatta => "Sammanfattning av '{name}'",
            ZoneId::TillEngelska => "Översättning till engelska av '{name}'",
            ZoneId::TillSvenska => "Översättning till svenska av '{name}'",
            ZoneId::Punktlista => "Punktlista över '{name}'",
            ZoneId::Anonymisera => "Anonymiserad version av '{name}'",
            ZoneId::Forenkla => "Förenklad version av '{name}'",
            ZoneId::Kontakter => "Kontaktuppgifter från '{name}'",
            ZoneId::Generera => "Genererad juridisk text från '{name}'",
            ZoneId::Kallor => "Källförteckning för '{name}'",
        }
    }

    /// FR-006 — per-zone Swedish system prompt sent to gemma3:4b.
    pub fn system_prompt(self) -> &'static str {
        match self {
            ZoneId::Sammanfatta => SAMMANFATTA_SYSTEM_PROMPT,
            ZoneId::TillEngelska => TILLENGELSKA_SYSTEM_PROMPT,
            ZoneId::TillSvenska => TILLSVENSKA_SYSTEM_PROMPT,
            ZoneId::Punktlista => PUNKTLISTA_SYSTEM_PROMPT,
            ZoneId::Anonymisera => ANONYMISERA_SYSTEM_PROMPT,
            ZoneId::Forenkla => FORENKLA_SYSTEM_PROMPT,
            ZoneId::Kontakter => KONTAKTER_SYSTEM_PROMPT,
            ZoneId::Generera => GENERERA_SYSTEM_PROMPT,
            ZoneId::Kallor => KALLOR_SYSTEM_PROMPT,
        }
    }

    /// FR-013 + FR-014 — disclaimer paragraph inserted between the
    /// FR-009 header pair and the body. Present for Anonymisera +
    /// Forenkla (spec 004) + Generera (spec 013 — AI-generated legal
    /// text needs review against authoritative sources).
    pub fn disclaimer_paragraph(self) -> Option<&'static str> {
        match self {
            ZoneId::Anonymisera => {
                Some("AI-anonymisering är inte hundra procent — granska resultatet innan du delar.")
            }
            ZoneId::Forenkla => {
                Some("Förenklad version — granska att inga juridiska poänger gick förlorade.")
            }
            ZoneId::Generera => Some(
                "AI-genererad text — kontrollera juridisk korrekthet mot källa innan användning.",
            ),
            _ => None,
        }
    }

    /// Convenience for tests + the React side: does this zone produce
    /// a disclaimer paragraph?
    pub fn has_disclaimer(self) -> bool {
        self.disclaimer_paragraph().is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_variants_have_unique_slugs() {
        let slugs: Vec<&str> = ZoneId::ALL.iter().map(|z| z.slug()).collect();
        let unique: std::collections::HashSet<_> = slugs.iter().collect();
        assert_eq!(
            unique.len(),
            ZoneId::ALL.len(),
            "slug duplicates: {slugs:?}"
        );
    }

    #[test]
    fn all_variants_have_unique_sidecar_suffixes() {
        let suffixes: Vec<&str> = ZoneId::ALL.iter().map(|z| z.sidecar_suffix()).collect();
        let unique: std::collections::HashSet<_> = suffixes.iter().collect();
        assert_eq!(
            unique.len(),
            ZoneId::ALL.len(),
            "suffix duplicates: {suffixes:?}"
        );
    }

    #[test]
    fn every_zone_has_a_non_empty_system_prompt() {
        for z in ZoneId::ALL {
            let prompt = z.system_prompt();
            assert!(!prompt.is_empty(), "{z:?} has empty system prompt");
            // The "skriv bara" / "Output ... only" guardrail prevents the
            // common gemma3 opening "Här är en sammanfattning:" etc.
            assert!(
                prompt.to_lowercase().contains("bara")
                    || prompt.to_lowercase().contains("only")
                    || prompt.to_lowercase().contains("skriv"),
                "{z:?} prompt missing the no-greeting guardrail: {prompt:?}"
            );
        }
    }

    #[test]
    fn header_template_contains_name_token() {
        for z in ZoneId::ALL {
            let tmpl = z.header_paragraph_template();
            assert!(
                tmpl.contains("{name}"),
                "{z:?} header template missing {{name}} token: {tmpl:?}"
            );
        }
    }

    #[test]
    fn only_anonymisera_forenkla_and_generera_have_disclaimer() {
        // Spec 013 expansion: Generera also gets a disclaimer because
        // AI-generated legal text demands human review against a source.
        for z in ZoneId::ALL {
            let expected = matches!(z, ZoneId::Anonymisera | ZoneId::Forenkla | ZoneId::Generera);
            assert_eq!(
                z.has_disclaimer(),
                expected,
                "{z:?} disclaimer presence drifted from FR-013/014 (+ spec 013 generera)"
            );
        }
    }

    #[test]
    fn snake_case_serialization_matches_slug() {
        for z in ZoneId::ALL {
            let json = serde_json::to_string(&z).unwrap();
            assert_eq!(json, format!("\"{}\"", z.slug()));
        }
    }

    #[test]
    fn round_trips_through_serde() {
        for z in ZoneId::ALL {
            let json = serde_json::to_string(&z).unwrap();
            let back: ZoneId = serde_json::from_str(&json).unwrap();
            assert_eq!(z, back);
        }
    }

    #[test]
    fn anonymisera_suffix_is_past_participle() {
        // R-008 + R-011 — "anonymiserad" not "anonymisera". Catches a
        // future PR that accidentally normalises to the verb stem.
        assert_eq!(ZoneId::Anonymisera.sidecar_suffix(), "anonymiserad");
    }

    #[test]
    fn spec_013_has_exactly_nine_zones() {
        // Spec 013 / FR-001 — pin the zone count + the canonical order
        // so a future refactor can't silently drop or reorder.
        assert_eq!(ZoneId::ALL.len(), 9);
        assert_eq!(ZoneId::ALL[6], ZoneId::Kontakter);
        assert_eq!(ZoneId::ALL[7], ZoneId::Generera);
        assert_eq!(ZoneId::ALL[8], ZoneId::Kallor);
    }
}
