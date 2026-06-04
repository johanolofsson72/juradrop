// Spec 013 US1 / FR-011 — Plocka ut kontaktuppgifter zone end-to-end.
// Spec 040 — output regrouped per PERSON: one `## ` section per person
// with category-labeled bullets; unattributable details under a final
// "## Övriga uppgifter" section.
mod common;
use juradrop_lib::zones::ZoneId;

// Spec 040 US1 (T004): per-person sections with labeled details survive
// to the sidecar; no per-category grouping headings remain.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn kontakter_pipeline_groups_details_per_person() {
    common::run_zone_pipeline_checked(
        ZoneId::Kontakter,
        "kontakter-input.docx",
        "## Anna Andersson\n\n\
         - Adress: Storgatan 1, Stockholm\n\
         - Personnummer: 19010101-0101\n\
         - Telefon: 070-123 45 67\n\
         - E-post: anna.andersson@example.se\n\n\
         ## Bertil Bengtsson\n\n\
         - Adress: Kungsvägen 14, Göteborg\n\
         - Personnummer: 19020202-0202\n\n\
         ## Övriga uppgifter\n\n\
         - Telefon: 08-987 65 43",
        &[
            "## Anna Andersson",
            "## Bertil Bengtsson",
            "## Övriga uppgifter",
            // NOTE: the .docx writer renders "- " bullets as list items and
            // re-extraction drops the dash, so markers omit the prefix.
            "Adress: Storgatan 1, Stockholm",
            "Telefon: 070-123 45 67",
            "E-post: anna.andersson@example.se",
            "Personnummer: 19020202-0202",
            "Telefon: 08-987 65 43",
        ],
        // Spec 040 SC-001: no per-category grouping headings in the output.
        &[
            "## Namn",
            "## Adresser",
            "## Personnummer",
            "## Telefonnummer",
            "## E-post",
        ],
    )
    .await;
}

// Spec 040 US2/FR-012 (T005, analyze G1): the single-part path is a
// byte-order pass-through — a model output where "## Övriga uppgifter"
// is deliberately NOT last must reach the sidecar in the model's order,
// proving no reordering/normalization runs outside the multi-part
// combine step (where Övriga-last IS guaranteed deterministically).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn kontakter_single_part_preserves_model_section_order() {
    let sidecar = common::run_zone_pipeline_checked(
        ZoneId::Kontakter,
        "kontakter-input.docx",
        "## Övriga uppgifter\n\n\
         - Telefon: 046-222 00 00\n\n\
         ## Cecilia Carlsson\n\n\
         - E-post: cecilia.carlsson@advokat.example.se",
        &[
            "## Övriga uppgifter",
            "Telefon: 046-222 00 00",
            "## Cecilia Carlsson",
        ],
        &[],
    )
    .await;

    let ovriga = sidecar
        .find("## Övriga uppgifter")
        .expect("ovriga section present");
    let cecilia = sidecar
        .find("## Cecilia Carlsson")
        .expect("person section present");
    assert!(
        ovriga < cecilia,
        "single-part output must preserve the model's section order \
         (pass-through, FR-012) — got reordered sidecar:\n{sidecar}"
    );
}
