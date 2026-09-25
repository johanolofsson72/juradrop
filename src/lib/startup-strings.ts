// Spec 051 — Swedish copy for the startup card (tip of the launch + "Nytt i
// versionen") and its settings toggle. Bundled: nothing here is fetched, so
// the card works offline and sends nothing anywhere (Principle I).
//
// Tone per design-system/MASTER.md: du-form, direct, no exclamation marks,
// no emojis. Every tip describes a feature that exists in this build.

export const STARTUP_TIPS: readonly string[] = [
  'Du behöver inte dra filen. Klicka på ”Välj fil” under en zon så öppnas en vanlig filväljare.',
  'Skriv en egen instruktion i fältet ovanför zonerna, till exempel ”fokusera på skadeståndet”. Den gäller bara nästa dokument du släpper.',
  'Anonymisera byter ut namn, personnummer, adresser, telefonnummer och e-post mot platshållare som [Person 1]. Läs ändå igenom resultatet innan du delar det.',
  'Resultatet sparas som en ny fil bredvid originalet och öppnas direkt. Originalet ändras aldrig.',
  'Allt körs på din dator. Dina dokument, instruktioner och resultat skickas aldrig någonstans.',
  'Tryck ⌘, (kommando och komma) för att öppna inställningarna.',
  'Har du en kraftfull Mac kan du välja modellen Stor i inställningarna för bästa kvalitet. Snabb passar äldre datorer och korta texter.',
  'Strukturera (IRAC) delar in ditt eget svar i rättsfråga, gällande rätt, subsumtion och slutsats. Bra när du skriver tentasvar.',
  'Identifiera rättsfrågorna ger dig en lista över frågorna i ett rättsfall eller en tentauppgift, utan färdiga svar.',
  'Förklara begreppen går igenom facktermerna i en text och förklarar dem på vanlig svenska.',
  'JuraDrop läser .docx, .pdf, .odt, .rtf, .txt och .md. En Pages-fil behöver du först exportera till Word.',
  'Långa dokument delas upp och bearbetas i sin helhet. Du behöver inte korta ner dem själv.',
  'Plocka ut kontaktuppgifter samlar adress, telefon, e-post och personnummer under varje persons namn.',
  'Källförteckning samlar hänvisningarna till lagar, rättsfall och litteratur i en lista.',
  'Ångrar du dig medan en zon arbetar kan du trycka Avbryt. Ingen halvfärdig fil sparas.',
  'Varje zon har en liten hjälpknapp i hörnet som förklarar vad den gör.',
  'Generera juridisk text tar en kort instruktion i en .txt- eller .md-fil och skriver ett utkast, till exempel en uppsägning.',
];

/**
 * Bundled release notes, keyed by the exact app version. Shown once, on
 * the first launch after updating to that version. A version with no
 * entry simply shows a tip instead.
 */
export const RELEASE_NOTES: Readonly<Record<string, readonly string[]>> = {
  '0.5.0': [
    'Uppdateringar startar nu om appen direkt på den nya versionen.',
    'Nedladdningen av AI-modellen klarar långsamma uppkopplingar och fastnar inte längre efter Avbryt.',
    'Word-filen anger rätt modell när du kör Snabb eller Stor.',
    'Cmd+Q stänger av AI-motorn så att den inte ligger kvar i minnet.',
    'Ett nytt tips varje gång du startar appen. Du kan stänga av dem i inställningarna.',
  ],
};

export const STARTUP_STRINGS = {
  tip_heading: 'Tips',
  tip_next: 'Nästa tips',
  dismiss_label: 'Stäng',
  whats_new_heading: (version: string) => `Nytt i version ${version}`,
  whats_new_ok: 'Okej',
  card_region_label: 'Tips vid start',
  section_title: 'Start',
  tips_toggle_label: 'Visa tips vid start',
  tips_toggle_helper: 'Ett kort tips om appen varje gång du öppnar den.',
} as const;
