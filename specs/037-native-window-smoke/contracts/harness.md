# Contract: Native smoke harness (spec 037)

## A. Runner CLI (`scripts/native-smoke.sh`)

```
usage: scripts/native-smoke.sh [--build] [--probe-only]
exit 0  — suite green
exit 1  — suite red (assertion/test failure)
exit 2  — preflight failure (permission missing, Xcode absent, build failed) with actionable message
```

Sequence: preflight (xcodebuild present, permission probe) → build-if-stale → export titles JSON → start mock (ephemeral port) → `lsregister -f` the bundle → `xcodebuild test` with env → propagate result → teardown (always: kill app tree, stop mock, remove temp).

## B. Mock endpoint surface

| Route | Response |
|---|---|
| `GET /api/tags` | `200 {"models":[{"name":"gemma3:4b"}]}` |
| `POST /api/generate` | `200 {"model":"gemma3:4b","response":"NATIV-SMOKE: sammanfattning klar.","done":true}` |
| anything else | `404` (the suite fails loudly if the app needs an unmocked route) |

## C. Suite assertions (clauses)

| # | Clause | Test |
|---|---|---|
| H-1 | Window appears within launch timeout (bounded wait) | test00 probe |
| H-2 | Probe outcome recorded; fallback path amends spec/register before scope reduction | test00 + process rule |
| H-3 | Twelve zone titles (canonical, JSON-exported — never retyped) present in the a11y tree | test01 |
| H-4 | Chrome affordances (help + settings) present | test01 |
| H-5 | Välj fil → native panel → fixture path → confirm completes | test02 |
| H-6 | Sidecar `dokument.sammanfatta.txt` exists AND contains the canned mock text | test02 |
| H-7 | No fixed sleeps — `waitForExistence`/expectations only | review + grep |
| H-8 | Teardown leaves: no JuraDrop process, no mock process, no temp dir | runner post-check |
| H-9 | The suite appears in NO default gate (npm test, cargo test, Playwright, CI) | analyze + grep absence |
