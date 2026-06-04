// Spec 013 FR-021 / FR-016a — TS mirror of the 12 zones' Swedish help strings.
//
// Single source of truth: src-tauri/tests/fixtures/zone-help-strings.json.
// The Rust mirror is src-tauri/src/help/zone_help.rs. The drift test
// `help-strings-drift.test.ts` asserts this const matches the JSON
// byte-for-byte; the Rust `help_strings_drift.rs` asserts Rust ↔ JSON.
// Edit all three together.
//
// Budgets: short ≤ 80 chars, long ≤ 300 chars.

import type { ZoneId } from '@/lib/tauri-bridge';

export interface ZoneHelp {
  short: string;
  long: string;
}

export const ZONE_HELP_STRINGS = {
  sammanfatta: {
    short: 'Kortar ner ett långt dokument till det viktigaste.',
    long: 'Släpp ett dokument här så får du en kortare version som lyfter fram de viktigaste punkterna. Bra när du snabbt behöver greppa vad ett långt domslut eller avtal egentligen handlar om.',
  },
  tillengelska: {
    short: 'Översätter dokumentet till engelska.',
    long: 'Översätter en svensk text till engelska. Tänk på att juridiska termer inte alltid har en exakt motsvarighet, så läs igenom resultatet innan du använder det skarpt.',
  },
  tillsvenska: {
    short: 'Översätter dokumentet till svenska.',
    long: 'Översätter en engelsk text till svenska. Praktiskt för utländska avtal eller artiklar du behöver läsa på svenska, men kontrollera fackuttrycken efteråt.',
  },
  punktlista: {
    short: 'Gör om texten till en punktlista.',
    long: 'Plockar ut huvudpunkterna ur dokumentet och ställer upp dem som en punktlista. Bra för att få överblick över ett resonemang eller inför en tenta.',
  },
  anonymisera: {
    short: 'Tar bort namn och personuppgifter ur texten.',
    long: 'Ersätter namn, personnummer, adresser och annat som kan peka ut en person med platshållare. Granska alltid resultatet själv, automatisk anonymisering fångar inte allt.',
  },
  forenkla: {
    short: 'Skriver om krångligt lagspråk till klarspråk.',
    long: 'Gör om tungt myndighets- och lagspråk till något som går att läsa utan juristexamen. Stäm av att inga juridiska poänger försvann på vägen.',
  },
  kontakter: {
    short: 'Samlar ihop alla kontaktuppgifter i dokumentet.',
    long: 'Letar igenom dokumentet och samlar adress, personnummer, telefon och e-post under varje persons namn. Uppgifter som inte säkert hör till någon hamnar under Övriga uppgifter. Smidigt när du snabbt behöver få fram vem som är vem i ett ärende.',
  },
  generera: {
    short: 'Skapar ny juridisk text utifrån dina instruktioner.',
    long: 'Släpp en kort instruktion eller punktlista så skriver appen ett utkast till exempelvis en uppsägning eller ett avtal. Det är ett utkast, så kontrollera alltid mot lag och källa innan du använder det.',
  },
  kallor: {
    short: 'Samlar källorna i en förteckning.',
    long: 'Plockar ut hänvisningar till lagar, rättsfall och litteratur ur texten och ställer upp dem som en samlad källförteckning. Dubbelkolla att inget föll bort och att formen stämmer med din kurs.',
  },
  // Spec 036 — study-method zones.
  identifiera: {
    short: 'Listar de juridiska frågorna som texten väcker.',
    long: 'Släpp ett rättsfall, ett PM eller en tentafråga så får du en lista över rättsfrågorna att lösa — utan svar och utan påhittade lagrum. Bra för att komma igång med en uppgift.',
  },
  strukturera: {
    short: 'Strukturerar om ett svar enligt IRAC-modellen.',
    long: 'Släpp ditt eget svar så delas det in i Rättsfråga, Gällande rätt, Subsumtion och Slutsats. Ordnar om din egen text — lägger inte till nytt juridiskt innehåll eller påhittade lagrum.',
  },
  forklara: {
    short: 'Förklarar de juridiska begreppen i klartext.',
    long: 'Släpp en text full av juridiska facktermer så får du varje begrepp förklarat på vanlig svenska. Bra för att läsa ett domslut eller en doktrintext utan att fastna på orden.',
  },
} as const satisfies Record<ZoneId, ZoneHelp>;

// Spec 041 FR-013 — chrome-level help for the per-drop instruction field
// (not a zone; rendered above the zone list). Mirrored as
// `_instruction_help` in the drift fixture and as INSTRUCTION_HELP_TITLE/
// _BODY in src-tauri/src/help/zone_help.rs — edit all three together.
export const INSTRUCTION_HELP = {
  title: 'Egna instruktioner',
  body: 'Du kan skriva egna instruktioner som gäller nästa dokument du släpper, på vilken zon som helst. Instruktionen är valfri. Den skickas bara till AI-modellen på din dator och sparas aldrig.',
} as const;

// Spec 042 FR-006 — chrome-level privacy entry (the honest fine print).
// Mirrored as `_privacy_help` in the drift fixture and as
// PRIVACY_HELP_TITLE/_BODY in src-tauri/src/help/zone_help.rs — edit all
// three together.
export const PRIVACY_HELP = {
  title: 'Dina dokument stannar på din dator',
  body: 'All bearbetning sker på din dator. Dokument, egna instruktioner och resultat skickas aldrig någonstans. Appen använder internet vid två tillfällen: när AI-modellen laddas ner första gången och när den letar efter uppdateringar. Inget av det innehåller något du har skrivit eller släppt.',
} as const;

// Chrome-bar + panel chrome strings (Swedish). Kept alongside the zone
// strings; the panel title and help labels are part of the same surface.
export const HELP_CHROME_STRINGS = {
  help_icon_label: 'Hjälp',
  panel_title: 'Hjälp',
  close_label: 'Stäng',
  zone_help_icon_label: (zoneTitle: string) => `Hjälp om ${zoneTitle}`,
} as const;
