# Quickstart: manual verification of Kontakter per-person grouping (spec 040)

Automated coverage proves the deterministic merge and the prompt contract; this manual pass checks real-model behavior (gemma3:4b) on the user's Mac.

## Short document (single part — prompt steering only)

1. `npm run tauri dev`
2. Create `kontakter-kort.txt`:

   ```text
   Käranden David Dahl, Storgatan 1, 211 34 Malmö, tel 070-123 45 67,
   david.dahl@exempel.se. Svaranden Eva Ek (personnummer 19850312-1234)
   nås på eva.ek@exempel.se. Växelnummer: 046-222 00 00.
   ```

3. Drop it on **Plocka ut kontaktuppgifter**.
4. Expect in the sidecar: `## David Dahl` with Adress/Telefon/E-post bullets; `## Eva Ek` with Personnummer/E-post bullets; the orphan växelnummer ideally under `## Övriga uppgifter` (model-quality — a misattribution here is a prompt-tuning signal, not a spec failure).
5. Verify: no `## Namn`/`## Adresser` category sections; no greeting line; bullets carry `Telefon:`-style labels.

## Long document (multi-part — deterministic merge engaged)

1. Use `juradrop-test/mycket-langt.txt` (≥2 chunks) or any >24k-char document mentioning the same person early and late with different details.
2. Drop on Kontakter; watch "Bearbetar del i av n…" progress.
3. Expect: ONE section per person even when the person spans parts; any `## Övriga uppgifter` as the LAST section; no duplicated bullets within a section.

## Help copy

1. Click the zone's help icon → the long text describes per-person grouping ("under varje person" wording), not "var för sig".
2. `npm test -- --run src/__tests__/help-strings-drift.test.ts` stays green (three-way mirror intact).

## Regression spot-checks

- Drop the same short doc on **Sammanfatta** — unchanged behavior (no merge change for other zones).
- Drop on **Anonymisera** — spec-039 scrub still anonymisera-only; Kontakter output remains verbatim extraction.
