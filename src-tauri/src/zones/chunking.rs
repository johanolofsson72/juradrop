// Spec 038 — structure-aware chunking for long documents.
//
// Pure, std-only module: no I/O, no async, no Tauri. The dispatch pipeline
// (sammanfatta.rs) builds a `ChunkPlan` from the extracted text and runs one
// model pass per chunk; this module owns the split, the user-facing 12-chunk
// cap, and the deterministic (non-model) combine strategies.
//
// Boundary cascade per contracts/chunking.md: paragraph ("\n\n") preferred,
// then sentence (with a Swedish-abbreviation guard so "t.ex. " never ends a
// sentence), then whitespace, then a UTF-8-safe char cut as the last resort
// for pathological whitespace-free runs. Chunks are contiguous slices of the
// input, so joining them reproduces the processed prefix exactly.

use super::zone_id::ZoneId;

/// Per-chunk size target in UTF-8 characters. Identical to the pre-038
/// single-pass limit (spec 003 FR-019) — the proven ~6,000-token sweet spot
/// for the smallest tier — so a single-chunk plan is byte-identical to the
/// old behavior.
pub const CHUNK_CHAR_TARGET: usize = 24_000;

/// The user-facing cap (clarified 2026-06-04): at most 12 chunks per run,
/// bounding worst-case wall clock at ~30 minutes on the slowest tier.
/// Chunking OWNS this cap (analyze F1) — boundary-aware chunks average
/// below `CHUNK_CHAR_TARGET`, so a capped extraction can still yield more
/// than 12 raw slices; the first 12 are kept and `was_capped` is set.
pub const MAX_CHUNKS: usize = 12;

/// How a zone's per-chunk results become the final output (spec FR-004).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CombineStrategy {
    /// Per-chunk partials condensed by a final model combine pass
    /// (Sammanfatta, Punktlista).
    Reduce,
    /// Deterministic in-order join (TillEngelska, TillSvenska, Forenkla,
    /// Anonymisera).
    Concat,
    /// Deterministic structural merge with exact-trim dedup (Kontakter,
    /// Kallor, Identifiera, Forklara).
    Aggregate,
    /// Per-chunk condensation passes, then the zone task runs once over the
    /// joined condensate (Strukturera/IRAC — whole-document reasoning).
    CondenseThenStructure,
    /// Never chunked — the input is user instructions, not a document
    /// (Generera).
    Exempt,
}

impl ZoneId {
    /// Spec 038 FR-004 — exhaustive: a future 13th zone fails to compile
    /// until it declares its combine semantics.
    pub fn combine_strategy(self) -> CombineStrategy {
        match self {
            ZoneId::Sammanfatta | ZoneId::Punktlista => CombineStrategy::Reduce,
            ZoneId::TillEngelska | ZoneId::TillSvenska | ZoneId::Forenkla | ZoneId::Anonymisera => {
                CombineStrategy::Concat
            }
            ZoneId::Kontakter | ZoneId::Kallor | ZoneId::Identifiera | ZoneId::Forklara => {
                CombineStrategy::Aggregate
            }
            ZoneId::Strukturera => CombineStrategy::CondenseThenStructure,
            ZoneId::Generera => CombineStrategy::Exempt,
        }
    }
}

/// The ordered chunk list for one document, fixed before processing starts.
#[derive(Debug)]
pub struct ChunkPlan {
    /// 1..=MAX_CHUNKS contiguous slices in document order, each at most
    /// `CHUNK_CHAR_TARGET` chars and never whitespace-only.
    pub chunks: Vec<String>,
    /// True iff a tail beyond chunk `MAX_CHUNKS` was dropped. Drives the
    /// truncation disclaimer together with extraction's `was_truncated`
    /// (writer flag = `was_truncated || was_capped`, analyze F1).
    pub was_capped: bool,
}

impl ChunkPlan {
    pub fn is_single_pass(&self) -> bool {
        self.chunks.len() == 1
    }
}

/// Swedish abbreviations whose trailing dot must not end a sentence.
/// Matched against the whitespace-delimited token ending at the candidate
/// dot (lowercased). Single-letter initials ("J.") are guarded separately.
const SWEDISH_ABBREVIATIONS: [&str; 15] = [
    "t.ex.", "bl.a.", "m.m.", "dvs.", "osv.", "kap.", "s.k.", "p.g.a.", "m.fl.", "jfr.", "prop.",
    "bet.", "st.", "nr.", "s.",
];

/// Split `text` (already blank-line-collapsed by extraction) into a plan.
/// Chunks are contiguous slices: joining them in order reproduces the
/// processed prefix of `text` exactly (the whole text when `was_capped`
/// is false).
pub fn split_into_chunks(text: &str) -> ChunkPlan {
    // Fast path: fits in one pass — identity chunk, today's behavior.
    if char_count_at_most(text, CHUNK_CHAR_TARGET) {
        return ChunkPlan {
            chunks: vec![text.to_string()],
            was_capped: false,
        };
    }

    let mut chunks: Vec<String> = Vec::new();
    let mut start = 0usize; // byte offset into `text`

    while start < text.len() && chunks.len() < MAX_CHUNKS {
        let remaining = &text[start..];
        if char_count_at_most(remaining, CHUNK_CHAR_TARGET) {
            push_non_blank(&mut chunks, remaining);
            start = text.len();
            break;
        }
        let cut = find_cut(remaining);
        push_non_blank(&mut chunks, &remaining[..cut]);
        start += cut;
    }

    ChunkPlan {
        was_capped: start < text.len(),
        chunks,
    }
}

/// Deterministic in-order join for `Concat` zones.
pub fn merge_concat(parts: &[String]) -> String {
    parts.join("\n\n")
}

/// Deterministic structural merge for `Aggregate` zones, per
/// contracts/chunking.md §1. Exact-trim dedup only — near-duplicates
/// (differently formatted phone numbers etc.) are out of scope.
pub fn merge_aggregate(zone: ZoneId, parts: &[String]) -> String {
    match zone {
        ZoneId::Kontakter => merge_kontakter(parts),
        ZoneId::Kallor | ZoneId::Identifiera => merge_numbered(parts),
        ZoneId::Forklara => merge_term_lines(parts),
        // Defensive: non-aggregate zones fall back to plain concat. The
        // dispatcher never routes them here (combine_strategy() match).
        _ => merge_concat(parts),
    }
}

// --- internals --------------------------------------------------------

/// True iff `s` has at most `limit` chars — without counting all of `s`
/// (a 288k-char count per loop iteration would be quadratic).
fn char_count_at_most(s: &str, limit: usize) -> bool {
    s.chars().nth(limit).is_none()
}

/// Byte offset of the char with index `n_chars` (i.e. the exclusive end of
/// an `n_chars`-char prefix). `s` is known to be longer than `n_chars`.
fn byte_at_char(s: &str, n_chars: usize) -> usize {
    s.char_indices()
        .nth(n_chars)
        .map(|(b, _)| b)
        .unwrap_or(s.len())
}

fn push_non_blank(chunks: &mut Vec<String>, slice: &str) {
    // Defensive: extraction rejects whitespace-only documents and collapses
    // blank-line runs, so a blank slice cannot occur in practice; skipping
    // (rather than panicking) keeps the pipeline honest if it ever does.
    if !slice.trim().is_empty() {
        chunks.push(slice.to_string());
    }
}

/// Find the cut (byte offset, 0 < cut <= the TARGET-char boundary) for the
/// next chunk of `s`, which is known to exceed `CHUNK_CHAR_TARGET` chars.
/// Cascade: paragraph → sentence → whitespace → char boundary. A candidate
/// that would produce a whitespace-only chunk falls through to the next
/// strategy.
fn find_cut(s: &str) -> usize {
    let limit_byte = byte_at_char(s, CHUNK_CHAR_TARGET);
    let window = &s[..limit_byte];

    // 1. Paragraph: cut after the last "\n\n" in the window (the separator
    //    stays with the preceding chunk, so joins reproduce the input).
    if let Some(pos) = window.rfind("\n\n") {
        let cut = pos + 2;
        if !window[..cut].trim().is_empty() {
            return cut;
        }
    }

    // 2. Sentence: cut after the last ".", "!" or "?" + whitespace, with
    //    the Swedish-abbreviation + single-initial guard for ".".
    if let Some(cut) = last_sentence_cut(window) {
        if !window[..cut].trim().is_empty() {
            return cut;
        }
    }

    // 3. Whitespace: cut after the last whitespace char in the window.
    if let Some((pos, ch)) = window.char_indices().rev().find(|(_, c)| c.is_whitespace()) {
        let cut = pos + ch.len_utf8();
        if !window[..cut].trim().is_empty() {
            return cut;
        }
    }

    // 4. Last resort: a clean char-boundary cut at the limit (pathological
    //    whitespace-free run — mid-"word" by necessity, never mid-char).
    limit_byte
}

/// Byte offset just past the whitespace following the last genuine sentence
/// terminator in `window`, or None.
fn last_sentence_cut(window: &str) -> Option<usize> {
    let mut best: Option<usize> = None;
    let mut iter = window.char_indices().peekable();
    while let Some((i, ch)) = iter.next() {
        if !matches!(ch, '.' | '!' | '?') {
            continue;
        }
        let Some(&(next_i, next_ch)) = iter.peek() else {
            break; // terminator is the window's last char — no whitespace after
        };
        if !next_ch.is_whitespace() {
            continue;
        }
        if ch == '.' && dot_ends_abbreviation(window, i) {
            continue;
        }
        best = Some(next_i + next_ch.len_utf8());
    }
    best
}

/// Does the dot at byte `dot_idx` terminate a Swedish abbreviation or a
/// single-letter initial ("J. Olofsson")?
fn dot_ends_abbreviation(window: &str, dot_idx: usize) -> bool {
    let before = &window[..dot_idx];
    let token_start = before
        .char_indices()
        .rev()
        .find(|(_, c)| c.is_whitespace())
        .map(|(i, c)| i + c.len_utf8())
        .unwrap_or(0);
    // Token including the candidate dot itself.
    let token = &window[token_start..dot_idx + 1];
    let lower = token.to_lowercase();
    if SWEDISH_ABBREVIATIONS.contains(&lower.as_str()) {
        return true;
    }
    // Single-letter initial: exactly one alphabetic char + the dot.
    let mut chars = token.chars();
    matches!((chars.next(), chars.next(), chars.next()), (Some(c), Some('.'), None) if c.is_alphabetic())
}

/// Spec 040 — the reserved catch-all heading for unattributable contact
/// details. Single source of truth shared by the merge below (which pins
/// this section last) and the Kontakter prompt-agreement test (which
/// asserts the system prompt demands exactly this heading), so prompt
/// and merge can never disagree — same pattern as spec 039's shared PII
/// regexes.
pub(crate) const OVRIGA_HEADING: &str = "## Övriga uppgifter";

/// Kontakter (spec 040): one section per PERSON. Sections are keyed by
/// exact trimmed `## ` heading text and merge across parts in first-seen
/// order (no canonical category order — spec 040 FR-010 removed it).
/// `OVRIGA_HEADING` is pinned LAST regardless of where it was first
/// seen; lines arriving before any heading in a part (including whole
/// heading-less parts) fold into it — unattributed by definition.
/// Exact-trim dedup per section ONLY: the same line under two different
/// persons stays under both (cross-section dedup would force choosing
/// an owner, i.e. fabricated attribution). A person heading with zero
/// lines is kept as a bare heading (a found name is information); an
/// empty Övriga section is omitted.
fn merge_kontakter(parts: &[String]) -> String {
    // Person sections in first-seen order; the Övriga bucket is separate
    // so its render position is structural, not first-seen.
    let mut sections: Vec<(String, Vec<String>)> = Vec::new();
    let mut ovriga: Vec<String> = Vec::new();

    for part in parts {
        // None => unattributed: before any heading, or under Övriga.
        let mut current: Option<usize> = None;
        for line in part.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("## ") {
                if trimmed == OVRIGA_HEADING {
                    current = None;
                } else if let Some(pos) = sections.iter().position(|(h, _)| h == trimmed) {
                    current = Some(pos);
                } else {
                    sections.push((trimmed.to_string(), Vec::new()));
                    current = Some(sections.len() - 1);
                }
            } else if !trimmed.is_empty() {
                let bucket = match current {
                    Some(pos) => &mut sections[pos].1,
                    None => &mut ovriga,
                };
                if !bucket.iter().any(|b| b == trimmed) {
                    bucket.push(trimmed.to_string());
                }
            }
        }
    }

    let mut out: Vec<String> = Vec::new();
    for (heading, items) in &sections {
        if items.is_empty() {
            // Bare person heading survives — a found name is information.
            out.push(heading.clone());
        } else {
            out.push(format!("{heading}\n\n{}", items.join("\n")));
        }
    }
    if !ovriga.is_empty() {
        out.push(format!("{OVRIGA_HEADING}\n\n{}", ovriga.join("\n")));
    }
    out.join("\n\n")
}

/// Kallor + Identifiera: strip leading numbering, exact-trim dedup in
/// first-seen order, renumber sequentially.
fn merge_numbered(parts: &[String]) -> String {
    let mut items: Vec<String> = Vec::new();
    for part in parts {
        for line in part.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let stripped = strip_leading_number(trimmed);
            if stripped.is_empty() {
                continue;
            }
            if !items.iter().any(|i| i == stripped) {
                items.push(stripped.to_string());
            }
        }
    }
    items
        .iter()
        .enumerate()
        .map(|(i, item)| format!("{}. {item}", i + 1))
        .collect::<Vec<_>>()
        .join("\n")
}

/// "12. foo" / "3) foo" → "foo"; non-numbered lines pass through.
fn strip_leading_number(line: &str) -> &str {
    let digits_end = line
        .char_indices()
        .find(|(_, c)| !c.is_ascii_digit())
        .map(|(i, _)| i)
        .unwrap_or(line.len());
    if digits_end == 0 {
        return line;
    }
    let rest = &line[digits_end..];
    if let Some(stripped) = rest.strip_prefix('.').or_else(|| rest.strip_prefix(')')) {
        stripped.trim_start()
    } else {
        line
    }
}

/// Forklara: dedup term–explanation lines on the term key (text before the
/// first ':', '–' or '-'); first occurrence wins; order preserved.
fn merge_term_lines(parts: &[String]) -> String {
    let mut seen_keys: Vec<String> = Vec::new();
    let mut lines: Vec<String> = Vec::new();
    for part in parts {
        for line in part.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let key = trimmed
                .split(['\u{2013}', ':', '-'])
                .next()
                .unwrap_or(trimmed)
                .trim()
                .to_string();
            if !seen_keys.iter().any(|k| k == &key) {
                seen_keys.push(key);
                lines.push(trimmed.to_string());
            }
        }
    }
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    // ===== split_into_chunks: contract guarantees G2-G6 =====

    #[test]
    fn g2_short_text_is_single_identity_chunk() {
        let text = "Ett kort dokument.\n\nMed två stycken.";
        let plan = split_into_chunks(text);
        assert_eq!(plan.chunks.len(), 1);
        assert_eq!(plan.chunks[0], text);
        assert!(!plan.was_capped);
        assert!(plan.is_single_pass());
    }

    #[test]
    fn g2_text_exactly_at_target_is_single_chunk() {
        let text = "a".repeat(CHUNK_CHAR_TARGET);
        let plan = split_into_chunks(&text);
        assert_eq!(plan.chunks.len(), 1);
        assert!(!plan.was_capped);
    }

    #[test]
    fn one_char_over_target_splits_into_two() {
        // Paragraph boundary near the middle so the split is structure-aware.
        let half = "b".repeat(12_001);
        let text = format!("{half}\n\n{half}"); // 24_004 chars total
        let plan = split_into_chunks(&text);
        assert_eq!(plan.chunks.len(), 2);
        assert!(!plan.was_capped);
        // G3: join reproduces the input exactly.
        assert_eq!(plan.chunks.concat(), text);
    }

    #[test]
    fn g3_join_reproduces_input_for_many_paragraphs() {
        // ~30 paragraphs of ~3k chars → ~90k chars → 4-5 chunks.
        let para = format!("{} slutet.", "ord ".repeat(750));
        let text = (0..30)
            .map(|_| para.clone())
            .collect::<Vec<_>>()
            .join("\n\n");
        let plan = split_into_chunks(&text);
        assert!(plan.chunks.len() > 1, "expected multi-chunk plan");
        assert!(!plan.was_capped);
        assert_eq!(plan.chunks.concat(), text, "G3: lossless in-order cover");
        for c in &plan.chunks {
            assert!(c.chars().count() <= CHUNK_CHAR_TARGET, "chunk over target");
            assert!(!c.trim().is_empty(), "blank chunk");
        }
    }

    #[test]
    fn paragraph_boundary_preferred() {
        // One paragraph of 20k, then one of 20k — cut must land exactly at
        // the "\n\n" boundary (after it), not mid-paragraph.
        let p1 = "x".repeat(20_000);
        let p2 = "y".repeat(20_000);
        let text = format!("{p1}\n\n{p2}");
        let plan = split_into_chunks(&text);
        assert_eq!(plan.chunks.len(), 2);
        assert_eq!(plan.chunks[0], format!("{p1}\n\n"));
        assert_eq!(plan.chunks[1], p2);
    }

    #[test]
    fn g4_ceiling_caps_at_max_chunks_and_flags() {
        // 13 paragraphs of ~23.9k chars each — each becomes its own chunk;
        // the 13th must be dropped and flagged.
        let para = "z".repeat(23_900);
        let text = (0..13)
            .map(|_| para.clone())
            .collect::<Vec<_>>()
            .join("\n\n");
        let plan = split_into_chunks(&text);
        assert_eq!(plan.chunks.len(), MAX_CHUNKS);
        assert!(plan.was_capped, "tail beyond 12 chunks must set was_capped");
        // The kept chunks still cover a prefix losslessly.
        let prefix = plan.chunks.concat();
        assert!(text.starts_with(&prefix));
    }

    #[test]
    fn g4_exactly_max_chunks_not_capped() {
        let para = "w".repeat(23_900);
        let text = (0..12)
            .map(|_| para.clone())
            .collect::<Vec<_>>()
            .join("\n\n");
        let plan = split_into_chunks(&text);
        assert_eq!(plan.chunks.len(), MAX_CHUNKS);
        assert!(!plan.was_capped, "exactly 12 chunks is within the cap");
        assert_eq!(plan.chunks.concat(), text);
    }

    #[test]
    fn g5_sentence_fallback_when_no_paragraphs() {
        // A single 30k-char paragraph of sentences — split lands after a
        // sentence terminator, not mid-sentence.
        let sentence = "Domstolen fann att kärandens talan skulle bifallas i denna del. ";
        let text = sentence.repeat(470); // ~30k chars, no "\n\n"
        let plan = split_into_chunks(&text);
        assert!(plan.chunks.len() >= 2);
        assert!(
            plan.chunks[0].ends_with(". "),
            "cut should land after a sentence terminator + space, got …{:?}",
            &plan.chunks[0][plan.chunks[0].len().saturating_sub(20)..]
        );
        assert_eq!(plan.chunks.concat(), text);
    }

    #[test]
    fn g5_swedish_abbreviations_do_not_end_sentences() {
        // Window ends shortly after an abbreviation — the cut must NOT land
        // right after "t.ex. " (the only dot+space in the text is the
        // abbreviation; the real sentence end is the final period+space).
        let filler = "ord ".repeat(5_990); // 23_960 chars
        let text = format!("{filler}t.ex. resten av meningen fortsätter här utan punkt och sedan kommer mer text som fyller på ordentligt mycket mer");
        assert!(text.chars().count() > CHUNK_CHAR_TARGET);
        let plan = split_into_chunks(&text);
        // The first chunk must not end with the abbreviation's dot+space —
        // whitespace fallback (after "t.ex. " is rejected) cuts at a plain
        // space instead.
        assert!(
            !plan.chunks[0].trim_end().ends_with("t.ex."),
            "abbreviation guard failed: chunk ends with t.ex."
        );
        assert_eq!(plan.chunks.concat(), text);
    }

    #[test]
    fn single_letter_initials_do_not_end_sentences() {
        let filler = "ord ".repeat(5_995);
        let text = format!("{filler}advokat J. Olofsson företrädde käranden i målet och mer text följer här tills gränsen passeras ordentligt");
        let plan = split_into_chunks(&text);
        assert!(
            !plan.chunks[0].trim_end().ends_with("J."),
            "initial guard failed: chunk ends with J."
        );
        assert_eq!(plan.chunks.concat(), text);
    }

    #[test]
    fn whitespace_fallback_for_sentence_free_text() {
        // 30k chars of space-separated tokens with NO sentence terminators.
        let text = "juridik ".repeat(3_750); // 30k chars
        let plan = split_into_chunks(&text);
        assert!(plan.chunks.len() >= 2);
        assert!(
            plan.chunks[0].ends_with(' '),
            "whitespace cut keeps the space with the preceding chunk"
        );
        assert_eq!(plan.chunks.concat(), text);
    }

    #[test]
    fn g6_char_fallback_is_utf8_safe_on_whitespace_free_swedish() {
        // Pathological: 30k Swedish multi-byte chars, no whitespace at all.
        let text = "åäö".repeat(10_000); // 30k chars, 60k bytes
        let plan = split_into_chunks(&text);
        assert_eq!(plan.chunks.len(), 2);
        assert_eq!(plan.chunks[0].chars().count(), CHUNK_CHAR_TARGET);
        assert_eq!(plan.chunks.concat(), text, "no mid-char corruption");
    }

    #[test]
    fn no_blank_chunks_for_collapsed_input() {
        // Realistic collapsed input (max 2 blank lines) never yields a
        // whitespace-only chunk.
        let para = "text ".repeat(2_000);
        let text = (0..20)
            .map(|_| para.clone())
            .collect::<Vec<_>>()
            .join("\n\n\n");
        let plan = split_into_chunks(&text);
        for c in &plan.chunks {
            assert!(!c.trim().is_empty());
        }
    }

    // ===== combine_strategy mapping (contracts §2) =====

    #[test]
    fn combine_strategy_mapping_pinned() {
        use CombineStrategy::*;
        for z in ZoneId::ALL {
            let expected = match z {
                ZoneId::Sammanfatta | ZoneId::Punktlista => Reduce,
                ZoneId::TillEngelska
                | ZoneId::TillSvenska
                | ZoneId::Forenkla
                | ZoneId::Anonymisera => Concat,
                ZoneId::Kontakter | ZoneId::Kallor | ZoneId::Identifiera | ZoneId::Forklara => {
                    Aggregate
                }
                ZoneId::Strukturera => CondenseThenStructure,
                ZoneId::Generera => Exempt,
            };
            assert_eq!(z.combine_strategy(), expected, "{z:?} strategy drifted");
        }
    }

    // ===== merge_concat =====

    #[test]
    fn concat_joins_in_order() {
        let parts = vec![
            "första".to_string(),
            "andra".to_string(),
            "tredje".to_string(),
        ];
        assert_eq!(merge_concat(&parts), "första\n\nandra\n\ntredje");
    }

    // ===== merge_aggregate: G7 exactly-once =====

    #[test]
    fn g7_kontakter_merges_person_headings_and_dedups() {
        // Spec 040: per-person sections, exact-heading keyed across parts.
        let p1 = "## David Dahl\n\n- Telefon: 08-555 12 34\n\n## Erik Eriksson\n\n- E-post: erik@exempel.se".to_string();
        let p2 = "## David Dahl\n\n- Telefon: 08-555 12 34\n- E-post: david.dahl@dahl.exempel.se\n\n## Fatima Farah\n\n- Adress: Storgatan 1, 211 34 Malmö".to_string();
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2]);
        // ONE section per person (SC-003): cross-part heading dedup.
        assert_eq!(merged.matches("## David Dahl").count(), 1);
        assert_eq!(merged.matches("## Erik Eriksson").count(), 1);
        assert_eq!(merged.matches("## Fatima Farah").count(), 1);
        // Union of details, duplicate exactly once.
        assert_eq!(merged.matches("Telefon: 08-555 12 34").count(), 1);
        assert_eq!(
            merged.matches("E-post: david.dahl@dahl.exempel.se").count(),
            1
        );
        // First-seen order (M-2): David before Erik before Fatima.
        let david = merged.find("## David Dahl").expect("david heading");
        let erik = merged.find("## Erik Eriksson").expect("erik heading");
        let fatima = merged.find("## Fatima Farah").expect("fatima heading");
        assert!(david < erik && erik < fatima);
    }

    #[test]
    fn g7_kontakter_ovriga_pinned_last_even_when_first_seen_first() {
        // M-3/FR-007: Övriga seen in part 1 still renders after persons
        // introduced in part 2.
        let p1 = format!("{OVRIGA_HEADING}\n\n- Telefon: 046-222 00 00");
        let p2 = "## Greta Granlund\n\n- E-post: greta@exempel.se".to_string();
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2]);
        let ovriga = merged.find(OVRIGA_HEADING).expect("ovriga heading");
        let greta = merged.find("## Greta Granlund").expect("greta heading");
        assert!(greta < ovriga, "Övriga must render last: {merged}");
        assert_eq!(merged.matches(OVRIGA_HEADING).count(), 1);
    }

    #[test]
    fn g7_kontakter_cross_person_duplicate_preserved() {
        // M-5 (clarified): per-section dedup ONLY — the same line under
        // two persons stays under both (no fabricated owner choice).
        let p1 = "## Hanna Hall\n\n- Telefon: 070-111 22 33".to_string();
        let p2 = "## Ivar Isaksson\n\n- Telefon: 070-111 22 33".to_string();
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2]);
        assert_eq!(merged.matches("- Telefon: 070-111 22 33").count(), 2);
    }

    #[test]
    fn g7_kontakter_bare_person_heading_preserved() {
        // M-6/FR-009: a person found with no details is still a person.
        let p1 = "## Johan Jonsson".to_string();
        let p2 = "## Karin Kvist\n\n- E-post: karin@exempel.se".to_string();
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2]);
        assert!(
            merged.contains("## Johan Jonsson"),
            "bare heading dropped: {merged}"
        );
    }

    #[test]
    fn g7_kontakter_headingless_part_folds_into_ovriga() {
        // M-4/FR-008: a whole part with no headings is unattributed.
        let p1 = "- Telefon: 040-12 34 56\n- E-post: info@exempel.se".to_string();
        let p2 = "## Lena Lind\n\n- Adress: Kungsvägen 14, Göteborg".to_string();
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2]);
        let ovriga = merged.find(OVRIGA_HEADING).expect("ovriga heading");
        let lena = merged.find("## Lena Lind").expect("lena heading");
        assert!(lena < ovriga, "Övriga last: {merged}");
        // The orphan lines live INSIDE the Övriga section (after its heading).
        let tel = merged.find("- Telefon: 040-12 34 56").expect("orphan tel");
        assert!(tel > ovriga, "orphan must be under Övriga: {merged}");
    }

    #[test]
    fn g7_kontakter_ovriga_only_parts_yield_single_ovriga_section() {
        let p1 = format!("{OVRIGA_HEADING}\n\n- Telefon: 010-1\n");
        let p2 = format!("{OVRIGA_HEADING}\n\n- Telefon: 010-1\n- Telefon: 010-2\n");
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2]);
        assert_eq!(merged.matches(OVRIGA_HEADING).count(), 1);
        assert_eq!(merged.matches("- Telefon: 010-1").count(), 1, "{merged}");
        assert_eq!(merged.matches("- Telefon: 010-2").count(), 1);
    }

    #[test]
    fn g7_kontakter_no_empty_ovriga_section() {
        // M-7/FR-004: nothing unattributed → no Övriga section, even when
        // a part emitted the bare heading.
        let p1 = format!("## Maja Malm\n\n- Telefon: 070-9\n\n{OVRIGA_HEADING}");
        let p2 = "## Maja Malm\n\n- E-post: maja@exempel.se".to_string();
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2]);
        assert!(
            !merged.contains(OVRIGA_HEADING),
            "empty Övriga must be omitted: {merged}"
        );
    }

    #[test]
    fn g7_kontakter_dedup_ignores_surrounding_whitespace() {
        // Identical-after-trim headings and lines merge (M-1/M-5): trim
        // strips OUTER whitespace only.
        let p1 = "## Helena Holm\n\n- Telefon: 070-5".to_string();
        let p2 = "## Helena Holm  \n\n- Telefon: 070-5  ".to_string();
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2]);
        assert_eq!(merged.matches("## Helena Holm").count(), 1);
        assert_eq!(merged.matches("Telefon: 070-5").count(), 1);

        // INNER whitespace differs after trim → exact-heading mismatch →
        // separate sections (near-dupe merging out of scope per contract).
        let p3 = "## Helena Holm\n\n- Telefon: 070-5".to_string();
        let p4 = "##   Helena Holm\n\n- Telefon: 070-5".to_string();
        let merged2 = merge_aggregate(ZoneId::Kontakter, &[p3, p4]);
        assert!(merged2.contains("## Helena Holm"));
        assert!(merged2.contains("##   Helena Holm"));
        assert_eq!(merged2.matches("- Telefon: 070-5").count(), 2);
    }

    #[test]
    fn g7_kontakter_handles_headingless_lines_and_empty_parts() {
        // M-4: lines before any heading fold into Övriga (no headingless
        // leading block anymore); empty parts contribute nothing.
        let p1 = "- En rad utan rubrik".to_string();
        let p2 = String::new();
        let p3 = "## Gustav Grön\n\n- E-post: gustav@exempel.se".to_string();
        let merged = merge_aggregate(ZoneId::Kontakter, &[p1, p2, p3]);
        let ovriga = merged.find(OVRIGA_HEADING).expect("ovriga heading");
        let rad = merged.find("- En rad utan rubrik").expect("orphan line");
        assert!(rad > ovriga, "orphan line must be under Övriga: {merged}");
        assert!(merged.contains("## Gustav Grön"));
        assert!(merged.find("## Gustav Grön").expect("gustav") < ovriga);
    }

    #[test]
    fn g7_numbered_merge_dedups_and_renumbers() {
        let p1 = "1. SFS 2010:110, Socialförsäkringsbalk\n2. NJA 1994 s. 74".to_string();
        let p2 = "1. NJA 1994 s. 74\n2. Prop. 2009/10:80".to_string();
        let merged = merge_aggregate(ZoneId::Kallor, &[p1, p2]);
        let lines: Vec<&str> = merged.lines().collect();
        assert_eq!(lines.len(), 3, "dedup to 3 unique items: {merged}");
        assert!(lines[0].starts_with("1. "));
        assert!(lines[1].starts_with("2. "));
        assert!(lines[2].starts_with("3. "));
        assert_eq!(merged.matches("NJA 1994 s. 74").count(), 1);
    }

    #[test]
    fn g7_numbered_merge_handles_paren_numbering() {
        let p1 = "1) Fråga om uppsåt\n2) Fråga om preskription".to_string();
        let p2 = "1) Fråga om preskription".to_string();
        let merged = merge_aggregate(ZoneId::Identifiera, &[p1, p2]);
        assert_eq!(merged.lines().count(), 2);
        assert_eq!(merged.matches("preskription").count(), 1);
    }

    #[test]
    fn g7_term_merge_first_occurrence_wins() {
        let p1 = "Preskription: rätten att kräva har gått ut.\nUppsåt: avsikt.".to_string();
        let p2 = "Preskription: en annan förklaring.\nVårdslöshet: oaktsamhet.".to_string();
        let merged = merge_aggregate(ZoneId::Forklara, &[p1, p2]);
        assert_eq!(merged.matches("Preskription").count(), 1);
        assert!(merged.contains("rätten att kräva har gått ut"));
        assert!(!merged.contains("en annan förklaring"));
        assert!(merged.contains("Vårdslöshet"));
    }

    #[test]
    fn aggregate_fallback_for_non_aggregate_zone_is_concat() {
        let parts = vec!["a".to_string(), "b".to_string()];
        assert_eq!(merge_aggregate(ZoneId::Sammanfatta, &parts), "a\n\nb");
    }
}
