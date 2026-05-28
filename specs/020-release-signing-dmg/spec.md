# Feature Specification: First signed + notarized DMG (RUNBOOK — BLOCKED ON USER)

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: BLOCKED (requires your Apple account, secrets, and a tag push)
**Track**: Spec-only. The CI pipeline already exists (spec 006); this is the runbook + the human steps only.

## The blocker (why I can't do this)

Producing the first real signed + notarized DMG requires resources only you have:
- An **Apple Developer Program** membership (€99/yr) + a Developer ID Application certificate.
- The cert exported as `.p12`, an app-specific password, and a Tauri updater keypair.
- Those secrets pasted into **GitHub repository secrets**.
- A **git tag push** (`v0.1.0`) to trigger the release workflow.

None of that is doable from this environment. The code side is already built (spec 006: `.github/workflows/release.yml`, `tauri.conf.json` updater block, `scripts/release-prep.sh`, `.claude/docs/deployment.md`).

## The one code gap

- [ ] The Tauri updater **public key** in `src-tauri/tauri.conf.json` (`plugins.updater.pubkey`) is still a **placeholder** (spec 006). It must be replaced with the real public key generated alongside your updater private key. This is the only code change — and it depends on the keypair you generate, so it's yours to make (or paste the key here and I'll wire it in).

## Runbook — your action items (in order)

1. [ ] Buy/confirm Apple Developer Program membership.
2. [ ] Create a **Developer ID Application** certificate in the Apple Developer portal; download + export it as `.p12` with a password.
3. [ ] Generate an **app-specific password** for `notarytool` (appleid.apple.com → Sign-In and Security).
4. [ ] Generate the **Tauri updater keypair**: `npm run tauri signer generate -- -w ~/.tauri/juradrop.key` (or `npx @tauri-apps/cli signer generate`). Keep the private key secret; copy the **public** key.
5. [ ] Replace the placeholder `plugins.updater.pubkey` in `src-tauri/tauri.conf.json` with that public key (or hand it to me).
6. [ ] Set the **GitHub repository secrets** (names per `.claude/docs/deployment.md`, tauri-action's expected env): `APPLE_CERTIFICATE` (.p12 base64), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_PASSWORD` (app-specific), `APPLE_TEAM_ID`, `TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`, plus `KEYCHAIN_PASSWORD` if the workflow uses one.
7. [ ] Run `scripts/release-prep.sh` locally to verify HEAD is on `main`, tree clean, versions pinned across `Cargo.toml`/`tauri.conf.json`/`package.json`.
8. [ ] Push the tag: `git tag v0.1.0 && git push origin v0.1.0`. GitHub Actions builds → signs → notarizes → uploads the DMG + updater manifest to Releases.
9. [ ] **Verify on a clean Mac:** download the DMG, drag to /Applications, launch — Gatekeeper must NOT warn (proves notarization). This is the real "zero-CLI install" test (Principle II).

## Success Criteria (verified by you on hardware)
- A notarized `JuraDrop.dmg` + signed `latest.json` attached to the `v0.1.0` GitHub Release.
- Clean-Mac install with no Gatekeeper warning.
- The auto-updater manifest validates against the embedded pubkey.

## Status
SCAFFOLDED — runbook complete; CI already wired (spec 006). Blocked on your Apple account + secrets + tag. The only code touch (real pubkey) is yours, or paste it and I'll wire it.
