# Scenario map

Living, surveyable exploded view of every scenario. Append as the project grows; never reuse an SC-id.
Status:  ☐ mapped  ·  ◐ tested  ·  ✓ validated (proven to actually work at runtime)

> **Provenance:** this map was **derived from the existing specs (001–047 + H1)** during a fleet sync on 2026-06-20. Every row traces to a shipped spec. The scenarios are written down but **not yet validated through a scenario interview** — all rows are `☐ mapped`. A validation interview (per `.claude/rules/scenarios.md`) should confirm the four-state coverage (success / error / empty / loading) and flip rows to `◐`/`✓`.

> **Actor model:** JuraDrop is a **single-user macOS desktop app**. There is exactly one human actor — the **law student / user**. There is no multi-user auth, no roles, no server-side actor. The only non-human "actors" are the **Ollama sidecar** (local inference at `127.0.0.1:11434`) and the **GitHub Releases endpoint** (updater manifest + signed DMG only — never document content). Those appear in flows as systems, not actors.

## Use case overview (who can do what)

```mermaid
flowchart LR
  user([Law student])
  user --> uc1([Drop a document on a zone · SC-001..])
  user --> uc2([Pick a file via 'Välj fil' · SC-070])
  user --> uc3([Complete first-run wizard · SC-040])
  user --> uc4([Open Settings / pick model tier · SC-080])
  user --> uc5([Download a model tier on demand · SC-090])
  user --> uc6([Read privacy / 'inget lämnar din Mac' · SC-130])
  user --> uc7([Get / install an app update · SC-110])
  user --> uc8([Open Help for a zone · SC-085])

  uc1 --> ollama([Ollama sidecar 127.0.0.1:11434])
  uc3 --> ollama
  uc5 --> ollama
  uc7 --> gh([GitHub Releases — manifest + DMG only])
```

---

## Actor: Law student

### Feature: Drop-zone processing — transform & extract zones   (specs: 003-first-zone-sammanfatta, 004-all-six-zones, 013-nine-zones, 036-study-method-zones)

The workhorse. The same per-zone state machine drives every zone (Sammanfatta, Till engelska, Till svenska, Förenkla, Punktlista, Anonymisera, Kontakter, Källor, Generera, Identifiera rättsfrågorna, Strukturera (IRAC), Förklara begreppen). The zones differ only in their system prompt and combine strategy — the flow below is shared.

User flow:

```mermaid
flowchart TD
  A[Zone idle] --> B{Sidecar Klar?}
  B -- no --> Z[Zone disabled · same Swedish hint as welcome · SC-005]
  B -- yes --> C[Drag over → zone highlight + drop cursor · SC-002]
  C --> D{Drop payload}
  D -- 2+ files --> E[Ett dokument i taget · SC-007]
  D -- zone busy --> F[Vänta tills föregående är klart · SC-008]
  D -- one file --> G{Format supported?}
  G -- no --> H[Filformatet stöds inte … · SC-006]
  G -- yes --> I[Extract text]
  I -- parse fail --> J[Kunde inte läsa dokumentet · SC-010]
  I -- empty text --> K[Dokumentet innehåller ingen text · SC-011]
  I -- ok --> L[processing — spinner 'Sammanfattar…' + Avbryt · SC-003]
  L --> M{Model result}
  M -- timeout --> N[AI-motorn svarade inte — försök igen · SC-012]
  M -- cancelled --> A
  M -- ok --> O[success 'Klar — öppnar fil…' → sidecar opens · SC-001]
  O --> A
  N --> A
```

| ID     | Type        | Scenario                                                        | Expected outcome                                                  | Status |
|--------|-------------|-----------------------------------------------------------------|------------------------------------------------------------------|--------|
| SC-001 | happy       | Drop a supported `.docx` on a transform zone                    | Extract → model → sidecar written next to source → opens         | ☐      |
| SC-002 | happy       | Drag a file over a zone                                          | Zone highlights, macOS shows accepted-drop cursor                | ☐      |
| SC-003 | loading     | While a zone processes                                          | Spinner + zone-specific Swedish label + visible "Avbryt"         | ☐      |
| SC-004 | happy       | Source file integrity                                           | Original file never modified (SHA-256 unchanged)                 | ☐      |
| SC-005 | error       | Drop while sidecar not `Klar`                                   | Zone visibly disabled, drop rejected, welcome-card hint shown    | ☐      |
| SC-006 | error       | Drop an unsupported format (e.g. `.xlsx`)                       | Swedish "Filformatet stöds inte …" naming accepted formats       | ☐      |
| SC-007 | error       | Drop 2+ files at once                                           | "Ett dokument i taget" — no processing started                   | ☐      |
| SC-008 | adversarial | Drop a 2nd file while the zone is mid-process (single-flight)   | "Vänta tills föregående dokument är klart" — exactly one job     | ☐      |
| SC-009 | adversarial | Double-drop the SAME file rapidly (race)                        | Single-flight holds; one sidecar, no duplicate run               | ☐      |
| SC-010 | error       | Drop a corrupt / unreadable document                            | "Kunde inte läsa dokumentet" — no stack trace                    | ☐      |
| SC-011 | empty       | Drop a file that extracts to zero text                          | "Dokumentet innehåller ingen text"                               | ☐      |
| SC-012 | error       | Model times out / does not respond                              | "AI-motorn svarade inte — försök igen", zone returns to idle     | ☐      |
| SC-013 | edge        | Cancel mid-process via "Avbryt"                                 | Run aborts cleanly, zone → idle, no partial sidecar              | ☐      |
| SC-014 | edge        | Sidecar name collision (canonical output exists)               | Timestamp-suffixed sidecar, source untouched                     | ☐      |
| SC-015 | adversarial | Drop documents on multiple zones simultaneously                | Per-zone independence holds; no cross-zone corruption (spec 017) | ☐      |

### Feature: Click-to-browse file picker   (spec: 016-click-to-browse-fallback)

User flow:

```mermaid
flowchart TD
  A[Focus 'Välj fil' on a zone] --> B[Enter/Space activates]
  B --> C[Native macOS picker, filtered to zone formats, single-select · SC-070]
  C -- cancel --> A
  C -- pick file --> D[Same dispatch pipeline as drag-drop → SC-001 flow]
  A --> E{Sidecar Klar?}
  E -- no --> F['Välj fil' inert when zone disabled · SC-071]
```

| ID     | Type   | Scenario                                              | Expected outcome                                            | Status |
|--------|--------|-------------------------------------------------------|------------------------------------------------------------|--------|
| SC-070 | happy  | Open file picker via keyboard, select one file        | Native picker filtered to formats; pick feeds same pipeline | ☐      |
| SC-071 | error  | "Välj fil" while zone disabled (sidecar not Klar)     | Button inert, no picker, same hint as drop path             | ☐      |
| SC-072 | edge   | Cancel the native picker                              | Returns to idle, nothing dispatched                         | ☐      |

### Feature: Input formats & extraction   (specs: 005-additional-input-formats, 009-long-tail-formats, 028-remove-pages-support, 029-silence-pdf-extract-noise, 038-chunked-summarization)

User flow:

```mermaid
flowchart TD
  A[File dropped] --> B{Extension}
  B -- .docx/.pdf --> C[→ .docx sidecar]
  B -- .txt/.md --> D[mirror format; MD frontmatter stripped+restored]
  B -- .rtf/.odt --> E[best-effort; fall back to .docx if write unavailable · SC-022]
  B -- .pages --> F[Pages stöds inte — exportera till Word/PDF först · SC-023]
  C --> G{Extracted length}
  D --> G
  E --> G
  G -- > 24k chars, single pass --> H[Truncation notice paragraph · SC-024]
  G -- long doc --> I[Chunk → per-part pass → combine · 'Bearbetar del N av M' · SC-025]
  I -- any chunk fails --> J[All-or-nothing: no sidecar, error state · SC-026]
  G -- UTF-16 / bad encoding --> K[Teckenkodning stöds inte — spara som UTF-8 · SC-027]
  G -- scanned PDF, no text --> L[Hittade ingen text … skannade bilder stöds inte än · SC-028]
```

| ID     | Type   | Scenario                                                      | Expected outcome                                                   | Status |
|--------|--------|---------------------------------------------------------------|-------------------------------------------------------------------|--------|
| SC-020 | happy  | Drop `.pdf`, `.txt`, `.md`                                     | Correct extraction; sidecar mirrors input format (PDF→.docx)      | ☐      |
| SC-021 | edge   | `.md` with YAML/TOML frontmatter                              | Frontmatter stripped before model, restored on sidecar write      | ☐      |
| SC-022 | edge   | `.rtf` / `.odt` where native write unavailable               | Best-effort extract; graceful fall back to `.docx` sidecar        | ☐      |
| SC-023 | error  | Drop a `.pages` file (zip OR legacy bundle)                   | Actionable Swedish msg: export to Word/PDF first (spec 028)        | ☐      |
| SC-024 | edge   | Document over 24k chars in a single-pass zone                | Honest truncation-disclaimer paragraph appended                   | ☐      |
| SC-025 | happy  | Long document (20–240 pages) on a chunking zone              | Map-reduce/concat combine; "Bearbetar del N av M" progress        | ☐      |
| SC-026 | error  | A chunk or the combine pass fails mid-run                    | All-or-nothing: no sidecar written, zone shows error              | ☐      |
| SC-027 | error  | UTF-16 / unsupported-encoding text file                      | "Teckenkodning stöds inte — spara som UTF-8"                       | ☐      |
| SC-028 | error  | Scanned (image-only) PDF, no extractable text               | "Hittade ingen text … skannade bilder stöds inte än"              | ☐      |
| SC-029 | edge   | Document beyond the 12-chunk (~240-page) ceiling             | "Endast de första N delarna" honest disclaimer                    | ☐      |

### Feature: Anonymisera — deterministic PII scrub + residue sweep   (specs: 014-pii-sweep, 039-anonymisera-hardening, 040-kontakter-per-person, 044-citatbevarande, 045-postnummer, 046-gatuadress, 047-hel-rads-adress)

User flow:

```mermaid
flowchart TD
  A[Drop doc on Anonymisera] --> B[Mask quoted spans → [CITAT N] if 'behåll citat' · SC-104]
  B --> C[Deterministic regex scrub BEFORE model]
  C --> C1[personnummer/telefon/e-post → placeholders · SC-100]
  C --> C2[postnummer NNN NN → [Postnr N] · SC-101]
  C --> C3[full address line gata+postnr+ort → [Adress N] · SC-102]
  C1 --> D[Model anonymises fuzzy PII: names, free-text addresses]
  C2 --> D
  C3 --> D
  D --> E[PII residue sweep on OUTPUT]
  E -- residue found --> F[Warning paragraph: granska före delning · SC-103]
  E -- clean --> G[Disclaimer: AI-anonymisering är inte 100% · SC-105]
  F --> H[Sidecar opens]
  G --> H
```

| ID     | Type        | Scenario                                                       | Expected outcome                                                  | Status |
|--------|-------------|----------------------------------------------------------------|------------------------------------------------------------------|--------|
| SC-100 | adversarial | personnummer / telefon / e-post in the document               | Deterministically replaced BEFORE model — can never leak          | ☐      |
| SC-101 | adversarial | Postnummer in spaced `NNN NN` form                            | Scrubbed to `[Postnr N]`; amounts/case-numbers untouched          | ☐      |
| SC-102 | adversarial | Full street address line (gata + postnr + ort)               | Collapsed to a single `[Adress N]` (leftmost-longest, spec 047)   | ☐      |
| SC-103 | error       | Output still contains a missed personnummer/email/phone       | Residue sweep appends a specific visible warning paragraph        | ☐      |
| SC-104 | edge        | Instruction "behåll citaten på svenska" + translate zone     | Quoted spans masked to `[CITAT N]`, restored verbatim after       | ☐      |
| SC-105 | happy       | Clean anonymise run                                            | Placeholders applied + honest "inte 100 %" disclaimer             | ☐      |
| SC-106 | edge        | Multi-chunk anonymise (placeholder labels differ per section) | Disclaimer about inconsistent placeholders across chunks          | ☐      |
| SC-107 | edge        | Kontakter groups output per PERSON, not per category          | Per-person grouping; unpaired details → "Övriga uppgifter"        | ☐      |

### Feature: Prompt-injection framing   (spec: 022-prompt-injection-framing, 041-custom-instructions)

User flow:

```mermaid
flowchart TD
  A[Build prompt] --> B{Zone kind}
  B -- transform/extract --> C[System + anti-injection guard + DOKUMENT BÖRJAR/SLUTAR delimiters · SC-120]
  B -- Generera --> D[System + INSTRUKTIONER delimiters · input IS instruction · SC-121]
  C --> E{Custom instruction set?}
  E -- yes --> F[User instruction slot ABOVE the doc-data framing · trusted · SC-122]
  E -- no --> G[Document content treated strictly as DATA]
```

| ID     | Type        | Scenario                                                      | Expected outcome                                                 | Status |
|--------|-------------|---------------------------------------------------------------|-----------------------------------------------------------------|--------|
| SC-120 | adversarial | Document contains "ignore previous instructions …"           | Treated as DATA inside delimiters; model does not obey it        | ☐      |
| SC-121 | edge        | Generera zone whose input IS instructions                    | No anti-injection guard; instructions are followed by design    | ☐      |
| SC-122 | edge        | Per-drop custom instruction (e.g. keep quotes in Swedish)    | Instruction sits ABOVE doc framing; injection seam stays closed  | ☐      |

### Feature: First-run wizard   (spec: 008-first-run-wizard)

User flow:

```mermaid
flowchart TD
  A[Launch: no consent + no model] --> B[Welcome overlay: local-only copy + 'Fortsätt' · SC-040]
  B -- Avbryt --> B
  B -- Fortsätt --> C[Download progress: % + MB + ETA · SC-041]
  C --> D{Network}
  D -- drops --> E[Väntar på nätverk… freeze % · SC-042]
  E -- returns --> F[Resume from last byte idempotent · SC-043]
  E -- ≥5 min fail --> G[Modellnedladdningen avbröts — försök igen · SC-044]
  D -- ok --> H{Disk}
  H -- full --> I[Disk-full error state · SC-045]
  H -- ok --> J[Complete → fade out ~300ms → zones interactive · SC-046]
  K[Launch: consent + model exist] --> L[No wizard; zones immediately · SC-047]
```

| ID     | Type    | Scenario                                                | Expected outcome                                              | Status |
|--------|---------|---------------------------------------------------------|--------------------------------------------------------------|--------|
| SC-040 | happy   | First launch, click "Fortsätt"                          | Welcome explains local-only; consent captured on continue    | ☐      |
| SC-041 | loading | Model download in progress                              | Percent bar + "X MB av Y MB" + ETA, "Avbryt" available       | ☐      |
| SC-042 | error   | Network drops mid-download                              | "Väntar på nätverk…", percent freezes                        | ☐      |
| SC-043 | offline | Network returns after a drop                            | Resume from last received byte (idempotent pull)             | ☐      |
| SC-044 | error   | ≥5 min continuous download failure                      | "Modellnedladdningen avbröts — försök igen"                  | ☐      |
| SC-045 | error   | Disk fills during model download                        | Specific disk-full error, not a silent hang                  | ☐      |
| SC-046 | happy   | Download completes                                      | Wizard fades (~300ms min), zones become interactive          | ☐      |
| SC-047 | happy   | Subsequent launch (consent + model present)             | No wizard; zones visible immediately                         | ☐      |

### Feature: Settings panel & model tiers   (specs: 010-settings-panel, 025-local-crash-diagnostics, 042-privacy-visibility)

User flow:

```mermaid
flowchart TD
  A[Click gear / Cmd+,] --> B[Panel slides in from right · SC-080]
  B --> C{Section}
  C -- tier --> D[Radio: Snabb / Smart / Stor; helper text · SC-081]
  C -- appearance --> E[Read-only 'följer systemet'; live OS-theme follow · SC-082]
  C -- about --> F[Version + MIT + 'Visa utgåvor på GitHub' → browser · SC-083]
  C -- diagnostics --> G[Toggle Felsökningslogg default OFF, content-free · SC-084]
  B -- Esc / X / outside-click --> H[Panel dismissed]
  I[Settings file corrupt] --> J[Fall back to defaults, no crash · SC-086]
```

| ID     | Type   | Scenario                                                  | Expected outcome                                               | Status |
|--------|--------|-----------------------------------------------------------|---------------------------------------------------------------|--------|
| SC-080 | happy  | Open settings via gear or Cmd+,                           | Panel slides in; Esc/X/outside-click dismiss                  | ☐      |
| SC-081 | happy  | Select a model tier (Snabb / Smart / Stor)               | Selection persists; helper text shown per tier               | ☐      |
| SC-082 | edge   | OS appearance changes while panel open                   | Read-only line updates live (follows system, no toggle)      | ☐      |
| SC-083 | happy  | Click "Visa utgåvor på GitHub"                            | Default browser opens the releases page                      | ☐      |
| SC-084 | edge   | Toggle diagnostics on (default OFF)                      | Content-free local log; enum-only API; consent stored apart  | ☐      |
| SC-085 | happy  | Open Help for a zone (? icon)                            | Per-zone short + long help strings shown                     | ☐      |
| SC-086 | error  | Settings file is corrupt on load                         | Defaults used, no crash, no leaked stack trace               | ☐      |

### Feature: On-demand tier download   (specs: 027-on-demand-tier-download, 034-tier-download-pull-timeout)

User flow:

```mermaid
flowchart TD
  A[Unpulled tier row: size badge + 'Ladda ned' · SC-090] --> B[Click → /api/pull streaming]
  B --> C[Row progress '62 % · 5,0 / 8,1 GB' · SC-091]
  C --> D{Outcome}
  D -- stalled ≥90s silence --> E[Idle-timeout → network error → 'Försök igen' · SC-094]
  D -- network drop --> F[Error state + 'Försök igen' · SC-093]
  D -- disk full --> G[Disk-full error + 'Försök igen' · SC-095]
  D -- user Avbryt --> H[Cancelled, row returns to 'Ladda ned' · SC-096]
  D -- complete --> I[Row flips to selectable radio · SC-092]
  C --> J[Close+reopen panel → download survives in background · SC-097]
```

| ID     | Type        | Scenario                                                | Expected outcome                                              | Status |
|--------|-------------|---------------------------------------------------------|--------------------------------------------------------------|--------|
| SC-090 | happy       | Unpulled tier shows "Ladda ned" + size                  | Click starts `/api/pull` with streaming progress             | ☐      |
| SC-091 | loading     | Tier download in progress                               | Row shows percent + "X / Y GB"                               | ☐      |
| SC-092 | happy       | Download completes                                      | Row auto-flips to a selectable radio                        | ☐      |
| SC-093 | error       | Network drops during pull                               | Error state + "Försök igen"                                 | ☐      |
| SC-094 | error       | Pull silently stalls (no bytes ≥90s) — /tla GAP-1       | Idle timeout → network error → retry path takes over        | ☐      |
| SC-095 | error       | Disk fills during pull                                  | Specific disk-full error + "Försök igen"                    | ☐      |
| SC-096 | edge        | User clicks "Avbryt" mid-download                       | Cancelled; row returns to "Ladda ned"                       | ☐      |
| SC-097 | edge        | Close + reopen settings panel during a download         | Download survives (background task), progress persists       | ☐      |
| SC-098 | adversarial | Start a 2nd tier download while one is running          | Only one download at a time (single-flight)                  | ☐      |

### Feature: Auto-updater   (spec: 007-auto-updater)

User flow:

```mermaid
flowchart TD
  A[Launch +5s, then every 4h] --> B[Checking → GitHub Releases manifest]
  B -- up to date --> C[UpToDate, no banner]
  B -- available --> D[Badge 'Uppdatering tillgänglig' · SC-110]
  D --> E[Installera nu → Downloading N% · SC-111]
  E --> F{Verify signature}
  F -- invalid --> G[Säkerhetskontrollen misslyckades · SC-114]
  F -- ok --> H[ReadyToInstall → 'Starta om?' · SC-112]
  H -- zone busy --> I[Väntar tills jobben är klara… + Avbryt · SC-113]
  I --> J[Auto-restart when last zone idle]
  B -- no network --> K[Kan inte nå GitHub … · SC-115]
  B -- malformed manifest --> L[Ogiltigt innehåll · SC-116]
```

| ID     | Type   | Scenario                                                 | Expected outcome                                               | Status |
|--------|--------|----------------------------------------------------------|---------------------------------------------------------------|--------|
| SC-110 | happy  | An update is available                                   | Non-modal badge "Uppdatering tillgänglig" + notes             | ☐      |
| SC-111 | loading| Update downloading                                       | "Hämtar uppdatering… N%"                                      | ☐      |
| SC-112 | happy  | Update ready                                             | "Klar att installera — starta om?" → restart applies it       | ☐      |
| SC-113 | edge   | Update ready but a zone is still processing             | "Väntar tills jobben är klara…" + Avbryt; auto-restart later  | ☐      |
| SC-114 | error  | Update signature invalid                                | "Säkerhetskontrollen misslyckades — installeras inte"         | ☐      |
| SC-115 | error  | No network when checking                                 | "Kan inte nå GitHub — kontrollera nätverksanslutningen"       | ☐      |
| SC-116 | error  | Malformed update manifest                                | "Uppdateringsservern svarade med ogiltigt innehåll"           | ☐      |
| SC-117 | edge   | Unsupported macOS for the new version                    | "Den nya versionen kräver en nyare macOS — uppdatera först"    | ☐      |

### Feature: Resilient Ollama & honest readiness   (spec: 026-resilient-ollama-and-drop-ux, 011-error-recovery)

User flow:

```mermaid
flowchart TD
  A[App start] --> B{User's own Ollama on 127.0.0.1:11434?}
  B -- yes --> C[Detect + reuse it → header Klar · SC-120R]
  B -- no --> D[Start bundled sidecar]
  D -- start fail --> E[Honest Swedish error — NOT a fake 'ready' · SC-121R]
  D -- ok --> F[Header Klar; per-zone readiness reflects TRUE readiness · SC-122R]
  F --> G{Sidecar crashes}
  G -- 1st crash --> H[Silent auto-restart ≤10s; brief 'Startar AI…' · SC-123R]
  G -- 2nd crash same session --> I[AI-motorn svarar inte. Starta om JuraDrop · SC-124R]
  H --> J[In-flight job → ModelError → zone error, retryable]
```

| ID      | Type        | Scenario                                                  | Expected outcome                                              | Status |
|---------|-------------|-----------------------------------------------------------|--------------------------------------------------------------|--------|
| SC-120R | happy       | User already runs their own Ollama                       | Detect + reuse it, mark sidecar Ready                        | ☐      |
| SC-121R | error       | Sidecar fails to start                                    | Honest Swedish error — never silently fake "ready"          | ☐      |
| SC-122R | edge        | Per-zone readiness vs global header                       | They always agree; no zone enabled behind a false "Klar"    | ☐      |
| SC-123R | edge        | Sidecar crashes once                                      | Auto-restart within ~10s, brief "Startar AI…" flicker       | ☐      |
| SC-124R | error       | Sidecar crashes a second time in one session             | Terminal "AI-motorn svarar inte. Starta om JuraDrop."        | ☐      |
| SC-125R | error       | In-flight job interrupted by a crash                      | Zone shows ModelError copy; user can retry immediately      | ☐      |

### Feature: Frontend resilience & large-file guard   (specs: 023-frontend-error-boundary, 024-large-file-guard)

| ID     | Type   | Scenario                                                  | Expected outcome                                              | Status |
|--------|--------|-----------------------------------------------------------|--------------------------------------------------------------|--------|
| SC-126 | error  | A React component throws during render                    | Full-screen Swedish fallback + "Starta om" (no white screen) | ☐      |
| SC-127 | error  | Drop a multi-GB file (>50 MB cap)                         | "Filen är för stor — max 50 MB" before reading into memory   | ☐      |

### Feature: Privacy visibility   (spec: 042-privacy-visibility, 030-strict-csp)

| ID     | Type   | Scenario                                                  | Expected outcome                                              | Status |
|--------|--------|-----------------------------------------------------------|--------------------------------------------------------------|--------|
| SC-130 | happy  | User wants to confirm nothing leaves the Mac             | Persistent UI affordance "ingenting lämnar din dator"        | ☐      |
| SC-131 | happy  | First-run wizard privacy copy                             | Explains the model lives on the Mac and works offline        | ☐      |
| SC-132 | adversarial | WKWebView attempts any non-localhost egress          | Strict CSP blocks all egress except 127.0.0.1:11434 + ipc    | ☐      |

<!-- On-demand artifacts (journey map / wireflow with design-frame links / storyboard)
     to be added during the scenario-validation interview if a flow warrants it. -->

## Scenario history
- 2026-06-20 — seeded from existing specs during fleet sync (derived, awaiting validation interview)
