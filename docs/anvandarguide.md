# JuraDrop – användarguide

JuraDrop är en Mac-app som hjälper dig att sammanfatta, översätta, anonymisera och förenkla juridiska texter. Allt sker på din egen dator. Dina dokument skickas aldrig någonstans.

Den här guiden går igenom allt du behöver för att komma igång. Du behöver ingen Terminal och inga förkunskaper.

## Installera

1. Hämta den senaste filen `JuraDrop_x.y.z_universal.dmg` från [Releases](https://github.com/johanolofsson72/juradrop/releases/latest).
2. Dubbelklicka på filen.
3. Dra `JuraDrop` till mappen `Program`.
4. Öppna JuraDrop från `Program`.

Appen är signerad och granskad av Apple, så du ska inte få någon varning när du öppnar den. Den fungerar på macOS 12 eller senare, både på nya Mac-datorer med Apple-chip och äldre med Intel.

## Första starten

Första gången du öppnar appen behöver den hämta en AI-modell på cirka 3,3 GB. Välkomstsidan förklarar vad som händer. Tryck **Fortsätt** för att börja.

- Nedladdningen visar hur långt den har kommit och ungefär hur lång tid som återstår.
- Har du en långsam uppkoppling tar det längre tid. Det gör inget, nedladdningen fortsätter så länge det kommer data.
- Tappar du nätet står det **Väntar på nätverk…**. Kommer nätet inte tillbaka inom 90 sekunder avbryts nedladdningen och du kan trycka **Försök igen**.
- Du behöver minst 4 GB ledigt på disken.

När modellen är nedladdad fungerar appen helt utan internet.

## Så använder du appen

Fönstret har tolv rutor, så kallade zoner. Varje zon gör en sak med ditt dokument.

1. Dra ett dokument från Finder och släpp det på en zon. Du kan också klicka på **Välj fil** under zonen.
2. Zonen visar att den arbetar. Du kan trycka **Avbryt** om du ångrar dig.
3. När den är klar sparas resultatet som en ny fil bredvid originalet, och den öppnas direkt. Originalet ändras aldrig.

Appen läser `.docx`, `.pdf`, `.odt`, `.rtf`, `.txt` och `.md`. Ett dokument i taget per zon, max 50 MB. Långa dokument delas upp och bearbetas i sin helhet.

## De tolv zonerna

| Zon | Vad den gör |
|---|---|
| **Sammanfatta** | Kortar ner ett långt dokument till det viktigaste. Bra för att snabbt förstå vad en dom eller ett avtal handlar om. |
| **Till engelska** | Översätter en svensk text till engelska. Läs igenom juridiska termer efteråt, de har inte alltid en exakt motsvarighet. |
| **Till svenska** | Översätter en engelsk text till svenska. |
| **Punktlista** | Ställer upp huvudpunkterna som en lista. Bra inför en tenta. |
| **Anonymisera** | Byter ut namn, personnummer, adresser, telefonnummer och e-post mot platshållare som [Person 1] och [Adress 1]. Granska alltid resultatet innan du delar det. |
| **Förenkla** | Skriver om krångligt lagspråk till vanlig svenska. |
| **Plocka ut kontaktuppgifter** | Samlar adress, personnummer, telefon och e-post under varje persons namn. |
| **Generera juridisk text** | Skriver ett utkast, till exempel en uppsägning, utifrån en kort instruktion i en `.txt`- eller `.md`-fil. Kontrollera alltid utkastet mot lag och källor. |
| **Källförteckning** | Samlar hänvisningarna till lagar, rättsfall och litteratur i en lista. |
| **Identifiera rättsfrågorna** | Listar frågorna i ett rättsfall eller en tentauppgift, utan färdiga svar. |
| **Strukturera (IRAC)** | Delar in ditt eget svar i rättsfråga, gällande rätt, subsumtion och slutsats. Den ordnar om din text och lägger inte till något nytt. |
| **Förklara begreppen** | Förklarar facktermerna i en text på vanlig svenska. |

Varje zon har en liten hjälpknapp i hörnet. Frågetecknet uppe till höger i fönstret öppnar en hjälppanel med alla zoner.

## Egna instruktioner

Ovanför zonerna finns ett textfält. Det du skriver där gäller nästa dokument du släpper, på vilken zon som helst. Några exempel:

- ”fokusera på skadeståndet”
- ”skriv kortare”
- ”behåll citaten” (på Till engelska: citerad text lämnas ordagrant)

Fältet är valfritt. Instruktionen skickas bara till AI-modellen på din dator och sparas aldrig.

## Tips vid start

Varje gång du öppnar appen visas ett kort tips ovanför zonerna, ett nytt varje gång. Klicka **Nästa tips** för att se fler, eller krysset för att stänga det. Vill du inte se tipsen alls stänger du av dem under **Inställningar → Start → Visa tips vid start**.

Första gången du öppnar en ny version visas i stället vad som är nytt i den versionen.

## Inställningar

Öppna inställningarna med kugghjulet uppe till höger eller med ⌘, (kommando och komma).

- **AI-modell:** *Snabb* passar äldre datorer och korta texter. *Smart* är standard och en bra balans. *Stor* ger bäst kvalitet men tar längre tid och mer plats. Snabb och Stor laddas ner när du väljer dem.
- **Utseende:** ljust, mörkt eller samma som din Mac.
- **Start:** slå av eller på tips vid start.
- **Felsökningslogg:** om du slår på *Spara felsökningslogg lokalt* sparas en logg på din dator, utan innehåll från dina dokument. Den skickas ingenstans.

## Uppdateringar

JuraDrop letar efter nya versioner när du startar appen och sedan ungefär var fjärde timme. Finns det en uppdatering syns en liten knapp uppe till höger.

1. Tryck **Installera nu**. Uppdateringen hämtas och kontrolleras.
2. Välj när appen ska starta om. Arbetar en zon väntar appen tills den är klar.
3. Appen startar om på den nya versionen och visar vad som är nytt.

Uppdateringen kontrolleras med en digital signatur innan den installeras. Ingenting från dina dokument är inblandat.

## Integritet

- All bearbetning sker på din dator.
- Dokument, instruktioner och resultat skickas aldrig någonstans.
- Appen använder bara internet för två saker: att hämta AI-modellen och att leta efter uppdateringar.
- Appen samlar inte in någon statistik.

## Om något går fel

| Meddelandet | Vad du gör |
|---|---|
| **Filformatet stöds inte** | Spara dokumentet som `.docx`, `.pdf`, `.txt`, `.md`, `.rtf` eller `.odt`. |
| **Pages-filer stöds inte** | Öppna filen i Pages och välj Arkiv → Exportera till → Word eller PDF. |
| **Dokumentet är lösenordsskyddat** | Ta bort lösenordet och försök igen. |
| **Hittade ingen text att läsa i PDF-filen** | PDF:en är troligen en skannad bild. Den kan appen inte läsa än. |
| **Filen är för stor** | Dela upp dokumentet. Gränsen är 50 MB. |
| **Ett dokument i taget** | Släpp ett dokument åt gången på varje zon. |
| **Vänta tills föregående dokument är klart** | Zonen arbetar redan. Vänta, eller tryck Avbryt. |
| **AI-motorn svarade inte** | Försök igen. Hjälper det inte, starta om JuraDrop. |
| **Inte tillräckligt med diskutrymme** | Frigör minst 4 GB och tryck Försök igen. |
| **Modellnedladdningen avbröts** | Kontrollera nätet och tryck Försök igen. |
| **Ett annat AI-program använder anslutningen** | Ett annat program upptar porten som AI-motorn behöver. Stäng det och starta om JuraDrop. (Har du redan Ollama igång använder JuraDrop den i stället.) |

Hjälper inget av detta kan du rapportera problemet på [GitHub](https://github.com/johanolofsson72/juradrop/issues). Klistra aldrig in innehåll från konfidentiella dokument där.
