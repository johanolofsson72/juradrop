// Spec 039 — Anonymisera deterministic-scrub integration tests (T006-T010).
//
// Proof shape: the scrub runs on the INPUT, so the strongest assertions are
// on the recorded /api/generate request prompts (raw PII absent, bracketed
// placeholders present) — independent of what any model would do. Output-
// side behavior (sweep banner) is driven with crafted mock responses.

mod common;

use std::time::Duration;

use common::{long_doc_with_sentinels, ok_generate, ChunkedSetup};
use juradrop_lib::zones::chunking::split_into_chunks;
use juradrop_lib::zones::ZoneId;

const SETTLE: Duration = Duration::from_secs(10);

const PNR: &str = "19850312-1234";
const PHONE_A: &str = "070-123 45 67";
const PHONE_B: &str = "08-555 12 34";
const EMAIL: &str = "david.dahl@dahl.exempel.se";

// ===== T006 — US1/SC-001: structured PII never reaches the model ==========

#[tokio::test]
async fn anonymisera_prompt_carries_placeholders_never_raw_pii() {
    let doc = format!(
        "Kärande: Anna Andersson, {PNR}, nås på {PHONE_A} eller {EMAIL}. \
         Svarande: Bolaget AB. Anna Andersson yrkar ersättning."
    );
    // Mock response in the post-039 convention the model is instructed to keep.
    let setup = ChunkedSetup::new(
        ZoneId::Anonymisera,
        &doc,
        vec![ok_generate(
            "Person A ([Personnr 1]) nås på [Telefon 1] eller [E-post 1]. \
             Svarande: Företag X. Person A yrkar ersättning.",
        )],
    )
    .await;
    setup.drop_file().await;
    let sidecar = setup.wait_settled(SETTLE).await.expect("sidecar written");

    // INPUT-side proof (model-independent): the request prompt holds the
    // placeholders and ZERO raw values.
    let bodies = setup.generate_bodies().await;
    assert_eq!(bodies.len(), 1);
    let prompt = bodies[0]["prompt"].as_str().expect("prompt");
    assert!(prompt.contains("[Personnr 1]"), "prompt: {prompt}");
    assert!(prompt.contains("[Telefon 1]"));
    assert!(prompt.contains("[E-post 1]"));
    assert!(!prompt.contains(PNR), "raw personnummer reached the model");
    assert!(!prompt.contains(PHONE_A), "raw phone reached the model");
    assert!(!prompt.contains(EMAIL), "raw email reached the model");

    // OUTPUT side: placeholders pass the sweep unflagged — no banner.
    assert!(sidecar.contains("[Personnr 1]"));
    assert!(
        !sidecar.contains("Automatisk kontroll hittade"),
        "clean placeholders must not trigger the sweep banner"
    );
}

// ===== T007 — US3/SC-003: fabricated PII still triggers the net ===========

#[tokio::test]
async fn fabricated_pii_in_model_output_still_warns() {
    let doc = format!("Anna Andersson ({PNR}) väcker talan mot Bolaget AB.");
    // The model hallucinates a NEW phone number not present in the input.
    let setup = ChunkedSetup::new(
        ZoneId::Anonymisera,
        &doc,
        vec![ok_generate(&format!(
            "Person A ([Personnr 1]) väcker talan. Ring {PHONE_B} för info."
        ))],
    )
    .await;
    setup.drop_file().await;
    let sidecar = setup.wait_settled(SETTLE).await.expect("sidecar written");

    assert!(
        sidecar.contains("Automatisk kontroll hittade"),
        "fabricated phone must trigger the spec-014 banner"
    );
    assert!(sidecar.contains("1 telefonnummer"));
}

// ===== T008 — US1/SC-002: global indices across chunks ====================

#[tokio::test]
async fn multi_chunk_scrub_keeps_global_placeholder_indices() {
    // Same phone planted at the very start AND the very end (boundary
    // positions, T010); a distinct phone in the middle.
    let mut doc = long_doc_with_sentinels(30_000, &["MITT-AVSNITT", "SLUT-AVSNITT"]);
    doc.insert_str(0, &format!("Ring {PHONE_A} först. "));
    let mid = doc.len() / 2;
    doc.insert_str(mid, &format!(" Växel: {PHONE_B}. "));
    doc.push_str(&format!(" Ring {PHONE_A} igen sist."));

    let plan = split_into_chunks(&doc);
    assert!(plan.chunks.len() >= 2, "fixture must be multi-chunk");

    let n = plan.chunks.len();
    let templates = (0..n)
        .map(|i| ok_generate(&format!("Anonymiserad del {i}.")))
        .collect();
    let setup = ChunkedSetup::new(ZoneId::Anonymisera, &doc, templates).await;
    setup.drop_file().await;
    setup.wait_settled(SETTLE).await.expect("sidecar written");

    let bodies = setup.generate_bodies().await;
    assert_eq!(bodies.len(), n, "concat zone: chunk passes only");
    let prompts: Vec<&str> = bodies
        .iter()
        .map(|b| b["prompt"].as_str().expect("prompt"))
        .collect();

    // No raw number in ANY chunk prompt.
    for p in &prompts {
        assert!(!p.contains(PHONE_A) && !p.contains(PHONE_B));
    }
    // PHONE_A appears first → [Telefon 1] in BOTH first and last chunk
    // (global numbering across chunks); PHONE_B → [Telefon 2].
    assert!(
        prompts[0].contains("[Telefon 1]"),
        "first chunk: {}",
        &prompts[0][..200.min(prompts[0].len())]
    );
    assert!(
        prompts[n - 1].contains("[Telefon 1]"),
        "last chunk must reuse the SAME index for the same value"
    );
    assert!(
        prompts.iter().any(|p| p.contains("[Telefon 2]")),
        "distinct number gets the next index"
    );
}

// ===== T009 — SC-004: every other zone gets byte-identical raw input ======

#[tokio::test]
async fn other_zones_receive_raw_unscrubbed_input() {
    let doc = format!("Anna Andersson ({PNR}, {PHONE_A}, {EMAIL}) yrkar ersättning.");
    let setup = ChunkedSetup::new(
        ZoneId::Sammanfatta,
        &doc,
        vec![ok_generate("En sammanfattning.")],
    )
    .await;
    setup.drop_file().await;
    setup.wait_settled(SETTLE).await.expect("sidecar written");

    let bodies = setup.generate_bodies().await;
    let prompt = bodies[0]["prompt"].as_str().expect("prompt");
    // The scrub is Anonymisera-only — Sammanfatta must see the document
    // exactly as written (a summary of "[Telefon 1]" would be wrong).
    assert!(prompt.contains(PNR));
    assert!(prompt.contains(PHONE_A));
    assert!(prompt.contains(EMAIL));
    assert!(!prompt.contains("[Personnr"));
}
