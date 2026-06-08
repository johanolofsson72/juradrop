// Spec 004 / T008 — anonymization prompt for gemma3:4b.
//
// Spec 039 rewrite: structured PII (personnummer, telefonnummer, e-post) is
// now replaced DETERMINISTICALLY in code before the model sees the text
// (zones/pii_scrub.rs) — the model is told to preserve those bracketed
// placeholders verbatim and only handles the fuzzy categories no regex can
// catch: names, organizations, free-text addresses. The old prompt never
// mentioned telefon/e-post at all and trusted a 4b model with personnummer
// (the exact field failure in the 2026-06-04 tester report).
//
// Spec 045: the canonical spaced Swedish postnummer is now also pre-replaced
// deterministically (zones/pii_scrub.rs → [Postnr N]), so the preserve-verbatim
// list below names it alongside the three spec-039 placeholders.
//
// Spec 046: the dominant Swedish street-address form (Capital + street-type
// suffix + house number) is now pre-replaced too (→ [Adress N]) because the 4b
// model ignored the free-text instruction in the live test.
//
// Spec 047: the WHOLE address line (street + postnummer + city) is now collapsed
// to one [Adress N] deterministically (RE_ADRESS_FULL), so the free-text
// "Ersätt varje adress med Adress 1" instruction is REMOVED — it competed with
// the [Adress N] placeholder and made the model strip the brackets
// ([Adress 1] → Adress 1, the 2026-06-08 live test). With no competing
// instruction the model preserves [Adress N] verbatim like the other
// placeholders. Streets the regex cannot catch (no known suffix, PO boxes) now
// rely on the disclaimer rather than an unreliable model fallback (user
// decision: the regex is more trustworthy than the 4b model anyway).

pub const ANONYMISERA_SYSTEM_PROMPT: &str = "Du anonymiserar ett svenskt juridiskt dokument. Ersätt varje personnamn med \"Person A\", \"Person B\", och så vidare i förekomstordning. Ersätt varje organisation med \"Företag X\", \"Företag Y\", och så vidare. Använd samma placeholder för samma identitet genom hela dokumentet — om Anna Andersson förekommer fem gånger ska hon vara \"Person A\" alla fem gångerna. Texten innehåller redan färdiga platshållare i hakparenteser, till exempel [Personnr 1], [Telefon 2], [Postnr 1], [Adress 1] och [E-post 1] — de är redan anonymiserade och ska stå kvar exakt som de är skrivna. Bevara meningsstrukturen i övrigt. Skriv bara den anonymiserade texten, inga inledande kommentarer.";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prompt_names_all_preserved_placeholders() {
        // Spec 045/046 — every deterministically pre-replaced category must be
        // named in the preserve-verbatim list so the model keeps them intact.
        for marker in [
            "[Personnr 1]",
            "[Telefon 2]",
            "[Postnr 1]",
            "[Adress 1]",
            "[E-post 1]",
        ] {
            assert!(
                ANONYMISERA_SYSTEM_PROMPT.contains(marker),
                "prompt must name {marker} as an already-anonymized placeholder"
            );
        }
    }

    #[test]
    fn prompt_has_no_free_text_address_instruction() {
        // Spec 047 FR-006 — the free-text "Adress 1/2" instruction is REMOVED
        // (it competed with [Adress N] and made the model strip the brackets);
        // the placeholder [Adress 1] is preserved verbatim instead. The prompt
        // must therefore contain the bracketed form but NOT the quoted free-text
        // form ("Adress 1").
        assert!(
            ANONYMISERA_SYSTEM_PROMPT.contains("[Adress 1]"),
            "the [Adress N] placeholder must remain in the preserve list"
        );
        assert!(
            !ANONYMISERA_SYSTEM_PROMPT.contains("\"Adress 1\""),
            "the competing free-text address instruction must be gone"
        );
    }
}
