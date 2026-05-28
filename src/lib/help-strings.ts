// Spec 013 FR-021 / FR-016a — TS mirror of the 9 zones' Swedish help strings.
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
    long: 'Letar igenom dokumentet och listar namn, adresser, personnummer, telefonnummer och e-post var för sig. Smidigt när du snabbt behöver få fram vem som är vem i ett ärende.',
  },
  generera: {
    short: 'Skapar ny juridisk text utifrån dina instruktioner.',
    long: 'Släpp en kort instruktion eller punktlista så skriver appen ett utkast till exempelvis en uppsägning eller ett avtal. Det är ett utkast, så kontrollera alltid mot lag och källa innan du använder det.',
  },
  kallor: {
    short: 'Samlar källorna i en förteckning.',
    long: 'Plockar ut hänvisningar till lagar, rättsfall och litteratur ur texten och ställer upp dem som en samlad källförteckning. Dubbelkolla att inget föll bort och att formen stämmer med din kurs.',
  },
} as const satisfies Record<ZoneId, ZoneHelp>;

// Chrome-bar + panel chrome strings (Swedish). Kept alongside the zone
// strings; the panel title and help labels are part of the same surface.
export const HELP_CHROME_STRINGS = {
  help_icon_label: 'Hjälp',
  panel_title: 'Hjälp',
  close_label: 'Stäng',
  zone_help_icon_label: (zoneTitle: string) => `Hjälp om ${zoneTitle}`,
} as const;
