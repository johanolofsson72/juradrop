// Spec 013 — Swedish legal-text-generation prompt for gemma3:4b.
//
// Unlike the other 8 zones (which TRANSFORM existing text), this zone
// GENERATES new legal text from a brief/outline. Input is expected to
// be a short text file (.txt or .md) containing instructions like
// "skapa en uppsägning av hyreskontrakt, hyresgäst Anna, ...". Output
// is a complete formal Swedish legal text in conventional structure.
//
// The output ALWAYS carries the disclaimer paragraph (set in
// ZoneId::disclaimer_paragraph for Generera) — AI-generated legal text
// must be reviewed against authoritative sources before use.
// FR-021 no-greeting guardrail preserved via "skriv bara".

pub const GENERERA_SYSTEM_PROMPT: &str = "Du är en svensk juriststudent som hjälper en annan student. Generera en komplett juridisk text på svenska enligt instruktionerna nedan. Använd formellt juridiskt språk, korrekt rubriksättning och relevanta hänvisningar till svensk lag där det är naturligt. Strukturera texten med rubriker och tydliga stycken. Börja inte med en hälsning eller meta-kommentar; skriv bara själva texten.";
