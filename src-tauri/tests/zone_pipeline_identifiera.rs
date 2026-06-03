// Spec 036 US1 / FR-004 — Identifiera rättsfrågorna zone end-to-end.
// Lists the legal issues the dropped document raises; SC-002 asserts the
// citation-free mock output stays citation-free (no fabricated lagrum/case).
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn identifiera_pipeline_lists_legal_issues() {
    common::run_zone_pipeline_checked(
        ZoneId::Identifiera,
        "identifiera-input.docx",
        "Rättsfrågor i materialet:\n\
         1. Förelåg ett köprättsligt fel i bilen, och kan Anna i så fall häva köpet eller få prisavdrag trots förbehållet om befintligt skick?\n\
         2. Utgör säljarens uppgift om att bilen gick utan problem en utfästelse han svarar för?\n\
         3. Ansvarar Anna för skadan som hunden orsakade, och påverkas ansvaret av att grannen kan ha retat hunden?",
        &["Rättsfrågor", "1.", "2.", "3."],
        // Principle-VIII guard: no fabricated statute/case reference (SC-002).
        &["§", "SFS", "NJA", "kap."],
    )
    .await;
}
