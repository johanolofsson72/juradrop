// Spec 013 US1 / FR-011 — Förenkla zone end-to-end on a real fixture.
// Disclaimer presence checked by the harness.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn forenkla_pipeline_writes_sidecar() {
    common::run_zone_pipeline(
        ZoneId::Forenkla,
        "forenkla-input.docx",
        "Vi har tagit emot din ansökan. Vi börjar handlägga ärendet och fattar beslut \
         så snart vi har allt underlag. Om vi behöver fler papper hör vi av oss, och \
         då får du chans att svara inom en viss tid.",
        &["din ansökan", "handlägga"],
    )
    .await;
}
