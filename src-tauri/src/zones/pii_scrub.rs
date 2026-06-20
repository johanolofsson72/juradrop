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

use super::pii_sweep::{
    RE_ADRESS, RE_ADRESS_FULL, RE_EMAIL, RE_PERSONNUMMER, RE_PHONE, RE_POSTNUMMER,
};

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
    // The shared patterns. RE_ADRESS_FULL precedes RE_ADRESS so the whole-line
    // address (street+postnummer+city, spec 047) is offered BEFORE the
    // street-only form; both feed Category::Adress and leftmost-longest keeps the
    // longer full-line span, collapsing the line to one [Adress N].
    let patterns: [(&Regex, Category); 6] = [
        (&*RE_EMAIL, Category::Epost),
        (&*RE_PHONE, Category::Telefon),
        (&*RE_PERSONNUMMER, Category::Personnr),
        (&*RE_POSTNUMMER, Category::Postnr),
        (&*RE_ADRESS_FULL, Category::Adress),
        (&*RE_ADRESS, Category::Adress),
    ];

    // 1+2. Streaming leftmost-longest overlap resolution (spec 048).
    //
    // From a moving cursor, find each pattern's leftmost match in the REMAINDER
    // text[cursor..], pick the overall leftmost-longest (start asc, len desc,
    // category priority asc), commit it, and advance the cursor past it. The
    // region between the cursor and the winner's start is provably match-free for
    // EVERY pattern (the winner is the leftmost match of all of them), so it is
    // skipped wholesale and the loop is linear in the text length.
    //
    // This is the spec-048 fix. The pre-048 code collected ALL candidates from one
    // whole-text scan and resolved overlaps once; a candidate whose greedy
    // whole-text match BRIDGED into an earlier winner was discarded, and its
    // clean sub-span — which only surfaces as a match when the text BEFORE it is
    // removed — was never reconsidered. A phone whose digit run is whitespace-glued
    // to an earlier postnummer ("100 00 01-000 00 00") leaked INTO the model that
    // way (only the output sweep netted it). Re-finding from the cursor after each
    // commit reconsiders exactly those clean sub-spans, so the scrub is complete on
    // its own. For non-glued input the cursor walk yields the identical result to
    // the pre-048 pass (every existing scrub test is unchanged); only the
    // previously-leaking glued cases now scrub to the full placeholder (FR-002).
    //
    // `kept` comes out strictly ascending (the cursor only moves forward), so the
    // first-occurrence registry below indexes in document order (FR-003).
    let mut kept: Vec<(std::ops::Range<usize>, &str, Category)> = Vec::new();
    let mut cursor = 0usize;
    // `loop` (not `while cursor < text.len()`): the empty-remainder case is the
    // None branch below — `&text[text.len()..]` is "" and finds nothing — so a
    // separate bound check would be a redundant, mutation-equivalent comparison.
    loop {
        let slice = &text[cursor..];
        let mut best: Option<(std::ops::Range<usize>, &str, Category)> = None;
        for (re, cat) in patterns {
            if let Some(m) = re.find(slice) {
                let cand = (cursor + m.start()..cursor + m.end(), m.as_str(), cat);
                // Keep the leftmost match. On an IDENTICAL start the first pattern
                // in `patterns` wins (a later one fails `start < best.start`), and
                // the array is deliberately ordered so first-listed == the correct
                // leftmost-longest / lowest-category winner for every collision the
                // six patterns can actually produce: RE_ADRESS_FULL before
                // RE_ADRESS (the only same-start different-length pair → longer
                // wins) and category order Epost<Telefon<Personnr<Postnr<Adress
                // (the only same-start same-length pair, phone vs personnummer →
                // lower category wins). An explicit length/category comparison here
                // would be unreachable dead code — the mutation gate confirmed it —
                // so the tie-break lives in the array order, pinned by
                // `phone_wins_identical_span_tiebreak` and the whole-line collapse
                // tests. KEEP THIS ORDERING when adding a pattern.
                let wins = match &best {
                    None => true,
                    Some(b) => cand.0.start < b.0.start,
                };
                if wins {
                    best = Some(cand);
                }
            }
        }
        match best {
            // No pattern matches anywhere in the remainder — done.
            None => break,
            Some((range, value, cat)) => {
                // Termination invariant: every pattern matches >= 1 byte, so the
                // cursor strictly advances. A future zero-length-match pattern
                // would stall the cursor here and spin on untrusted input — fail
                // loudly in test/CI rather than hang in the field (no-op in
                // release). All six current patterns are >= 5 bytes.
                debug_assert!(
                    range.end > range.start,
                    "zero-length PII match at byte {} would stall the scrub cursor",
                    range.start
                );
                cursor = range.end;
                kept.push((range, value, cat));
            }
        }
    }

    // 3. Per-category first-occurrence registries (FR-003: same value →
    //    same index). Values live only in this stack frame (FR-005).
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
        // Spec 047 update: a postnummer INSIDE an address line is now folded
        // into [Adress N] (see whole-line tests). This pins the STANDALONE
        // postnummer guarantee — no street before it, so it stays [Postnr N].
        let out = scrub_structured_pii("Brevet skickades till 114 35 utan gata.");
        assert_eq!(out.text, "Brevet skickades till [Postnr 1] utan gata.");
        assert_eq!(out.postnummer, 1);
        assert_eq!(out.adress, 0);
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
        // Spec 047: street and postnummer are kept in SEPARATE positions so the
        // whole-line collapse does not fold the postnummer into [Adress N] —
        // this test proves all five categories can co-exist as placeholders.
        let input = "Anna 19850312-1234 på 070-123 45 67, anna@exempel.se. \
                     Kontoret: Storgatan 5. Postnr 114 35 separat.";
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

    // ── Spec 047 — whole-line address collapse ───────────────────────────

    #[test]
    fn whole_line_address_collapses_to_one_placeholder() {
        // SC-001 — street + postnummer + city → ONE [Adress N]; no separate
        // [Postnr], no leftover city.
        let out = scrub_structured_pii("Svaranden bor på Storgatan 5, 114 35 Stockholm idag.");
        assert_eq!(out.text, "Svaranden bor på [Adress 1] idag.");
        assert_eq!(out.adress, 1);
        assert_eq!(out.postnummer, 0, "postnummer folded into the address line");
        assert!(scan_residual_pii(&out.text).is_clean());
    }

    #[test]
    fn whole_line_catches_unspaced_postnummer_in_context() {
        // SC-001 — the unspaced 5-digit form is caught HERE (street before,
        // city after disambiguate it), unlike a standalone bare run.
        let out = scrub_structured_pii("Lökgatan 1, 32456 Stockholm");
        assert_eq!(out.text, "[Adress 1]", "{}", out.text);
        assert_eq!(out.adress, 1);
    }

    #[test]
    fn whole_line_nbsp_and_commaless_forms() {
        let nbsp = scrub_structured_pii("Lillgatan 12B, 412\u{00A0}96 Göteborg");
        assert_eq!(nbsp.text, "[Adress 1]", "{}", nbsp.text);
        let commaless = scrub_structured_pii("Vasagatan 1 111 20 Stockholm");
        assert_eq!(commaless.text, "[Adress 1]", "{}", commaless.text);
    }

    #[test]
    fn whole_line_same_address_same_index() {
        let out = scrub_structured_pii(
            "Bor på Storgatan 5, 114 35 Stockholm. Äger Storgatan 5, 114 35 Stockholm.",
        );
        assert_eq!(out.text.matches("[Adress 1]").count(), 2, "{}", out.text);
        assert_eq!(out.adress, 1, "one DISTINCT address line");
    }

    #[test]
    fn field_doc_four_address_lines_become_four_placeholders() {
        // SC-001 — the exact live-test shape: four party address lines.
        let input = "Storgatan 5, 114 35 Stockholm. \
                     Lillgatan 12B, 412\u{00A0}96 Göteborg. \
                     Vasagatan 1, 111 20 Stockholm. \
                     Hamngatan 8, 211 22 Malmö.";
        let out = scrub_structured_pii(input);
        for n in 1..=4 {
            assert!(
                out.text.contains(&format!("[Adress {n}]")),
                "missing [Adress {n}]: {}",
                out.text
            );
        }
        assert_eq!(out.adress, 4);
        // Zero raw streets, cities, or postnummer survive.
        for raw in [
            "Storgatan",
            "Göteborg",
            "Malmö",
            "Stockholm",
            "114 35",
            "412",
        ] {
            assert!(!out.text.contains(raw), "raw {raw:?} leaked: {}", out.text);
        }
        assert!(scan_residual_pii(&out.text).is_clean());
    }

    #[test]
    fn whole_line_utf8_city_adjacency() {
        let out = scrub_structured_pii("ärendet Köpmangatan 3, 211 22 Malmö åter");
        assert_eq!(out.text, "ärendet [Adress 1] åter", "{}", out.text);
    }

    #[test]
    fn partials_and_standalones_survive_whole_line_addition() {
        // SC-002 — street-only still [Adress N]; standalone postnummer still
        // [Postnr N]; amounts/case-numbers byte-identical.
        let street_only = scrub_structured_pii("Kontoret ligger på Storgatan 5 (vån 2).");
        assert!(
            street_only.text.contains("[Adress 1]"),
            "{}",
            street_only.text
        );
        assert_eq!(street_only.postnummer, 0);

        let standalone = scrub_structured_pii("postnr 114 35 ensamt");
        assert_eq!(standalone.text, "postnr [Postnr 1] ensamt");
        assert_eq!(standalone.adress, 0);

        for input in ["15 000 kr", "mål nr T 4521-25", "referens 11435"] {
            let out = scrub_structured_pii(input);
            assert_eq!(out.text, input, "altered: {input:?} -> {}", out.text);
            assert_eq!((out.adress, out.postnummer), (0, 0));
        }
    }

    // ── H1 integration-hardening — audit M-1 (Unicode digits) ────────────

    #[test]
    fn fullwidth_digit_personnummer_is_replaced() {
        // The `regex` crate is Unicode-aware by default (`\d` == `\p{Nd}`), so
        // a personnummer typed with FULLWIDTH digits — a real OCR / copy-paste
        // artefact — is matched and REPLACED by the scrub, not leaked to the
        // model. Locks the behaviour in as a regression guard against a future
        // narrowing to `[0-9]`.
        let fullwidth = "Klient \u{FF11}\u{FF19}\u{FF18}\u{FF15}\u{FF10}\u{FF13}\u{FF11}\u{FF12}-\u{FF11}\u{FF12}\u{FF13}\u{FF14} i målet."; // 19850312-1234
        let out = scrub_structured_pii(fullwidth);
        assert_eq!(
            out.personnummer, 1,
            "fullwidth personnummer must be scrubbed: {}",
            out.text
        );
        assert!(out.text.contains("[Personnr 1]"), "{}", out.text);
        // And the scrubbed text passes the independent sweep — no residue.
        assert!(scan_residual_pii(&out.text).is_clean(), "{}", out.text);
    }

    #[test]
    fn postnummer_adjacent_phone_is_scrubbed_by_gap_rescan() {
        // Spec 048 — the H1 finding, now FIXED. When a phone's digit run is
        // whitespace-glued to an earlier postnummer with no intervening
        // non-`[\s-]` character (`"100 00 01-000 00 00"`), `find_iter`'s greedy
        // phone match bridges the boundary, that bridging span loses the
        // first-pass leftmost-longest contest, and PRE-048 the clean phone span
        // ("01-000 00 00") was never reconsidered — so the phone leaked INTO the
        // model (the output sweep netted it). The gap re-scan now re-examines the
        // uncovered range after the postnummer and replaces the phone too: the
        // scrub is complete on its own, the sweep finds nothing.
        let out = scrub_structured_pii("100 00 01-000 00 00");
        assert!(
            out.text.contains("[Postnr 1]"),
            "postnummer must scrub: {}",
            out.text
        );
        assert!(
            out.text.contains("[Telefon 1]"),
            "the glued phone must now be scrubbed by the gap re-scan: {}",
            out.text
        );
        assert_eq!(out.text, "[Postnr 1] [Telefon 1]", "{}", out.text);
        assert_eq!((out.postnummer, out.telefon), (1, 1));
        // The scrub no longer relies on the sweep to net the phone — the output
        // is clean of every detectable pattern by construction.
        assert!(
            scan_residual_pii(&out.text).is_clean(),
            "gap re-scan must leave no residue: {}",
            out.text
        );
    }

    // ── Spec 048 — gap re-scan functional + destructive coverage ─────────────

    #[test]
    fn gap_rescan_postnummer_glued_to_personnummer() {
        // A personnummer whose 10-digit run is space-glued to a leading
        // postnummer: "100 00 19850312-1234". The personnummer's leftmost match
        // and the postnummer can bridge; the gap re-scan must catch both.
        let out = scrub_structured_pii("100 00 19850312-1234");
        assert_eq!(out.text, "[Postnr 1] [Personnr 1]", "{}", out.text);
        assert_eq!((out.postnummer, out.personnummer), (1, 1));
        assert!(scan_residual_pii(&out.text).is_clean(), "{}", out.text);
    }

    #[test]
    fn gap_rescan_three_way_glued_chain() {
        // A chain that forces >1 re-scan pass: postnummer, phone, postnummer all
        // bare-space joined. Every span must end up replaced, none leaking.
        let out = scrub_structured_pii("100 00 070-123 45 67 200 10");
        assert!(out.text.contains("[Postnr 1]"), "{}", out.text);
        assert!(out.text.contains("[Telefon 1]"), "{}", out.text);
        assert!(out.text.contains("[Postnr 2]"), "{}", out.text);
        assert_eq!((out.postnummer, out.telefon), (2, 1));
        assert!(scan_residual_pii(&out.text).is_clean(), "{}", out.text);
    }

    #[test]
    fn gap_rescan_preserves_same_value_same_index_across_a_gap() {
        // FR-003 — a value first seen via the gap re-scan and then again later
        // must share its index. The first phone is glued (re-scan path); the
        // second is the same number standalone (first-pass path).
        let out = scrub_structured_pii("100 00 070-123 45 67. Igen: 070-123 45 67.");
        assert_eq!(
            out.text.matches("[Telefon 1]").count(),
            2,
            "same number → same index regardless of which pass found it: {}",
            out.text
        );
        assert_eq!(out.telefon, 1, "one DISTINCT phone");
        assert!(scan_residual_pii(&out.text).is_clean(), "{}", out.text);
    }

    #[test]
    fn gap_rescan_is_idempotent() {
        // Re-scanning already-scrubbed glued text changes nothing.
        let once = scrub_structured_pii("100 00 01-000 00 00");
        let twice = scrub_structured_pii(&once.text);
        assert_eq!(once.text, twice.text, "placeholders must never re-match");
        assert_eq!((twice.postnummer, twice.telefon), (0, 0));
    }

    #[test]
    fn gap_rescan_utf8_adjacency_across_a_gap() {
        // FR-004 — Swedish characters either side of a glued pair survive intact.
        let out = scrub_structured_pii(" åäö 100 00 01-000 00 00 öäå");
        assert_eq!(out.text, " åäö [Postnr 1] [Telefon 1] öäå", "{}", out.text);
        assert!(out.text.chars().count() > 0);
    }

    #[test]
    fn gap_rescan_boundary_single_char_gap_between_kept_spans() {
        // The gap between two kept spans is a single non-word char (no PII to
        // find there) — the loop must still settle and leave it untouched.
        let out = scrub_structured_pii("114 35 200 10");
        assert_eq!(out.text, "[Postnr 1] [Postnr 2]", "{}", out.text);
        assert_eq!(out.postnummer, 2);
    }

    #[test]
    fn first_pass_identity_on_a_non_glued_document() {
        // FR-002 — for input with no glued-adjacency edge case, the gap re-scan
        // adds nothing: the result is exactly what the pre-048 single pass gave.
        let input = "Anna 19850312-1234 bor på Storgatan 5, 114 35 Lund. \
                     Tel 070-123 45 67, e-post anna@exempel.se.";
        let out = scrub_structured_pii(input);
        assert!(out.text.contains("[Personnr 1]"), "{}", out.text);
        assert!(out.text.contains("[Adress 1]"), "{}", out.text);
        assert!(out.text.contains("[Telefon 1]"), "{}", out.text);
        assert!(out.text.contains("[E-post 1]"), "{}", out.text);
        // The whole-line address folded the postnummer in (spec 047) → no [Postnr].
        assert_eq!(
            out.postnummer, 0,
            "postnummer folded into address: {}",
            out.text
        );
        assert!(scan_residual_pii(&out.text).is_clean(), "{}", out.text);
    }

    #[test]
    fn gap_rescan_stress_long_glued_chain_terminates_and_is_clean() {
        // Hardened stress (T007 / SC-109 / DoS mitigation): a long run of
        // bare-space-glued postnummer+phone pairs must terminate quickly, replace
        // every span, and leave zero residue — no unbounded loop, no leak.
        let unit = "100 00 01-000 00 00 ";
        let input = unit.repeat(1000);
        let out = scrub_structured_pii(&input);
        assert_eq!(out.postnummer, 1, "one DISTINCT postnummer value");
        assert_eq!(out.telefon, 1, "one DISTINCT phone value");
        assert!(
            !out.text.contains("01-000"),
            "no raw phone fragment may survive in {} chars",
            out.text.len()
        );
        assert!(
            scan_residual_pii(&out.text).is_clean(),
            "stress input must scrub clean"
        );
    }
}

// ── H1 integration-hardening — property-based fuzzing of the privacy core ──
//
// The scrub (input-side replacement) and the sweep (output-side residue net)
// share the SAME regexes by construction, so the load-bearing invariant is:
// whatever the scrub replaces, the sweep can no longer find. These properties
// fuzz that across a wide generated input space — the leak paths a fixed
// example set cannot reach.
#[cfg(test)]
mod prop_tests {
    use super::*;
    use crate::zones::pii_sweep::scan_residual_pii;
    use proptest::prelude::*;

    /// A generator of realistic PII-rich Swedish text: random personnummer,
    /// phone numbers, e-post, street addresses, postnummer and filler.
    ///
    /// Spec 048 — fragments are joined with a **bare space** alongside prose
    /// separators. The bare-space join is the strong case: it reproduces the H1
    /// finding where a phone's digit run is whitespace-glued to an earlier
    /// postnummer with no intervening non-`[\s-]` character
    /// (`"100 00 01-000 00 00"`), the boundary-bridging match loses the
    /// leftmost-longest contest, and PRE-048 the clean phone span was never
    /// reconsidered. With the gap re-scan that case is now scrubbed completely, so
    /// the residue property below holds even under bare-space adjacency — the
    /// prose-only workaround the H1 checkpoint used is retired.
    fn pii_rich_text() -> impl Strategy<Value = String> {
        let fragment = prop_oneof![
            (1900u32..2030, 1u32..13, 1u32..29, 0u32..10_000)
                .prop_map(|(y, m, d, n)| format!("{y:04}{m:02}{d:02}-{n:04}")),
            // Spec 048 (adversarial-review F2): also fuzz the separator-less
            // 12-digit personnummer and the '+'-separator (born >100 yrs ago)
            // forms — RE_PERSONNUMMER matches both, so the residue property must
            // exercise them, not just the canonical YYMMDD-NNNN shape.
            (1900u32..2030, 1u32..13, 1u32..29, 0u32..10_000)
                .prop_map(|(y, m, d, n)| format!("{y:04}{m:02}{d:02}{n:04}")),
            (0u32..130, 1u32..13, 1u32..29, 0u32..10_000)
                .prop_map(|(y, m, d, n)| format!("{:02}{m:02}{d:02}+{n:04}", y % 100)),
            (1u32..1000, 0u32..1000, 0u32..100, 0u32..100)
                .prop_map(|(a, b, c, d)| format!("0{a}-{b:03} {c:02} {d:02}")),
            "[a-zåäö]{1,8}\\.[a-zåäö]{1,8}@[a-z]{2,8}\\.[a-z]{2,3}",
            "(Stor|Lill|Vasa|Hamn|Köpman|Kungs)gatan [1-9][0-9]?[A-B]?",
            (100u32..990, 0u32..100).prop_map(|(a, b)| format!("{a} {b:02}")),
            "[A-Za-zåäöÅÄÖ]{0,12}",
        ];
        // Bare space FIRST — the adjacency the H1 finding lives in.
        let separator = prop_oneof![Just(" "), Just(", "), Just(". "), Just(" och "), Just(": ")];
        (prop::collection::vec(fragment, 0..8), separator).prop_map(|(parts, sep)| parts.join(sep))
    }

    proptest! {
        /// Robustness: the scrub must never panic on ANY input, including
        /// arbitrary Unicode (untrusted document text is fed in verbatim).
        #[test]
        fn scrub_never_panics(s in ".{0,400}") {
            let _ = scrub_structured_pii(&s);
        }

        /// Idempotence: scrubbing already-scrubbed text changes nothing —
        /// the emitted `[Category N]` placeholders are never re-matched as PII.
        #[test]
        fn scrub_is_idempotent(s in pii_rich_text()) {
            let once = scrub_structured_pii(&s).text;
            let twice = scrub_structured_pii(&once).text;
            prop_assert_eq!(&once, &twice);
        }

        /// THE privacy invariant: a scrubbed document is clean of every
        /// structured category the residue sweep can detect. If this ever
        /// fails, the shrunk counterexample is a concrete leak path.
        #[test]
        fn scrub_output_leaves_no_sweepable_residue(s in pii_rich_text()) {
            let out = scrub_structured_pii(&s).text;
            let residue = scan_residual_pii(&out);
            prop_assert!(
                residue.is_clean(),
                "residue {:?} survived scrub of {:?} -> {:?}",
                residue, s, out
            );
        }
    }
}
