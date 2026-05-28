// Spec 013 US1 / FR-011 — Anonymisera zone end-to-end on a real fixture.
// US1 acceptance scenario 1: names/personnummer/addresses replaced with
// placeholders. Disclaimer presence checked by the harness.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn anonymisera_pipeline_writes_sidecar_with_placeholders() {
    common::run_zone_pipeline(
        ZoneId::Anonymisera,
        "anonymisera-input.docx",
        "Klientärende: arvstvist. Klienten [Person 1], personnummer [Personnr 1], \
         bosatt på [Adress 1], har kontaktat byrån. Motpart är [Person 2], [Personnr 2], \
         med adress [Adress 2].",
        &["[Person 1]", "[Personnr 1]", "[Adress 1]"],
    )
    .await;
}
