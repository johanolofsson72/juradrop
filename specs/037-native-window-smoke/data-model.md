# Data Model: Native Window Smoke (spec 037)

The system under specification is the harness (see spec.allium `TestRun`). No app-side entities change.

## TestRun lifecycle (mirrors spec.allium)

```
preflight ─(permission missing)→ settled_fail
preflight → building → launching → probing → asserting_render ─┬→ driving_pick → settled_pass/fail
                                                               └→ settled_pass  (chrome_only_fallback)
settled_* → cleaned   (terminal; app dead, mock stopped, temp removed)
```

## Concrete shapes

| spec.allium entity | Implementation |
|---|---|
| `TestRun` | one `scripts/native-smoke.sh` invocation + the XCTest case lifecycle inside it |
| `AppUnderTest` | `src-tauri/target/aarch64-apple-darwin/debug/bundle/macos/JuraDrop.app`, bundle id `se.noisycricket.juradrop`, launched via `XCUIApplication(bundleIdentifier:)` |
| `MockEndpoint` | `scripts/mock-ollama.py` on an ephemeral port; `/api/tags` + `/api/generate` |
| `FixtureWorkspace` | `mktemp -d` dir containing `dokument.txt`; sidecar expectation `dokument.sammanfatta.txt` |
| `ProbeOutcome` | recorded in the run log + (on fallback) a spec/register amendment |

## Environment contract (runner → app/test)

| Variable | Consumer | Meaning |
|---|---|---|
| `JURADROP_OLLAMA_URL` | app (debug seam, client.rs) | mock base URL, e.g. `http://127.0.0.1:<port>` |
| `JURADROP_SMOKE_FIXTURE_DIR` | Swift test | absolute temp dir holding the fixture |
| `ZONE_TITLES_JSON` | Swift test | path to the runner-exported canonical titles JSON |

## Invariant → enforcement map

| spec.allium invariant | Enforcement |
|---|---|
| `Hermetic` | mock URL is the only model endpoint the client can reach (seam); debug build asserted by the runner (bundle path under `debug/`) |
| `TerminalIsCleaned` | Swift teardown + runner `trap EXIT` (pkill app, kill mock, rm temp) + post-run residue check |
| `FailuresExitNonZero` | `xcodebuild test` exit code propagated; `set -euo pipefail` |
| `OptInOnly` | no reference from package.json scripts' default test, cargo, Playwright config, or any workflow file |
| `PassImpliesSidecar` | the pick test's final assertion IS the sidecar content check |
