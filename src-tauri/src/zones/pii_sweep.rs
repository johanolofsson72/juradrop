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
}

impl PiiFindings {
    pub fn total(&self) -> usize {
        self.personnummer + self.email + self.phone
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
// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
pub(crate) static RE_PHONE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?x)
        (?: \+46 [\s-]? \d (?:[\s-]?\d){7,9} )      # +46 ...
        |
        (?: \b 0 \d{1,3} [\s-]? \d{2,4} [\s-]? \d{2,4} \b )  # 0NN-NN NN NN
        ",
    )
    .expect("phone regex")
});

// Placeholder spans the model is SUPPOSED to emit — masked before counting
// so `[Personnr 1]` never reads as a personnummer, etc.
// expect on a compile-time-constant literal regex — infallible, test-covered.
#[allow(clippy::expect_used)]
static RE_PLACEHOLDER: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\[(?:Person|Personnr|Adress|Telefon|E-post)[^\]]*\]").expect("placeholder regex")
});

/// Scan the OUTPUT `text` for residual PII the anonymiser missed.
pub fn scan_residual_pii(text: &str) -> PiiFindings {
    // Mask placeholders so they cannot be miscounted as residue.
    let masked = RE_PLACEHOLDER.replace_all(text, " ");
    PiiFindings {
        personnummer: RE_PERSONNUMMER.find_iter(&masked).count(),
        email: RE_EMAIL.find_iter(&masked).count(),
        phone: RE_PHONE.find_iter(&masked).count(),
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
    Some(format!(
        "⚠️ Automatisk kontroll hittade möjlig kvarvarande information: {}. Granska och ta bort manuellt.",
        join_swedish(&parts)
    ))
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
        };
        let w = warning_paragraph(&f).unwrap();
        // Single-item list: no list conjunction — the item is immediately
        // followed by the sentence period. (The fixed suffix "Granska och
        // ta bort" legitimately contains "och", so assert on the list span.)
        assert!(w.contains("information: 1 personnummer. Granska"));
    }
}
