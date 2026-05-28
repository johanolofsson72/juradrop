// Spec 013 US1 / FR-011 — Källförteckning zone end-to-end on a real fixture.
// US1 acceptance scenario 3: numbered, consistently formatted citation list.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn kallor_pipeline_writes_numbered_citation_list() {
    common::run_zone_pipeline(
        ZoneId::Kallor,
        "kallor-input.docx",
        "Källförteckning\n\
         1. Lag (2016:1145) om offentlig upphandling.\n\
         2. Prop. 2015/16:195.\n\
         3. NJA 2013 s. 762.\n\
         4. NJA 2016 s. 358.\n\
         5. EU-direktiv 2014/24/EU.",
        &["Källförteckning", "NJA 2013 s. 762"],
    )
    .await;
}
