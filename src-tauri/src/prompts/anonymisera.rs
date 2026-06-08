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
// model ignored the free-text instruction in the live test. The bracketed
// [Adress N] is preserve-verbatim; the free-text "Adress 1/2" instruction STAYS
// as the fallback for street forms the regex cannot catch (no suffix, PO boxes).

pub const ANONYMISERA_SYSTEM_PROMPT: &str = "Du anonymiserar ett svenskt juridiskt dokument. Ersätt varje personnamn med \"Person A\", \"Person B\", och så vidare i förekomstordning. Ersätt varje organisation med \"Företag X\", \"Företag Y\", och så vidare. Ersätt varje adress som inte redan är en platshållare med \"Adress 1\", \"Adress 2\". Använd samma placeholder för samma identitet genom hela dokumentet — om Anna Andersson förekommer fem gånger ska hon vara \"Person A\" alla fem gångerna. Texten innehåller redan färdiga platshållare i hakparenteser, till exempel [Personnr 1], [Telefon 2], [Postnr 1], [Adress 1] och [E-post 1] — de är redan anonymiserade och ska stå kvar exakt som de är skrivna. Bevara meningsstrukturen i övrigt. Skriv bara den anonymiserade texten, inga inledande kommentarer.";

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
    fn prompt_keeps_free_text_address_fallback() {
        // Spec 046 FR-007 — streets the RE_ADRESS regex cannot catch (no known
        // suffix, PO boxes) still need a model-side handler, so the free-text
        // "Adress 1/2" instruction must remain.
        assert!(
            ANONYMISERA_SYSTEM_PROMPT.contains("\"Adress 1\""),
            "the free-text address fallback instruction must remain"
        );
    }
}
