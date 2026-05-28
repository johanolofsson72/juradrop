// Spec 013 US1 / FR-011 — Till engelska zone end-to-end on a real fixture.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tillengelska_pipeline_writes_sidecar() {
    common::run_zone_pipeline(
        ZoneId::TillEngelska,
        "tillengelska-input.docx",
        "Agreement on transfer of tenant-ownership. The seller hereby transfers \
         apartment number 142 to the buyer for a purchase price of SEK 2,950,000.",
        &["Agreement", "purchase price"],
    )
    .await;
}
