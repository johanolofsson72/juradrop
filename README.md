# JuraDrop

> **Privata juridiska dokument förtjänar privat AI.**
> En Mac-app som översätter, sammanfattar, anonymiserar och förenklar juridiska texter — utan att en enda bokstav lämnar din dator.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey.svg)](#installation)
[![Release](https://img.shields.io/github/v/release/johanolofsson72/juradrop?label=release)](https://github.com/johanolofsson72/juradrop/releases/latest)

![JuraDrops huvudfönster: tolv dropzoner i ett 3×4-rutnät, mörkt läge](docs/screenshots/zone-grid-dark.png)

## Vad är JuraDrop?

JuraDrop är en macOS-app för svenska juridikstudenter. Dra ett Word- eller PDF-dokument till en av tolv zoner i fönstret, så bearbetar en lokal AI-modell (Ollama) dokumentet och sparar resultatet bredvid originalet. Resultatfilen öppnas automatiskt när den är klar.

**Tolv zoner:**

| Zon | Vad den gör |
|---|---|
| **Till engelska** | Översätter svensk text till engelska |
| **Till svenska** | Översätter engelsk text till svenska |
| **Sammanfatta** | Skapar en kort sammanfattning |
| **Punktlista** | Plockar ut nyckelpunkter som listpunkter |
| **Anonymisera** | Ersätter namn, adresser och personnummer med `[Person 1]`, `[Adress 1]`, `[Personnr 1]` |
| **Förenkla** | Skriver om juridisk svenska i klarspråk |
| **Plocka ut kontaktuppgifter** | Samlar adress, personnummer, telefon och e-post under varje persons namn |
| **Generera juridisk text** | Skriver ett utkast utifrån en kort instruktion (`.txt`/`.md`) |
| **Källförteckning** | Samlar lagar, rättsfall och litteratur i en förteckning |
| **Identifiera rättsfrågorna** | Listar de juridiska frågorna som texten väcker |
| **Strukturera (IRAC)** | Strukturerar om ett svar enligt IRAC-modellen |
| **Förklara begreppen** | Förklarar de juridiska begreppen i klartext |

Varje zon har en `(?)`-ikon med en kort förklaring, och hjälp-ikonen uppe till höger öppnar en panel som listar alla zoner.

**Egna instruktioner:** ovanför rutnätet finns ett fält där du kan skriva en instruktion som gäller nästa dokument du släpper, på vilken zon som helst — till exempel ”behåll citaten” på Till engelska. Skriver du just det bevaras citattecken-markerad text ordagrant: appen maskar citaten innan modellen ser texten och återställer dem efteråt. Instruktionen är valfri, skickas bara till AI-modellen på din dator och sparas aldrig.

## Skärmdumpar

| Välkomstguide (modellnedladdning) | Inställningspanel |
|---|---|
| ![Välkomstguiden laddar ner AI-modellen med progressbar](docs/screenshots/welcome-wizard-download.png) | ![Inställningspanelen med modellval, utseende och felsökningslogg](docs/screenshots/settings-panel.png) |

## Varför?

Att klistra in konfidentiella domar, klientkorrespondens eller pågående mål i ChatGPT bryter mot tystnadsplikten och kan stå i strid med GDPR. Befintliga "AI-för-studier"-guider säger åt studenter att ladda upp privilegierad information till OpenAI — det är fel.

JuraDrop löser det med arkitektur, inte löften:

- **Allt körs lokalt.** Ollama är inbäddat i appen. Modellen lever på din disk.
- **Inget innehåll lämnar datorn.** Ingen telemetri, ingen molnanalys, ingen API-nyckel som kan läcka.
- **Inget terminalstrul.** Ingen `brew install`, ingen `pip`, inget kommandoradsmys. Dra .app till Program-mappen och kör.
- **Öppen källkod (MIT).** Alla kan läsa koden och bekräfta att löftet håller.

## Så fungerar det

Varje zon tar emot sex format: `.docx`, `.pdf`, `.txt`, `.md`, `.rtf` och `.odt`. Texten extraheras lokalt, skickas till modellen på `127.0.0.1:11434` med en zonspecifik svensk systemprompt, och resultatet sparas som `<originalnamn>.<zon>.<format>` bredvid originalet.

Några detaljer som är bra att känna till:

- **Resultatformatet följer indataformatet** där det går: `.txt` in ger `.txt` ut, `.md` in bevarar Markdown-strukturen. `.rtf` och `.odt` sparas alltid som `.docx`-sidofil, eftersom ingen ren Rust-skrivare finns för de formaten.
- **Långa dokument bearbetas i delar.** En 100-sidig dom sammanfattas i sin helhet — zonen visar "Bearbetar del i av n…" och väver sedan ihop delarna.
- **Anonymisera ersätter personnummer, telefonnummer och e-post med regler, inte AI.** Strukturerade personuppgifter byts ut deterministiskt innan modellen ens ser texten, så de kan inte läcka igenom. Modellen hanterar bara namn och friare adresstext, och en automatisk PII-koll flaggar eventuella rester i resultatet.
- **Modellval i inställningarna:** Snabb, Smart eller Stor. Standardvalet är Smart (`gemma3:4b`). Snabb och Stor laddas ner direkt från panelen när du vill ha dem.
- **Felen är ärliga och på svenska.** Krypterade PDF:er, bildbaserade PDF:er utan textlager och korrupta filer ger tydliga felmeddelanden i stället för att tyst misslyckas. Apple Pages-filer stöds inte (moderna Pages sparar i ett oläsbart format), och appen säger det rakt ut: `Pages-filer stöds inte — exportera till Word eller PDF först`.
- **Kraschar AI-motorn startas den om automatiskt en gång.** Vid en andra krasch visas `AI-motorn svarar inte. Starta om JuraDrop.` — aldrig en stack trace.
- Zoner vars resultat kräver extra granskning (Anonymisera, Förenkla, Generera och de tre studiemetod-zonerna) har en varningstext om AI-modellens begränsningar.

Testsviten har dessutom en spärr som vägrar bygget om någon `sentry`/`plausible`/`posthog`/liknande dyker upp bland beroendena.

## Status

Publik beta. Senaste versionen är [v0.3.0](https://github.com/johanolofsson72/juradrop/releases/latest), signerad och notariserad. Extern betatestning pågår, och hela 0.3.0-versionen är driven av den första testrundans återkoppling — se [`CHANGELOG.md`](CHANGELOG.md) för vad varje version innehåller och [`specs/INDEX.md`](specs/INDEX.md) för spec-historiken.

Releasekedjan är automatiserad: GitHub Actions bygger en universal `.app` (Apple Silicon + Intel), signerar med Developer ID, notariserar via Apple och laddar upp en signerad DMG under [Releases](https://github.com/johanolofsson72/juradrop/releases). Den inbyggda uppdateraren hämtar nya versioner med signaturverifiering.

## Installation

1. Hämta `JuraDrop_x.y.z_universal.dmg` från [Releases](https://github.com/johanolofsson72/juradrop/releases/latest).
2. Öppna DMG-filen genom att dubbelklicka — ingen Gatekeeper-varning, appen är signerad och notariserad av Apple.
3. Dra `JuraDrop.app` till `Program`.
4. Starta appen. Vid första start laddas en AI-modell (~2 GB) ner från `ollama.com` — det är enda gången appen behöver internet för något annat än uppdateringskollen.
5. Klart — dra ett dokument till en zon.

## Auto-updater

JuraDrop letar efter nya versioner ungefär var fjärde timme medan appen är öppen. När en uppdatering finns dyker en liten knapp upp uppe till höger — ingen modal som blockerar arbetet. Klicka för att se vad som är nytt och tryck **Installera nu** för att hämta. Signaturen verifieras lokalt innan något skrivs till disk. När nedladdningen är klar väljer du själv när omstarten ska ske; om en zon fortfarande jobbar väntar appen tills jobben är klara.

Vill du inte bli störd just nu finns en × som döljer indikatorn tills nästa version dyker upp. En diskret tidsstämpel längst ner till höger visar när senaste sökningen gjordes, och en knapp där kör en manuell sökning om du föredrar det.

Uppdateringskollen pratar bara med `api.github.com` (manifestet) och `objects.githubusercontent.com` (DMG-binären) — inget dokumentinnehåll är inblandat.

## Build from source

For contributors and the curious. End-users should grab a [release](https://github.com/johanolofsson72/juradrop/releases/latest) instead.

### Prerequisites

- macOS 12 (Monterey) or later, Apple Silicon
- [Xcode Command Line Tools](https://developer.apple.com/) — `xcode-select --install`
- [Node 20+](https://nodejs.org/) — via `nvm` or Homebrew
- [Rust toolchain](https://rustup.rs/) — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- The Apple Silicon Rust target — `rustup target add aarch64-apple-darwin`

### Clone and run

```bash
git clone https://github.com/johanolofsson72/juradrop.git
cd juradrop
npm install
bash scripts/fetch-ollama.sh   # one-time: pulls the pinned Ollama binary (~75 MB) into src-tauri/binaries/
npm run tauri dev              # opens the dev window
```

`fetch-ollama.sh` is required before `npm run tauri dev` because JuraDrop bundles Ollama as a Tauri sidecar — without the binary at `src-tauri/binaries/ollama-aarch64-apple-darwin`, the app launches with the "AI-motorn kunde inte starta" error state. The script verifies a pinned SHA-256, so it's safe to re-run and will exit cleanly if the binary is already present. CI fetches the binary automatically as part of the release workflow.

### Production build

```bash
bash scripts/fetch-ollama.sh   # same prerequisite as `tauri dev`
npm run tauri:build            # produces src-tauri/target/aarch64-apple-darwin/release/bundle/macos/JuraDrop.app
```

Local production builds are unsigned by design — `npm run tauri:build` produces a `.app` that macOS Gatekeeper will block on double-click. Right-click → Open the first time to bypass when iterating locally. The signed + notarized universal DMG is produced by the GitHub Actions release workflow; it runs `fetch-ollama.sh` as part of the pipeline so end users never need that step.

### Verifying the toolchain

```bash
npm test                                       # vitest (frontend)
npm run lint                                   # eslint
npm run typecheck                              # tsc --noEmit
npm run test:e2e                               # playwright smoke against the real frontend (mocked Tauri IPC)
cd src-tauri && cargo test                     # Rust unit tests
cd src-tauri && cargo clippy -- -D warnings    # Rust lints
cd src-tauri && cargo fmt -- --check           # Rust format check
scripts/native-smoke.sh                        # native XCUITest against the real .app (opt-in, needs Xcode + GUI)
```

Every command should exit 0 on a clean checkout.

The README screenshots in `docs/screenshots/` are generated from the real frontend — regenerate them after UI changes with:

```bash
README_SCREENSHOTS=1 npx playwright test tests/e2e/readme-screenshots.spec.ts
```

For signing and notarization configuration, see [`.claude/docs/deployment.md`](.claude/docs/deployment.md).

## Tech stack

- **Tauri 2.x** — Rust core + WKWebView UI
- **React 18 + TypeScript + Tailwind + shadcn/ui** — frontend
- **Ollama** (bundled as Tauri sidecar) — local LLM runtime
- **Default model**: `gemma3:4b` (Smart tier; Snabb is `llama3.2:1b`, Stor is `gemma3:12b`)

See [`PROJECT-BRIEF.md`](PROJECT-BRIEF.md) for the full architecture and [`/.specify/memory/constitution.md`](.specify/memory/constitution.md) for the project's nine governing principles.

## Privacy guarantees

The only network traffic JuraDrop makes:

1. **App updater** — pulls a signed update manifest from `github.com/johanolofsson72/juradrop/releases`. No user content involved.
2. **Model downloads** — pulls the chosen Ollama model from `ollama.com` on first launch or model change. No user content involved.

That's it. No analytics, no crash reports that include document text, no cloud LLM fallback, no "anonymous usage statistics", no `phone-home-just-this-once`. The WKWebView runs under a Content-Security-Policy that forbids all network egress except localhost Ollama, so the guarantee is structural, not a code-review promise. Adding any new outbound network call requires a constitutional amendment — see [Principle I of the constitution](.specify/memory/constitution.md).

Dina dokument, egna instruktioner och resultat lämnar aldrig din dator — och appen säger det rakt ut: en rad under zonerna i huvudfönstret, en förklaring i välkomstguiden och en post i hjälppanelen upprepar samma fakta som ovan. AI-modellen bor på din dator; efter den första nedladdningen fungerar all bearbetning utan internet.

## Documentation map

| File | Purpose |
|---|---|
| [`README.md`](README.md) | You are here |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed in each release |
| [`PROJECT-BRIEF.md`](PROJECT-BRIEF.md) | Architecture, target users, decisions, risks |
| [`.specify/memory/constitution.md`](.specify/memory/constitution.md) | Nine governing principles (privacy, zero-CLI, native feel, …) |
| [`design-system/MASTER.md`](design-system/MASTER.md) | Colors, typography, motion, the twelve drop zones |
| [`specs/INDEX.md`](specs/INDEX.md) | Spec register — what's planned, in order |
| [`.claude/docs/deployment.md`](.claude/docs/deployment.md) | Apple Developer setup, signing, notarization, CI |
| [`CLAUDE.md`](CLAUDE.md) | Working instructions for Claude Code in this repo |

## Contributing

Contributions welcome — but every change must respect the constitution, especially Principle I (Privacy by Architecture). PRs that add cloud calls, telemetry that captures user content, or outbound traffic of any kind will be rejected on principle, not negotiated.

Before opening a PR:
- Read [`.specify/memory/constitution.md`](.specify/memory/constitution.md).
- Read [`CLAUDE.md`](CLAUDE.md) for the workflow conventions.
- Run `npm test`, `cd src-tauri && cargo test`, and the Playwright smoke suite locally.

## License

MIT — see [`LICENSE`](LICENSE).

Built by [Johan Olofsson](https://github.com/johanolofsson72) with [Claude Code](https://claude.com/claude-code).
