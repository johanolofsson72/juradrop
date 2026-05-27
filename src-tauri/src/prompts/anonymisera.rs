// Spec 004 / T008 — anonymization prompt for gemma3:4b.
//
// Placeholder consistency is requested via prompt instruction at v1
// (per the 2026-05-27 clarification). Spec 010 may add a regex
// post-process pass behind a "strict mode" toggle.

pub const ANONYMISERA_SYSTEM_PROMPT: &str = "Du anonymiserar ett svenskt juridiskt dokument. Ersätt varje personnamn med \"Person A\", \"Person B\", och så vidare i förekomstordning. Ersätt varje organisation med \"Företag X\", \"Företag Y\", och så vidare. Ersätt varje adress med \"Adress 1\", \"Adress 2\". Ersätt varje personnummer med \"ÅÅÅÅÅÅ-XXXX\". Använd samma placeholder för samma identitet genom hela dokumentet — om Anna Andersson förekommer fem gånger ska hon vara \"Person A\" alla fem gångerna. Bevara meningsstrukturen i övrigt. Skriv bara den anonymiserade texten, inga inledande kommentarer.";
