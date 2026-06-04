// Spec 039 — Anonymisera deterministic structured-PII replacement.
//
// Pure, local, deterministic REPLACEMENT of structured PII (personnummer,
// telefonnummer, e-post) in the EXTRACTED document text, BEFORE any model
// pass and before the spec-038 chunk plan is built. What the model never
// sees it cannot echo back — the spec-014 sweep stays as the independent
// net for fabricated or unmatched PII.
//
// Reuses the spec-014 patterns verbatim (pii_sweep::RE_*) so
// detect-and-replace can never disagree with detect-and-warn.
//
// Placeholders are the bracketed indexed forms the sweep already masks:
// "[Personnr N]" / "[Telefon N]" / "[E-post N]". Same matched value → same
// index everywhere in the document (first-occurrence order per category) —
// deterministic, and globally consistent across spec-038 chunks because the
// scrub runs on the whole text first.
//
// Privacy (FR-007): the value→index registry lives in this function's stack
// for one run; nothing is persisted, nothing is logged.
//
// Anonymisera ONLY — every other zone receives byte-identical input (a
// summary that says "[Telefon 1]" instead of the number would be wrong).

use regex::Regex;

use super::pii_sweep::{RE_EMAIL, RE_PERSONNUMMER, RE_PHONE};

/// Scrubbed text + per-category counts of DISTINCT values replaced.
/// Counts are content-free (safe for tests/diagnostics); the matched
/// values themselves never leave `scrub_structured_pii`.
#[derive(Debug)]
pub struct ScrubOutcome {
    pub text: String,
    pub personnummer: usize,
    pub telefon: usize,
    pub epost: usize,
}

/// Category of one candidate match. Tie-break priority for identical spans
/// (lower wins): an e-post always contains '@' so it can only tie itself;
/// a separator-less 10-digit mobile ("0701234567") shape-matches BOTH phone
/// and personnummer — Telefon wins the tie (the 0-prefix is the stronger
/// signal; either way the value is replaced, only the label differs).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Category {
    Epost = 0,
    Telefon = 1,
    Personnr = 2,
}

impl Category {
    fn label(self) -> &'static str {
        match self {
            Category::Epost => "E-post",
            Category::Telefon => "Telefon",
            Category::Personnr => "Personnr",
        }
    }
}

/// Replace every spec-014-shaped e-post, telefonnummer and personnummer in
/// `text` with bracketed indexed placeholders.
///
/// All three patterns match against the ORIGINAL text simultaneously and
/// overlaps are resolved leftmost-longest (then category priority). This is
/// load-bearing: sequential per-category passes let the phone pattern
/// bridge ACROSS two adjacent personnummer ("…-0101 19020202-…") and leave
/// PII fragments behind — caught by the document_of_only_pii test.
pub fn scrub_structured_pii(text: &str) -> ScrubOutcome {
    // 1. Collect all candidates from all categories on the original text.
    let mut candidates: Vec<(std::ops::Range<usize>, &str, Category)> = Vec::new();
    for (re, cat) in [
        (&*RE_EMAIL, Category::Epost),
        (&*RE_PHONE, Category::Telefon),
        (&*RE_PERSONNUMMER, Category::Personnr),
    ] {
        let re: &Regex = re;
        for m in re.find_iter(text) {
            candidates.push((m.range(), m.as_str(), cat));
        }
    }

    // 2. Leftmost-longest sweep: sort by (start asc, len desc, category
    //    priority asc) and keep non-overlapping winners in order.
    candidates.sort_by(|a, b| {
        a.0.start
            .cmp(&b.0.start)
            .then(b.0.len().cmp(&a.0.len()))
            .then((a.2 as u8).cmp(&(b.2 as u8)))
    });
    let mut kept: Vec<(std::ops::Range<usize>, &str, Category)> = Vec::new();
    let mut covered_until = 0usize;
    for (range, value, cat) in candidates {
        if range.start >= covered_until {
            covered_until = range.end;
            kept.push((range, value, cat));
        }
    }

    // 3. Per-category first-occurrence registries (FR-002: same value →
    //    same index). Values live only in this stack frame (FR-007).
    let mut registries: [Vec<&str>; 3] = [Vec::new(), Vec::new(), Vec::new()];
    for (_, value, cat) in &kept {
        let reg = &mut registries[*cat as usize];
        if !reg.iter().any(|v| v == value) {
            reg.push(value);
        }
    }

    // 4. Back-to-front byte-range splicing: ranges are from the original
    //    string, so later replacements never shift earlier ranges, and
    //    regex match ranges are char-boundary-aligned (UTF-8-safe, FR-008).
    let mut out = text.to_string();
    for (range, value, cat) in kept.iter().rev() {
        let index = registries[*cat as usize]
            .iter()
            .position(|v| v == value)
            .map(|i| i + 1)
            .unwrap_or(1); // unreachable: kept values are registered above
        out.replace_range(range.clone(), &format!("[{} {index}]", cat.label()));
    }

    ScrubOutcome {
        text: out,
        personnummer: registries[Category::Personnr as usize].len(),
        telefon: registries[Category::Telefon as usize].len(),
        epost: registries[Category::Epost as usize].len(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zones::pii_sweep::scan_residual_pii;

    #[test]
    fn replaces_all_three_categories_with_indexed_placeholders() {
        let input = "Kärande: Anna Andersson, 19850312-1234, tel 070-123 45 67, \
                     e-post anna.andersson@exempel.se.";
        let out = scrub_structured_pii(input);
        assert!(out.text.contains("[Personnr 1]"), "{}", out.text);
        assert!(out.text.contains("[Telefon 1]"), "{}", out.text);
        assert!(out.text.contains("[E-post 1]"), "{}", out.text);
        assert!(!out.text.contains("19850312-1234"));
        assert!(!out.text.contains("070-123 45 67"));
        assert!(!out.text.contains("anna.andersson@exempel.se"));
        assert_eq!((out.personnummer, out.telefon, out.epost), (1, 1, 1));
    }

    #[test]
    fn same_value_gets_same_index_everywhere() {
        let input = "Nås på 070-123 45 67 dagtid. Upprepar: 070-123 45 67. \
                     Annars 08-555 12 34.";
        let out = scrub_structured_pii(input);
        assert_eq!(out.text.matches("[Telefon 1]").count(), 2, "{}", out.text);
        assert_eq!(out.text.matches("[Telefon 2]").count(), 1);
        assert_eq!(out.telefon, 2, "two DISTINCT numbers");
    }

    #[test]
    fn indices_follow_first_occurrence_order() {
        let input = "Först b@x.se sedan a@x.se sedan b@x.se igen.";
        let out = scrub_structured_pii(input);
        // b@x.se appears first → index 1; a@x.se → index 2.
        assert_eq!(
            out.text,
            "Först [E-post 1] sedan [E-post 2] sedan [E-post 1] igen."
        );
    }

    #[test]
    fn swedish_char_email_is_replaced_in_full() {
        // FR-009 pin — no leading å left behind.
        let out = scrub_structured_pii("kontakta åsa.öberg@exempel.se snarast");
        assert_eq!(out.text, "kontakta [E-post 1] snarast");
    }

    #[test]
    fn utf8_neighbors_survive_replacement() {
        let input = "ångrenseröd 19850312-1234 åäö och é-tecken";
        let out = scrub_structured_pii(input);
        assert_eq!(out.text, "ångrenseröd [Personnr 1] åäö och é-tecken");
        // Round-trip through chars() proves no boundary corruption.
        assert!(out.text.chars().count() > 0);
    }

    #[test]
    fn phone_wins_identical_span_tiebreak() {
        // "0701234567" shape-matches BOTH phone (0 + area + digits) and
        // personnummer ((?:\d{2})?\d{6}\d{4}) on the SAME span. The
        // category tie-break picks Telefon (0-prefix is the stronger
        // signal); either way the value is replaced.
        let out = scrub_structured_pii("ring 0701234567 ikväll");
        assert!(
            out.text.contains("[Telefon 1]"),
            "phone precedence: {}",
            out.text
        );
        assert_eq!(out.personnummer, 0);
        assert!(scan_residual_pii(&out.text).is_clean());
    }

    #[test]
    fn no_match_text_is_identity() {
        let input = "Hovrätten fastställer tingsrättens domslut i alla delar.";
        let out = scrub_structured_pii(input);
        assert_eq!(out.text, input);
        assert_eq!((out.personnummer, out.telefon, out.epost), (0, 0, 0));
    }

    #[test]
    fn scrub_is_idempotent_on_scrubbed_text() {
        let once = scrub_structured_pii("nr 19850312-1234 och e-post a@b.se");
        let twice = scrub_structured_pii(&once.text);
        assert_eq!(once.text, twice.text, "placeholders must never re-match");
        assert_eq!((twice.personnummer, twice.telefon, twice.epost), (0, 0, 0));
    }

    #[test]
    fn scrubbed_output_is_clean_per_the_sweep() {
        // The sweep (same patterns) finds NOTHING in scrubbed text —
        // detect-and-replace agrees with detect-and-warn by construction.
        let input = "19850312-1234, 850312+1234, 070-123 45 67, +46 70 123 45 67, \
                     a@b.se, åsa.öberg@exempel.se";
        let out = scrub_structured_pii(input);
        let findings = scan_residual_pii(&out.text);
        assert!(findings.is_clean(), "residue after scrub: {findings:?}");
    }

    #[test]
    fn document_of_only_pii_becomes_only_placeholders() {
        let out = scrub_structured_pii("19010101-0101 19020202-0202 19030303-0303");
        assert_eq!(out.text, "[Personnr 1] [Personnr 2] [Personnr 3]");
        assert_eq!(out.personnummer, 3);
    }

    #[test]
    fn large_distinct_index_growth_is_stable() {
        // 200 distinct personnummer — indices stay dense and ordered.
        let input: String = (0..200)
            .map(|i| format!("19{:02}0101-{:04}", i % 100, 1000 + i))
            .collect::<Vec<_>>()
            .join(" ");
        let out = scrub_structured_pii(&input);
        assert_eq!(out.personnummer, 200);
        assert!(out.text.contains("[Personnr 1]"));
        assert!(out.text.contains("[Personnr 200]"));
        assert!(scan_residual_pii(&out.text).is_clean());
    }

    #[test]
    fn pii_adjacent_to_document_markers_is_replaced() {
        // Hostile shape from tasks T010: PII hugging framing-marker text.
        let input = "--- DOKUMENT SLUTAR ---070-123 45 67";
        let out = scrub_structured_pii(input);
        assert!(!out.text.contains("070-123 45 67"), "{}", out.text);
    }
}
