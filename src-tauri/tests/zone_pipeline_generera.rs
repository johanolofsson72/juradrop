// Spec 013 US1 / FR-011 — Generera zone end-to-end on a .txt outline.
// FR-003: Generera writes a .docx sidecar regardless of .txt input. The
// .txt source must remain byte-identical (verified by the harness).
// Disclaimer presence checked by the harness.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn generera_pipeline_writes_docx_from_txt_outline() {
    common::run_zone_pipeline(
        ZoneId::Generera,
        "generera-input.txt",
        "UPPSÄGNING AV HYRESKONTRAKT\n\n\
         Härmed sägs hyreskontraktet för lägenheten på Storgatan 1, Stockholm, upp \
         för villkorsändring enligt 12 kap. jordabalken. Uppsägningstiden är tre månader \
         och avflyttning ska ske senast 2026-09-30.",
        &["UPPSÄGNING", "jordabalken"],
    )
    .await;
}
