# JuraDrop

> **Privata juridiska dokument förtjänar privat AI.**
> En Mac-app som översätter, sammanfattar, anonymiserar och förenklar juridiska texter — utan att en enda bokstav lämnar din dator.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS%2011%2B-lightgrey.svg)](#installation)
[![Status](https://img.shields.io/badge/status-pre--MVP-orange.svg)](#status)

---

## Vad är JuraDrop?

JuraDrop är en macOS-app för svenska juridikstudenter. Dra ett Word- eller PDF-dokument till en av sex zoner i fönstret, så bearbetar en lokal AI (Ollama) dokumentet och sparar resultatet bredvid originalet.

**Sex zoner i v1.0:**

| Zon | Vad den gör |
|---|---|
| **Till engelska** | Översätter svensk text till engelska |
| **Till svenska** | Översätter engelsk text till svenska |
| **Sammanfatta** | Skapar en kort sammanfattning |
| **Punktlista** | Plockar ut nyckelpunkter som listpunkter |
| **Anonymisera** | Ersätter namn, adresser och personnummer med `[Person 1]`, `[Adress 1]`, `[Personnr 1]` |
| **Förenkla** | Skriver om juridisk svenska i klarspråk |

## Varför?

Att klistra in konfidentiella domar, klientkorrespondens eller pågående mål i ChatGPT bryter mot tystnadsplikten och kan stå i strid med GDPR. Befintliga "AI-för-studier"-guider säger åt studenter att ladda upp privilegierad information till OpenAI — det är fel.

JuraDrop löser det med arkitektur, inte löften:

- **Allt körs lokalt.** Ollama är inbäddat i appen. Modellen lever på din disk.
- **Inget innehåll lämnar datorn.** Ingen telemetri, ingen molnanalys, ingen API-nyckel som kan läcka.
- **Inget terminalstrul.** Ingen `brew install`, ingen `pip`, inget kommandoradsmys. Dra .app till Program-mappen och kör.
- **Öppen källkod (MIT).** Alla kan läsa koden och bekräfta att löftet håller.

## Status

Pre-MVP. Inget byggt än — bara projektets grundvalar (constitution, design system, deployment-plan, spec register). Se [`specs/INDEX.md`](specs/INDEX.md) för planerade specifikationer.

Första signerade och notariserade DMG släpps under `Releases` när spec 006 är klar.

## Installation

> JuraDrop är ännu inte släppt. När v0.1 finns kommer instruktionerna här.

Förväntat installationsflöde när första utgåvan finns:

1. Hämta `JuraDrop_x.y.z_universal.dmg` från [Releases](https://github.com/johanolofsson72/juradrop/releases).
2. Öppna DMG-filen, dra `JuraDrop.app` till `Program`.
3. Starta appen. Vid första start laddas en AI-modell (~2 GB) ner.
4. Klart — dra ett dokument till en zon.

## Build from source

For contributors and the curious. End-users should wait for a release rather than building from source.

```bash
# Prerequisites: Node 20+, Rust toolchain, Xcode Command Line Tools
git clone https://github.com/johanolofsson72/juradrop.git
cd juradrop
npm install
npm run tauri dev          # run in development mode
npm run tauri build        # build a .app + .dmg (unsigned without a Developer ID cert)
```

For signing and notarization configuration, see [`.claude/docs/deployment.md`](.claude/docs/deployment.md).

## Tech stack

- **Tauri 2.x** — Rust core + WKWebView UI
- **React 18 + TypeScript + Tailwind + shadcn/ui** — frontend
- **Ollama** (bundled as Tauri sidecar) — local LLM runtime
- **Default model**: `gemma3:4b` or `llama3.2:3b` (~2–3 GB, downloaded on first launch)

See [`PROJECT-BRIEF.md`](PROJECT-BRIEF.md) for the full architecture and [`/.specify/memory/constitution.md`](.specify/memory/constitution.md) for the project's nine governing principles.

## Privacy guarantees

The only network traffic JuraDrop makes:

1. **App updater** — pulls a signed update manifest from `github.com/johanolofsson72/juradrop/releases`. No user content involved.
2. **Initial model download** — pulls the chosen Ollama model from `ollama.com` on first launch or model change. No user content involved.

That's it. No analytics, no crash reports that include document text, no cloud LLM fallback, no "anonymous usage statistics", no `phone-home-just-this-once`. Adding any new outbound network call requires a constitutional amendment, not a code review — see [Principle I of the constitution](.specify/memory/constitution.md).

## Documentation map

| File | Purpose |
|---|---|
| [`README.md`](README.md) | You are here |
| [`PROJECT-BRIEF.md`](PROJECT-BRIEF.md) | Architecture, target users, decisions, risks |
| [`.specify/memory/constitution.md`](.specify/memory/constitution.md) | Nine governing principles (privacy, zero-CLI, native feel, …) |
| [`design-system/MASTER.md`](design-system/MASTER.md) | Colors, typography, motion, the six drop zones |
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
