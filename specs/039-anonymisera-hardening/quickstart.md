# Quickstart: verifying deterministic PII replacement (039)

## Automated

```bash
cd src-tauri && cargo test pii_scrub && cargo test --test zone_pipeline_anonymisera && cargo test
cd src-tauri && cargo clippy --all-targets -- -D warnings && cargo fmt --check
npm test && npm run lint && npm run typecheck && npm run test:e2e
```

## Manual (real model, `npm run tauri dev`)

1. Drop `juradrop-test/01-per-zon/05-anonymisera-stamningsansokan.docx` (contains
   personnummer 19850312-1234, phones, e-mails — Meja's exact field case) on Anonymisera.
2. Output MUST contain `[Personnr 1]`, `[Telefon 1]`, `[E-post 1]`-style placeholders and
   ZERO raw personnummer/phone/email values — regardless of model tier.
3. The yellow "Automatisk kontroll hittade…" banner should be ABSENT (nothing for the
   sweep to find), unless the model fabricated new numbers (then it fires — that is the
   net working, not a bug).
4. Names should still be "Person A/B…" per the prompt; addresses "Adress 1/2" (model-side,
   still review-worthy per the zone disclaimer).
5. Repeat on Snabb (llama3.2:1b): the structured categories are STILL clean — they never
   depended on the model.
