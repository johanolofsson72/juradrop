// Spec 044 — quote-preservation integration (T005): the trigger masks
// quoted spans into [CITAT N] before the model, restores them verbatim
// after; everything else is byte-identical pre-044 behavior.

mod common;

use std::time::Duration;

use common::{ok_generate, ChunkedSetup};
use juradrop_lib::prompts::frame_prompt;
use juradrop_lib::zones::quote_mask::TRIGGER_PHRASE;
use juradrop_lib::zones::ZoneId;
use wiremock::ResponseTemplate;

const SETTLE: Duration = Duration::from_secs(10);
const INSTR: &str = "behåll citaten på svenska";

// ===== (a) triggered single-pass: placeholders in, originals out ==========

#[tokio::test]
async fn triggered_run_masks_prompt_and_restores_sidecar_verbatim() {
    let doc = "Avtalet stadgar: ”Skadestånd omfattar utebliven vinst.” \
               Vidare gäller: ”Ingenting lämnar byrån utan medgivande.” Slut.";
    // The mock "translates" everything around the markers and preserves them.
    let setup = ChunkedSetup::new(
        ZoneId::TillEngelska,
        doc,
        vec![ok_generate(
            "The contract stipulates: [CITAT 1] Furthermore: [CITAT 2] End.",
        )],
    )
    .await;
    setup
        .drop_file_with_instruction(Some(INSTR.to_string()))
        .await;
    let sidecar = setup.wait_settled(SETTLE).await.expect("sidecar written");

    let bodies = setup.generate_bodies().await;
    assert_eq!(bodies.len(), 1);
    let prompt = bodies[0]["prompt"].as_str().expect("prompt");
    // FR-001 — the model sees placeholders, never the quoted text.
    assert!(prompt.contains("[CITAT 1]") && prompt.contains("[CITAT 2]"));
    assert!(!prompt.contains("Skadestånd omfattar utebliven vinst"));
    assert!(!prompt.contains("Ingenting lämnar byrån"));

    // SC-001 — the sidecar restores the spans character-identically,
    // quote marks included.
    assert!(sidecar.contains("”Skadestånd omfattar utebliven vinst.”"));
    assert!(sidecar.contains("”Ingenting lämnar byrån utan medgivande.”"));
    assert!(!sidecar.contains("[CITAT"), "no bare markers may remain");
}

// ===== (b) the dormant trio: byte-identical pre-044 behavior ==============

#[tokio::test]
async fn dormant_without_instruction_is_byte_identical() {
    let doc = "Texten har ett ”citat” i sig.";
    let setup =
        ChunkedSetup::new(ZoneId::TillEngelska, doc, vec![ok_generate("Translated.")]).await;
    setup.drop_file().await;
    setup.wait_settled(SETTLE).await.expect("sidecar written");

    let bodies = setup.generate_bodies().await;
    let prompt = bodies[0]["prompt"].as_str().expect("prompt");
    let expected = frame_prompt(
        ZoneId::TillEngelska,
        ZoneId::TillEngelska.system_prompt(),
        doc,
        None,
    );
    assert_eq!(prompt, expected, "FR-003: dormant must be byte-identical");
    // NOTE: the system prompt's verbatim-guard sentence itself mentions
    // "[CITAT 1]" as an example, so a blanket absence check would lie.
    // Byte-identity above IS the proof; additionally the quote survives
    // unmasked in the document region:
    assert!(prompt.contains("”citat”"), "quote must remain unmasked");
}

#[tokio::test]
async fn dormant_on_non_translation_zone_despite_trigger_phrase() {
    let doc = "Domskälen citerar: ”utebliven vinst ersätts”. Slut.";
    let setup = ChunkedSetup::new(
        ZoneId::Sammanfatta,
        doc,
        vec![ok_generate("Sammanfattning.")],
    )
    .await;
    setup
        .drop_file_with_instruction(Some(INSTR.to_string()))
        .await;
    setup.wait_settled(SETTLE).await.expect("sidecar written");

    let bodies = setup.generate_bodies().await;
    let prompt = bodies[0]["prompt"].as_str().expect("prompt");
    // The instruction rides the trusted slot as plain guidance…
    assert!(prompt.contains(INSTR));
    // …but no masking happens outside the translation zones.
    assert!(!prompt.contains("[CITAT"));
    assert!(prompt.contains("”utebliven vinst ersätts”"));
}

#[tokio::test]
async fn dormant_on_opposite_instruction() {
    let doc = "Här finns ”ett citat” att översätta.";
    let setup =
        ChunkedSetup::new(ZoneId::TillEngelska, doc, vec![ok_generate("Translated.")]).await;
    setup
        .drop_file_with_instruction(Some("översätt även citaten".to_string()))
        .await;
    setup.wait_settled(SETTLE).await.expect("sidecar written");

    let bodies = setup.generate_bodies().await;
    let prompt = bodies[0]["prompt"].as_str().expect("prompt");
    // The guard sentence in the system prompt mentions "[CITAT 1]", so
    // prove non-masking by the quote's survival instead:
    assert!(
        prompt.contains("”ett citat”"),
        "'översätt även citaten' must NOT trigger masking ({TRIGGER_PHRASE:?} absent)"
    );
}

// ===== (c) chunked: global indices across chunk boundaries (SC-003) =======

#[tokio::test]
async fn chunked_run_restores_quotes_across_boundaries_with_global_indices() {
    // Build a 2-chunk doc with one quote early and one late.
    let filler = "Avtalsvillkoren beskriver parternas åtaganden i detalj. ".repeat(500);
    let doc = format!(
        "Inledning: ”första citatet står här”. {filler} Avslutning: ”andra citatet står här”. Slut."
    );
    let plan = juradrop_lib::zones::chunking::split_into_chunks(&doc);
    assert!(plan.chunks.len() >= 2, "fixture must span >= 2 chunks");
    let n = plan.chunks.len();

    // Concat strategy: one pass per chunk, no combine call. Each mock
    // response preserves whatever markers its chunk carried.
    let templates: Vec<ResponseTemplate> = (0..n)
        .map(|i| {
            ok_generate(&format!(
                "Translated part {i} keeping [CITAT 1] and [CITAT 2] if present."
            ))
        })
        .collect();
    let setup = ChunkedSetup::new(ZoneId::TillEngelska, &doc, templates).await;
    setup
        .drop_file_with_instruction(Some(INSTR.to_string()))
        .await;
    let sidecar = setup.wait_settled(SETTLE).await.expect("sidecar written");

    // Masking ran BEFORE chunking: no chunk prompt contains either
    // original span; placeholders are globally numbered.
    let bodies = setup.generate_bodies().await;
    assert_eq!(bodies.len(), n, "concat = chunk passes only");
    for b in &bodies {
        let p = b["prompt"].as_str().expect("prompt");
        assert!(!p.contains("första citatet står här"));
        assert!(!p.contains("andra citatet står här"));
    }
    let all_prompts: String = bodies
        .iter()
        .map(|b| b["prompt"].as_str().unwrap_or_default().to_string())
        .collect();
    assert!(all_prompts.contains("[CITAT 1]") && all_prompts.contains("[CITAT 2]"));

    // Restoration on the combined output (the mock parroted both markers
    // in every part — every occurrence restores; FR-005 duplicates rule).
    assert!(sidecar.contains("”första citatet står här”"));
    assert!(sidecar.contains("”andra citatet står här”"));
    assert!(!sidecar.contains("[CITAT"));
}

// ===== (d) hostile pre-existing literal marker (FR-009) ===================

#[tokio::test]
async fn preexisting_literal_marker_in_document_is_collision_safe() {
    let doc = "Texten innehåller redan [CITAT 1] som löptext samt ”ett äkta citat”.";
    let setup = ChunkedSetup::new(
        ZoneId::TillEngelska,
        doc,
        vec![ok_generate("Output keeps [CITAT 1] and [CITAT 2].")],
    )
    .await;
    setup
        .drop_file_with_instruction(Some(INSTR.to_string()))
        .await;
    let sidecar = setup.wait_settled(SETTLE).await.expect("sidecar written");

    let bodies = setup.generate_bodies().await;
    let prompt = bodies[0]["prompt"].as_str().expect("prompt");
    // Issued numbering starts ABOVE the literal: the real quote is [CITAT 2].
    assert!(prompt.contains("[CITAT 2]"));
    assert!(!prompt.contains("ett äkta citat"));

    // Restore touches only the issued placeholder; the literal survives.
    assert!(sidecar.contains("”ett äkta citat”"));
    assert!(
        sidecar.contains("[CITAT 1]"),
        "pre-existing literal survives"
    );
}
