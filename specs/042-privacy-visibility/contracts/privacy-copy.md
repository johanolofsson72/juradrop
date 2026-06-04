# Contract: Privacy copy — the fact base and its four renderings (spec 042)

## A. The fact base (normative)

| Fact | Content |
|---|---|
| F1 — processing location | Documents are processed on this computer ("din dator") |
| F2 — never-leaves scope | Documents, custom instructions, results — never leave the computer |
| F3 — network use 1 | One-time AI-model download when the app is set up |
| F4 — network use 2 | Update check (release manifest + signed app update) — no user content |

## B. Per-surface rendering contract

| # | Clause | Enforced by |
|---|---|---|
| P-1 | The badge renders F1+F2 in ONE Swedish line, visible whenever the zone grid is visible, in every zone state | Playwright state sweep + co-location in App.tsx |
| P-2 | The badge is non-interactive: no link, no focus, no handlers; exposed as content to AT | vitest + Playwright a11y assertions |
| P-3 | Wizard welcome carries F1 (+F2 scope) with canonical vocabulary | WizardCopy drift test + content pins |
| P-4 | Wizard download note carries F3's one-time + offline-after meaning (existing copy, kept) | content pin |
| P-5 | Help `_privacy_help` and README each carry F1+F2 AND name F3+F4 | help drift tests (Rust↔JSON↔TS) + README review |
| P-6 | No surface claims the app never uses the internet (F3/F4 exist) | overclaim-pattern vitest (with explicit allowlist for the scoped offline-after claim) |
| P-7 | Canonical vocabulary: "din dator" in all in-app strings; "Mac" only where the platform is the subject (README install) | vocabulary vitest |
| P-8 | Exactly two network uses are listed — a third entry fails the build (Principle I alarm) | `PRIVACY_NETWORK_USES.length === 2` pin |
| P-9 | Zero behavioral surface: no new IPC, no new network, no state | existing no-egress e2e + CSP pins pass unchanged |
| P-10 | Window fit: grid bottom row + badge visible without scroll at default size | Playwright bounding-box assertion |
