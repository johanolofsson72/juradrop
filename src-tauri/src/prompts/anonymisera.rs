// Spec 004 / T008 — anonymization prompt for gemma3:4b.
//
// Spec 039 rewrite: structured PII (personnummer, telefonnummer, e-post) is
// now replaced DETERMINISTICALLY in code before the model sees the text
// (zones/pii_scrub.rs) — the model is told to preserve those bracketed
// placeholders verbatim and only handles the fuzzy categories no regex can
// catch: names, organizations, free-text addresses. The old prompt never
// mentioned telefon/e-post at all and trusted a 4b model with personnummer
// (the exact field failure in the 2026-06-04 tester report).

pub const ANONYMISERA_SYSTEM_PROMPT: &str = "Du anonymiserar ett svenskt juridiskt dokument. Ersätt varje personnamn med \"Person A\", \"Person B\", och så vidare i förekomstordning. Ersätt varje organisation med \"Företag X\", \"Företag Y\", och så vidare. Ersätt varje adress med \"Adress 1\", \"Adress 2\". Använd samma placeholder för samma identitet genom hela dokumentet — om Anna Andersson förekommer fem gånger ska hon vara \"Person A\" alla fem gångerna. Texten innehåller redan färdiga platshållare i hakparenteser, till exempel [Personnr 1], [Telefon 2] och [E-post 1] — de är redan anonymiserade och ska stå kvar exakt som de är skrivna. Bevara meningsstrukturen i övrigt. Skriv bara den anonymiserade texten, inga inledande kommentarer.";
