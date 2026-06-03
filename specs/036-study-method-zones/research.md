# Research: Study-method drop zones

Phase 0. No `NEEDS CLARIFICATION` remained (the 4 soft decisions were locked in `/clarify`; the layout was locked by the `frontend-design` gate). This file records the layout decision, the per-zone semantics, and the DRAFT Swedish copy — which MUST pass the `humanizer` skill before shipping (FR-009 / SC-006).

## R-001 — Window/grid layout (frontend-design decision, RESOLVED)

**Decision**: window height 760 → **1000** (width 1160 unchanged); `minHeight` 500 unchanged; grid classes `grid-cols-1 / sm:grid-cols-2 / lg:grid-cols-3` unchanged.
**Rationale**: see plan.md §"Layout decision". 12 = clean 3×4 with zero orphan tiles at every breakpoint.
**Alternatives considered**: a new `xl:grid-cols-4` (→ 3 rows) — rejected, it would shrink tiles and break the established 3-column rhythm; widening the window instead of heightening — rejected, width is already comfortable and 3 columns is the design intent.

## R-002 — Per-zone semantics + Principle-VIII citation guard

All three are **transform** zones (mirror input format; fall through `output_format.rs` `_` arm) and **DATA**-framed (fall through `framing.rs` `_` arm — document delimiters + anti-injection guard). Each `system_prompt` MUST include: (a) a "skriv bara …" no-preamble guardrail (the existing prompt convention), and (b) an explicit "hitta inte på lagrum/paragrafer/rättsfall" anti-fabrication clause (FR-003, the guard that replaces a rejected citation zone).

| Zone | slug | sidecar_suffix | kind | framing | disclaimer | output shape |
|---|---|---|---|---|---|---|
| Identifiera rättsfrågorna | `identifiera` | `rattsfragor` | transform | data | yes | a list of the legal issues |
| Strukturera (IRAC) | `strukturera` | `irac` | transform | data | yes | four headed sections: Rättsfråga / Gällande rätt / Subsumtion / Slutsats |
| Förklara begreppen | `forklara` | `begrepp` | transform | data | yes | term → plain-Swedish explanation pairs |

Suffixes are descriptive of the OUTPUT (matching the existing pattern — `anonymisera`→`anonymiserad`, content-describing), ASCII, lowercase. `header_paragraph_template` mirrors the existing `"<Output> … '{name}'"` shape.

## R-003 — DRAFT Swedish copy (→ humanizer before shipping)

Matches the established voice (`hint_copy` = `"Släpp .docx/.pdf/.txt/.md/.rtf/.odt för <noun>"`; `processing_hint` = `"<verb>…"`; help `short` = one sentence; `long` ≤ 300 chars, 2 sentences; disclaimer = `"<caveat> — granska <what>."`).

### identifiera (Identifiera rättsfrågorna)
- title: `Identifiera rättsfrågorna`
- hint_copy: `Släpp .docx/.pdf/.txt/.md/.rtf/.odt för att hitta rättsfrågorna`
- processing_hint: `Letar rättsfrågor…`
- header_paragraph_template: `Rättsfrågor i '{name}'`
- disclaimer: `AI:n kan missa en rättsfråga eller hitta en som inte finns — granska listan själv.`
- help.short: `Listar de juridiska frågorna som texten väcker.`
- help.long: `Släpp ett rättsfall, ett PM eller en tentafråga så får du en lista över rättsfrågorna att lösa — utan svar och utan påhittade lagrum. Bra för att komma igång med en uppgift.`
- system_prompt (draft): `Du är ett studieverktyg för en svensk juriststudent. Läs dokumentet och lista de rättsfrågor (juridiska frågor) som materialet väcker. Besvara dem inte. Hitta inte på lagrum, paragrafer eller rättsfall. Skriv bara listan med rättsfrågor, inget annat.`

### strukturera (Strukturera (IRAC))
- title: `Strukturera (IRAC)`
- hint_copy: `Släpp .docx/.pdf/.txt/.md/.rtf/.odt för IRAC-struktur`
- processing_hint: `Strukturerar…`
- header_paragraph_template: `IRAC-struktur av '{name}'`
- disclaimer: `AI:n kan placera ett resonemang under fel rubrik — granska strukturen själv.`
- help.short: `Strukturerar om ett svar enligt IRAC-modellen.`
- help.long: `Släpp ditt eget svar så delas det in i Rättsfråga, Gällande rätt, Subsumtion och Slutsats. Ordnar om din egen text — lägger inte till nytt juridiskt innehåll eller påhittade lagrum.`
- system_prompt (draft): `Du är ett studieverktyg. Strukturera om texten enligt IRAC-modellen, under de fyra svenska rubrikerna i ordning: Rättsfråga, Gällande rätt, Subsumtion, Slutsats. Använd bara innehållet i texten — lägg inte till nytt juridiskt innehåll och hitta inte på lagrum eller rättsfall. Skriv bara den strukturerade texten.`

### forklara (Förklara begreppen)
- title: `Förklara begreppen`
- hint_copy: `Släpp .docx/.pdf/.txt/.md/.rtf/.odt för begreppsförklaringar`
- processing_hint: `Förklarar begrepp…`
- header_paragraph_template: `Begreppsförklaringar för '{name}'`
- disclaimer: `AI:n kan förenkla för mycket — stäm av viktiga begrepp mot en ordbok eller lärobok.`
- help.short: `Förklarar de juridiska begreppen i klartext.`
- help.long: `Släpp en text full av juridiska facktermer så får du varje begrepp förklarat på vanlig svenska. Bra för att läsa ett domslut eller en doktrintext utan att fastna på orden.`
- system_prompt (draft): `Du är ett studieverktyg. Plocka ut de juridiska facktermerna i dokumentet och förklara varje term kort på vanlig, begriplig svenska. Hitta inte på lagrum eller rättsfall. Skriv bara begrepp och förklaringar, inget annat.`

## R-004 — Mock responses for the zone-pipeline tests

Each `zone_pipeline_<slug>.rs` calls `run_zone_pipeline(zone, fixture, mock_response, markers)`. The mock_response is realistic Swedish output containing the zone-specific markers AND no fabricated citation (so SC-002's "citation-free output" is the asserted path). Marker plan:
- identifiera → contains `Rättsfråga` / a numbered issue list; markers e.g. `["Rättsfråga", "1."]`
- strukturera → contains the four IRAC headings; markers `["Rättsfråga", "Gällande rätt", "Subsumtion", "Slutsats"]`
- forklara → contains a term→definition pair; markers e.g. `["Subsumtion", "betyder"]` (a term + an explanation cue)

SC-002 citation-free assertion: the mock output deliberately contains NO `SFS`/`NJA`/`kap.`/`§` token, and the test asserts their absence — exercising the Principle-VIII guard as a property of the produced sidecar.
