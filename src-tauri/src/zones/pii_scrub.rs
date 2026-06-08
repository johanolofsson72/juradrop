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

use super::pii_sweep::{RE_ADRESS, RE_EMAIL, RE_PERSONNUMMER, RE_PHONE, RE_POSTNUMMER};

/// Scrubbed text + per-category counts of DISTINCT values replaced.
/// Counts are content-free (safe for tests/diagnostics); the matched
/// values themselves never leave `scrub_structured_pii`.
#[derive(Debug)]
pub struct ScrubOutcome {
    pub text: String,
    pub personnummer: usize,
    pub telefon: usize,
    pub epost: usize,
    pub postnummer: usize,
    pub adress: usize,
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
    // Spec 045 — the canonical spaced postnummer (RE_POSTNUMMER) requires a
    // 1–9 first digit, so it can never share a span with Telefon (needs a 0
    // prefix) nor Personnr (10–12 contiguous digits; the separator breaks the
    // run). The tiebreak slot is therefore defensive only.
    Postnr = 3,
    // Spec 046 — a street address (RE_ADRESS) is a Capital+suffix word + house
    // number; it shares no span with the digit-only categories (the address
    // match ends at the house number, before any comma/postnummer). Tiebreak
    // slot defensive only.
    Adress = 4,
}

impl Category {
    fn label(self) -> &'static str {
        match self {
            Category::Epost => "E-post",
            Category::Telefon => "Telefon",
            Category::Personnr => "Personnr",
            Category::Postnr => "Postnr",
            Category::Adress => "Adress",
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
        (&*RE_POSTNUMMER, Category::Postnr),
        (&*RE_ADRESS, Category::Adress),
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
    let mut registries: [Vec<&str>; 5] =
        [Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new()];
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
        postnummer: registries[Category::Postnr as usize].len(),
        adress: registries[Category::Adress as usize].len(),
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

    // ── Spec 045 — postnummer ────────────────────────────────────────────

    #[test]
    fn replaces_canonical_postnummer_with_indexed_placeholder() {
        // Spec 046 update: the street is now ALSO scrubbed (RE_ADRESS), so the
        // full line becomes [Adress 1], [Postnr 1] — the postnummer guarantee
        // (the point of this test) is unchanged.
        let out = scrub_structured_pii("Storgatan 5, 114 35 Stockholm");
        assert_eq!(out.text, "[Adress 1], [Postnr 1] Stockholm");
        assert_eq!(out.postnummer, 1);
        assert_eq!(out.adress, 1);
        assert!(scan_residual_pii(&out.text).is_clean());
    }

    #[test]
    fn replaces_nbsp_separated_postnummer() {
        // Word .docx exports commonly encode the separator as U+00A0.
        let out = scrub_structured_pii("postort 114\u{00A0}35 Stockholm");
        assert_eq!(out.text, "postort [Postnr 1] Stockholm");
        assert_eq!(out.postnummer, 1);
    }

    #[test]
    fn same_postnummer_same_index_distinct_sequential() {
        let out = scrub_structured_pii("114 35 ... 114 35 ... 902 47");
        assert_eq!(out.text.matches("[Postnr 1]").count(), 2, "{}", out.text);
        assert_eq!(out.text.matches("[Postnr 2]").count(), 1);
        assert_eq!(out.postnummer, 2, "two DISTINCT postnummer");
    }

    #[test]
    fn all_four_categories_replaced_and_clean() {
        let input = "Anna 19850312-1234, 070-123 45 67, anna@exempel.se, 114 35 Lund.";
        let out = scrub_structured_pii(input);
        assert!(out.text.contains("[Personnr 1]"), "{}", out.text);
        assert!(out.text.contains("[Telefon 1]"), "{}", out.text);
        assert!(out.text.contains("[E-post 1]"), "{}", out.text);
        assert!(out.text.contains("[Postnr 1]"), "{}", out.text);
        assert_eq!(
            (out.personnummer, out.telefon, out.epost, out.postnummer),
            (1, 1, 1, 1)
        );
        // DetectAndReplaceAgree extends to postnummer.
        assert!(scan_residual_pii(&out.text).is_clean());
    }

    #[test]
    fn non_postnummer_numbers_are_left_byte_identical() {
        // SC-002 / FR-004 — precision: amounts, case numbers, year ranges,
        // unspaced 5-digit runs and double spaces are NOT postnummer AND no
        // scrubber claims them, so the text is byte-identical.
        for input in [
            "ersättning 15 000 kr",    // amount grouped NN NNN
            "mål nr T 4521-25",        // case number with dash
            "perioden 2015–2020",      // en-dash year range
            "referens 11435 i akten",  // unspaced 5-digit
            "koden 114  35 (dubbelt)", // double space — not canonical
        ] {
            let out = scrub_structured_pii(input);
            assert_eq!(
                out.postnummer, 0,
                "false positive in {input:?}: {}",
                out.text
            );
            assert_eq!(out.text, input, "non-postnummer token altered: {input:?}");
        }
    }

    #[test]
    fn leading_zero_spaced_form_is_phone_not_postnummer() {
        // FR-004 — the 0-band is reserved to RE_PHONE; postnummer must NOT
        // claim a leading-0 spaced form (it would otherwise fight the phone
        // pattern over the same span). Postnr count stays 0; no [Postnr] marker.
        let out = scrub_structured_pii("ring 012 34 56 78 ikväll");
        assert_eq!(
            out.postnummer, 0,
            "postnummer must not claim a 0-prefixed form"
        );
        assert!(!out.text.contains("[Postnr"), "{}", out.text);
    }

    #[test]
    fn postnummer_utf8_adjacency_and_idempotence() {
        // FR-011 — Swedish characters adjacent to the match survive intact.
        let out = scrub_structured_pii("ångrenseröd 114 35 åäö");
        assert_eq!(out.text, "ångrenseröd [Postnr 1] åäö");
        // Scrubbing scrubbed text is a no-op for [Postnr N].
        let twice = scrub_structured_pii(&out.text);
        assert_eq!(twice.text, out.text);
        assert_eq!(twice.postnummer, 0);
    }

    // ── Spec 046 — gatuadress ────────────────────────────────────────────

    #[test]
    fn replaces_canonical_street_addresses() {
        let out = scrub_structured_pii("Svaranden bor på Storgatan 5 i stan.");
        assert_eq!(out.text, "Svaranden bor på [Adress 1] i stan.");
        assert_eq!(out.adress, 1);
        assert!(scan_residual_pii(&out.text).is_clean());
    }

    #[test]
    fn replaces_street_with_house_letter_forms() {
        // 12B (no space) and 3 A (spaced letter) both captured in full.
        let a = scrub_structured_pii("Lillgatan 12B");
        assert_eq!(a.text, "[Adress 1]", "{}", a.text);
        let b = scrub_structured_pii("Köpmangatan 3 A");
        assert_eq!(b.text, "[Adress 1]", "{}", b.text);
    }

    #[test]
    fn same_street_same_index_distinct_sequential() {
        let out = scrub_structured_pii("Storgatan 5 ... Storgatan 5 ... Hamngatan 8");
        assert_eq!(out.text.matches("[Adress 1]").count(), 2, "{}", out.text);
        assert_eq!(out.text.matches("[Adress 2]").count(), 1);
        assert_eq!(out.adress, 2);
    }

    #[test]
    fn all_five_categories_replaced_and_clean() {
        let input = "Anna 19850312-1234, 070-123 45 67, anna@exempel.se, \
                     Storgatan 5, 114 35 Lund.";
        let out = scrub_structured_pii(input);
        for marker in [
            "[Personnr 1]",
            "[Telefon 1]",
            "[E-post 1]",
            "[Adress 1]",
            "[Postnr 1]",
        ] {
            assert!(out.text.contains(marker), "missing {marker}: {}", out.text);
        }
        assert_eq!(
            (
                out.personnummer,
                out.telefon,
                out.epost,
                out.postnummer,
                out.adress
            ),
            (1, 1, 1, 1, 1)
        );
        assert!(scan_residual_pii(&out.text).is_clean());
    }

    #[test]
    fn street_scrub_precision_leaves_non_addresses() {
        // SC-002 / FR-003 — capital + included-suffix + house number is the
        // only triad that moves; everything else is byte-identical.
        for input in [
            "vi ses på plan 3 imorgon", // excluded suffix (= floor), lowercase
            "Plan 3 i huset",           // excluded suffix, capitalized
            "Storgatan är avstängd",    // street word, NO house number
            "vägen 3 meter bort",       // lowercase, not a proper street
            "kör på motorled 4",        // 'led' excluded
            "en fin park 5 träd",       // 'park' excluded
            "möte på Plats 7",          // 'plats' excluded
        ] {
            let out = scrub_structured_pii(input);
            assert_eq!(out.adress, 0, "false positive in {input:?}: {}", out.text);
            assert_eq!(out.text, input, "non-address token altered: {input:?}");
        }
    }

    #[test]
    fn street_match_does_not_grab_following_word() {
        // The optional trailing letter must not swallow the first letter of the
        // next word; only "Storgatan 5" moves, "och Lillgatan" (no number) stays.
        let out = scrub_structured_pii("Storgatan 5 och Lillgatan vidare");
        assert_eq!(out.text, "[Adress 1] och Lillgatan vidare", "{}", out.text);
        assert_eq!(out.adress, 1);
    }

    #[test]
    fn street_utf8_adjacency_and_idempotence() {
        // FR-012 — Swedish characters adjacent to the match survive intact.
        let out = scrub_structured_pii("ångrenseröd Köpmangatan 3 åäö");
        assert_eq!(out.text, "ångrenseröd [Adress 1] åäö");
        let twice = scrub_structured_pii(&out.text);
        assert_eq!(twice.text, out.text);
        assert_eq!(twice.adress, 0);
    }

    // ── Spec 046 — phone-tail fix ────────────────────────────────────────

    #[test]
    fn phone_with_third_group_captured_in_full() {
        // FR-009 / SC-004 — `0NN-NNN NN NN` no longer leaves a 2-digit tail.
        let out = scrub_structured_pii("Ring 070-123 45 67 dagtid.");
        assert_eq!(out.text, "Ring [Telefon 1] dagtid.", "{}", out.text);
        assert_eq!(out.telefon, 1);
        // The whole number is gone — no stray "67".
        assert!(!out.text.contains("67"), "phone tail leaked: {}", out.text);
    }

    #[test]
    fn existing_phone_forms_unchanged_by_widening() {
        // Two-group and +46 forms must still scrub fully (no regression).
        assert_eq!(scrub_structured_pii("08-555 12 34").text, "[Telefon 1]");
        assert_eq!(scrub_structured_pii("+46 70 123 45 67").text, "[Telefon 1]");
        // The 031 field number from the live test, captured in full.
        let out = scrub_structured_pii("Telefon: 031-22 33 44");
        assert_eq!(out.text, "Telefon: [Telefon 1]", "{}", out.text);
        assert!(!out.text.contains("44"));
    }
}
