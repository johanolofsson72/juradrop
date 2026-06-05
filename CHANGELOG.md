# Changelog

Alla noterbara ändringar i JuraDrop dokumenteras här.

Formatet följer [Keep a Changelog](https://keepachangelog.com/sv/1.1.0/), och projektet använder [Semantic Versioning](https://semver.org/lang/sv/).

## [Unreleased]

## [0.3.0] - 2026-06-05

Hela versionen är driven av den första externa betatestrundan — varje punkt
nedan spårar tillbaka till en testares konkreta observation.

### Added
- **Egna instruktioner** (spec 041): ett fält ovanför zonerna där du kan styra nästa körning ("fokusera på skadeståndsfrågan"). Instruktionen gäller vilken zon som helst, skickas bara till AI-modellen på din dator och sparas aldrig — fältet är tomt vid varje appstart.
- **Citatgaranti** (spec 044): skriv "behåll citaten" i instruktionsfältet och släpp på en översättningszon, så bevaras citattecken-markerad text ordagrant. Appen maskar citaten innan AI-modellen ser texten och återställer dem efteråt — en garanti, inte en förhoppning.
- **Synlig integritet** (spec 042): raden "Dina dokument bearbetas av lokala AI-modeller på din dator och lämnar den aldrig." står alltid under zonerna, och hjälppanelen listar ärligt appens enda två nätanvändningar (modellnedladdningen och uppdateringskollen).
- **Långa dokument bearbetas i delar** (spec 038): en 100-sidig dom sammanfattas i sin helhet — zonen visar "Bearbetar del i av n…" och väver sedan ihop delarna. Den gamla trunkeringen vid ~20 sidor är borta.
- Nativ XCUITest-svit (spec 037) som kör den riktiga appen — fönster, IPC och filväljare på riktigt (utvecklarverktyg, körs lokalt).

### Changed
- **Anonymisera ersätter personnummer, telefonnummer och e-post deterministiskt** (spec 039): strukturerade personuppgifter byts ut med regler innan AI-modellen ser texten — de kan inte längre läcka igenom, oavsett modell.
- **Plocka ut kontaktuppgifter grupperar per person** (spec 040): "## David Dahl" med hans adress, telefon och e-post under sig, i stället för kategorilistor. Uppgifter utan säker ägare hamnar under "Övriga uppgifter".
- Resultatfilen öppnas nu med fönsterfokus (öppningen kunde tidigare landa bakom appfönstret).
- Samtyckesrutan och välkomstguiden säger "din dator" konsekvent och lovar inte mer än vad som är sant.

### Fixed
- Hjälppanelen visade fortfarande ett PAGES-märke trots att `.pages`-stödet togs bort i 0.2.0 (spec 043).
- README beskrev nio zoner i ett 3×3-rutnät — uppdaterad till verklighetens tolv i 3×4.

## [0.2.0] - 2026-06-03

### Added
- **Tolv dropzoner** — rutnätet är nu 3×4. Tre nya studiemetod-zoner (spec 036) som bara bearbetar det du släpper, utan att hitta på lagrum eller rättsfall:
  - **Identifiera rättsfrågorna** — listar de rättsfrågor ett rättsfall, PM eller tentafråga väcker (utan att besvara dem).
  - **Strukturera (IRAC)** — formar om ett svar under rubrikerna Rättsfråga → Gällande rätt → Subsumtion → Slutsats.
  - **Förklara begreppen** — plockar ut juridiska facktermer och förklarar var och en på vanlig svenska.
- Tre dropzoner sedan tidigare i samma serie: **Plocka ut kontaktuppgifter**, **Generera juridisk text** och **Källförteckning**.
- Hjälpsystem: en `(?)`-ikon på varje zonkort med en kort förklaring, plus en hjälp-ikon i fönsterlisten som öppnar en panel med längre förklaringar för alla zoner.
- On-demand modellnedladdning i inställningarna (spec 027): ladda ner **Snabb** eller **Stor** direkt från panelen med progress, avbryt och felhantering.
- Klicka **Välj fil** per zon (spec 016) som tangentbords- och tillgänglighets­alternativ till drag-och-släpp.
- Lokal, frivillig felsökningslogg (spec 025) — av som standard, innehållsfri (kan aldrig logga dokumenttext), aldrig utgående.
- Automatisk PII-koll på **Anonymisera**-resultatet (spec 014): flaggar kvarvarande personnummer/e-post/telefon i sidofilen.

### Changed
- **Tryckfärdig dokumentformatering** (spec 036): Times New Roman, luft mellan stycken, feta rubriker och riktiga indragna Word-punktlistor — resultatet går att använda utan redigering.
- Robustare samexistens med en egen Ollama (spec 026): appen återanvänder en Ollama som redan kör på `127.0.0.1:11434` istället för att tysta alla zoner bakom en "redo"-rubrik. Drag-över-markering + rätt släpp-pekare.
- Fönstret startar 1160×1000 så alla tolv zoner syns utan att scrolla.
- Konstitutionen bumpad 1.1.0 → 1.2.0 (spec 036, MINOR — sex → tolv zoner). Ingen princip försvagad.

### Security
- **Strikt Content-Security-Policy** (spec 030): WKWebView får bara nå localhost-Ollama + ipc — `csp: null` är ersatt med en låst policy som gör integritetslöftet till en strukturell vägg.
- **Prompt-injection-ramning** (spec 022): det släppta dokumentet behandlas som data, inte instruktioner, så text inuti dokumentet inte kan kapa systemprompten.
- **Läs-/idle-timeout på modellnedladdning** (spec 034): en tyst stallad nedladdning hänger inte längre kvar i "laddar ned" för evigt — den faller tillbaka till nätverksfelet med **Försök igen**.
- **Panic-spärr** (spec 035): en clippy-ratchet hindrar nya `unwrap()`/`expect()` i dokument- och kommando-modulerna från att slinka in.
- CI kör alla kvalitetsgrindar på varje push (spec 031), plus `cargo audit` + `npm audit` och Dependabot (spec 032).
- Robusthetsbatteri mot trasig/illvillig indata till parsrarna (spec 015): ingen panik, ingen hängning, ingen läckt stack-trace.

### Fixed
- En render-krasch i gränssnittet visar nu ett lugnt svenskt fel med omstartsknapp i stället för vit skärm (spec 023).
- Filer större än 50 MB ger ett vänligt svenskt "filen är för stor"-fel i stället för att läsas in i minnet och riskera krasch (spec 024).
- `.pages` stöds inte längre på ett missvisande sätt — en släppt `.pages` ger en ärlig uppmaning att först exportera till Word eller PDF (spec 028).

## [0.1.0] - 2026-05-29

Första publika beta-utgåva.

### Added
- Sex svenska dropzoner: **Sammanfatta**, **Till engelska**, **Till svenska**, **Punktlista**, **Anonymisera** och **Förenkla**.
- Sju indataformat: `.docx`, `.pdf`, `.txt`, `.md`, `.rtf`, `.pages` och `.odt`. Resultatfilen följer indataformatet där en ren Rust-skrivare finns; långsvansformaten (`.rtf`, `.pages`, `.odt`) sparas alltid som `.docx`-sidofil.
- Inbäddad lokal Ollama-sidecar med modellen `gemma3:4b` (Smart-nivån). Allt körs på `127.0.0.1:11434`; inget dokumentinnehåll lämnar din Mac.
- Välkomstguide vid första start: laddar ner AI-modellen (~3 GB) med svensk progressindikator, ETA, avbryt-knapp och nätverkspaus.
- Inställningspanel (kugghjul uppe till höger) med tre modell-nivåer:
  - **Snabb** (`llama3.2:1b`, ~1.3 GB) — snabbast och minst.
  - **Smart** (`gemma3:4b`, ~3.3 GB) — standardvalet, bra balans.
  - **Stor** (`gemma3:12b`, ~8.1 GB) — bästa kvaliteten.
- Auto-uppdaterare: hämtar signerade uppdateringar från GitHub Releases var fjärde timme; väntar med omstart tills aktiva jobb är klara.
- Cmd+, öppnar inställningspanelen (macOS-konvention).
- Auto-följer systemets ljus/mörkt-läge via SF Pro-typografi.
- Felåterhämtning: sidecar-krasch detekteras + en (1) automatisk omstart per appsession. Vid andra krasch visas svenska felet **AI-motorn svarar inte. Starta om JuraDrop.** tills användaren startar om appen själv.
- Signerad + notariserad DMG via GitHub Actions; signaturverifiering på alla uppdateringar.
- Engelsk-läckage-spärr i CI: 14 förbjudna substrängar (panicked at, RUST_BACKTRACE, Box<dyn med flera) får inte förekomma i något användarsynligt strängfält.
- Telemetri-spärr i CI: 18 förbjudna biblioteksnamn (sentry, plausible, posthog med flera) får inte förekomma i någon dependency-manifest. JuraDrop samlar in noll data.

### Security
- Privacy-by-architecture: inga molntjänster för AI-inferens, ingen telemetri, ingen analys av dokumentinnehåll. Den enda utgående trafiken är (1) Tauri-uppdaterarens manifest-koll mot GitHub Releases och (2) första nedladdningen av Ollama-modellen från `ollama.com`. Båda innehåller noll användarinnehåll.

[Unreleased]: https://github.com/johanolofsson72/juradrop/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/johanolofsson72/juradrop/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/johanolofsson72/juradrop/releases/tag/v0.1.0
