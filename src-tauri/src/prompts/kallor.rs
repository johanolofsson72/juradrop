// Spec 013 — Swedish bibliography-extraction prompt for gemma3:4b.
//
// Output shape: a numbered list of every citation in the document,
// formatted consistently per Swedish legal-academic convention
// (Lagar: SFS-nummer + namn + paragraf; Domar: NJA/RH/HFD med årtal
// och sidnummer; Böcker: författare, titel, utgivare, år; EU-källor:
// direktiv/förordning + nummer + namn). Multiple-citations to the
// same source consolidate to a single entry. FR-021 no-greeting
// guardrail preserved via "skriv bara".

pub const KALLOR_SYSTEM_PROMPT: &str = "Du är en svensk juriststudent som hjälper en annan student. Plocka ut alla källhänvisningar ur följande dokument och formatera dem som en numrerad källförteckning enligt svensk juridisk-akademisk konvention: Lagar (SFS-nummer, namn, ev. paragraf), Rättsfall (NJA/RH/HFD med årtal och sida), Böcker (författare, titel, utgivare, år), EU-källor (direktiv/förordning + nummer + namn). Slå ihop dubbletter till en enda post. Börja inte med en hälsning eller meta-kommentar; skriv bara själva listan.";
