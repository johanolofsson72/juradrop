# Writer interface contract

## Top-level dispatcher

```rust
// src-tauri/src/zones/extract.rs (or a new writer.rs)
pub fn write_sidecar(plan: &SidecarPlan, extracted: &ExtractedText, body: &str) -> Result<(), ZoneFailure>;
```

Single entry point for sidecar writing. Dispatches to the per-format writer based on `plan.output_format`. Receives the model's output text via `body`; the writer combines it with the extractor's metadata (frontmatter, truncation flag, partial flag) and the zone's identity (header template, disclaimer paragraph).

**Required behaviour:**
- Writes to `plan.output_path` atomically — write `.tmp`, fsync, rename. Inherits spec 003's atomic-write invariant unchanged.
- Returns `Err(ZoneFailure::WriteFailure { detail })` on any I/O failure.
- The output file is opened by the OS default handler after a successful write (existing spec 003 behaviour — `open` crate, unchanged).

## Per-format writers

### DOCX (modified from spec 003)

```rust
// src-tauri/src/zones/docx_write.rs
pub fn write(
    plan: &SidecarPlan,
    extracted: &ExtractedText,
    body: &str,
) -> Result<(), ZoneFailure>;
```

**Layout (top to bottom):**
1. Header paragraph: `ZoneId::header_paragraph_template(plan.zone_id)` with `{name}` substituted by `plan.source_path.file_stem()`.
2. Meta paragraph (spec 003 FR-005a): timestamp + model label.
3. **NEW for spec 005**: if `extracted.was_partial == true`, prepend a Swedish partial-extraction notice paragraph: "Delar av PDF-filen kunde inte läsas — resultatet kan vara ofullständigt."
4. If `extracted.was_truncated == true`, the spec 003 truncation-notice paragraph.
5. Disclaimer paragraph (italic) for `ZoneId::Anonymisera` and `ZoneId::Forenkla` (per spec 004 FR-013/014).
6. Spacer paragraph.
7. Body — each `\n\n`-separated chunk becomes a `<w:p>` paragraph.

Per-paragraph rendering identical to spec 003 (no rich formatting beyond italic for the disclaimer).

### TXT (new)

```rust
// src-tauri/src/zones/txt_write.rs
pub fn write(
    plan: &SidecarPlan,
    extracted: &ExtractedText,
    body: &str,
) -> Result<(), ZoneFailure>;
```

**Layout:**
```
# <basename> — <zone_title> — <YYYY-MM-DD>

(blank line)
[optional] # Delar av PDF-filen kunde inte läsas — resultatet kan vara ofullständigt.   (NB: PDF→DOCX, so this is never reached on TXT; included for symmetry only)
[optional] # Texten kortades av — modellen såg bara början av dokumentet.   (truncation notice — same shape as docx)

<model body>

[only on Anonymisera + Forenkla]
# <disclaimer text>
```

**Concrete example (Sammanfatta zone, no truncation, no disclaimer):**
```
# mydoc.txt — Sammanfatta — 2026-05-27

Här är en sammanfattning av dokumentets centrala...
[model body continues]
```

**Rules:**
- File written in UTF-8, no BOM.
- Line endings: LF (`\n`) for portability. Even on Windows-1252 input, output is UTF-8 LF.
- No trailing newline at EOF (idiomatic Unix text file).
- Header comment uses `# ` prefix (single hash + space) so the file remains readable when piped through `cat`, `less`, `tail`, etc.

### MD (new)

```rust
// src-tauri/src/zones/md_write.rs
pub fn write(
    plan: &SidecarPlan,
    extracted: &ExtractedText,
    body: &str,
) -> Result<(), ZoneFailure>;
```

**Layout:**
```
[optional] <captured frontmatter block verbatim>

# <basename> — <zone_title>
> <YYYY-MM-DD>

[optional truncation/partial notices as Markdown blockquotes]

<model body>

[only on Anonymisera + Forenkla]
> **OBS!** <disclaimer text>
```

**Concrete example (Förenkla zone, with YAML frontmatter, no truncation):**
```markdown
---
title: Min studieanteckning
tags: [juridik, exam]
date: 2026-05-15
---

# anteckning.md — Förenkla
> 2026-05-27

Här är texten i klarspråk...
[model body]

> **OBS!** Förenklad version — granska att inga juridiska poänger gick förlorade.
```

**Rules:**
- Captured frontmatter (if any) is prepended verbatim INCLUDING both `---`/`+++` fences and the trailing newline.
- File written in UTF-8, no BOM.
- LF line endings.
- One blank line between every block.
- Disclaimer formatted as `> **OBS!** <text>` (Markdown blockquote + strong emphasis).
- Truncation notice formatted as `> *<text>*` (blockquote + italic).
- Partial-PDF notice does NOT appear in MD output (because PDF input maps to DOCX output, not MD).

## SidecarPlan resolution

```rust
// src-tauri/src/zones/sidecar_path.rs
pub fn resolve_target(source: &Path, zone_id: ZoneId, output_format: OutputFormat) -> PathBuf;
```

Returns `<parent_dir>/<stem>.<zone_id.suffix()>.<output_format.as_str()>`.

If a file already exists at that path, append the spec 003 FR-006 collision timestamp: `<stem>.<suffix>.YYYY-MM-DD-HHMMSS.<ext>`. The rule is unchanged from spec 003 — only the extension varies.

**Examples:**

| Source | Zone | OutputFormat | Resolved sidecar |
|---|---|---|---|
| `case.docx` | Sammanfatta | Docx | `case.sammanfatta.docx` |
| `judgment.pdf` | TillEngelska | Docx | `judgment.tillengelska.docx` |
| `notes.txt` | Anonymisera | Txt | `notes.anonymiserad.txt` |
| `brief.md` | Förenkla | Md | `brief.forenkla.md` |
| `notes.txt` (collision) | Anonymisera | Txt | `notes.anonymiserad.2026-05-27-143022.txt` |
