// Spec 013 US1 / FR-011 — Sammanfatta zone end-to-end on a real fixture.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn sammanfatta_pipeline_writes_sidecar() {
    common::run_zone_pipeline(
        ZoneId::Sammanfatta,
        "sammanfatta-input.docx",
        "Sammanfattning: tvisten gällde utebliven betalning för hantverksarbete. \
         Tingsrätten biföll käromålet delvis och dömde ut ett prisavdrag.",
        &["Sammanfattning", "prisavdrag"],
    )
    .await;
}
