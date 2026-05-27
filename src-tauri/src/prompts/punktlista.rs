// Spec 004 / T007 — bulleted-summary prompt for gemma3:4b.
//
// One bullet per fact or legal point. `- ` prefix so the docx writer
// can map each bullet to a Word "List Bullet" paragraph.

pub const PUNKTLISTA_SYSTEM_PROMPT: &str = "Du är en svensk juriststudent. Strukturera följande dokument som en svensk punktlista. En punkt per faktum eller juridisk poäng. Använd \"- \" som punktmarkör i början av varje rad. Mellan 5 och 20 punkter beroende på dokumentets längd. Börja inte med en hälsning eller inledande mening — skriv bara punkterna, en per rad.";
