// Spec 044 — deterministic quote preservation for the translation zones.
//
// The field-confirmed truth (2026-06-05): "behåll citaten på svenska" is
// beyond gemma3:4b AND 12b as model BEHAVIOR (7 prompt variants, 0
// obedience, lab + field). So it becomes STRUCTURE instead: quoted spans
// turn into `[CITAT N]` placeholders BEFORE the model (before chunking —
// the spec-039 global-index lesson) and the originals return verbatim
// AFTER the combine. The model cannot translate what it never sees.
//
// Same discipline as pii_scrub.rs: pure functions, the span registry
// lives only on the caller's stack frame, and this module contains NO
// log macros (quotes are document content — Principle I; pinned by the
// chunked_path_privacy static invariant).

use crate::zones::ZoneId;

/// Per-span char cap (excl. the two marks). A "quote" longer than this is
/// treated as unbalanced punctuation and left untouched rather than
/// masking half the document (clarification 2, 2026-06-05).
pub const MAX_QUOTE_SPAN_CHARS: usize = 1000;

/// The documented trigger phrase (case-insensitive substring of the
/// per-drop instruction). Deliberately ONE phrase in v1 — the help entry
/// teaches it; synonyms can come later if field data demands.
pub const TRIGGER_PHRASE: &str = "behåll citat";

/// One masked span: the original text (marks included) and the
/// placeholder that replaced it.
pub struct MaskedSpan {
    pub placeholder: String,
    pub original: String,
}

pub struct MaskOutcome {
    pub text: String,
    pub spans: Vec<MaskedSpan>,
}

/// FR-001 trigger: a translation zone + the documented phrase in the
/// pinned per-drop instruction. Everything else is dormant (FR-003).
pub fn is_triggered(zone: ZoneId, instruction: Option<&str>) -> bool {
    zone.is_translation() && instruction.is_some_and(|i| i.to_lowercase().contains(TRIGGER_PHRASE))
}

/// The closer set for an opening mark. `»` accepts both continental `«`
/// and Swedish `»` closers.
fn closers_for(open: char) -> &'static [char] {
    match open {
        '”' => &['”'],
        '“' => &['”'],
        '"' => &['"'],
        '»' => &['«', '»'],
        _ => &[],
    }
}

/// Highest pre-existing literal `[CITAT k]` in `text`, so issued numbering
/// starts above it and restoration can never touch a span the masker did
/// not issue (FR-009 collision determinism).
fn collision_floor(text: &str) -> usize {
    let mut max = 0usize;
    let mut rest = text;
    while let Some(pos) = rest.find("[CITAT ") {
        let tail = &rest[pos + "[CITAT ".len()..];
        let digits: String = tail.chars().take_while(|c| c.is_ascii_digit()).collect();
        if !digits.is_empty() && tail[digits.len()..].starts_with(']') {
            if let Ok(n) = digits.parse::<usize>() {
                max = max.max(n);
            }
        }
        rest = &rest[pos + "[CITAT ".len()..];
    }
    max
}

/// Replace every balanced quoted span (marks included) with `[CITAT N]`.
/// Single forward scan; an opener with no same-class closer within the
/// cap is abandoned (scanning resumes right after the opener) so
/// unbalanced punctuation can never swallow the document.
pub fn mask_quotes(text: &str) -> MaskOutcome {
    let mut spans: Vec<(std::ops::Range<usize>, String)> = Vec::new();
    let chars: Vec<(usize, char)> = text.char_indices().collect();
    let mut i = 0usize;
    while i < chars.len() {
        let (start_byte, c) = chars[i];
        let closers = closers_for(c);
        if closers.is_empty() {
            i += 1;
            continue;
        }
        // Look for the matching closer within the cap.
        let mut found: Option<usize> = None; // index into `chars`
        let mut j = i + 1;
        while j < chars.len() && j - i - 1 <= MAX_QUOTE_SPAN_CHARS {
            if closers.contains(&chars[j].1) {
                found = Some(j);
                break;
            }
            j += 1;
        }
        match found {
            Some(close_idx) => {
                let end_byte = chars[close_idx].0 + chars[close_idx].1.len_utf8();
                spans.push((start_byte..end_byte, text[start_byte..end_byte].to_string()));
                i = close_idx + 1;
            }
            None => {
                // Over-cap or unbalanced. Marks like ” are the SAME glyph
                // as opener and closer, so abandoning at i+1 would flip
                // pairing parity (the abandoned span's closer becomes a
                // bogus opener masking the GAP between quotes). Resync:
                // if a closer exists beyond the cap, skip past the whole
                // over-cap region untouched; if none exists at all, the
                // mark is genuinely unbalanced and i+1 is safe (nothing
                // later can pair with anything).
                let mut resync = None;
                let mut k = j;
                while k < chars.len() {
                    if closers.contains(&chars[k].1) {
                        resync = Some(k);
                        break;
                    }
                    k += 1;
                }
                i = match resync {
                    Some(close_idx) => close_idx + 1,
                    None => i + 1,
                };
            }
        }
    }

    if spans.is_empty() {
        return MaskOutcome {
            text: text.to_string(),
            spans: Vec::new(),
        };
    }

    let floor = collision_floor(text);
    let mut out = text.to_string();
    let mut masked: Vec<MaskedSpan> = Vec::with_capacity(spans.len());
    // Back-to-front splicing: ranges are from the original string, so
    // later replacements never shift earlier ranges (the 039 pattern).
    for (k, (range, original)) in spans.iter().enumerate().rev() {
        let placeholder = format!("[CITAT {}]", floor + k + 1);
        out.replace_range(range.clone(), &placeholder);
        masked.push(MaskedSpan {
            placeholder,
            original: original.clone(),
        });
    }
    masked.reverse(); // restore document order

    MaskOutcome {
        text: out,
        spans: masked,
    }
}

/// Put the originals back. Per-placeholder best-effort (FR-005): a
/// placeholder the model destroyed simply never matches; one the model
/// duplicated is restored at every occurrence (better the original twice
/// than a bare marker once).
pub fn restore_quotes(output: &str, spans: &[MaskedSpan]) -> String {
    let mut out = output.to_string();
    for span in spans {
        out = out.replace(&span.placeholder, &span.original);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_single_swedish_quote() {
        let text = "Avtalet säger: ”Skadestånd omfattar utebliven vinst.” Punkt.";
        let m = mask_quotes(text);
        assert_eq!(m.spans.len(), 1);
        assert!(m.text.contains("[CITAT 1]"));
        assert!(!m.text.contains("Skadestånd omfattar"));
        let restored = restore_quotes(&m.text, &m.spans);
        assert_eq!(restored, text, "round-trip must be character-identical");
    }

    #[test]
    fn multiple_spans_get_sequential_indices_in_document_order() {
        let text = "Först ”ett” sedan “två” och så \"tre\" samt »fyra«.";
        let m = mask_quotes(text);
        assert_eq!(m.spans.len(), 4);
        assert_eq!(m.spans[0].placeholder, "[CITAT 1]");
        assert_eq!(m.spans[0].original, "”ett”");
        assert_eq!(m.spans[3].placeholder, "[CITAT 4]");
        assert_eq!(m.spans[3].original, "»fyra«");
        assert_eq!(restore_quotes(&m.text, &m.spans), text);
    }

    #[test]
    fn unbalanced_opener_is_left_untouched() {
        let text = "Ett ensamt ” citattecken utan slut i hela dokumentet";
        let m = mask_quotes(text);
        assert!(m.spans.is_empty());
        assert_eq!(m.text, text);
    }

    #[test]
    fn over_cap_span_is_abandoned() {
        let long_inner = "x".repeat(MAX_QUOTE_SPAN_CHARS + 1);
        let text = format!("”{long_inner}” och sen ”kort”.");
        let m = mask_quotes(&text);
        // The over-cap span is skipped; the short one after it still masks.
        assert_eq!(m.spans.len(), 1);
        assert_eq!(m.spans[0].original, "”kort”");
        assert!(m.text.contains(&long_inner), "over-cap content untouched");
        assert_eq!(restore_quotes(&m.text, &m.spans), text);
    }

    #[test]
    fn collision_with_preexisting_literal_marker_is_deterministic() {
        // FR-009: the document itself contains "[CITAT 1]" — issued
        // numbering starts above it, restoration never touches it.
        let text = "Det står redan [CITAT 1] i texten samt ”ett riktigt citat”.";
        let m = mask_quotes(text);
        assert_eq!(m.spans.len(), 1);
        assert_eq!(m.spans[0].placeholder, "[CITAT 2]");
        let restored = restore_quotes(&m.text, &m.spans);
        assert_eq!(restored, text);
        assert!(
            restored.contains("[CITAT 1]"),
            "pre-existing literal survives"
        );
    }

    #[test]
    fn destroyed_placeholder_vanishes_without_damage() {
        let text = "”behåll mig” och vanlig text";
        let m = mask_quotes(text);
        // Model "destroyed" the placeholder: output lacks it entirely.
        let model_output = "translated text without any marker";
        let restored = restore_quotes(model_output, &m.spans);
        assert_eq!(restored, model_output, "FR-005: no-op, no error");
    }

    #[test]
    fn duplicated_placeholder_restores_both_occurrences() {
        let text = "”citat”";
        let m = mask_quotes(text);
        let doubled = format!("{p} mitt {p}", p = m.spans[0].placeholder);
        let restored = restore_quotes(&doubled, &m.spans);
        assert_eq!(restored, "”citat” mitt ”citat”");
    }

    #[test]
    fn empty_and_adjacent_quotes_work() {
        let text = "”” och ”a” och ”b”";
        let m = mask_quotes(text);
        assert_eq!(m.spans.len(), 3);
        assert_eq!(restore_quotes(&m.text, &m.spans), text);
    }

    #[test]
    fn trigger_matrix() {
        // Positive: translation zones + the phrase, any case, embedded.
        for z in [ZoneId::TillEngelska, ZoneId::TillSvenska] {
            assert!(is_triggered(z, Some("behåll citaten på svenska")));
            assert!(is_triggered(z, Some("BEHÅLL CITATEN tack")));
            assert!(is_triggered(z, Some("översätt noga och behåll citat")));
        }
        // Negative: wrong zone, no instruction, the OPPOSITE request.
        assert!(!is_triggered(ZoneId::Sammanfatta, Some("behåll citaten")));
        assert!(!is_triggered(ZoneId::TillEngelska, None));
        assert!(!is_triggered(
            ZoneId::TillEngelska,
            Some("översätt även citaten")
        ));
    }

    #[test]
    fn straight_quotes_mask_too() {
        let text = "Klausulen lyder: \"Ingenting lämnar byrån.\" Slut.";
        let m = mask_quotes(text);
        assert_eq!(m.spans.len(), 1);
        assert_eq!(restore_quotes(&m.text, &m.spans), text);
    }
}
