// Spec 036 US2 / FR-005 — Strukturera (IRAC) zone end-to-end.
// Reshapes the dropped answer into the four Swedish IRAC sections. The markers
// assert all four headings are present (the prompt enforces their order);
// SC-002 asserts the citation-free mock output stays citation-free.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn strukturera_pipeline_uses_irac_headings() {
    common::run_zone_pipeline_checked(
        ZoneId::Strukturera,
        "strukturera-input.docx",
        "Rättsfråga\nHar Anna rätt att häva köpet eller få prisavdrag för felet i bilen?\n\n\
         Gällande rätt\nEtt köp kan hävas vid väsentligt fel, annars kan prisavdrag bli aktuellt. En uttrycklig uppgift om varans skick kan utgöra en utfästelse som säljaren svarar för.\n\n\
         Subsumtion\nSäljaren uppgav att bilen gick utan problem, vilket talar för en utfästelse. Att växellådan havererade efter kort tid talar för att felet fanns redan vid köpet.\n\n\
         Slutsats\nAnna har sannolikt rätt till prisavdrag, och möjligen hävning om felet bedöms väsentligt.",
        &["Rättsfråga", "Gällande rätt", "Subsumtion", "Slutsats"],
        &["§", "SFS", "NJA", "kap."],
    )
    .await;
}
