// Spec 013 FR-021 / FR-016a — per-zone Swedish help strings.
//
// This is the Rust source of truth. The TS mirror lives at
// `src/lib/help-strings.ts`; the drift fixture at
// `src-tauri/tests/fixtures/zone-help-strings.json`. The
// `help_strings_drift.rs` integration test asserts this const matches
// the fixture byte-for-byte (Rust ↔ JSON), and `help-strings-drift`
// asserts the TS const matches it (TS ↔ JSON). Edit all three together.
//
// Budgets (FR-021): short ≤ 80 chars, long ≤ 300 chars. All copy is
// Swedish and has passed the humanizer review.

use crate::zones::ZoneId;

/// Two Swedish help strings for one zone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ZoneHelp {
    /// Popover body (≤ 80 chars).
    pub short: &'static str,
    /// HelpPanel body (≤ 300 chars, 2–3 sentences).
    pub long: &'static str,
}

/// All twelve zones' help strings, in canonical `ZoneId::ALL` order.
pub const ZONE_HELP_STRINGS: [(ZoneId, ZoneHelp); 12] = [
    (
        ZoneId::Sammanfatta,
        ZoneHelp {
            short: "Kortar ner ett långt dokument till det viktigaste.",
            long: "Släpp ett dokument här så får du en kortare version som lyfter fram de viktigaste punkterna. Bra när du snabbt behöver greppa vad ett långt domslut eller avtal egentligen handlar om.",
        },
    ),
    (
        ZoneId::TillEngelska,
        ZoneHelp {
            short: "Översätter dokumentet till engelska.",
            long: "Översätter en svensk text till engelska. Tänk på att juridiska termer inte alltid har en exakt motsvarighet, så läs igenom resultatet innan du använder det skarpt.",
        },
    ),
    (
        ZoneId::TillSvenska,
        ZoneHelp {
            short: "Översätter dokumentet till svenska.",
            long: "Översätter en engelsk text till svenska. Praktiskt för utländska avtal eller artiklar du behöver läsa på svenska, men kontrollera fackuttrycken efteråt.",
        },
    ),
    (
        ZoneId::Punktlista,
        ZoneHelp {
            short: "Gör om texten till en punktlista.",
            long: "Plockar ut huvudpunkterna ur dokumentet och ställer upp dem som en punktlista. Bra för att få överblick över ett resonemang eller inför en tenta.",
        },
    ),
    (
        ZoneId::Anonymisera,
        ZoneHelp {
            short: "Tar bort namn och personuppgifter ur texten.",
            long: "Ersätter namn, personnummer, adresser och annat som kan peka ut en person med platshållare. Granska alltid resultatet själv, automatisk anonymisering fångar inte allt.",
        },
    ),
    (
        ZoneId::Forenkla,
        ZoneHelp {
            short: "Skriver om krångligt lagspråk till klarspråk.",
            long: "Gör om tungt myndighets- och lagspråk till något som går att läsa utan juristexamen. Stäm av att inga juridiska poänger försvann på vägen.",
        },
    ),
    (
        ZoneId::Kontakter,
        ZoneHelp {
            short: "Samlar ihop alla kontaktuppgifter i dokumentet.",
            long: "Letar igenom dokumentet och samlar adress, personnummer, telefon och e-post under varje persons namn. Uppgifter som inte säkert hör till någon hamnar under Övriga uppgifter. Smidigt när du snabbt behöver få fram vem som är vem i ett ärende.",
        },
    ),
    (
        ZoneId::Generera,
        ZoneHelp {
            short: "Skapar ny juridisk text utifrån dina instruktioner.",
            long: "Släpp en kort instruktion eller punktlista så skriver appen ett utkast till exempelvis en uppsägning eller ett avtal. Det är ett utkast, så kontrollera alltid mot lag och källa innan du använder det.",
        },
    ),
    (
        ZoneId::Kallor,
        ZoneHelp {
            short: "Samlar källorna i en förteckning.",
            long: "Plockar ut hänvisningar till lagar, rättsfall och litteratur ur texten och ställer upp dem som en samlad källförteckning. Dubbelkolla att inget föll bort och att formen stämmer med din kurs.",
        },
    ),
    // Spec 036 — study-method zones.
    (
        ZoneId::Identifiera,
        ZoneHelp {
            short: "Listar de juridiska frågorna som texten väcker.",
            long: "Släpp ett rättsfall, ett PM eller en tentafråga så får du en lista över rättsfrågorna att lösa — utan svar och utan påhittade lagrum. Bra för att komma igång med en uppgift.",
        },
    ),
    (
        ZoneId::Strukturera,
        ZoneHelp {
            short: "Strukturerar om ett svar enligt IRAC-modellen.",
            long: "Släpp ditt eget svar så delas det in i Rättsfråga, Gällande rätt, Subsumtion och Slutsats. Ordnar om din egen text — lägger inte till nytt juridiskt innehåll eller påhittade lagrum.",
        },
    ),
    (
        ZoneId::Forklara,
        ZoneHelp {
            short: "Förklarar de juridiska begreppen i klartext.",
            long: "Släpp en text full av juridiska facktermer så får du varje begrepp förklarat på vanlig svenska. Bra för att läsa ett domslut eller en doktrintext utan att fastna på orden.",
        },
    ),
];

/// Spec 041 FR-013 — chrome-level help for the per-drop instruction
/// field (not a zone; lives above the zone list in the help panel).
/// Mirrored as `_instruction_help` in the JSON fixture and as
/// `INSTRUCTION_HELP` in `src/lib/help-strings.ts` — edit all three
/// together. Swedish, humanizer-reviewed.
pub const INSTRUCTION_HELP_TITLE: &str = "Egna instruktioner";
pub const INSTRUCTION_HELP_BODY: &str = "Du kan skriva egna instruktioner som gäller nästa dokument du släpper, på vilken zon som helst. Instruktionen är valfri. Den skickas bara till AI-modellen på din dator och sparas aldrig. Modellen följer den så gott den kan — enkla önskemål, som vad resultatet ska fokusera på, fungerar bäst. Skriver du behåll citaten i en översättningszon bevaras citattecken-markerad text ordagrant — det garanterar appen, inte modellen.";

/// Spec 042 FR-006 — chrome-level privacy entry (the honest fine print:
/// what never leaves + the only two network uses). Mirrored as
/// `_privacy_help` in the JSON fixture and as `PRIVACY_HELP` in
/// `src/lib/help-strings.ts` — edit all three together. Swedish,
/// humanizer-reviewed.
pub const PRIVACY_HELP_TITLE: &str = "Dina dokument stannar på din dator";
pub const PRIVACY_HELP_BODY: &str = "All bearbetning sker på din dator. Dokument, egna instruktioner och resultat skickas aldrig någonstans. Appen använder internet vid två tillfällen: när AI-modellen laddas ner första gången och när den letar efter uppdateringar. Inget av det innehåller något du har skrivit eller släppt.";

/// Look up one zone's help strings.
pub fn zone_help(zone: ZoneId) -> ZoneHelp {
    ZONE_HELP_STRINGS
        .iter()
        .find(|(z, _)| *z == zone)
        .map(|(_, h)| *h)
        .expect("ZONE_HELP_STRINGS is total over ZoneId")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_zone_has_help_within_budget() {
        for zone in ZoneId::ALL {
            let h = zone_help(zone);
            assert!(
                !h.short.is_empty() && h.short.chars().count() <= 80,
                "{zone:?} short out of budget ({} chars)",
                h.short.chars().count()
            );
            assert!(
                !h.long.is_empty() && h.long.chars().count() <= 300,
                "{zone:?} long out of budget ({} chars)",
                h.long.chars().count()
            );
        }
    }

    #[test]
    fn strings_table_is_in_canonical_zone_order() {
        for (i, zone) in ZoneId::ALL.iter().enumerate() {
            assert_eq!(ZONE_HELP_STRINGS[i].0, *zone, "order drift at index {i}");
        }
    }
}
