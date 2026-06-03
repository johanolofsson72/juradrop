// Spec 013 T025 — deterministic fixture generator.
//
// Produces every committed test fixture from authored Swedish content:
//   - 6 cross-format extraction probes (docx/pdf/md/rtf/odt; txt is the
//     hand-written source of truth) all carrying the SAME canonical
//     paragraph (FR-009 / FR-010).
//   - 9 zone-representative documents (FR-007), personal-data ones
//     carrying the `[TESTDATA — fiktiva uppgifter]` marker (FR-008).
//
// Run once; commit the output:
//   cd src-tauri && cargo run --example generate_fixtures
//
// The generator SELF-VERIFIES each probe by round-tripping it back
// through the production extractor and asserting equality with the
// canonical text — so a broken fixture fails loudly here, never in CI.
//
// No network, no randomness — fully deterministic.

use std::fs;
use std::io::{Cursor, Write};
use std::path::{Path, PathBuf};

use docx_rs::{Docx, Paragraph, Run};
use juradrop_lib::zones::extract::extract_text;
use juradrop_lib::zones::input_format::InputFormat;

fn fixtures_dir() -> PathBuf {
    // Run from src-tauri/; fixtures live under tests/fixtures/.
    PathBuf::from("tests/fixtures")
}

fn main() {
    let probe_dir = fixtures_dir().join("extraction-probe");
    let docs_dir = fixtures_dir().join("documents");
    fs::create_dir_all(&probe_dir).expect("mkdir probe");
    fs::create_dir_all(&docs_dir).expect("mkdir documents");

    // --- Canonical probe text: the .txt fixture is the source of truth. ---
    let canonical = fs::read_to_string(probe_dir.join("extraction-probe.txt"))
        .expect("extraction-probe.txt must exist (hand-authored source of truth)");
    let canonical = canonical.trim_end_matches('\n').to_string();
    println!(
        "canonical ({} chars): {}",
        canonical.chars().count(),
        canonical
    );

    // --- Probe: DOCX ---
    write_docx(&probe_dir.join("extraction-probe.docx"), &[&canonical]);
    // --- Probe: MD (frontmatter + body; only body is extracted) ---
    fs::write(
        probe_dir.join("extraction-probe.md"),
        format!("---\ntitle: Prov\nlang: sv\n---\n\n{canonical}\n"),
    )
    .expect("write md");
    // --- Probe: RTF (cp1252 hex escapes for å ä ö) ---
    fs::write(
        probe_dir.join("extraction-probe.rtf"),
        rtf_document(&canonical),
    )
    .expect("write rtf");
    // --- Probe: ODT (zip bundle) ---
    write_odt(&probe_dir.join("extraction-probe.odt"), &canonical);
    // --- Probe: PDF (lopdf, Helvetica + WinAnsiEncoding) ---
    write_pdf(&probe_dir.join("extraction-probe.pdf"), &canonical);

    // --- Self-verify every probe round-trips to the canonical text. ---
    verify_probe(&probe_dir, "docx", InputFormat::Docx, &canonical);
    verify_probe(&probe_dir, "pdf", InputFormat::Pdf, &canonical);
    verify_probe(&probe_dir, "txt", InputFormat::Txt, &canonical);
    verify_probe(&probe_dir, "md", InputFormat::Md, &canonical);
    verify_probe(&probe_dir, "rtf", InputFormat::Rtf, &canonical);
    verify_probe(&probe_dir, "odt", InputFormat::Odt, &canonical);

    // --- Zone-representative documents (FR-007). ---
    write_docx(
        &docs_dir.join("sammanfatta-input.docx"),
        &sammanfatta_text(),
    );
    write_docx(
        &docs_dir.join("tillengelska-input.docx"),
        &tillengelska_text(),
    );
    write_docx(
        &docs_dir.join("tillsvenska-input.docx"),
        &tillsvenska_text(),
    );
    write_docx(&docs_dir.join("punktlista-input.docx"), &punktlista_text());
    let anon = anonymisera_text();
    write_docx(&docs_dir.join("anonymisera-input.docx"), &anon);
    write_docx(&docs_dir.join("forenkla-input.docx"), &forenkla_text());
    // FR-007 — Kontakter REUSES the anonymisera content (has every contact type).
    write_docx(&docs_dir.join("kontakter-input.docx"), &anon);
    write_docx(&docs_dir.join("kallor-input.docx"), &kallor_text());
    // Spec 036 — study-method zone inputs.
    write_docx(
        &docs_dir.join("identifiera-input.docx"),
        &identifiera_text(),
    );
    write_docx(
        &docs_dir.join("strukturera-input.docx"),
        &strukturera_text(),
    );
    write_docx(&docs_dir.join("forklara-input.docx"), &forklara_text());
    // Generera takes a .txt instruction/outline.
    fs::write(docs_dir.join("generera-input.txt"), generera_text()).expect("write generera txt");

    println!("\nAll fixtures generated + verified OK.");
}

// ---------- format writers ----------

fn write_docx(path: &Path, paragraphs: &[&str]) {
    let mut doc = Docx::new();
    for p in paragraphs {
        doc = doc.add_paragraph(Paragraph::new().add_run(Run::new().add_text(*p)));
    }
    let mut bytes: Vec<u8> = Vec::new();
    doc.build()
        .pack(Cursor::new(&mut bytes))
        .expect("pack docx");
    fs::write(path, &bytes).unwrap_or_else(|e| panic!("write {path:?}: {e}"));
}

/// RTF document with cp1252 hex escapes (`\'XX`) for non-ASCII. All
/// Swedish characters (å ä ö Å Ä Ö é etc.) live in cp1252, so this is
/// lossless for the fixture content.
fn rtf_document(text: &str) -> String {
    let mut body = String::new();
    for ch in text.chars() {
        match ch {
            '\\' => body.push_str("\\\\"),
            '{' => body.push_str("\\{"),
            '}' => body.push_str("\\}"),
            c if (c as u32) < 0x80 => body.push(c),
            c => {
                if let Some(b) = cp1252_byte(c) {
                    body.push_str(&format!("\\'{b:02x}"));
                } else {
                    // Outside cp1252 — fall back to a unicode escape.
                    body.push_str(&format!("\\u{}?", c as u32));
                }
            }
        }
    }
    format!("{{\\rtf1\\ansi\\ansicpg1252\\deff0{{\\fonttbl{{\\f0\\fswiss Helvetica;}}}}\\pard\\f0 {body}\\par}}")
}

fn cp1252_byte(c: char) -> Option<u8> {
    // Latin-1 range maps 1:1 to cp1252 for the chars we use.
    let u = c as u32;
    if (0xA0..=0xFF).contains(&u) {
        Some(u as u8)
    } else {
        None
    }
}

/// Minimal ODT: a zip with `mimetype` (stored, first), `content.xml`,
/// and `META-INF/manifest.xml`.
fn write_odt(path: &Path, text: &str) {
    use zip::write::FileOptions;
    use zip::CompressionMethod;

    let escaped = xml_escape(text);
    let content_xml = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
<office:document-content \
xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" \
xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\">\
<office:body><office:text><text:p>{escaped}</text:p></office:text></office:body>\
</office:document-content>"
    );
    let manifest = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.2\">\
<manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"application/vnd.oasis.opendocument.text\"/>\
<manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/>\
</manifest:manifest>";

    let mut buf: Vec<u8> = Vec::new();
    {
        let mut zw = zip::ZipWriter::new(Cursor::new(&mut buf));
        // mimetype MUST be first + stored (uncompressed) per ODF spec.
        zw.start_file(
            "mimetype",
            FileOptions::default().compression_method(CompressionMethod::Stored),
        )
        .unwrap();
        zw.write_all(b"application/vnd.oasis.opendocument.text")
            .unwrap();
        let deflated = FileOptions::default().compression_method(CompressionMethod::Deflated);
        zw.start_file("content.xml", deflated).unwrap();
        zw.write_all(content_xml.as_bytes()).unwrap();
        zw.start_file("META-INF/manifest.xml", deflated).unwrap();
        zw.write_all(manifest.as_bytes()).unwrap();
        zw.finish().unwrap();
    }
    fs::write(path, &buf).unwrap_or_else(|e| panic!("write {path:?}: {e}"));
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// Minimal single-page PDF with a Helvetica/WinAnsiEncoding text object.
fn write_pdf(path: &Path, text: &str) {
    use lopdf::{dictionary, Document, Object, Stream};

    let mut doc = Document::with_version("1.5");
    let font_id = doc.add_object(dictionary! {
        "Type" => "Font",
        "Subtype" => "Type1",
        "BaseFont" => "Helvetica",
        "Encoding" => "WinAnsiEncoding",
    });
    let resources_id = doc.add_object(dictionary! {
        "Font" => dictionary! { "F1" => font_id },
    });

    // Content stream: one Tj with the whole paragraph (visual overflow is
    // irrelevant — pdf-extract reads the text operands, not the layout).
    let escaped = pdf_winansi_escape(text);
    let stream = format!("BT\n/F1 12 Tf\n72 760 Td\n({escaped}) Tj\nET");
    let content_id = doc.add_object(Stream::new(dictionary! {}, stream.into_bytes()));

    let page_id = doc.add_object(dictionary! {
        "Type" => "Page",
        "Contents" => content_id,
        "Resources" => resources_id,
        "MediaBox" => vec![0.into(), 0.into(), 612.into(), 792.into()],
    });
    let pages_id = doc.add_object(dictionary! {
        "Type" => "Pages",
        "Kids" => vec![page_id.into()],
        "Count" => 1,
    });
    if let Ok(Object::Dictionary(d)) = doc.get_object_mut(page_id) {
        d.set("Parent", pages_id);
    }
    let catalog_id = doc.add_object(dictionary! {
        "Type" => "Catalog",
        "Pages" => pages_id,
    });
    doc.trailer.set("Root", catalog_id);

    let mut buf: Vec<u8> = Vec::new();
    doc.save_to(&mut Cursor::new(&mut buf)).expect("save pdf");
    fs::write(path, &buf).unwrap_or_else(|e| panic!("write {path:?}: {e}"));
}

/// Escape a string for a PDF literal string with WinAnsiEncoding: ( ) \
/// get backslash-escaped; non-ASCII (Latin-1 range) becomes an octal byte.
fn pdf_winansi_escape(s: &str) -> String {
    let mut out = String::new();
    for ch in s.chars() {
        match ch {
            '(' => out.push_str("\\("),
            ')' => out.push_str("\\)"),
            '\\' => out.push_str("\\\\"),
            c if (c as u32) < 0x80 => out.push(c),
            c if (c as u32) <= 0xFF => out.push_str(&format!("\\{:03o}", c as u32)),
            c => out.push_str(&format!("\\{:03o}", (c as u32) & 0xFF)),
        }
    }
    out
}

// ---------- verification ----------

fn verify_probe(dir: &Path, ext: &str, fmt: InputFormat, canonical: &str) {
    let path = dir.join(format!("extraction-probe.{ext}"));
    let extracted =
        extract_text(&path, fmt).unwrap_or_else(|e| panic!("{ext}: extraction failed: {e:?}"));
    let got = normalize(extracted.raw.as_inner());
    let want = normalize(canonical);
    assert!(
        got == want || got.contains(&want),
        "{ext}: extracted text != canonical.\n got: {got:?}\nwant: {want:?}"
    );
    println!("  ✓ {ext} round-trips to canonical");
}

/// Whitespace-insensitive comparison (PDF/RTF extraction inserts spacing
/// variation; per US2 acceptance scenario 2 a normalized compare is used).
fn normalize(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

// ---------- authored Swedish fixture content ----------

const TESTDATA: &str = "[TESTDATA — fiktiva uppgifter]";

fn sammanfatta_text() -> Vec<&'static str> {
    vec![
        "Dom i tvistemål T 4521-25, meddelad av Solna tingsrätt den 3 februari 2026.",
        "Bakgrund: Käranden yrkade att svaranden skulle förpliktas att betala 84 000 kronor jämte ränta för utebliven betalning av utfört hantverksarbete. Svaranden bestred käromålet och invände att arbetet utförts felaktigt och att avtalat pris aldrig hade överenskommits.",
        "Domskäl: Tingsrätten konstaterar inledningsvis att ett bindande avtal om arbetets utförande har förelegat mellan parterna. Av utredningen framgår att käranden utfört det arbete som beställts, men att vissa brister förekommit i utförandet. Rätten finner att svaranden har rätt till ett prisavdrag motsvarande kostnaden för att avhjälpa bristerna, vilken uppskattas till 12 000 kronor.",
        "Domslut: Svaranden förpliktas att till käranden betala 72 000 kronor jämte ränta enligt 6 § räntelagen från den 1 oktober 2025 till dess betalning sker. Vardera parten ska stå sin egen rättegångskostnad.",
    ]
}

fn tillengelska_text() -> Vec<&'static str> {
    vec![
        "Avtal om upplåtelse av bostadsrätt.",
        "Säljaren överlåter härmed till köparen bostadsrätten till lägenheten nummer 142 i bostadsrättsföreningen Eken i Uppsala. Överlåtelsen sker mot en köpeskilling om 2 950 000 kronor.",
        "Tillträde sker den 1 september 2026. Köparen svarar från tillträdesdagen för samtliga avgifter till föreningen. Säljaren garanterar att lägenheten på tillträdesdagen inte belastas av andra skulder än de som framgår av föreningens lägenhetsförteckning.",
        "Tvist med anledning av detta avtal ska i första hand lösas genom förhandling mellan parterna. Om enighet inte kan nås avgörs tvisten av allmän domstol med tingsrätten som första instans.",
    ]
}

fn tillsvenska_text() -> Vec<&'static str> {
    // The ONLY non-Swedish fixture (English contract for translation).
    vec![
        "Mutual Non-Disclosure Agreement.",
        "This Agreement is entered into between the Disclosing Party and the Receiving Party for the purpose of preventing the unauthorised disclosure of Confidential Information. The parties agree to enter into a confidential relationship concerning the disclosure of certain proprietary and confidential information.",
        "The Receiving Party shall hold and maintain the Confidential Information in strictest confidence for the sole and exclusive benefit of the Disclosing Party. The Receiving Party shall not, without prior written approval, use the Confidential Information for any purpose except to evaluate the potential business relationship between the parties.",
        "This Agreement shall remain in effect for a period of three years from the date of execution. Any dispute arising out of this Agreement shall be governed by the laws of Sweden.",
    ]
}

fn punktlista_text() -> Vec<&'static str> {
    vec![
        "Promemoria: iakttagelser inför styrelsemötet den 20 maj 2026.",
        "Föreningens ekonomi är fortsatt stabil men kassaflödet har försämrats under det första kvartalet på grund av ökade uppvärmningskostnader. Underhållsplanen behöver revideras eftersom fasadrenoveringen blivit dyrare än budgeterat. Två leverantörsavtal löper ut under hösten och bör omförhandlas i god tid.",
        "Vidare har tre medlemmar inkommit med klagomål rörande bristande ventilation i trapphus B. En extern besiktning rekommenderas före sommaren. Slutligen noteras att försäkringspremien höjs med åtta procent vid förnyelsen, vilket bör beaktas i nästa års budget.",
        "Frågan om laddstolpar för elbilar har åter aktualiserats och kräver ett principbeslut innan offerter kan begäras in.",
    ]
}

fn anonymisera_text() -> Vec<&'static str> {
    // Personal data is OBVIOUSLY fake (FR-008 / edge case): personnummer
    // use the reserved 19010101-0101 form. Marker on the first line.
    vec![
        TESTDATA,
        "Klientärende: arvstvist efter avliden anhörig.",
        "Klienten Anna Andersson, personnummer 19010101-0101, bosatt på Storgatan 1, 111 22 Stockholm, har kontaktat byrån angående en tvist om arvskifte. Hon nås på telefon 070-123 45 67 och e-post anna.andersson@example.se.",
        "Motpart i ärendet är Bertil Bengtsson, personnummer 19020202-0202, med adress Kungsvägen 14, 222 33 Göteborg. Bengtsson företräds av ombudet Cecilia Carlsson, som kan nås på telefon 08-987 65 43 och e-post cecilia.carlsson@advokat.example.se.",
        "Den avlidne, David Davidsson, efterlämnade en bostadsrätt på Strandvägen 7 i Stockholm samt banktillgångar om cirka 1,2 miljoner kronor. Bouppteckning förrättades den 12 januari 2026.",
    ]
}

fn forenkla_text() -> Vec<&'static str> {
    vec![
        "Information om handläggning av ärende enligt förvaltningslagen.",
        "Med anledning av Eder till myndigheten inkomna ansökan får härmed meddelas att ärendet upptagits till handläggning och att beslut i frågan kommer att fattas så snart erforderligt underlag inkommit. För den händelse att kompletterande handlingar bedöms nödvändiga kommer sådana att infordras, varvid Eder beredes tillfälle att inom angiven frist inkomma med yttrande.",
        "Det åligger sökanden att tillse att samtliga för ärendets avgörande relevanta omständigheter bringas till myndighetens kännedom. Underlåtenhet härvidlag kan föranleda att ärendet avgörs på befintligt underlag, vilket icke utesluter att ansökan helt eller delvis lämnas utan bifall.",
    ]
}

fn kallor_text() -> Vec<&'static str> {
    vec![
        "Rättsutredning: skadeståndsansvar vid offentlig upphandling.",
        "Frågan om en upphandlande myndighets skadeståndsansvar regleras främst i lagen (2016:1145) om offentlig upphandling. Av 20 kap. framgår förutsättningarna för ogiltighet och skadestånd.",
        "Källor som ligger till grund för utredningen:",
        "1. Lag (2016:1145) om offentlig upphandling. 2. Prop. 2015/16:195 Nytt regelverk om upphandling. 3. NJA 2013 s. 762. 4. NJA 2016 s. 358. 5. RÅ 2009 ref. 69. 6. EU-direktiv 2014/24/EU om offentlig upphandling. 7. Sundstrand, Andrea, Offentlig upphandling — en introduktion, 3 uppl., Studentlitteratur 2019. 8. Asplund m.fl., Överprövning av upphandling, Jure 2012. 9. HFD 2018 ref. 28. 10. Kammarrätten i Stockholm, mål nr 1425-20.",
        "Sammantaget talar rättskällorna för att skadestånd förutsätter att överträdelsen av upphandlingsreglerna varit klar och att ett orsakssamband mellan felet och skadan kan styrkas.",
    ]
}

// Spec 036 — study-method zone inputs.

fn identifiera_text() -> Vec<&'static str> {
    // A PM raising more than one legal issue (köprätt + skadestånd) so the
    // zone has real rättsfrågor to spot.
    vec![
        "PM: tvist om begagnad bil och en hund som bitit en granne.",
        "Anna köpte en begagnad bil av Bertil för 80 000 kr. Vid köpet sa Bertil att bilen \"gick utan problem\". Två veckor senare havererade växellådan. Anna vill häva köpet eller få prisavdrag. Bertil menar att bilen såldes i befintligt skick och att han inte kände till felet.",
        "Samtidigt har Annas hund sprungit lös och bitit grannen Cecilia, som nu kräver skadestånd för sjukvårdskostnader och sveda och värk. Anna hävdar att Cecilia retade hunden.",
        "Uppgiften gäller både köpet av bilen och ansvaret för hunden.",
    ]
}

fn strukturera_text() -> Vec<&'static str> {
    // An unstructured student draft answer, to be reshaped into IRAC.
    vec![
        "Mitt svar (utkast):",
        "Jag tror att det handlar om fel i vara enligt köplagen. Bertil sa att bilen gick utan problem men växellådan gick sönder. Befintligt skick spelar roll, men en säljare kan ändå bli ansvarig om han lämnat en utfästelse. Bertil sa ju att den gick utan problem, det kan vara en utfästelse.",
        "Att bilen gick sönder efter två veckor talar för att felet fanns redan vid köpet. Anna borde kunna få prisavdrag, kanske häva om felet är väsentligt. Hon måste reklamera i tid.",
        "Slutsatsen blir nog att Anna har rätt till prisavdrag, men det beror på om utfästelsen och väsentligheten är uppfyllda.",
    ]
}

fn forklara_text() -> Vec<&'static str> {
    // A jargon-dense doctrine excerpt with terms to explain in plain Swedish.
    vec![
        "Utdrag ur doktrin om skadestånds- och avtalsrätt.",
        "För skadeståndsansvar i utomobligatoriska förhållanden krävs i regel culpa. Bedömningen sker genom en culpabedömning, där domstolen prövar om handlandet avvikit från en aktsamhetsnorm. Ett centralt rekvisit är adekvat kausalitet mellan handlingen och skadan.",
        "Vid subsumtionen ställs de konstaterade omständigheterna mot rekvisiten i den tillämpliga normen. Är en bestämmelse dispositiv kan parterna avtala bort den; en indispositiv (tvingande) regel kan de inte avtala bort. Jämkning innebär att ett ansvar eller ett avtalsvillkor sätts ned efter en skälighetsbedömning.",
    ]
}

fn generera_text() -> String {
    // .txt instruction/outline (FR-007). Carries fictitious personal data,
    // so it gets the TESTDATA marker too.
    format!(
        "{TESTDATA}\n\
Skapa en uppsägning av hyreskontrakt enligt 12 kap. jordabalken.\n\
- Hyresgäst: Anna Andersson, Storgatan 1, 111 22 Stockholm\n\
- Hyresvärd: Fastighets AB Eken, org.nr 556000-0000\n\
- Objekt: lägenhet om 2 rok på Storgatan 1\n\
- Grund: uppsägning för villkorsändring\n\
- Avflyttningsdatum: 2026-09-30\n\
- Ange uppsägningstid och hänvisa till relevant lagrum\n\
- Avsluta med datum och plats för underskrift\n"
    )
}
