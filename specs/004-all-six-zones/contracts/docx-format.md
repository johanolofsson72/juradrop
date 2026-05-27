# Sidecar `.docx` format contract — spec 004

Extends spec 003's `docx-format.md` with per-zone header templates and the Anonymise + Förenkla disclaimer paragraphs.

## Document structure (per ZoneId)

| Paragraph index | Sammanfatta | TillEngelska | TillSvenska | Punktlista | Anonymisera | Förenkla |
|---|---|---|---|---|---|---|
| 0 (bold) | `Sammanfattning av '<filename>'` | `Översättning till engelska av '<filename>'` | `Översättning till svenska av '<filename>'` | `Punktlista över '<filename>'` | `Anonymiserad version av '<filename>'` | `Förenklad version av '<filename>'` |
| 1 (regular) | `Genererad <YYYY-MM-DD HH:MM> av JuraDrop med modellen gemma3:4b.` | (same) | (same) | (same) | (same) | (same) |
| 2 (italic) — conditional | (truncation notice if applicable) | (same) | (same, plus the "Dokumentet är redan på svenska" notice when language detected) | (same) | (same; PLUS the FR-013 disclaimer) | (same; PLUS the FR-014 disclaimer) |
| spacer | (empty paragraph) | (empty) | (empty) | (empty) | (empty) | (empty) |
| 3+ | model body, split on `\n\n` | (same) | (same) | bulleted lines from the model (each `- ` becomes a `<w:p>` with bullet list style) | model body | model body |

## Anonymise disclaimer (FR-013)

Insert this italic paragraph BEFORE the spacer, AFTER any truncation notice:

```
AI-anonymisering är inte hundra procent — granska resultatet innan du delar.
```

## Förenkla disclaimer (FR-014)

```
Förenklad version — granska att inga juridiska poänger gick förlorade.
```

## TillSvenska "already in Swedish" notice (clarification 2026-05-27)

When the model detects the source is already Swedish, insert (italic) BEFORE the body and BEFORE any other notice:

```
(Dokumentet är redan på svenska — endast lätt korrigerad.)
```

## Punktlista body format

The body for Punktlista is a Swedish bulleted list. The model is instructed (R-008 prompt) to output one bullet per line, prefixed with `- `. The writer maps each `- ` line to a Word "List Bullet" styled `<w:p>`. Lines without the prefix are written as plain paragraphs (defensive — the model is good but not perfect).

## File-level metadata (unchanged from spec 003)

- Title: omitted.
- Author: omitted.
- Language: `sv-SE` for all zones EXCEPT TillEngelska, which sets `en-GB`.
- No comments, no tracked changes, no embedded images, no headers/footers.

## Filename (per ZoneId)

| ZoneId | Canonical | Collision-suffixed |
|---|---|---|
| Sammanfatta | `<stem>.sammanfatta.docx` | `<stem>.sammanfatta.<ts>.docx` |
| TillEngelska | `<stem>.tillengelska.docx` | `<stem>.tillengelska.<ts>.docx` |
| TillSvenska | `<stem>.tillsvenska.docx` | `<stem>.tillsvenska.<ts>.docx` |
| Punktlista | `<stem>.punktlista.docx` | `<stem>.punktlista.<ts>.docx` |
| Anonymisera | `<stem>.anonymiserad.docx` | `<stem>.anonymiserad.<ts>.docx` |
| Förenkla | `<stem>.forenkla.docx` | `<stem>.forenkla.<ts>.docx` |

`<ts>` is `YYYY-MM-DD-HHMMSS` in local time per spec 003 FR-006.

## Atomic write + source immutability

Identical to spec 003: write `.tmp` → `fsync` → `rename`. Source `O_RDONLY`. SHA-256 invariant holds across all six zones.
