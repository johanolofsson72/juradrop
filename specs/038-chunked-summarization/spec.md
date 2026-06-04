# Feature Specification: Chunked Processing for Long Documents

**Feature Branch**: `038-chunked-summarization`

**Created**: 2026-06-04

**Status**: Draft

**Input**: User description: "Field bug from beta tester Meja (2026-06-04): dropping a 30- or 100-page document on a transform zone only processes the beginning of the text. The app hard-cuts extracted text at 24,000 characters (~20 pages) before it reaches the model, and the model call sets no explicit context window, so long input can be silently clipped a second time inside the model. Long documents must be split into chunks, each chunk processed per the zone's task, and the results combined per zone semantics — so the whole document is processed, not just the beginning."

## Clarifications

### Session 2026-06-04

- Q: Anonymisera cross-chunk placeholder consistency — same person may get different placeholders in different chunks? → A: Accept per-chunk independence; multi-chunk Anonymisera output carries an honest Swedish disclaimer that placeholder labels can differ between document sections and need review (structured PII moves to deterministic replacement in spec 039).
- Q: Chunked-processing ceiling — size and unit? → A: Ceiling is 12 chunks (~288,000 characters ≈ ~240 pages), expressed in chunks because chunk count is what bounds worst-case wall clock; documents beyond it are processed up to the ceiling with the honest disclaimer.
- Q: Strukturera (IRAC) long-document strategy? → A: Condense-then-structure — per-chunk condensation (reduce) first, then the IRAC structuring runs once on the condensate, preserving whole-document reasoning; the zone's existing disclaimer covers the quality caveat.
- Q: Cancel affordance for multi-minute chunked runs? → A: Out of scope for 038 — the 12-chunk ceiling plus the existing per-chunk timeout bounds worst case; cancellation is a candidate future register row if field feedback demands it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Summarize a long document end to end (Priority: P1)

A law student drops a 100-page court judgment on the Sammanfatta zone. Today only the first ~20 pages influence the summary; the final 80 pages — typically the court's reasoning and conclusion, the parts a law student actually needs — are silently discarded (with a small disclaimer). After this feature, the produced summary reflects the whole document: beginning, middle, and end.

**Why this priority**: This is the reported field bug, on the app's flagship zone. A summary that misses the court's conclusion is worse than no summary — it misleads. Every long-document zone benefits from the same machinery, but Sammanfatta is the proof.

**Independent Test**: Drop a document longer than the single-pass limit (e.g. 100 pages) whose distinctive content is distributed across beginning/middle/end on Sammanfatta; verify the output references content from all three regions and carries no truncation disclaimer.

**Acceptance Scenarios**:

1. **Given** a document longer than the single-pass limit with identifiable facts near the end, **When** the user drops it on Sammanfatta, **Then** the resulting summary includes material from the final part of the document and contains no "texten kortades av" disclaimer.
2. **Given** a document shorter than the single-pass limit, **When** the user drops it on any zone, **Then** behavior is unchanged from today (single model pass, identical output path, no chunking overhead).
3. **Given** a long document, **When** processing succeeds, **Then** the sidecar file appears next to the original and opens automatically, exactly as for short documents.

---

### User Story 2 - Translate / transform a long document in full (Priority: P2)

A student drops a 40-page English-language ruling on Till svenska. The full text must come back translated, in the original order, not just the first fifth.

**Why this priority**: Ordered-transform zones (Till engelska, Till svenska, Förenkla, Anonymisera) lose user content today in the most visible way — the output simply stops partway through the document.

**Independent Test**: Drop a long document with numbered sections on Till svenska; verify the output contains all sections in order.

**Acceptance Scenarios**:

1. **Given** a long document with distinguishable sections from start to finish, **When** dropped on an ordered-transform zone, **Then** the output contains transformed counterparts of all sections in the original order with no gaps at chunk boundaries.
2. **Given** a long document, **When** dropped on Anonymisera, **Then** every part of the document is anonymized (not only the first chunk), and **because chunks are anonymized independently** the multi-chunk output carries an honest Swedish disclaimer that placeholder labels (e.g. "Person A") can differ between document sections and the result must be reviewed. Single-chunk Anonymisera output is unchanged.

---

### User Story 3 - Extract from a long document without losing the tail (Priority: P2)

A student drops a long compilation on Kontakter, Källor, Identifiera or Förklara. Items that appear only late in the document (a phone number on page 70, a case citation on page 90) must appear in the output.

**Why this priority**: Extraction zones silently lie today — the output looks complete but only covers the head of the document. A källförteckning missing half the sources is unusable for academic work.

**Independent Test**: Drop a long document with unique extractable items planted late in the text on an extraction zone; verify those items appear in the output exactly once.

**Acceptance Scenarios**:

1. **Given** a long document with unique extractable items in its final third, **When** dropped on an extraction zone, **Then** those items appear in the output.
2. **Given** an item that occurs in multiple chunks (e.g. the same person's contact details repeated), **When** the per-chunk results are combined, **Then** the item appears once in the final output, not once per chunk.

---

### User Story 4 - Honest progress and honest failure for slow long-document runs (Priority: P3)

Processing a 100-page document means several model passes and can take minutes. The user must be able to tell the app is working — and if a pass fails partway, must get an honest Swedish error, never a silently partial result presented as complete.

**Why this priority**: Principle VIII (honest failure states). Without visible progress, a multi-minute run is indistinguishable from a hang; without all-or-nothing semantics, a mid-run failure produces a plausible-looking but incomplete sidecar file — the exact failure mode this feature exists to kill.

**Independent Test**: Drop a long document and observe per-part progress in the zone; simulate a mid-run model failure and verify a Swedish error state with no sidecar file written.

**Acceptance Scenarios**:

1. **Given** a long document being processed in multiple parts, **When** the user watches the zone, **Then** the zone shows that work is progressing through the parts (e.g. "Bearbetar del 3 av 8") rather than a static processing state for minutes.
2. **Given** a mid-run failure on chunk N of M, **When** processing aborts, **Then** the user sees an existing-style honest Swedish error, no sidecar file is written, and the zone returns to its normal error flow.
3. **Given** a long-document run in progress, **When** the user drops a file on another zone, **Then** the other zone processes independently, as today.

---

### Edge Cases

- Document length exactly at / one character over the single-pass limit — must not produce a degenerate tiny second chunk that the model handles poorly.
- Chunk boundaries must respect text structure: never split mid-word; prefer paragraph breaks, fall back to sentence breaks (Swedish abbreviations like "t.ex.", "bl.a.", "kap." must not be treated as sentence ends), fall back to whitespace.
- A single paragraph longer than a whole chunk (e.g. machine-generated text with no line breaks) must still be split safely.
- Documents above the chunked-processing ceiling (12 chunks ≈ ~240 pages): processed up to the ceiling with the existing-style honest disclaimer naming what was skipped. The ceiling is expressed in chunks because chunk count bounds worst-case wall clock (~30 minutes on the slowest practical tier).
- The combine pass input (concatenated per-chunk results) can itself exceed the single-pass limit — the combine step must handle its own input recursively or bound per-chunk output so this cannot occur.
- A model that loops/repeats on one chunk (small-model failure mode) must not stall the whole run indefinitely — existing per-call timeouts apply per chunk.
- The whole-document-reasoning zone Strukturera (IRAC) cannot be naively chunk-concatenated: the rättsfråga may be stated on page 3 and the conclusion on page 95, and an IRAC produced per chunk is structurally wrong. Resolved strategy: **condense-then-structure** — per-chunk condensation (reduce) first, then the IRAC structuring runs once on the condensate, so the whole document informs one coherent rättsfråga→slutsats chain. The zone's existing review disclaimer covers the condensation quality caveat.
- Empty or whitespace-only chunks after splitting must be skipped, not sent to the model.
- The sidecar consistency check for Anonymisera (PII residue sweep) must run on the full combined output, not per chunk.
- Concurrency: a long run occupies the model for minutes; simultaneous drops on other zones must still behave per the existing concurrency semantics (spec 017).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST process the entire extracted text of a dropped document (up to the documented ceiling), not only its first 24,000 characters.
- **FR-002**: Documents that fit within a single model pass MUST be processed exactly as today: one model call, no chunking, byte-identical output path.
- **FR-003**: Documents exceeding the single-pass limit MUST be split into chunks at text-structure-aware boundaries (paragraph preferred, then sentence, then whitespace; never mid-word), each chunk processed with the zone's task, and the results combined per the zone's combine semantics.
- **FR-004**: Each zone MUST declare its combine semantics: **reduce** (Sammanfatta, Punktlista — per-chunk partial results condensed by a final combine pass into one coherent result honoring the zone's output conventions), **concat** (Till engelska, Till svenska, Förenkla, Anonymisera — per-chunk transforms joined in original order), **aggregate** (Kontakter, Källor, Identifiera, Förklara — per-chunk extractions merged with duplicates removed), **condense-then-structure** (Strukturera — per-chunk condensation first, then the structuring task runs once on the condensate). Generera is exempt (its input is user instructions, not a document).
- **FR-005**: Every model call MUST declare an explicit context-window size sufficient for the prompt framing + chunk + expected response, on all three model tiers, so input is never silently clipped inside the model runtime.
- **FR-006**: The existing truncation disclaimer MUST appear only when content was genuinely not processed (document exceeds the chunked-processing ceiling), and MUST NOT appear for any document fully processed via chunking.
- **FR-007**: The prompt-injection framing (DOKUMENT BÖRJAR/SLUTAR markers + guard, spec 022) MUST wrap every chunk and every combine-pass input that contains document-derived content.
- **FR-008**: During a multi-chunk run, the zone MUST show per-part progress in Swedish (which part of how many) instead of a static processing state.
- **FR-009**: If any chunk or combine pass fails, the run MUST abort with an existing-style honest Swedish error; no sidecar file may be written from partial results.
- **FR-010**: The Anonymisera PII residue sweep (spec 014) MUST run on the final combined output.
- **FR-011**: Chunked processing MUST work on all three model tiers (Snabb/Smart/Stor); chunk sizing MAY differ per tier but the user-visible contract (whole document processed) is identical.
- **FR-012**: Processing MUST remain local-only: chunking introduces no new outbound traffic and no persistence of document content beyond the existing sidecar output (Principle I).
- **FR-013**: A document above the chunked-processing ceiling of **12 chunks (~288,000 characters)** MUST be processed up to the ceiling with the honest disclaimer naming what was skipped (e.g. "endast de första N delarna").
- **FR-014**: Multi-chunk Anonymisera output MUST carry an honest Swedish disclaimer that placeholder labels can differ between document sections (chunks are anonymized independently) and the result must be reviewed; single-chunk output is unchanged.

### Key Entities

- **Chunk**: A contiguous slice of the extracted document text, bounded by structure-aware split points, sized to fit one model pass together with prompt framing and response headroom. Has an index (order) and knows whether it is the only chunk.
- **Chunk plan**: The ordered list of chunks for one document + the zone's combine strategy; determines single-pass vs multi-pass execution and the progress denominator.
- **Combine strategy**: Per-zone declaration (reduce / concat / aggregate / exempt) describing how per-chunk results become the final output.
- **Chunked run**: The execution of a chunk plan — sequential model passes, per-part progress events, all-or-nothing completion semantics.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A 100-page test document with unique sentinel facts planted at the beginning, middle, and end produces a Sammanfatta output containing material from all three regions, with no truncation disclaimer.
- **SC-002**: For an ordered-transform zone, a long document with numbered sections yields output containing 100% of the sections in original order.
- **SC-003**: For extraction zones, sentinel items planted in the final third of a long document appear in the output exactly once.
- **SC-004**: Documents under the single-pass limit show zero behavior change: same number of model calls (one), same output format, no new disclaimer.
- **SC-005**: A mid-run model failure on a long document never produces a sidecar file; the user sees an honest Swedish error within the existing error flow.
- **SC-006**: During a multi-chunk run, the UI displays per-part progress that advances as parts complete (observable within one part-completion of the actual state).
- **SC-007**: All chunked-processing behavior holds on all three model tiers.

## Assumptions

- Chunks are processed **sequentially**, not in parallel — local Ollama serves one generate call at a time per model, and parallel chunk requests would contend rather than speed up (consistent with the existing one-inference-at-a-time reality of the sidecar).
- Per-chunk progress reuses the existing zone-status event channel and processing-state UI surface; no new window or panel is introduced.
- The existing per-call generate timeout (180 s) applies per chunk, bounding a stuck chunk the same way a stuck single-pass run is bounded today.
- The existing 50 MB pre-read file guard (spec 024) remains the outer bound on input size; the chunked-processing ceiling sits far below it.
- Combine-pass quality on small models (a summary of summaries on llama3.2:1b) is inherently weaker than single-pass quality on short documents; the contract is full-document *coverage*, not large-model-grade prose.
- Auto-clear timers, drag-drop mechanics, file-type support, and output-format mirroring are untouched by this feature.
- Cancellation of an in-flight chunked run is **out of scope** (clarified 2026-06-04): no cancel affordance exists today for single-pass runs either; the 12-chunk ceiling plus the existing per-chunk timeout bounds worst-case duration. Candidate future register row if field feedback demands it.
