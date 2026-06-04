// Spec 013 — Swedish contact-extraction prompt for gemma3:4b.
// Spec 040 — output regrouped per PERSON (field UX: per-category lists
// forced the reader to re-pair details with their owner by hand).
//
// Output shape: one `## ` heading per person, with that person's
// details as labeled bullets (Adress / Personnummer / Telefon / E-post).
// Details the model cannot confidently attribute go under a final
// "## Övriga uppgifter" section — guessing an owner is explicitly
// forbidden (Principle VIII: fabricated attribution is worse than no
// attribution). Extraction scope is unchanged from spec 013: names plus
// the four detail categories, nothing more.
// Empty sections are omitted entirely (no "(inga)" placeholder), and an
// all-attributed result omits "## Övriga uppgifter" itself.
// FR-021 no-greeting guardrail preserved via "skriv bara".
//
// The "## Övriga uppgifter" literal must match
// `crate::zones::chunking::OVRIGA_HEADING` (the multi-chunk merge pins
// that section last); the agreement test below locks this.

pub const KONTAKTER_SYSTEM_PROMPT: &str = "Du är en svensk juriststudent som hjälper en annan student. Plocka ut alla kontaktuppgifter ur följande dokument och gruppera dem per person: en rubrik per person (till exempel '## David Dahl') och under den en bullet per uppgift med etikett — '- Adress: Storgatan 1, 211 34 Malmö', '- Personnummer: 19850312-1234', '- Telefon: 070-123 45 67', '- E-post: namn@exempel.se'. Ta bara med namn, adresser, personnummer, telefonnummer och e-post. Uppgifter som du inte säkert kan koppla till en viss person lägger du under rubriken '## Övriga uppgifter' sist i listan — gissa aldrig vem en uppgift tillhör. Hoppa över etiketter som saknar innehåll, och om alla uppgifter har en ägare utelämnar du '## Övriga uppgifter' helt. Börja inte med en hälsning eller meta-kommentar; skriv bara själva listan.";

#[cfg(test)]
mod tests {
    use super::KONTAKTER_SYSTEM_PROMPT as P;
    use crate::zones::chunking::OVRIGA_HEADING;

    // Contract §1 I-1 — per-person grouping with one heading per person.
    #[test]
    fn demands_per_person_grouping() {
        assert!(P.contains("gruppera dem per person"));
        assert!(P.contains("en rubrik per person"));
    }

    // Contract §1 I-3 — the catch-all heading the prompt demands is the
    // exact heading the merge pins last: prompt and merge cannot disagree.
    #[test]
    fn agrees_with_merge_on_ovriga_heading() {
        assert!(P.contains(OVRIGA_HEADING));
    }

    // Contract §1 I-2 — all four category labels, colon-suffixed.
    #[test]
    fn labels_all_four_categories() {
        for label in ["Adress:", "Personnummer:", "Telefon:", "E-post:"] {
            assert!(P.contains(label), "missing label {label}");
        }
    }

    // Contract §1 I-3 — no force-pairing: uncertain details are never
    // guessed onto a person.
    #[test]
    fn forbids_force_pairing() {
        assert!(P.contains("gissa aldrig vem en uppgift tillhör"));
        assert!(P.contains("sist i listan"));
    }

    // Contract §1 I-4 — empty sections omitted, incl. Övriga itself.
    #[test]
    fn omits_empty_sections() {
        assert!(P.contains("Hoppa över etiketter som saknar innehåll"));
        assert!(P.contains("utelämnar du '## Övriga uppgifter' helt"));
    }

    // Contract §1 I-5 — FR-021 no-greeting guardrail preserved.
    #[test]
    fn keeps_no_greeting_guardrail() {
        assert!(P.contains("skriv bara"));
    }

    // Contract §1 I-6 — extraction scope unchanged (names + the four
    // categories) and the old per-category output headings are gone.
    #[test]
    fn scope_unchanged_and_no_category_heading_grouping() {
        assert!(P.contains("namn, adresser, personnummer, telefonnummer och e-post"));
        for old in [
            "## Namn",
            "## Adresser",
            "## Personnummer",
            "## Telefonnummer",
            "## E-post",
        ] {
            assert!(!P.contains(old), "stale category heading {old} in prompt");
        }
    }
}
