// Spec 013 US1 / FR-011 — Plocka ut kontaktuppgifter zone end-to-end.
// US1 acceptance scenario 2: all 5 contact-type categories listed.
mod common;
use juradrop_lib::zones::ZoneId;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn kontakter_pipeline_lists_contact_categories() {
    common::run_zone_pipeline(
        ZoneId::Kontakter,
        "kontakter-input.docx",
        "Namn: Anna Andersson; Bertil Bengtsson.\n\
         Adress: Storgatan 1, Stockholm; Kungsvägen 14, Göteborg.\n\
         Personnummer: 19010101-0101; 19020202-0202.\n\
         Telefonnummer: 070-123 45 67; 08-987 65 43.\n\
         E-post: anna.andersson@example.se; cecilia.carlsson@advokat.example.se.",
        &["Namn", "Adress", "Personnummer", "Telefonnummer", "E-post"],
    )
    .await;
}
