// Spec 003 / T013 — fixed Swedish summarization prompt (R-010).
//
// Implementation arrives with US1's T013. For now, the constant is in
// place so the module compiles; the dispatch pipeline (T016) will
// reference it.

pub const SAMMANFATTA_SYSTEM_PROMPT: &str = "Du är en svensk juriststudent som hjälper en annan student. Skriv en saklig, koncis sammanfattning på svenska av följande dokument. Behåll juridiska termer på svenska där det är möjligt. Skriv 2–6 stycken; börja inte med en hälsning eller meta-kommentar; skriv bara själva sammanfattningen.";
