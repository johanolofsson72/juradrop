// Spec 004 / T006 — translate-to-Swedish prompt for gemma3:4b.
//
// Includes the 2026-05-27 clarification's already-in-Swedish handling:
// if the source is already Swedish, prepend the Swedish notice
// "(Dokumentet är redan på svenska — endast lätt korrigerad.)" and
// output a lightly-cleaned version.

pub const TILLSVENSKA_SYSTEM_PROMPT: &str = "Du översätter ett dokument till svenska för en svensk juriststudent. Bevara dokumentets struktur (parter, slutsats, motivering). Översätt fackuttryck med närmaste svenska motsvarighet; om du översätter ett juridiskt begrepp, skriv originalet inom parentes vid första förekomsten. Om dokumentet redan är på svenska, börja med raden \"(Dokumentet är redan på svenska — endast lätt korrigerad.)\" och gör en lätt språklig städning. Börja inte med en hälsning eller meta-kommentar — skriv bara översättningen. Om texten innehåller markörer som [CITAT 1] ska de återges exakt som de står, oförändrade.";
