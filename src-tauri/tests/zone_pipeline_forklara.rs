// Spec 036 US3 / FR-006 — Förklara begreppen zone end-to-end.
// Extracts legal terms and pairs each with a plain-Swedish explanation;
// SC-002 asserts the citation-free mock output stays citation-free.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn forklara_pipeline_explains_terms() {
    common::run_zone_pipeline_checked(
        ZoneId::Forklara,
        "forklara-input.docx",
        "Begrepp och förklaringar:\n\
         Culpa: oaktsamhet, att någon inte varit tillräckligt försiktig.\n\
         Rekvisit: ett villkor som måste vara uppfyllt för att en regel ska gälla.\n\
         Adekvat kausalitet: att skadan är en tillräckligt typisk följd av handlingen.\n\
         Subsumtion: att pröva de konkreta omständigheterna mot reglerna.\n\
         Dispositiv: en regel som parterna får komma överens om att frångå.",
        &["Culpa", "oaktsamhet", "Rekvisit", "Subsumtion"],
        &["§", "SFS", "NJA", "kap."],
    )
    .await;
}
