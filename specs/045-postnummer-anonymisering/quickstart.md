# Quickstart: verifying deterministic postnummer replacement (045)

## Automated

```bash
cd src-tauri && cargo test pii_scrub && cargo test pii_sweep && cargo test --test zone_pipeline_anonymisera && cargo test
cd src-tauri && cargo clippy --all-targets -- -D warnings && cargo fmt --check
npm test && npm run lint && npm run typecheck && npm run test:e2e
```

## Manual (real model, `npm run tauri dev`)

1. Drop a document whose party block contains a street address with a postnummer, e.g.
   `Storgatan 5, 114 35 Stockholm` (ideally a `.docx` exported from Word, so the separator
   is a non-breaking space — the common real case) on Anonymisera.
2. Output MUST contain `[Postnr 1]` in place of `114 35` and ZERO raw `114 35` — regardless
   of model tier.
3. A second distinct postnummer gets `[Postnr 2]`; the same postnummer repeated keeps `[Postnr 1]`.
4. Sanity on precision: a document containing an amount `15 000 kr`, a case number
   `T 4521-25`, and a bare `11435` must come through with those tokens UNCHANGED (only the
   canonical spaced `NNN NN` grouping is scrubbed).
5. If the model fabricates or echoes a raw `114 35`, the yellow "Automatisk kontroll hittade…"
   banner fires AND frames it as a possible address line to re-check — that is the net + the
   address anchor working, not a bug.
6. Repeat on Snabb (llama3.2:1b): the postnummer category is STILL clean — it never depended
   on the model.
