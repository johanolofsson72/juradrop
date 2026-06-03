// Spec 013 US1 / FR-011 — Punktlista zone end-to-end on a real fixture.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn punktlista_pipeline_writes_sidecar() {
    common::run_zone_pipeline(
        ZoneId::Punktlista,
        "punktlista-input.docx",
        "• Kassaflödet har försämrats första kvartalet.\n\
         • Underhållsplanen behöver revideras.\n\
         • Två leverantörsavtal bör omförhandlas.\n\
         • Klagomål om ventilation i trapphus B.",
        // Spec 036 follow-up — bullets are now real Word numbering, so the "•"
        // glyph is a paragraph property, not run text; assert the content.
        &["Kassaflödet", "Underhållsplanen"],
    )
    .await;
}
