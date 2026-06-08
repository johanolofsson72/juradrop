// Spec 014 — Anonymisera PII-residue sweep.
//
// A pure, local, deterministic scan of the Anonymisera model OUTPUT for
// personal data the model failed to redact: personnummer, e-post,
// telefonnummer. Detection ONLY — never edits the scanned text. When
// residue is found, the caller prepends `warning_paragraph()` to the
// sidecar so the student is told, in writing, what to re-check.
//
// Design notes:
//   - Shape-based personnummer matching (no Luhn) — over-warns rather than
//     under-warns, the safe direction for a privacy net (Clarification Q4).
//   - Placeholders (`[Personnr 1]`, `[Telefon 1]`, `[E-post 1]`) are masked
//     out before counting so they never register as residue (FR-005).
//   - Names + free-form addresses are intentionally NOT detected (no
//     deterministic pattern; would be noise) — they stay the model's job
//     plus the static disclaimer.
//   - No network, reads only the output string — Principle I unaffected.

use std::sync::LazyLock;

use regex::Regex;

/// Counts of residual PII detected in a piece of text.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct PiiFindings {
    pub personnummer: usize,
    pub email: usize,
    pub phone: usize,
    pub postnummer: usize,
    pub adress: usize,
}

impl PiiFindings {
    pub fn total(&self) -> usize {
        self.personnummer + self.email + self.phone + self.postnummer + self.adress
    }

    pub fn is_clean(&self) -> bool {
        self.total() == 0
    }
}

// Personnummer: optional century (2 digits) + YYMMDD + optional separator
// (- or +) + 4 digits. Word-boundaried. Shape only.
// Spec 039 — pub(crate): the pii_scrub REPLACER reuses these exact patterns
// so detect-and-replace can never disagree with detect-and-warn.
// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
pub(crate) static RE_PERSONNUMMER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\b(?:\d{2})?\d{6}[-+]?\d{4}\b").expect("personnummer regex"));

// E-post: standard pragmatic email shape. Spec 039 FR-009 — the local part
// also matches Swedish å/ä/ö (the local part is where names live; the
// pre-039 \w-only pattern left "åsa@…" partially matched, leaking the å).
// Domain labels stay ASCII (IDN domains are punycode on the wire).
// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
pub(crate) static RE_EMAIL: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\b[\wåäöÅÄÖ.+-]+@[\w-]+\.[\w.-]+\b").expect("email regex"));

// Telefonnummer: Swedish national (0 + 1–3 digit area + 5–8 digits, with
// optional single space/dash separators) OR +46 international form. The
// `(?x)` verbose flag keeps the alternation readable.
// Spec 046: the national branch gained an OPTIONAL third trailing group so a
// `0NN-NNN NN NN` number (e.g. `070-123 45 67`, three pairs after the area) is
// captured in full. Pre-046 the branch had only two trailing groups, so that
// form left a 2-digit tail ("[Telefon 1] 67") — surfaced by the 2026-06-08
// live test. Two-group forms (`08-555 12 34`) and the +46 branch are unchanged.
// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
pub(crate) static RE_PHONE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?x)
        (?: \+46 [\s-]? \d (?:[\s-]?\d){7,9} )      # +46 ...
        |
        (?: \b 0 \d{1,3} [\s-]? \d{2,4} [\s-]? \d{2,4} (?:[\s-]? \d{2,4})? \b )  # 0NN-NN NN NN[ NN]
        ",
    )
    .expect("phone regex")
});

// Postnummer (Swedish postcode), spec 045: the canonical SPACED grouping only —
// first digit 1–9, two digits, exactly one separator (ASCII space OR U+00A0
// non-breaking space, the latter common in Word .docx exports), two digits,
// word-boundaried. Rationale for each constraint:
//   - `[1-9]` first digit: real postnummer span 10000–98499 and never lead with
//     0, AND a leading-0 spaced 5-digit form (`012 34`) matches RE_PHONE — keeping
//     0 out of this pattern means scrub and phone never fight over the same span.
//   - single space|NBSP only: the spaced grouping `NNN NN` is distinctive in
//     Swedish text (amounts group `NN NNN` from the right), so this rarely
//     collides; unspaced `NNNNN` is intentionally NOT matched (indistinguishable
//     from an amount/reference — left to the model + the static disclaimer, the
//     same stance taken for free-text street addresses above).
//   - `\b` both ends: never matches inside a longer digit run.
// Spec 045 — pub(crate): the pii_scrub REPLACER reuses this exact pattern so
// detect-and-replace can never disagree with detect-and-warn.
// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
pub(crate) static RE_POSTNUMMER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\b[1-9]\d{2}[\x{00A0} ]\d{2}\b").expect("postnummer regex"));

// Gatuadress (Swedish street address), spec 046: the live test (2026-06-08)
// proved gemma3:4b ignores the prompt's "Ersätt varje adress" instruction and
// leaves streets in cleartext — so the dominant Swedish street form is now
// scrubbed deterministically, the same medicine as 039/045. Shape:
//   Capital initial + letters + a KNOWN street-type suffix + house number.
// Rationale for each gate:
//   - `[A-ZÅÄÖ]` initial: Swedish street names are proper nouns — the capital
//     drops `plan 3` / `vägen 3 meter` (lowercase, not addresses).
//   - included suffixes only (longest-first within families: `gatan` before
//     `gata`); EXCLUDED as too ambiguous: plan (= våning), led (= motorled),
//     ring, park, plats — they collide with non-address senses, so they stay
//     the model's job + the static disclaimer.
//   - required `\s+\d{1,3}` house number: a bare street word ("Storgatan är
//     avstängd") is the street-as-topic, not an address — not redacted.
//   - optional trailing apartment letter — ATTACHED any-case (`12B`) OR a
//     SPACED uppercase letter (`3 A`). A spaced LOWERCASE letter is rejected so
//     a lone Swedish word after the number ("Storgatan 5 i stan" → "i") is not
//     eaten; the closing `\b` also stops grabbing a following capitalized word
//     ("Storgatan 5 Stockholm" → "Storgatan 5"). Multi-word streets ("Sankt
//     Eriksgatan 5") capture the street+number span — the leading word stays
//     harmlessly (documented edge). Streets without a known suffix (Polhem 3,
//     Box 1234) and city names are NOT caught — model's job.
// Spec 046 — pub(crate): the pii_scrub REPLACER reuses this exact pattern so
// detect-and-replace can never disagree with detect-and-warn.
//
// Spec 047 — the street body is extracted into STREET_BODY so RE_ADRESS
// (street-only) and RE_ADRESS_FULL (whole line) share one source.
const STREET_BODY: &str = r"[A-ZÅÄÖ][a-zåäöA-ZÅÄÖ]*(?:gatan|gata|vägen|väg|gränden|gränd|stigen|stig|torget|torg|allén|allé|backen|backe|liden|lid|kajen|kaj|stranden|strand|brinken|brink|hamnen|hamn|esplanaden|esplanad|promenaden|promenad|gången|gång)\s+\d{1,3}(?:[A-Za-zÅÄÖåäö]|\s[A-ZÅÄÖ])?";

// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
pub(crate) static RE_ADRESS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&(String::from(r"\b") + STREET_BODY + r"\b")).expect("adress regex")
});

// Spec 047 — whole-line address: street + optional comma + postnummer + city,
// collapsed to ONE [Adress N]. The postnummer here may be SPACED, NBSP, OR
// UNSPACED — the street-before/city-after context disambiguates the 5-digit form
// (e.g. "Lökgatan 1, 32456 Stockholm"), unlike standalone RE_POSTNUMMER which
// stays spaced-only because a bare 5-digit run is indistinguishable from an
// amount. City = one capitalized word (a multi-word city keeps only its first
// word — low-risk fragment, documented). This is a SCRUB-ONLY superset: the
// leftmost-longest sweep prefers this longer span over the partial street +
// postnummer matches; the sweep keeps RE_ADRESS for residual-street detection.
// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
pub(crate) static RE_ADRESS_FULL: LazyLock<Regex> = LazyLock::new(|| {
    let pat = String::from(r"\b")
        + STREET_BODY
        + r"\s*,?\s+[1-9]\d{2}[\x{00A0} ]?\d{2}\s+[A-ZÅÄÖ][a-zåäö]+\b";
    Regex::new(&pat).expect("adress full regex")
});

// Placeholder spans the model is SUPPOSED to emit — masked before counting
// so `[Personnr 1]` never reads as a personnummer, etc.
// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
static RE_PLACEHOLDER: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\[(?:Person|Personnr|Adress|Telefon|E-post|Postnr)[^\]]*\]")
        .expect("placeholder regex")
});

/// Scan the OUTPUT `text` for residual PII the anonymiser missed.
pub fn scan_residual_pii(text: &str) -> PiiFindings {
    // Mask placeholders so they cannot be miscounted as residue.
    let masked = RE_PLACEHOLDER.replace_all(text, " ");
    PiiFindings {
        personnummer: RE_PERSONNUMMER.find_iter(&masked).count(),
        email: RE_EMAIL.find_iter(&masked).count(),
        phone: RE_PHONE.find_iter(&masked).count(),
        postnummer: RE_POSTNUMMER.find_iter(&masked).count(),
        adress: RE_ADRESS.find_iter(&masked).count(),
    }
}

/// The Swedish warning paragraph for the sidecar, or `None` when the
/// output is clean. Categories with a zero count are omitted from the
/// sentence. Humanizer-reviewed.
pub fn warning_paragraph(f: &PiiFindings) -> Option<String> {
    if f.is_clean() {
        return None;
    }
    let mut parts: Vec<String> = Vec::new();
    if f.personnummer > 0 {
        // "personnummer" is identical in Swedish singular/plural.
        parts.push(format!("{} personnummer", f.personnummer));
    }
    if f.email > 0 {
        let noun = if f.email == 1 {
            "e-postadress"
        } else {
            "e-postadresser"
        };
        parts.push(format!("{} {noun}", f.email));
    }
    if f.phone > 0 {
        // "telefonnummer" is identical in Swedish singular/plural.
        parts.push(format!("{} telefonnummer", f.phone));
    }
    if f.postnummer > 0 {
        // "postnummer" is identical in Swedish singular/plural.
        parts.push(format!("{} postnummer", f.postnummer));
    }
    if f.adress > 0 {
        // Spec 046 — "adress" inflects: 1 adress / 2 adresser.
        let noun = if f.adress == 1 { "adress" } else { "adresser" };
        parts.push(format!("{} {noun}", f.adress));
    }
    let base = format!(
        "⚠️ Automatisk kontroll hittade möjlig kvarvarande information: {}. Granska och ta bort manuellt.",
        join_swedish(&parts)
    );
    // Spec 045 — address anchor: a surviving postnummer is the cheapest honest
    // signal that a whole street address may have slipped through (addresses
    // themselves have no reliable pattern). Point the student at the address
    // line rather than just the five digits. Humanizer-reviewed (FR-012).
    if f.postnummer > 0 {
        Some(format!(
            "{base} Ett postnummer betyder oftast att en hel adress står kvar. Ta bort hela adressraden, inte bara siffrorna."
        ))
    } else {
        Some(base)
    }
}

/// Join with commas + a final "och" (Swedish list style): "a, b och c".
fn join_swedish(parts: &[String]) -> String {
    match parts.len() {
        0 => String::new(),
        1 => parts[0].clone(),
        // len >= 2 here (0 and 1 handled above), so split_last is always Some —
        // but match it explicitly to keep this panic-free (spec 035).
        _ => match parts.split_last() {
            Some((last, head)) => format!("{} och {}", head.join(", "), last),
            None => String::new(),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_personnummer_shapes() {
        assert_eq!(scan_residual_pii("19850101-1234").personnummer, 1);
        assert_eq!(scan_residual_pii("198501011234").personnummer, 1);
        assert_eq!(scan_residual_pii("850101+1234").personnummer, 1);
        assert_eq!(
            scan_residual_pii("Anna 19010101-0101 och Bo 19020202-0202").personnummer,
            2
        );
    }

    #[test]
    fn case_numbers_and_year_ranges_are_not_personnummer() {
        // Case number T 4521-25 — too few digits, wrong shape.
        assert_eq!(scan_residual_pii("mål nr T 4521-25").personnummer, 0);
        // Year range — en-dash, only 4+4 with no 6-digit core.
        assert_eq!(scan_residual_pii("perioden 2015–2020").personnummer, 0);
    }

    #[test]
    fn placeholders_are_not_residue() {
        let t =
            "Klienten [Person 1], personnummer [Personnr 1], nås på [Telefon 1] och [E-post 1].";
        let f = scan_residual_pii(t);
        assert!(f.is_clean(), "placeholders must not count, got {f:?}");
    }

    #[test]
    fn detects_email() {
        assert_eq!(scan_residual_pii("anna.andersson@example.se").email, 1);
        assert_eq!(scan_residual_pii("inget here").email, 0);
    }

    #[test]
    fn detects_swedish_char_email_in_full() {
        // Spec 039 FR-009 — the å must be INSIDE the match, not left behind.
        let f = scan_residual_pii("kontakta åsa.öberg@exempel.se snarast");
        assert_eq!(f.email, 1);
        let m = RE_EMAIL
            .find("kontakta åsa.öberg@exempel.se snarast")
            .expect("match");
        assert_eq!(m.as_str(), "åsa.öberg@exempel.se");
    }

    #[test]
    fn detects_swedish_phone_forms() {
        assert!(scan_residual_pii("070-123 45 67").phone >= 1);
        assert!(scan_residual_pii("08-987 65 43").phone >= 1);
        assert!(scan_residual_pii("+46 70 123 45 67").phone >= 1);
    }

    #[test]
    fn clean_output_yields_no_warning() {
        let f = scan_residual_pii("Klienten [Person 1] bor på [Adress 1].");
        assert!(f.is_clean());
        assert_eq!(warning_paragraph(&f), None);
    }

    #[test]
    fn warning_omits_zero_categories_and_lists_swedish() {
        let f = PiiFindings {
            personnummer: 1,
            email: 0,
            phone: 2,
            postnummer: 0,
            adress: 0,
        };
        let w = warning_paragraph(&f).expect("warning expected");
        assert!(w.contains("1 personnummer"));
        assert!(w.contains("2 telefonnummer"));
        assert!(!w.contains("e-post"), "zero category must be omitted");
        assert!(w.contains(" och "), "Swedish list join expected");
        assert!(w.contains("Granska och ta bort manuellt"));
    }

    #[test]
    fn single_category_warning_has_no_conjunction() {
        let f = PiiFindings {
            personnummer: 1,
            email: 0,
            phone: 0,
            postnummer: 0,
            adress: 0,
        };
        let w = warning_paragraph(&f).unwrap();
        // Single-item list: no list conjunction — the item is immediately
        // followed by the sentence period. (The fixed suffix "Granska och
        // ta bort" legitimately contains "och", so assert on the list span.)
        assert!(w.contains("information: 1 personnummer. Granska"));
    }

    // ── Spec 045 — postnummer ────────────────────────────────────────────

    #[test]
    fn detects_canonical_spaced_postnummer() {
        assert_eq!(scan_residual_pii("114 35").postnummer, 1);
        assert_eq!(
            scan_residual_pii("Storgatan 5, 114 35 Stockholm").postnummer,
            1
        );
        // Two distinct postnummer.
        assert_eq!(scan_residual_pii("114 35 och 902 47").postnummer, 2);
    }

    #[test]
    fn detects_nbsp_separated_postnummer() {
        // Word .docx exports commonly use a non-breaking space (U+00A0).
        assert_eq!(scan_residual_pii("114\u{00A0}35").postnummer, 1);
    }

    #[test]
    fn non_postnummer_shapes_are_not_postnummer() {
        // Unspaced 5-digit run — intentionally out of scope (model's job).
        assert_eq!(scan_residual_pii("11435").postnummer, 0);
        // Leading 0 spaced form belongs to the phone pattern, not postnummer.
        assert_eq!(scan_residual_pii("012 34").postnummer, 0);
        // Amount grouped NN NNN (from the right) — the opposite grouping.
        assert_eq!(scan_residual_pii("15 000 kr").postnummer, 0);
        // Case number with a dash.
        assert_eq!(scan_residual_pii("mål nr T 4521-25").postnummer, 0);
        // Double space is not the canonical single-separator form.
        assert_eq!(scan_residual_pii("114  35").postnummer, 0);
        // Never matches inside a longer digit run.
        assert_eq!(scan_residual_pii("27114 35").postnummer, 0);
    }

    #[test]
    fn postnummer_placeholder_is_not_residue() {
        let f = scan_residual_pii("Klienten bor på [Adress 1], [Postnr 1].");
        assert!(f.is_clean(), "[Postnr N] must not count, got {f:?}");
    }

    #[test]
    fn warning_reports_postnummer_with_address_anchor() {
        let f = PiiFindings {
            personnummer: 0,
            email: 0,
            phone: 0,
            postnummer: 1,
            adress: 0,
        };
        let w = warning_paragraph(&f).expect("warning expected");
        assert!(w.contains("1 postnummer"));
        // The address-anchor sentence must be present.
        assert!(
            w.contains("adressraden"),
            "address-anchor sentence expected: {w}"
        );
    }

    #[test]
    fn warning_omits_address_anchor_when_no_postnummer() {
        let f = PiiFindings {
            personnummer: 1,
            email: 0,
            phone: 0,
            postnummer: 0,
            adress: 0,
        };
        let w = warning_paragraph(&f).expect("warning expected");
        assert!(!w.contains("postnummer"), "no postnummer fragment expected");
        assert!(
            !w.contains("adressraden"),
            "no address-anchor sentence when postnummer == 0"
        );
    }

    #[test]
    fn warning_lists_postnummer_in_multi_category_join() {
        let f = PiiFindings {
            personnummer: 0,
            email: 0,
            phone: 2,
            postnummer: 1,
            adress: 0,
        };
        let w = warning_paragraph(&f).expect("warning expected");
        assert!(w.contains("2 telefonnummer"));
        assert!(w.contains("1 postnummer"));
        assert!(w.contains(" och "), "Swedish list join expected");
        assert!(w.contains("adressraden"), "anchor present with postnummer");
    }

    // ── Spec 046 — gatuadress + phone widening ───────────────────────────

    #[test]
    fn detects_canonical_street_address() {
        assert_eq!(scan_residual_pii("Storgatan 5").adress, 1);
        assert_eq!(scan_residual_pii("Lillgatan 12B och Hamngatan 8").adress, 2);
    }

    #[test]
    fn non_address_shapes_are_not_streets() {
        assert_eq!(scan_residual_pii("plan 3").adress, 0);
        assert_eq!(scan_residual_pii("Plan 3").adress, 0); // excluded suffix
        assert_eq!(scan_residual_pii("Storgatan är avstängd").adress, 0); // no number
        assert_eq!(scan_residual_pii("vägen 3 meter").adress, 0); // lowercase
    }

    #[test]
    fn adress_placeholder_is_not_residue() {
        let f = scan_residual_pii("Klienten bor på [Adress 1], [Postnr 1].");
        assert!(f.is_clean(), "[Adress N] must not count, got {f:?}");
    }

    #[test]
    fn widened_phone_counts_full_number_once() {
        // Spec 046 — `070-123 45 67` is ONE match now (no leftover fragment).
        assert_eq!(scan_residual_pii("070-123 45 67").phone, 1);
        assert_eq!(scan_residual_pii("08-555 12 34").phone, 1);
    }

    #[test]
    fn warning_inflects_adress_plural() {
        // Spec 046 — 1 adress / 2 adresser (unlike the invariant nouns).
        let one = warning_paragraph(&PiiFindings {
            adress: 1,
            ..Default::default()
        })
        .expect("warning");
        assert!(one.contains("1 adress"), "{one}");
        assert!(!one.contains("1 adresser"), "singular must not pluralize");

        let many = warning_paragraph(&PiiFindings {
            adress: 2,
            ..Default::default()
        })
        .expect("warning");
        assert!(many.contains("2 adresser"), "{many}");
    }
}
