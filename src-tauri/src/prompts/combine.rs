// Spec 038 — model-facing Swedish instructions for the multi-chunk combine
// and condense passes. These are NOT user-facing UI copy (they never appear
// in the sidecar or the window) — they instruct the model, in the same
// register as the per-zone system prompts, that its input consists of
// partial results from a longer document.
//
// All three carry the FR-021 "skriv bara" no-greeting guardrail, and every
// combine/condense pass is routed through `framing::frame_prompt` so the
// partials sit inside DOKUMENT markers under the anti-injection guard
// (spec 038 FR-007 — partials are derived from the untrusted document).

/// Reduce-combine for Sammanfatta: weave per-chunk partial summaries into
/// one coherent whole-document summary.
pub const SAMMANFATTA_COMBINE_PROMPT: &str = "Du är en svensk juriststudent som hjälper en annan student. Texten nedan består av delsammanfattningar av ett längre dokument, märkta \"Del 1\", \"Del 2\" och så vidare i ursprunglig ordning. Väv ihop dem till EN sammanhängande, saklig sammanfattning på svenska av hela dokumentet. Behåll juridiska termer på svenska där det är möjligt. Skriv 2–6 stycken; börja inte med en hälsning eller meta-kommentar; skriv bara själva sammanfattningen.";

/// Reduce-combine for Punktlista: merge per-chunk bullet lists into one
/// list honoring the zone's 5-20-bullet convention.
pub const PUNKTLISTA_COMBINE_PROMPT: &str = "Du är en svensk juriststudent. Texten nedan består av punktlistor från olika delar av ett längre dokument, märkta \"Del 1\", \"Del 2\" och så vidare i ursprunglig ordning. Slå ihop dem till EN svensk punktlista över hela dokumentet. Ta bort dubbletter och behåll en punkt per faktum eller juridisk poäng. Använd \"- \" som punktmarkör i början av varje rad. Mellan 5 och 20 punkter. Börja inte med en hälsning eller inledande mening — skriv bara punkterna, en per rad.";

/// Condense pass for Strukturera (condense-then-structure): compress one
/// part of a longer document to the legally essential content so the IRAC
/// pass can reason over the whole document at once. Carries the
/// Principle-VIII no-fabricated-citation guard.
pub const STRUKTURERA_CONDENSE_PROMPT: &str = "Du är ett studieverktyg. Texten nedan är en del av ett längre dokument. Komprimera delen till det juridiskt väsentliga: rättsfrågor, parternas ståndpunkter, domstolens resonemang och slutsatser samt de lagrum och rättsfall som uttryckligen nämns i texten. Lägg inte till nytt juridiskt innehåll och hitta inte på lagrum eller rättsfall. Skriv bara den komprimerade texten.";

#[cfg(test)]
mod tests {
    use super::*;
    use crate::prompts::frame_prompt;
    use crate::prompts::framing::{DOC_BEGIN, INJECTION_GUARD};
    use crate::zones::ZoneId;

    #[test]
    fn combine_prompts_are_non_empty_with_no_greeting_guardrail() {
        for p in [
            SAMMANFATTA_COMBINE_PROMPT,
            PUNKTLISTA_COMBINE_PROMPT,
            STRUKTURERA_CONDENSE_PROMPT,
        ] {
            assert!(!p.is_empty());
            assert!(
                p.to_lowercase().contains("skriv bara"),
                "combine prompt missing the no-greeting guardrail: {p:?}"
            );
        }
    }

    #[test]
    fn condense_prompt_carries_no_fabrication_guard() {
        // Spec 036 SC-002 heritage — the condense pass must not invite
        // fabricated lagrum/rättsfall.
        assert!(STRUKTURERA_CONDENSE_PROMPT.contains("hitta inte på lagrum"));
    }

    /// FR-007 — combine passes route through frame_prompt and therefore get
    /// the DOKUMENT framing + anti-injection guard (partials are document-
    /// derived content).
    #[test]
    fn framed_combine_pass_has_guard_and_doc_markers() {
        let partials = "Del 1:\nförsta delsammanfattningen\n\nDel 2:\nandra delsammanfattningen";
        let p = frame_prompt(ZoneId::Sammanfatta, SAMMANFATTA_COMBINE_PROMPT, partials);
        assert!(p.starts_with(SAMMANFATTA_COMBINE_PROMPT));
        assert!(p.contains(INJECTION_GUARD));
        assert!(p.contains(DOC_BEGIN));
        assert!(p.contains("Del 2:"));
    }
}
