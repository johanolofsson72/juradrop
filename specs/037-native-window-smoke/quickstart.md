# Quickstart: native window smoke (spec 037)

## One-time setup

1. Xcode installed (the harness was built against Xcode 26.5).
2. First run will trigger macOS consent: **System Settings → Privacy & Security → Accessibility** (and Automation) — allow your terminal and "Xcode Helper" when prompted. The runner's preflight tells you if this is missing.

## Run

```bash
scripts/native-smoke.sh            # build-if-stale → mock → XCUITest → report → clean
scripts/native-smoke.sh --build    # force rebuild of the debug .app first
scripts/native-smoke.sh --probe-only  # just the FR-009 accessibility probe (test00)
```

Expected: the JuraDrop window opens on screen, the suite clicks "Välj fil" on Sammanfatta, the file dialog navigates itself, and after a few seconds the window closes again. Green exit, no leftovers.

## What it covers / deliberately does not

- Covers: real WKWebView render of the twelve zones + chrome, real IPC, real `NSOpenPanel`, sidecar-on-pick with canned model output (hermetic — no model needed, nothing downloaded).
- Does NOT cover: real inference quality (model-dependent), OS drag-drop (not automatable), release-build behavior (the hermetic seam is debug-only by design).
- NOT in CI, not part of `npm test`/`cargo test` — run it when native wiring changes or before a release.

## Troubleshooting

- Exit 2 + permission message → grant the listed permission and rerun.
- "window never appeared" → run `--build`; a stale bundle from before a config change is the usual cause.
- Mock port collision is impossible (ephemeral port), but a previous interrupted run's app instance is killed by the preflight.
