// Dev tool — generate a rich, well-organised manual-test corpus into
// ~/Desktop/juradrop-test/. NOT part of the build or test suite.
//
//   cargo run --example gen_testdocs
//
// Layout:
//   01-per-zon/   one rich document per drop zone (the happy paths)
//   02-format/    the same legal text in every supported input format
//   03-kantfall/  edge cases: empty, tiny, long (truncation), oversized,
//                 corrupt, and an unsupported .pages
//   LÄS-MIG.txt   what to drop where + what to expect

use std::fs;
use std::io::{Cursor, Write};
use std::path::{Path, PathBuf};

use docx_rs::{Docx, Paragraph, Run};

fn main() {
    let root = desktop().join("juradrop-test");
    let per_zon = root.join("01-per-zon");
    let format = root.join("02-format");
    let edge = root.join("03-kantfall");
    for d in [&per_zon, &format, &edge] {
        fs::create_dir_all(d).unwrap_or_else(|e| panic!("mkdir {d:?}: {e}"));
    }

    // ---- 01 per-zon (the happy paths) ----
    docx(&per_zon.join("01-sammanfatta-langt-domslut.docx"), &sammanfatta_doc());
    docx(&per_zon.join("02-till-engelska-avtal.docx"), &till_engelska_doc());
    docx(&per_zon.join("03-till-svenska-english-contract.docx"), &till_svenska_doc());
    docx(&per_zon.join("04-punktlista-styrelseprotokoll.docx"), &punktlista_doc());
    docx(&per_zon.join("05-anonymisera-stamningsansokan.docx"), &anonymisera_doc());
    docx(&per_zon.join("06-forenkla-myndighetstext.docx"), &forenkla_doc());
    docx(&per_zon.join("07-kontakter-arendelista.docx"), &kontakter_doc());
    fs::write(per_zon.join("08-generera-instruktion.txt"), generera_txt()).unwrap();
    docx(&per_zon.join("09-kallforteckning-rattsutredning.docx"), &kallor_doc());
    docx(&per_zon.join("10-identifiera-rattsfragor-pm.docx"), &identifiera_doc());
    docx(&per_zon.join("11-strukturera-irac-studentsvar.docx"), &strukturera_doc());
    docx(&per_zon.join("12-forklara-begrepp-doktrin.docx"), &forklara_doc());

    // ---- 02 format coverage (same text, every format) ----
    // .docx + .txt + .md written here; .pdf/.rtf/.odt copied from the repo's
    // extraction probes (already valid in those formats).
    docx(&format.join("samma-text.docx"), &format_sample());
    fs::write(format.join("samma-text.txt"), format_sample().join("\n\n")).unwrap();
    fs::write(
        format.join("samma-text.md"),
        format!(
            "---\ntitel: Formattest\n---\n\n# Formattest\n\n{}\n",
            format_sample().join("\n\n")
        ),
    )
    .unwrap();
    copy_probe(&format);

    // ---- 03 edge cases ----
    docx(&edge.join("tom.docx"), &[]); // empty body → "ingen text att läsa"
    fs::write(edge.join("mycket-kort.txt"), "Hej.").unwrap();
    // > 24 000 tecken → trunkeringsnotis i resultatet.
    let long = "Detta är en lång mening som upprepas för att överstiga trunkeringsgränsen på tjugofyratusen tecken så att appen visar sin svenska trunkeringsnotis. ".repeat(220);
    fs::write(edge.join("mycket-langt.txt"), &long).unwrap();
    // Unsupported .pages — appen ska ge en ärlig uppmaning att exportera först.
    fs::write(
        edge.join("svensk.pages"),
        b"PK\x03\x04 (fejkad Pages-fil for att testa det artiga felmeddelandet)",
    )
    .unwrap();
    // Skadad .docx — ogiltiga bytes med .docx-ändelse → parse-fel.
    fs::write(edge.join("skadad.docx"), b"Det har ar INTE en giltig docx-fil.").unwrap();
    // > 50 MB → "filen är för stor"-felet (skrivs som 51 MB 'a').
    {
        let mut f = fs::File::create(edge.join("for-stor.txt")).unwrap();
        let chunk = vec![b'a'; 1024 * 1024]; // 1 MB
        for _ in 0..51 {
            f.write_all(&chunk).unwrap();
        }
    }

    fs::write(root.join("LÄS-MIG.txt"), readme()).unwrap();

    println!("Testunderlag genererat i {}", root.display());
    println!("  01-per-zon/   12 dokument (ett per zon)");
    println!("  02-format/    samma text i .docx/.pdf/.txt/.md/.rtf/.odt");
    println!("  03-kantfall/  tom, kort, långt (trunkering), .pages, skadad, för stor");
    println!("  LÄS-MIG.txt   vad du släpper var");
}

fn desktop() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join("Desktop")
}

fn docx(path: &Path, paragraphs: &[&str]) {
    let mut doc = Docx::new();
    for p in paragraphs {
        doc = doc.add_paragraph(Paragraph::new().add_run(Run::new().add_text(*p)));
    }
    let mut bytes: Vec<u8> = Vec::new();
    doc.build().pack(Cursor::new(&mut bytes)).expect("pack docx");
    fs::write(path, &bytes).unwrap_or_else(|e| panic!("write {path:?}: {e}"));
}

fn copy_probe(dest: &Path) {
    let probe = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/extraction-probe");
    for (src, dst) in [
        ("extraction-probe.pdf", "samma-text.pdf"),
        ("extraction-probe.rtf", "samma-text.rtf"),
        ("extraction-probe.odt", "samma-text.odt"),
    ] {
        let from = probe.join(src);
        if from.exists() {
            let _ = fs::copy(&from, dest.join(dst));
        }
    }
}

// ---------- content (rikt, realistiskt svenskt juridiskt innehåll) ----------

fn sammanfatta_doc() -> Vec<&'static str> {
    vec![
        "DOM — Stockholms tingsrätt, mål nr T 4521-25",
        "PARTER. Kärande: Hantverksbolaget Eken AB. Svarande: Anna Andersson.",
        "BAKGRUND. Käranden utförde under hösten 2024 renoveringsarbeten i svarandens bostad enligt ett muntligt avtal. Parterna är oense om huruvida ett fast pris avtalades eller om arbetet skulle utföras på löpande räkning. Käranden har fakturerat 187 000 kr, varav svaranden betalat 90 000 kr.",
        "YRKANDEN. Käranden har yrkat att tingsrätten ska förplikta svaranden att betala 97 000 kr jämte dröjsmålsränta. Svaranden har bestritt yrkandet och i andra hand gjort gällande att priset är oskäligt och ska jämkas.",
        "DOMSKÄL. Tingsrätten konstaterar inledningsvis att bevisbördan för att ett fast pris avtalats åvilar svaranden. Av utredningen framgår att någon skriftlig prisuppgift inte lämnats. Vittnet Bertil Bengtsson har uppgett att han hörde parterna tala om 'ungefär hundra tusen', men tingsrätten finner att detta uttalande är för obestämt för att utgöra ett bindande fast pris. Arbetet ska därför anses ha utförts på löpande räkning.",
        "Vad gäller frågan om priset är skäligt har käranden lagt fram tidrapporter och materialspecifikationer. Svaranden har inte lyckats visa att den nedlagda tiden varit oskäligt hög. Tingsrätten finner att det fordrade priset är skäligt.",
        "DOMSLUT. Anna Andersson ska till Hantverksbolaget Eken AB betala 97 000 kr jämte ränta enligt 6 § räntelagen från den 1 december 2024 till dess betalning sker. Anna Andersson ska ersätta kärandens rättegångskostnader med 42 000 kr.",
    ]
}

fn till_engelska_doc() -> Vec<&'static str> {
    vec![
        "Avtalsklausul — Ansvarsbegränsning",
        "Leverantörens sammanlagda ansvar för skada som uppkommer i anledning av detta avtal är begränsat till ett belopp motsvarande den ersättning som beställaren erlagt under de tolv månader som föregått den skadegörande händelsen.",
        "Ansvarsbegränsningen gäller inte vid uppsåt eller grov vårdslöshet, och inte heller vid sådan skada som enligt tvingande lag inte får begränsas.",
        "Part är befriad från ansvar för underlåtenhet att fullgöra viss förpliktelse om underlåtenheten beror på en omständighet utanför partens kontroll (force majeure) som parten inte skäligen kunde förväntas ha räknat med.",
    ]
}

fn till_svenska_doc() -> Vec<&'static str> {
    vec![
        "Confidentiality Undertaking",
        "Each party undertakes to keep confidential all information disclosed to it by the other party in connection with this Agreement and designated as confidential or which a reasonable person would understand to be confidential.",
        "The receiving party shall not use the confidential information for any purpose other than the performance of its obligations under this Agreement, and shall not disclose it to any third party without the prior written consent of the disclosing party.",
        "This undertaking shall survive the termination of the Agreement for a period of five (5) years.",
    ]
}

fn punktlista_doc() -> Vec<&'static str> {
    vec![
        "Styrelseprotokoll — Bostadsrättsföreningen Almen, sammanträde 2025-04-14",
        "Vid dagens styrelsemöte behandlades föreningens ekonomi, underhåll och ett antal medlemsärenden. Närvarande var samtliga fem ledamöter samt en suppleant.",
        "Kassaflödet har försämrats under första kvartalet jämfört med budget, främst på grund av ökade uppvärmningskostnader. Underhållsplanen behöver revideras eftersom takomläggningen tidigarelagts till hösten 2025. Två av föreningens tre leverantörsavtal löper ut vid årsskiftet och bör omförhandlas. Flera medlemmar har klagat på bristande ventilation i trapphus B. Avgiften föreslås höjas med två procent från och med januari 2026. Den planerade stamrenoveringen skjuts upp i avvaktan på en oberoende besiktning.",
        "Styrelsen beslutade att uppdra åt ordföranden att inhämta tre offerter på takarbetet och att kalla till en extra föreningsstämma om avgiftshöjningen.",
    ]
}

fn anonymisera_doc() -> Vec<&'static str> {
    vec![
        "STÄMNINGSANSÖKAN",
        "Kärande: Anna Margareta Andersson, 19850312-1234, Storgatan 14 B, 111 22 Stockholm, telefon 070-123 45 67, e-post anna.andersson@exempel.se.",
        "Svarande: Bertil Erik Bengtsson, 19790824-5678, Kungsvägen 3, 222 33 Lund, telefon 046-12 34 56, e-post bertil.bengtsson@firma.exempel.se.",
        "Ombud för käranden: advokat Cecilia Carlsson, Advokatfirman Lindqvist & Partners, Drottninggatan 1, 411 14 Göteborg, telefon 031-700 00 00, e-post cecilia.carlsson@lindqvist.exempel.se.",
        "Saken gäller en obetald faktura om 48 500 kr avseende konsulttjänster som Anna Andersson utfört åt Bertil Bengtsson under perioden januari–mars 2025. Trots upprepade påminnelser, senast den 4 april 2025, har Bengtsson inte erlagt betalning.",
        "Anna Andersson yrkar att tingsrätten förpliktar Bertil Bengtsson att betala 48 500 kr jämte dröjsmålsränta samt att ersätta hennes rättegångskostnader.",
    ]
}

fn forenkla_doc() -> Vec<&'static str> {
    vec![
        "Underrättelse enligt 12 kap. 44 § jordabalken",
        "Med anledning av att hyresgästen vid upprepade tillfällen åsidosatt sina förpliktelser enligt hyresavtalet, närmare bestämt genom att icke erlägga hyra inom föreskriven tid, underrättas härmed hyresgästen om att hyresrätten är förverkad och att hyresvärden äger rätt att säga upp avtalet till omedelbart upphörande.",
        "Hyresgästen erinras dock om att hyresrätten icke är förverkad om det som ligger hyresgästen till last är av ringa betydelse, samt om att hyresgästen, för det fall att betalning av förfallen hyra sker inom tre veckor från det att hyresgästen delgivits underrättelse om uppsägningen jämte anmodan att vidta rättelse, äger rätt att återvinna hyresrätten.",
        "För det fall rättelse icke vidtages inom angiven frist kommer hyresvärden att hos Kronofogdemyndigheten ansöka om avhysning.",
    ]
}

fn kontakter_doc() -> Vec<&'static str> {
    vec![
        "Ärendelista — parter och ombud i mål T 1099-25",
        "Käranden företräds av advokat David Dahl, Advokatbyrån Dahl AB, Vasagatan 10, 111 20 Stockholm, telefon 08-555 12 34, e-post david.dahl@dahl.exempel.se.",
        "Svaranden Erik Eriksson, personnummer 19660101-0099, bor på Lillgatan 5, 211 44 Malmö och nås på 040-98 76 54 samt erik.eriksson@exempel.se.",
        "Vittnet Fatima Farah kan kontaktas via sitt ombud, jurist Gustav Grön, Juristhuset i Uppsala, Sysslomansgatan 2, 753 11 Uppsala, telefon 018-10 20 30, e-post gustav.gron@juristhuset.exempel.se.",
        "Sakkunnig i målet är docent Helena Holm vid Lunds universitet, helena.holm@jur.lu.exempel.se, telefon 046-222 00 00.",
    ]
}

fn generera_txt() -> String {
    "Skriv ett utkast till en uppsägning av ett hyresavtal för en bostadslägenhet.\n\
- Hyresgäst: Anna Andersson\n\
- Hyresvärd: Fastighets AB Eken\n\
- Objekt: en tvåa på Storgatan 1 i Stockholm\n\
- Grund: hyresgästen säger själv upp avtalet för avflyttning\n\
- Uppsägningstiden är tre månader\n\
- Avtalet ska upphöra vid månadsskiftet efter uppsägningstidens slut\n\
- Avsluta med plats för ort, datum och underskrift\n"
        .to_string()
}

fn kallor_doc() -> Vec<&'static str> {
    vec![
        "Rättsutredning — skadeståndsansvar vid offentlig upphandling",
        "Frågan om en upphandlande myndighets skadeståndsansvar regleras främst i lagen (2016:1145) om offentlig upphandling. Av 20 kap. samma lag framgår förutsättningarna för ogiltighet och skadestånd. Förarbetena, särskilt prop. 2015/16:195, ger ledning för tolkningen.",
        "Av praxis kan nämnas NJA 2013 s. 762 och NJA 2016 s. 358, där Högsta domstolen behandlat orsakssamband och beräkning av det positiva kontraktsintresset. Även RÅ 2009 ref. 69 är av betydelse. EU-rätten, främst direktiv 2014/24/EU, utgör bakgrund.",
        "I doktrinen behandlas frågan av Sundstrand, Offentlig upphandling — en introduktion (3 uppl., Studentlitteratur 2019) samt av Asplund m.fl., Överprövning av upphandling (Jure 2012).",
        "Sammantaget talar rättskällorna för att skadestånd förutsätter att överträdelsen varit klar och att ett orsakssamband mellan felet och skadan kan styrkas.",
    ]
}

fn identifiera_doc() -> Vec<&'static str> {
    vec![
        "PM — praktikfall till seminariet i förmögenhetsrätt",
        "Anna köpte i mars 2025 en begagnad bil av Bertil för 80 000 kr. Vid köpet sa Bertil att bilen 'gick utan problem'. Två veckor senare havererade växellådan. En verkstad bedömer att felet fanns redan vid köpet. Anna vill häva köpet eller åtminstone få prisavdrag. Bertil invänder att bilen sålts i befintligt skick och att han inte kände till felet.",
        "Samtidigt har Annas hund, som sprang lös i strid med kopplingstvång, bitit grannen Cecilia. Cecilia kräver skadestånd för sjukvårdskostnader och sveda och värk. Anna menar att Cecilia retade hunden och själv var medvållande.",
        "Dessutom har Anna lånat ut 20 000 kr till sin vän David mot ett muntligt löfte om återbetalning 'när han fick råd'. David vägrar nu betala och påstår att det rörde sig om en gåva.",
        "Diskutera de rättsliga frågor som situationen ger upphov till.",
    ]
}

fn strukturera_doc() -> Vec<&'static str> {
    vec![
        "Mitt tentasvar (utkast — behöver struktureras)",
        "Jag tror att det här handlar om fel i vara enligt köplagen. Bertil sa att bilen gick utan problem men sen gick växellådan sönder efter två veckor. Befintligt skick spelar roll men säljaren kan ändå bli ansvarig om han lämnat en utfästelse, och att säga att den 'gick utan problem' kan nog vara en sådan utfästelse.",
        "Att bilen gick sönder så snabbt talar för att felet fanns redan vid köpet. Då borde Anna kunna få prisavdrag, och kanske häva om felet är väsentligt. Men hon måste reklamera i tid annars förlorar hon rätten.",
        "Slutsatsen blir nog att Anna har rätt till prisavdrag, men om hon får häva beror på om felet bedöms väsentligt och om utfästelsen anses bindande.",
    ]
}

fn forklara_doc() -> Vec<&'static str> {
    vec![
        "Utdrag ur doktrin — allmän skadestånds- och avtalsrätt",
        "För skadeståndsansvar i utomobligatoriska förhållanden krävs i regel culpa. Bedömningen sker genom en culpabedömning där domstolen prövar om handlandet avvikit från en aktsamhetsnorm. Ett centralt rekvisit är adekvat kausalitet mellan handlingen och skadan; alltför avlägsna eller atypiska följder ersätts inte.",
        "Vid subsumtionen ställs de konstaterade omständigheterna mot rekvisiten i den tillämpliga normen. Är en bestämmelse dispositiv kan parterna avtala bort den, medan en indispositiv (tvingande) regel inte kan avtalas bort. Begreppet jämkning innebär att ett ansvar eller ett avtalsvillkor sätts ned efter en skälighetsbedömning, exempelvis med stöd av generalklausulen i 36 § avtalslagen.",
        "Termen condictio indebiti avser återkrav av en betalning som erlagts av misstag, medan negativt kontraktsintresse syftar till att försätta den skadelidande i samma läge som om avtalet aldrig ingåtts.",
    ]
}

fn format_sample() -> Vec<&'static str> {
    vec![
        "Formattest — samma text i flera filformat",
        "Den 14 mars 2026 träffades parterna för att förhandla om hyresavtalet gällande fastigheten på Strandvägen 7. Båda parter önskade förlänga avtalet, men frågan om uppsägningstiden förblev olöst när mötet avslutades.",
        "Syftet med den här filen är att kontrollera att JuraDrop läser ut exakt samma text oavsett om den kommer från .docx, .pdf, .txt, .md, .rtf eller .odt.",
    ]
}

fn readme() -> String {
    "JuraDrop — testunderlag för manuell testning\n\
=================================================\n\n\
01-per-zon/  — släpp varje fil på zonen med samma nummer:\n\
  01 Sammanfatta            02 Till engelska         03 Till svenska\n\
  04 Punktlista             05 Anonymisera           06 Förenkla\n\
  07 Plocka ut kontakt…     08 Generera (släpp .txt) 09 Källförteckning\n\
  10 Identifiera rättsfr…   11 Strukturera (IRAC)    12 Förklara begreppen\n\n\
  Tips: 04 visar de nya riktiga Word-punktlistorna, 05/07 är fulla av\n\
  personuppgifter, 10–12 är de nya studiemetod-zonerna.\n\n\
02-format/   — samma text i .docx/.pdf/.txt/.md/.rtf/.odt. Släpp var och en\n\
  på valfri zon (t.ex. Sammanfatta) och kontrollera att resultatet blir\n\
  likvärdigt oavsett format. Resultatet speglar formatet (utom .pdf → .docx).\n\n\
03-kantfall/ — förväntat beteende:\n\
  tom.docx          → ärligt fel: ingen läsbar text.\n\
  mycket-kort.txt   → fungerar, men kort resultat.\n\
  mycket-langt.txt  → trunkeringsnotis (texten kortas före AI:n).\n\
  svensk.pages      → artigt fel: exportera till Word eller PDF först.\n\
  skadad.docx       → ärligt fel: kunde inte läsa filen.\n\
  for-stor.txt      → 'filen är för stor' (över 50 MB).\n\n\
Obs: kräver en nedladdad modell (t.ex. gemma3:4b). Resultatfilen hamnar\n\
bredvid originalet och öppnas automatiskt.\n"
        .to_string()
}
