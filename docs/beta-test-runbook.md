# Betatest av JuraDrop — guide för testare

Tack för att du hjälper till att testa JuraDrop. Den här guiden tar dig genom installation, sex korta uppgifter och hur du rapporterar en bugg. Räkna med 20–30 minuter.

## 1. Vad JuraDrop är (och inte är)

JuraDrop är en macOS-app som översätter, sammanfattar, anonymiserar och förenklar juridiska texter med en **lokal** AI. Du drar ett dokument till en av sex zoner i fönstret, och en bearbetad version sparas bredvid originalet.

**Vad JuraDrop inte gör:**

- Skickar inte ditt dokument till någon molntjänst.
- Skickar inte din IP-adress, ditt namn eller dina sökord någonstans.
- Använder inte ChatGPT, Claude.ai, Gemini eller någon annan extern AI.

**Vad JuraDrop gör med data:**

> JuraDrop samlar in noll data om dig eller dina dokument.

All AI körs lokalt via en inbäddad Ollama-process. Den enda gången appen pratar med internet är (1) första gången du startar appen, då AI-modellen (~3 GB) laddas ner från `ollama.com`, och (2) när appen kollar efter uppdateringar mot `github.com/johanolofsson72/juradrop/releases`. Båda innehåller noll innehåll från dina dokument.

## 2. Installation

1. Hämta DMG-filen från [Releases](https://github.com/johanolofsson72/juradrop/releases/latest).
2. Dubbelklicka på DMG:n. Ett fönster öppnas.
3. Dra `JuraDrop.app` till `Program`-mappen.
4. Öppna `Program`-mappen och dubbelklicka på `JuraDrop`.

Första starten tar 2–10 minuter eftersom AI-modellen laddas ner. Du ser en svensk progressindikator med en ungefärlig tid kvar. Du kan avbryta nedladdningen när som helst.

## 3. Sex uppgifter att prova

Använd ett **icke-konfidentiellt** dokument första gången du testar (en gammal kurslitteratur-uppgift, en publik dom, eller en pressrelease). När du litar på flödet kan du testa med riktigt material.

| Uppgift | Vad du gör | Vad du förväntar dig |
|---|---|---|
| 1. Sammanfatta | Dra en svensk text på 2–10 sidor till **Sammanfatta**-zonen | En kort svensk sammanfattning sparas som `<originalnamn>.sammanfatta.docx` bredvid originalet |
| 2. Översätt till engelska | Dra samma fil till **Till engelska** | En engelsk översättning sparas som `<originalnamn>.tillengelska.docx` |
| 3. Punktlista | Dra en längre text till **Punktlista** | En punktlista över nyckelpunkterna sparas som `<originalnamn>.punktlista.docx` |
| 4. Anonymisera | Dra ett dokument med personnamn/adresser till **Anonymisera** | En version där `[Person 1]`, `[Adress 1]` osv. ersatt namnen sparas. Filen har en varningstext om AI-begränsningar — läs den. |
| 5. Förenkla | Dra en juridisk text till **Förenkla** | En klarspråksversion sparas. Också med varningstext. |
| 6. Inställningspanel | Klicka på kugghjulet uppe till höger | Panelen glider in. Prova att byta modell-nivå (Snabb / Smart / Stor). Kör en zon igen och se om resultatet känns annorlunda. |

## 4. Hur du rapporterar en bugg

Skapa ett ärende på [GitHub Issues](https://github.com/johanolofsson72/juradrop/issues/new).

Skriv:

1. **Vad du gjorde** (vilken zon, vilket filformat, ungefärlig storlek).
2. **Vad du förväntade dig.**
3. **Vad som faktiskt hände** (felmeddelandets exakta text — det är alltid på svenska).
4. **Vilken version av JuraDrop** (syns under kugghjulet → Om JuraDrop).
5. **Vilken macOS-version** (Apple-meny → Om den här datorn).

Bilägg inte själva dokumentet — det innehåller troligen privilegierad information. En textbeskrivning räcker.

## 5. Vad data-frågan handlar om

Promise från avsnitt 1 stämmer på arkitektur-nivå: det finns ingen kod i JuraDrop som skickar dokumentinnehåll, sökord eller användar-IDer någonstans. Du kan själv läsa koden på [GitHub](https://github.com/johanolofsson72/juradrop) eller använda nätverkstjänsten Little Snitch för att verifiera att appen bara pratar med `127.0.0.1:11434` (lokal Ollama), `ollama.com` (modellnedladdning, en gång) och `github.com` (uppdaterings-kollen).

## 6. Avinstallation

1. Stäng JuraDrop (Cmd+Q eller röd knapp).
2. Dra `JuraDrop.app` från `Program`-mappen till papperskorgen.
3. (Valfritt — frigör diskutrymmet AI-modellen tog) Öppna Finder → menyn `Gå` → `Gå till mapp…` → skriv `~/Library/Application Support/com.juradrop.app/` → dra hela mappen till papperskorgen.
4. (Valfritt — Ollama-modellen själv ligger separat) Öppna `~/.ollama/models/` och radera mappen om du inte använder Ollama till något annat.

Tack igen för att du testar. Skicka gärna en kort sammanfattning av din upplevelse när du är klar — vad fungerade, vad var förvirrande, vad saknas.
