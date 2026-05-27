# Feature Specification: All six drop zones (2×3 grid)

**Feature Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`)

**Created**: 2026-05-27

**Status**: Draft

**Input**: User description: Extend spec 003's single Sammanfatta zone to a 2×3 grid of six themed drop zones (Sammanfatta, TillEngelska, TillSvenska, Punktlista, Anonymisera, Förenkla). Each zone reuses the spec 003 state machine, dispatch pipeline, atomic-write sidecar, FR-005a header, error mapping, cancel affordance, and disabled gate — only the per-zone identity (slug, title, system prompt, sidecar suffix, event channel) changes. Per-zone state is independent (each zone has its own single-flight slot + cancel token + event stream); the OllamaClient is shared and Ollama's request queue serialises actual inference. Privacy invariant unchanged (no document content leaves the Mac; every prompt wrapped in `Redacted<String>` end-to-end).

## Clarifications

### Session 2026-05-27 (auto-picked recommendations per `.claude/settings.json`)

- Q: How does an OS-level drag-drop (Tauri's `WindowEvent::DragDrop` is window-scoped, not zone-scoped) map to which of the six zones receives the file? → A: **`elementFromPoint` in the WebView.** The Rust handler emits a single `juradrop://file-dropped` event carrying the OS file path(s) + the drop position (converted from physical to CSS pixels via `window.devicePixelRatio`). The JS layer calls `document.elementFromPoint(x, y)`, walks up to the nearest `[data-zone-id]` ancestor, reads the ZoneId, and invokes a Rust command `dispatch_to_zone(zone_id, paths)`. Privacy stays intact (the paths flow via the Rust event payload — the WebView never reads the file or its bytes; the zone-id is the only thing flowing back across the boundary).
- Q: If the user drops a Swedish `.docx` on TillSvenska (already in the target language) — passthrough, rewrite, or refuse? → A: **Model decides, with a Swedish notice prepended.** The system prompt instructs `gemma3:4b` to detect the source language; if already Swedish, output a lightly-cleaned version (typos, formatting) and prepend the body with the Swedish notice `(Dokumentet är redan på svenska — endast lätt korrigerad.)`. Same shape as the FR-019 truncation notice (between the FR-009 header and the model body). No hard error; the user just sees the original-ish content + the notice.
- Q: Anonymisera placeholder consistency (the same "Anna Andersson" → same "Person A" throughout) — prompt instruction only, or post-process? → A: **Prompt instruction only at v1.** The system prompt explicitly asks the model to maintain a stable map of source-name → placeholder across the document. Post-processing (regex replacement after model output) is deferred to spec 010 (settings panel) where a "strict anonymisation mode" toggle becomes meaningful. The FR-013 disclaimer ("AI-anonymisering är inte hundra procent — granska resultatet innan du delar.") sets the honest expectation at v1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Translate a Swedish legal text to English (Priority: P1)

A Swedish law student needs to send a Swedish ruling to a foreign-language reviewer. They drag the `.docx` onto the "TillEngelska" zone. Within a minute a sidecar `<stem>.tillengelska.docx` appears next to the original, opens automatically, and contains a faithful English translation that preserves the legal structure (parties, holding, reasoning). The original Swedish `.docx` is byte-identical to before the drop.

**Why this priority**: Translation is the second-most-requested utility after summarization (spec 003). For students collaborating with non-Swedish-speaking peers or professors, this is the load-bearing feature.

**Independent Test**: With the AI in `Klar`, drop a Swedish `.docx` onto the TillEngelska zone. Confirm the sidecar appears, the file is English, the file opens cleanly in Word, and the source is byte-identical (SHA-256 match).

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and a Swedish-language `.docx` sits on disk, **When** the user drops it on TillEngelska, **Then** the zone enters Processing, the dispatch runs the per-zone English-translation prompt against `gemma3:4b`, and a sidecar `<stem>.tillengelska.docx` is written and opened within 60 s.
2. **Given** the translation completed, **When** the user inspects the sidecar, **Then** the content is English prose preserving the source's paragraph structure, includes the FR-005a Swedish header ("Sammanfattning av '<filename>'" is REPLACED in this zone with "Översättning till engelska av '<filename>'"), and the original is unmodified.
3. **Given** a TillEngelska job is in flight, **When** the user drops a *different* `.docx` on a *different* zone (e.g. Sammanfatta), **Then** that second job starts independently and processes in parallel from the UI's POV (Ollama serialises the actual inference behind the scenes — both zones show Processing simultaneously, success/error arrives on whichever finishes first).

---

### User Story 2 — Bulleted summary for a study group (Priority: P1)

The student wants a quick bullet-list view of a 12-page ruling for a study group. They drop the `.docx` on Punktlista. Within a minute a sidecar `<stem>.punktlista.docx` appears with the document's key points as a clean Swedish bulleted list (one fact per bullet, no narrative paragraphs).

**Why this priority**: Bullet summaries are the most-used study format; they're how Swedish law students actually consume material before exams.

**Independent Test**: Drop a `.docx` on Punktlista. Confirm the sidecar contains a `<w:p>` per bullet (Word "List Bullet" style or equivalent), every paragraph reads as one fact/point, the bullet count is reasonable (5–20 for a 5-page input), and the original is byte-identical.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and a `.docx` is on disk, **When** the user drops it on Punktlista, **Then** the sidecar `<stem>.punktlista.docx` contains a Swedish bullet list (visually styled as bullets in Word) reflecting the document's key points.
2. **Given** a Punktlista job is processing, **When** the user clicks Avbryt on that zone, **Then** the cancellation behaves identically to spec 003 (no sidecar written, source byte-identical, "Sammanfattning avbruten" flash — copy reused from spec 003 since the user-visible cancel affordance is the same regardless of zone).

---

### User Story 3 — Anonymise a ruling before sharing (Priority: P1)

The student needs to share a ruling in a study group chat without leaking the parties' names. They drop the `.docx` on Anonymisera. Within a minute a sidecar `<stem>.anonymiserad.docx` appears in which every personal name, address, personnummer, and organisation has been replaced with a neutral placeholder ("Person A", "Företag X", "Adress 1"); the legal narrative is otherwise preserved word-for-word.

**Why this priority**: Anonymisation is the privacy use case for shared study work. It's also the closest spec 004 zone to the project's privacy mission and the one with the highest cost-of-mistake (a missed name in the output is a privacy regression).

**Independent Test**: Drop a `.docx` containing known personal names ("Anna Andersson", a personnummer like "19890214-1234") onto Anonymisera. Confirm the sidecar contains "Person A" (or similar) where the names were, retains the surrounding sentence structure, and does NOT contain any of the original identifiers verbatim.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and a `.docx` with personal names on disk, **When** the user drops it on Anonymisera, **Then** the sidecar replaces personal names with neutral placeholders and preserves the surrounding sentences (replaces tokens, not paragraphs).
2. **Given** the anonymisation completed, **When** the user reads the sidecar, **Then** no original personal names, personnummer-shaped strings, or addresses appear verbatim; placeholder tokens are consistent within a document (the same "Anna Andersson" is the same "Person A" throughout, not "Person A" then "Person C"). Per the 2026-05-27 clarification: consistency is achieved via system-prompt instruction at v1 — no post-process regex pass. The FR-013 disclaimer covers the residual risk; spec 010 may add a "strict mode" toggle.

---

### User Story 4 — Plain-Swedish rewrite for a layperson (Priority: P2)

The student needs to explain a ruling to a non-legal friend. They drop the `.docx` on Förenkla. Within a minute a sidecar `<stem>.forenkla.docx` appears that preserves every legal point but uses shorter sentences and explains Swedish legal jargon parenthetically ("preskription (rätten att kräva har gått ut)").

**Why this priority**: Plain-Swedish rewrites (klarspråk) are a documented Swedish public-administration norm and a clear secondary use case for students explaining their work to family/friends. P2 because the other three rewrites (translation, bullets, anonymise) are more frequently used.

**Independent Test**: Drop a `.docx` containing legal jargon (e.g. "preskription", "vårdslöshet i trafik", "uppsåt") onto Förenkla. Confirm the sidecar contains the same legal points but with shorter sentences and parenthetical explanations of the jargon terms.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and a `.docx` with legal jargon on disk, **When** the user drops it on Förenkla, **Then** the sidecar reads as plain Swedish with parenthetical explanations of Swedish legal terms.
2. **Given** the plain-Swedish rewrite completed, **When** the user compares it to the source, **Then** no legal point is dropped; explanations are added, not substitutions of the legal content.

---

### User Story 5 — Translate a foreign-language `.docx` to Swedish (Priority: P2)

The student receives an English `.docx` (a translated foreign ruling, or course material in English) and wants it in Swedish. They drop it on TillSvenska. Within a minute a sidecar `<stem>.tillsvenska.docx` appears with the content in Swedish.

**Why this priority**: Mirrors US1 (TillEngelska) in the reverse direction. P2 because Swedish-to-English is the more common student direction (sending out, vs receiving in). Both translation zones share most of the implementation.

**Independent Test**: Drop a `.docx` written in English onto TillSvenska. Confirm the sidecar is in Swedish, preserves the document structure, and the original is byte-identical.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and an English `.docx` is on disk, **When** the user drops it on TillSvenska, **Then** the sidecar `<stem>.tillsvenska.docx` is written in Swedish.
2. **Given** the user drops a Swedish `.docx` on TillSvenska by mistake, **When** the dispatch runs, **Then** the model detects the language and prepends the body with the Swedish notice `(Dokumentet är redan på svenska — endast lätt korrigerad.)` (clarification 2026-05-27). Graceful degradation, not a hard error.

---

### User Story 6 — Multiple zones processing in parallel (Priority: P2)

The student drops a `.docx` on Sammanfatta to get a summary, then immediately drops the same `.docx` on Anonymisera to also get an anonymised version. Both zones show Processing simultaneously. The user can see two distinct progress states. Each zone's success arrives independently and produces its own sidecar.

**Why this priority**: Demonstrates the per-zone independence design. P2 because the single-flight constraint is per-zone, not per-app — this exercises the parallel-zones contract that's the core architectural difference from spec 003.

**Independent Test**: Drop the same `.docx` on Sammanfatta and Anonymisera in quick succession. Verify both zones enter Processing, neither blocks the other, both sidecars are produced (`<stem>.sammanfatta.docx` AND `<stem>.anonymiserad.docx`).

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and a `.docx` is on disk, **When** the user drops it on Sammanfatta and (within 1 s) on Anonymisera, **Then** both zones show Processing simultaneously; the user can see two spinners at once.
2. **Given** both zones are processing, **When** the first completes, **Then** that zone shows Success and writes its sidecar while the other continues in Processing — no cross-zone interference.
3. **Given** one zone is processing, **When** the user drops a *second* `.docx` on the same zone (different source path), **Then** the per-zone single-flight rule rejects the second drop with the same "Vänta tills föregående dokument är klart" Swedish copy from spec 003.

---

### Edge Cases

- **Same source, different zone**: dropping the same `.docx` on Sammanfatta and TillEngelska produces TWO sidecars (`<stem>.sammanfatta.docx` AND `<stem>.tillengelska.docx`) side by side — they don't collide because the suffixes differ.
- **Repeated drop on the same zone, same source**: triggers the spec 003 FR-006 collision rule — the second drop produces `<stem>.<zone-slug>.YYYY-MM-DD-HHMMSS.docx`, preserving the first sidecar.
- **Disabled-while-processing**: a zone is in Processing when the sidecar status flips to non-Ready (sidecar crashes mid-job). The in-flight job continues (the model call is already issued); when the model call fails because the sidecar is gone, the zone surfaces `ZoneFailure::ModelError`. Other zones that were Idle become Disabled immediately.
- **Anonymisera mistakenly leaves a name**: the spec is honest — `gemma3:4b` is a 4B-parameter model and CAN miss names, especially uncommon Swedish ones. The header on the anonymised sidecar carries a Swedish disclaimer ("AI-anonymisering är inte hundra procent — granska resultatet innan du delar.") so users don't take the output as legally redacted.
- **Förenkla over-simplifies and loses a legal point**: the system prompt is constrained to "preserve every legal point". Spec 010 (settings panel) may add a "tighter/looser simplification" slider; until then, the rewritten file is best-effort and the disclaimer header notes that.
- **Multi-drop on the grid** (drag-and-drop the same file onto a zone seam): the OS routes the drop to whichever zone the cursor is over at release. No "drop on two zones at once" — the WindowEvent::DragDrop carries a single target window/area, not a multi-zone fan-out.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The main window MUST display a 2-row × 3-column grid of six drop zones. The six zones in left-to-right, top-to-bottom reading order are: row 1 = (Sammanfatta, TillEngelska, TillSvenska); row 2 = (Punktlista, Anonymisera, Förenkla).
- **FR-002**: On viewports narrower than the 6-zone grid's minimum comfortable width, the grid MUST collapse to 3 rows × 2 columns; on extremely narrow viewports (rare for a desktop app), to 6 rows × 1 column. The reading order is preserved across breakpoints.
- **FR-003**: Each zone MUST have a unique `ZoneId` — `sammanfatta`, `tillengelska`, `tillsvenska`, `punktlista`, `anonymisera`, `forenkla` — used as the slug across the event channel, sidecar filename suffix, and prompt module file.
- **FR-004**: Each zone MUST display its Swedish title verbatim. Titles: "Sammanfatta", "Till engelska", "Till svenska", "Punktlista", "Anonymisera", "Förenkla". (Spec 003 used the one-word "Sammanfatta"; the two-word "Till engelska" / "Till svenska" matches Swedish orthography for prepositional phrases.)
- **FR-005**: Each zone MUST display a one-line Swedish hint customised to its action (pulled into scope from the original spec 010 deferral, 2026-05-27). The per-zone hints are:
  - Sammanfatta: `Släpp ett .docx för sammanfattning`
  - TillEngelska: `Släpp ett .docx för engelsk översättning`
  - TillSvenska: `Släpp ett .docx för svensk översättning`
  - Punktlista: `Släpp ett .docx för punktlista`
  - Anonymisera: `Släpp ett .docx för anonymisering`
  - Förenkla: `Släpp ett .docx för klarspråk`
  Each hint follows the `Släpp ett .docx för <action-noun>` pattern; the action noun matches the zone's purpose. All hints MUST satisfy the spec 003 Swedish-copy invariants (≤ 80 chars, no `Error:` prefix, non-empty).
- **FR-006**: Each zone MUST own its system prompt as a `pub const <SLUG>_SYSTEM_PROMPT: &str = "..."` constant in `src-tauri/src/prompts/<slug>.rs`. The prompt is in Swedish (or English for TillEngelska's instruction to the model — the *target* output is English) and includes the same "no greeting, no meta-commentary" guardrails from spec 003.
- **FR-007**: Each zone MUST produce a sidecar `.docx` with a per-zone filename suffix. The suffixes are: `sammanfatta`, `tillengelska`, `tillsvenska`, `punktlista`, `anonymiserad` (note: past-participle adjective, not the verb stem), `forenkla`. Canonical name: `<source-stem>.<suffix>.docx`.
- **FR-008**: Each zone MUST reuse the spec 003 atomic-write + FR-006 collision rules unchanged.
- **FR-009**: Each zone MUST reuse the spec 003 FR-005a header structure but with a per-zone first paragraph. Specifically: paragraph 0 is `Sammanfattning av '<filename>'` (Sammanfatta), `Översättning till engelska av '<filename>'` (TillEngelska), `Översättning till svenska av '<filename>'` (TillSvenska), `Punktlista över '<filename>'` (Punktlista), `Anonymiserad version av '<filename>'` (Anonymisera), `Förenklad version av '<filename>'` (Förenkla). Paragraph 1 (timestamp + model) is unchanged from spec 003.
- **FR-010**: Each zone MUST emit its state-machine snapshots on a per-zone event channel `juradrop://zone/<slug>`. The payload shape (`ZoneSnapshot`) is unchanged from spec 003; only the channel name is per-zone.
- **FR-010a**: The OS-level drag-drop MUST be routed to the correct zone via the `elementFromPoint` pattern (clarification 2026-05-27). The Rust `WindowEvent::DragDrop` handler emits `juradrop://file-dropped` with `{ paths: PathBuf[], position: { x: f64, y: f64 } }` in **CSS pixels** (Rust converts from physical via the window's device pixel ratio). The WebView reads the event, calls `document.elementFromPoint(x, y)`, walks up to the nearest `[data-zone-id]` ancestor, and invokes `dispatch_to_zone(zone_id, paths)`. A drop that doesn't land on any zone (e.g. on the WelcomeCard area) is silently ignored — no error snapshot. Privacy invariant: the WebView only sees the path strings via the Rust event payload, never via the HTML5 drag-drop API.
- **FR-011**: Each zone MUST have its own single-flight slot. A drop on zone A while zone A is processing is rejected with the "Vänta tills föregående dokument är klart" Swedish copy (FR-015 from spec 003 reused). A drop on zone B while zone A is processing is accepted independently.
- **FR-012**: All six zones MUST be disabled simultaneously whenever `UserVisibleStatus != Klar`. The disabled state mirrors spec 003's FR-012 — same Swedish hint borrowed from WelcomeCard, same visual treatment.
- **FR-013**: The Anonymisera sidecar MUST include a Swedish disclaimer paragraph at the top of the body (between the FR-009 header and the model output): "AI-anonymisering är inte hundra procent — granska resultatet innan du delar.". The disclaimer is part of the .docx, not the UI.
- **FR-014**: The Förenkla sidecar MUST include a Swedish disclaimer paragraph at the top of the body: "Förenklad version — granska att inga juridiska poänger gick förlorade.". Same placement as FR-013.
- **FR-015**: The `cancel_summary` tauri::command (spec 003 T020) MUST be extended to accept a `zone_id` parameter so cancellation targets the right zone's in-flight job. The new signature: `cancel_summary(state, zone_id: String, job_id: String)`.
- **FR-016**: Every existing spec 003 invariant — privacy (Principle I), source immutability (FR-024), Swedish copy invariants (FR-021), atomic write (FR-022), aria-live announcer (FR-022) — MUST hold for every one of the six zones.
- **FR-017**: The six zones MUST share a single shared cross-language Swedish-string fixture extending `src-tauri/tests/fixtures/zone-error-strings.json` if any new variants are introduced. Spec 004 does NOT introduce new `ZoneFailure` variants — all nine spec 003 errors apply equally to all six zones.
- **FR-018**: Per-zone unit tests MUST assert each zone's `ZoneId`, sidecar suffix, system prompt presence, and per-zone first-header-paragraph against a parameterised table. No copy-pasted six-times test suites.

### Key Entities

- **ZoneId (enum)**: a discriminator with six variants (`Sammanfatta`, `TillEngelska`, `TillSvenska`, `Punktlista`, `Anonymisera`, `Forenkla`). Each variant carries (or has associated functions for) `slug`, `title`, `sidecar_suffix`, `header_paragraph_template`, `system_prompt`, `extra_body_disclaimer` (Option, set only for Anonymisera + Förenkla).
- **DropZone (per-instance)**: replaces the spec 003 `SammanfattaZone` with a generic `DropZone` parameterised by `ZoneId`. Holds its own single-flight slot, its own job, its own emit channel.
- **ZoneSnapshot wire shape**: unchanged from spec 003 plus an added `zone_id: ZoneId` field so the WebView can route the snapshot to the right component.
- **All other spec 003 entities** (DropJob, SummaryDoc, ExtractedText, ZoneFailure, etc.) are reused unchanged.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From any of the six zones with `gemma3:4b` warm in memory, a 5-page `.docx` produces its zone-specific sidecar within 60 s wall-clock — the same SC-001 budget from spec 003, applied per zone.
- **SC-002**: Dropping the same `.docx` on two different zones in quick succession (e.g. Sammanfatta + Anonymisera) produces both sidecars without either zone blocking the other in the UI. The user observes both zones in Processing simultaneously.
- **SC-003**: For every zone, the source `.docx` is byte-identical (SHA-256 match) before and after every drop — success, failure, or cancel. The FR-024 invariant from spec 003 holds for all six zones.
- **SC-004**: For each zone, the sidecar suffix matches its `ZoneId` exactly: `sammanfatta` → `.sammanfatta.docx`, `tillengelska` → `.tillengelska.docx`, etc. Six tests (or one parameterised over the six variants) enforce this.
- **SC-005**: The 2×3 grid layout is visible on a window ≥ 920 px wide; collapses to 3×2 below that breakpoint and 6×1 below ~520 px. No zone is clipped or hidden at any width above 480 px.
- **SC-006**: Cancelling a job on zone A does NOT cancel the in-flight job on zone B. The per-zone cancel token is scoped strictly to its zone.
- **SC-007**: All six zones honour the spec 003 SC-007 accessibility contract — each has its own `aria-label`, `aria-disabled`, `role="status"` live region with `aria-live="polite"` + `aria-atomic="true"`.

## Assumptions

- **Same model for all zones**: `gemma3:4b` per spec 002. Translation quality between Swedish↔English is acceptable for student-grade output at 4B parameters; spec 010 may add a "smarter/larger model" toggle, but spec 004 ships with the single shared model.
- **No per-zone disk-space pre-check**: each dispatch reuses the spec 002 disk-space gate at sidecar-write time. If two zones both fill the disk, one wins and the other surfaces `ZoneFailure::SaveError` cleanly.
- **HTML drag-and-drop still NOT used**: the Tauri `WindowEvent::DragDrop` handler from spec 003 is extended to route the drop to the right zone based on the drop coordinates (`position: PhysicalPosition<f64>`). The OS gives us a single drop event with a position; we map position to zone.
- **Per-zone components share a single React file with prop-driven differentiation**: `<DropZone zoneId="tillengelska" />` is the pattern, not six near-identical `.tsx` files.
- **Bulk-drop across multiple zones simultaneously**: not in scope. The user can drag once per zone; sequential drops in quick succession exercise the per-zone-parallel design, but a single drop event lands on a single zone (FR-001 layout determines which).
- **Per-zone error variants**: none added in spec 004. The nine spec 003 `ZoneFailure` variants cover every per-zone failure case. If `gemma3:4b` produces an empty or malformed translation, the existing `EmptyText`-after-extraction logic surfaces — but in spec 004's context "empty" applies to the MODEL OUTPUT, not the extraction. The dispatch already maps an empty model response to `ZoneFailure::ModelError` (spec 003 dispatch returns `EmptyResponse` from `OllamaClient::generate`, which maps to `ModelError`). No new error is needed.
- **Spec.allium reused**: spec 004's `spec.allium` extends spec 003's entities (DropZone, DropJob, etc.) by parameterising over `ZoneId`. The state machine, transitions, and invariants stay unchanged — only the cardinality bumps from 1 to 6.
