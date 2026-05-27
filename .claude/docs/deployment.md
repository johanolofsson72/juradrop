# Deployment — JuraDrop

JuraDrop is a macOS desktop app distributed as a signed + notarized DMG via GitHub Releases. There is no server, no cluster, no container. The "deployment" pipeline is: build the `.app` → sign it → notarize it via Apple → publish DMG + Tauri updater manifest to GitHub Releases. The Tauri auto-updater handles delivery to users.

## Apple Developer prerequisites (one-time)

Before the first release:

1. **Apple Developer Program membership** — €99/year. Register at `developer.apple.com`. Required to obtain a Developer ID Application certificate.
2. **Developer ID Application certificate** — create in Xcode → Settings → Accounts → Manage Certificates, or via `developer.apple.com/account/resources/certificates`. Choose "Developer ID Application" (NOT "Mac Development" — that's only for dev machines).
3. **Export the certificate as .p12** — Keychain Access → My Certificates → right-click → Export → set a strong password → save as `juradrop-signing.p12`.
4. **Generate an app-specific password for notarytool** — `appleid.apple.com` → Sign-In and Security → App-Specific Passwords → "+" → name it `juradrop-notarytool`. Save the generated password.
5. **Generate the Tauri updater signing keypair** — `npm run tauri signer generate -- -w ~/.tauri/juradrop-updater.key`. Keep the private key safe; the public key goes into `tauri.conf.json`.

## GitHub Secrets (set under repo Settings → Secrets and variables → Actions)

The names below are what `.github/workflows/release.yml` reads — they are the exact names `tauri-action@v0` expects. Each secret must be set BEFORE pushing the first release tag.

| Secret | Value | Where to get it |
|---|---|---|
| `APPLE_CERTIFICATE` | Base64 of `juradrop-signing.p12` | `base64 -i juradrop-signing.p12 \| pbcopy` then paste |
| `APPLE_CERTIFICATE_PASSWORD` | The password you set when exporting the .p12 | Your password manager |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: Johan Olofsson (TEAMID)` | Keychain Access → My Certificates → the cert's full subject |
| `APPLE_ID` | Your Apple ID email | `appleid.apple.com` |
| `APPLE_PASSWORD` | The app-specific password from step 4 above | NOT your Apple ID password — must be the app-specific one |
| `APPLE_TEAM_ID` | Your 10-character Team ID | `developer.apple.com/account` → Membership |
| `TAURI_SIGNING_PRIVATE_KEY` | Contents of `~/.tauri/juradrop-updater.key` | `cat ~/.tauri/juradrop-updater.key \| pbcopy` |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | Password protecting the Tauri updater private key | What you typed during `tauri signer generate` |

The auto-provided `GITHUB_TOKEN` covers draft-release creation + asset upload via the workflow's `permissions: contents: write` block — no PAT is needed.

Document the renewal date for the Developer ID certificate in `CLAUDE.local.md` and set a 30-day-out calendar reminder. A lapsed cert breaks every signed release.

## Tauri updater pubkey (one-time, before first release)

The updater plugin verifies every downloaded update against a public key embedded in the running binary. The matching private key is the `TAURI_SIGNING_PRIVATE_KEY` GitHub Secret.

After running `npm run tauri signer generate -- -w ~/.tauri/juradrop-updater.key`, the public key is printed to stdout (and saved to `~/.tauri/juradrop-updater.key.pub`). Paste that **public** key into `src-tauri/tauri.conf.json`:

```json
"plugins": {
  "updater": {
    "active": true,
    "dialog": true,
    "endpoints": ["https://github.com/johanolofsson72/juradrop/releases/latest/download/latest.json"],
    "pubkey": "<paste the public key here, replacing REPLACE_WITH_TAURI_PUBLIC_KEY_BEFORE_FIRST_RELEASE>"
  }
}
```

Commit + push that change BEFORE running `release-prep.sh v0.1.0`. The placeholder string is rejected by the release workflow because no installed app could verify signatures produced from a real private key against a placeholder pubkey.

## Local release-prep (run before every tag push)

`scripts/release-prep.sh` is a POSIX-sh helper that catches the common pre-tag mistakes:

```bash
scripts/release-prep.sh v0.1.0
```

It verifies all of:
- HEAD is on `main`
- working tree is clean (no uncommitted changes)
- `origin/main` is in sync with the local main
- `src-tauri/Cargo.toml`, `src-tauri/tauri.conf.json`, and `package.json` all have version `0.1.0`
- the tag `v0.1.0` doesn't already exist locally

On success it prints the literal `git tag v0.1.0 && git push origin v0.1.0` command — you copy-paste it. The script does NOT auto-push (deliberate human checkpoint).

## Release pipeline

```text
Developer pushes git tag v1.2.3
         │
GitHub Actions trigger: tag matches v*.*.*
         │
macos-latest runner spins up
         │
Checkout + cache (cargo + npm)
         │
npm install + npm test (vitest, must pass)
         │
cd src-tauri && cargo test (must pass)
         │
tauri-action: npm run tauri build
  ├── Compile Rust core for aarch64 + x86_64
  ├── Bundle React frontend
  ├── Bundle Ollama sidecar binary
  ├── Sign outer .app and inner sidecar binary with Developer ID
  ├── Build DMG installer
  └── Submit DMG to Apple notarytool, wait for ticket, staple
         │
tauri-action uploads to draft GitHub Release:
  ├── JuraDrop_1.2.3_universal.dmg (the signed + notarized installer)
  ├── JuraDrop_1.2.3_universal.dmg.sig (Tauri updater signature)
  └── latest.json (Tauri updater manifest)
         │
Developer publishes the draft release manually after smoke-testing locally
```

## Tauri configuration (`src-tauri/tauri.conf.json`)

Key fields the pipeline depends on (full file lives in the repo, updated by spec 006):

```json
{
  "identifier": "se.noisycricket.juradrop",
  "bundle": {
    "targets": ["app", "dmg"],
    "macOS": {
      "minimumSystemVersion": "12.0",
      "signingIdentity": null,
      "providerShortName": null
    }
  },
  "plugins": {
    "updater": {
      "active": true,
      "dialog": true,
      "endpoints": ["https://github.com/johanolofsson72/juradrop/releases/latest/download/latest.json"],
      "pubkey": "<paste the Tauri public key here>"
    }
  }
}
```

The `signingIdentity` is `null` in the file — the GH Actions runner reads it from `APPLE_SIGNING_IDENTITY` env var and `tauri-action` overrides at build time. `bundle.targets` includes both `app` (raw .app bundle) and `dmg` (the installer) so `tauri-action` produces a signed + notarized DMG plus the `.sig` file the Tauri updater plugin verifies against.

## Ollama sidecar bundling

`src-tauri/binaries/ollama-aarch64-apple-darwin` and `src-tauri/binaries/ollama-x86_64-apple-darwin` are the bundled Ollama binaries. They get included via `tauri.conf.json`:

```json
"externalBin": ["binaries/ollama"]
```

Both binaries MUST be code-signed individually with the same Developer ID before being bundled, OR `tauri-action` will sign them as nested executables during the outer `.app` signing pass. The latter is simpler and what we use.

## Document parsing (Rust crates)

Pinned in `src-tauri/Cargo.toml`:

| Crate | Purpose | Notes |
|---|---|---|
| `docx-rs` | `.docx` read + write | Pin version; API has churned historically |
| `pdf-extract` | `.pdf` text extraction | Text-only, no OCR in v1 |
| stdlib `std::fs` | `.txt`, `.md` | No crate needed |
| `rtf-parser` | `.rtf` | Best-effort, low test coverage upstream |
| `.pages`, `.odt` | Best-effort plaintext via custom zip-walker | Degrade to "format not supported" if extraction fails |

## End-to-end release procedure

For each release after the prereqs are in place:

1. Bump the version in three places: `src-tauri/Cargo.toml`, `src-tauri/tauri.conf.json`, `package.json`. All three must match `X.Y.Z`.
2. Update `CHANGELOG.md` (or the release-notes section of the README) with the new version's changes.
3. Commit + push to `main`: `git commit -m "chore: bump to vX.Y.Z" && git push origin main`.
4. Run `scripts/release-prep.sh vX.Y.Z`. It refuses to print the push command unless every precondition holds.
5. Copy-paste the printed `git tag vX.Y.Z && git push origin vX.Y.Z` command.
6. Watch the run at `github.com/johanolofsson72/juradrop/actions`. Cached builds complete in ~15 min; cold builds in ~30 min.
7. When the run succeeds, the draft release appears under [Releases → Drafts](https://github.com/johanolofsson72/juradrop/releases). Download the DMG attached there.
8. Smoke-test the DMG on a real Mac (your dev Mac is fine if it doesn't already have the old version cached — better to use a clean test user account).
9. If the smoke test passes, click **"Publish release"** in the GitHub UI. The Tauri updater manifest at `releases/latest/download/latest.json` now points at this version; any existing installs pick it up on next launch.

## Release checklist (pre-publish)

Before clicking "Publish release" on the GitHub draft:

- [ ] All CI gates green (lint, typecheck, vitest, cargo fmt, clippy strict, cargo test)
- [ ] DMG downloads, opens via double-click, drags to Applications WITHOUT any Gatekeeper warning
- [ ] `spctl --assess --type execute /Applications/JuraDrop.app` returns "accepted"
- [ ] `xcrun stapler validate /Applications/JuraDrop.app` returns "ready to be run"
- [ ] First-launch flow on a clean Mac (or fresh user account): Ollama model downloads, first translation works
- [ ] CHANGELOG.md updated for this version
- [ ] All three version files (`Cargo.toml`, `tauri.conf.json`, `package.json`) match the git tag
- [ ] (After v0.1.0 ships) Updater test: previous version's app sees the new release, downloads, restarts, runs correctly

## Re-running a failed release

If the workflow fails partway through, fix the underlying problem then retry. Some scenarios:

- **Quality gate failed (test, clippy, lint)** — push a fix to main, delete the broken tag (`git tag -d vX.Y.Z && git push --delete origin vX.Y.Z`), then re-run `release-prep.sh` and re-cut the tag.
- **Apple notarytool outage** — re-run the workflow from the GitHub Actions UI ("Re-run failed jobs"). Don't change the tag.
- **Existing draft release with same name** — go to Releases → Drafts → ⋯ → Delete the existing draft, then re-run the workflow from the Actions UI.
- **Signing certificate expired** — re-issue the cert at `developer.apple.com`, re-export the .p12, update `APPLE_CERTIFICATE` + `APPLE_CERTIFICATE_PASSWORD` secrets, re-run.

## Rollback procedure (v1 — fix forward only)

v1 has no "yank" mechanism. If a published release turns out to be broken:

1. Cut a new release with a bumped patch version (e.g. v0.2.0 → v0.2.1) containing the fix.
2. The Tauri updater manifest at `releases/latest/download/latest.json` automatically points to the latest *published* release. Users on the broken version receive the fix on next launch.
3. The broken DMG remains downloadable from its release page for audit/forensics. Do NOT delete it — the file's continued presence is a deliberate part of the audit trail.
4. Add a "⚠️ Known issues" section to the broken release's notes pointing users at the fixed version.

Manifest rewind ("yank-and-republish") is deferred — building a one-off tool for it is not worth it until a real incident demands it.

## What this project does NOT have

To prevent confusion when patterns from other Johan projects bleed in:

- **No Docker, no Docker Compose, no Docker Swarm.**
- **No NFS mounts, no SQLite-on-NFS rules** (`.claude/rules/sqlite.md` is N/A here).
- **No Azure Spot resilience** (`.claude/rules/spot-resilience.md` is N/A here).
- **No Nginx Proxy Manager, no Let's Encrypt.**
- **No Linux servers of any kind.**
- **No database server.**

If you find yourself reading about any of the above for JuraDrop, you took a wrong turn.
