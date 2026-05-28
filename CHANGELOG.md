# Changelog

Alla noterbara ändringar i JuraDrop dokumenteras här.

Formatet följer [Keep a Changelog](https://keepachangelog.com/sv/1.1.0/), och projektet använder [Semantic Versioning](https://semver.org/lang/sv/).

## [Unreleased]

### Added
- `LICENSE`-fil i rotkatalogen (MIT-licens, copyright Johan Olofsson 2026). README-skylten pekar nu på en riktig fil istället för 404.
- `docs/`-katalog med `screenshots/` (platshållarbilder fram till v0.1.0-taggen) och `beta-test-runbook.md` (svensk en-sidesguide för betatestare).
- `CHANGELOG.md` (den här filen).

### Changed
- README:s statussektion uppdaterad: specs 001-011 listas som klara, spec 012 (polish + beta-prep) markeras som pågående.
- Föråldrade `spec 001`-referenser i `npm`-instruktioner och installationssektionen borttagna eller omformulerade till att spegla den nuvarande signerade DMG-pipelinen (spec 006) och de hardenade fel-tillstånden (spec 011).

## [0.1.0] - YYYY-MM-DD

Första publika utgåva. Datum sätts vid `v0.1.0`-taggens push.

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

[Unreleased]: https://github.com/johanolofsson72/juradrop/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/johanolofsson72/juradrop/releases/tag/v0.1.0
