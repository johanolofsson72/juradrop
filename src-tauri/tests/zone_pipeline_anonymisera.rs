// Spec 013 US1 / FR-011 — Anonymisera zone end-to-end on a real fixture.
// US1 acceptance scenario 1: names/personnummer/addresses replaced with
// placeholders. Disclaimer presence checked by the harness.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn anonymisera_pipeline_writes_sidecar_with_placeholders() {
    // Clean model output (all placeholders) — spec 014 SC-002: no warning
    // paragraph is added, only the placeholders + static disclaimer.
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

// Spec 014 SC-001 — the model leaves a residual personnummer in the output;
// the sweep MUST surface it in a Swedish warning paragraph in the sidecar.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn anonymisera_residual_personnummer_triggers_warning() {
    common::run_zone_pipeline(
        ZoneId::Anonymisera,
        "anonymisera-input.docx",
        "Klienten [Person 1] men personnummer 19010101-0101 står kvar i texten.",
        &[
            "Automatisk kontroll hittade möjlig kvarvarande information",
            "1 personnummer",
            "Granska och ta bort manuellt",
        ],
    )
    .await;
}

// Spec 045 SC-004 — the model echoes/fabricates a raw postnummer in the
// output; the sweep MUST count it AND frame it as a possible address line.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn anonymisera_residual_postnummer_triggers_address_anchor() {
    common::run_zone_pipeline(
        ZoneId::Anonymisera,
        "anonymisera-input.docx",
        "Klienten [Person 1] bor kvar på adressen 114 35 i texten.",
        &[
            "Automatisk kontroll hittade möjlig kvarvarande information",
            "1 postnummer",
            "adressraden",
        ],
    )
    .await;
}
