// Spec 013 US1 / FR-011 — Till svenska zone end-to-end on a real fixture
// (the only English-input fixture).
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tillsvenska_pipeline_writes_sidecar() {
    common::run_zone_pipeline(
        ZoneId::TillSvenska,
        "tillsvenska-input.docx",
        "Sekretessavtal. Detta avtal ingås mellan den utlämnande parten och den \
         mottagande parten i syfte att förhindra obehörigt röjande av konfidentiell information.",
        &["Sekretessavtal", "konfidentiell information"],
    )
    .await;
}
