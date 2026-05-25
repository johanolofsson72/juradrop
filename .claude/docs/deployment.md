# Deployment — JuraDrop

JuraDrop is a macOS desktop app distributed as a signed + notarized DMG via GitHub Releases. There is no server, no cluster, no container. The "deployment" pipeline is: build the `.app` → sign it → notarize it via Apple → publish DMG + Tauri updater manifest to GitHub Releases. The Tauri auto-updater handles delivery to users.

## Apple Developer prerequisites (one-time)

Before the first release:

1. **Apple Developer Program membership** — €99/year. Register at `developer.apple.com`. Required to obtain a Developer ID Application certificate.
2. **Developer ID Application certificate** — create in Xcode → Settings → Accounts → Manage Certificates, or via `developer.apple.com/account/resources/certificates`. Choose "Developer ID Application" (NOT "Mac Development" — that's only for dev machines).
3. **Export the certificate as .p12** — Keychain Access → My Certificates → right-click → Export → set a strong password → save as `juradrop-signing.p12`.
4. **Generate an app-specific password for notarytool** — `appleid.apple.com` → Sign-In and Security → App-Specific Passwords → "+" → name it `juradrop-notarytool`. Save the generated password.
5. **Generate the Tauri updater signing keypair** — `npm run tauri signer generate -- -w ~/.tauri/juradrop-updater.key`. Keep the private key safe; the public key goes into `tauri.conf.json`.

## GitHub Secrets (set under repo Settings → Secrets → Actions)

| Secret | Value |
|---|---|
| `APPLE_CERTIFICATE` | Base64 of `juradrop-signing.p12` — `base64 -i juradrop-signing.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | The password you set when exporting the .p12 |
| `APPLE_SIGNING_IDENTITY` | e.g. `Developer ID Application: Johan Olofsson (TEAMID)` |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_PASSWORD` | The app-specific password from step 4 above (NOT your Apple ID password) |
| `APPLE_TEAM_ID` | Your 10-character Team ID from `developer.apple.com/account` |
| `TAURI_PRIVATE_KEY` | Contents of `~/.tauri/juradrop-updater.key` |
| `TAURI_KEY_PASSWORD` | Password for the Tauri updater private key |

Document the renewal date for the Developer ID certificate in `CLAUDE.local.md` and set a 30-day-out calendar reminder. A lapsed cert breaks every signed release.

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

Key fields the pipeline depends on (full file lives in the repo):

```json
{
  "tauri": {
    "bundle": {
      "identifier": "se.masterofapps.juradrop",
      "macOS": {
        "minimumSystemVersion": "11.0",
        "signingIdentity": null,
        "providerShortName": null
      }
    },
    "updater": {
      "active": true,
      "endpoints": ["https://github.com/johanolofsson72/juradrop/releases/latest/download/latest.json"],
      "dialog": true,
      "pubkey": "<paste the Tauri public key here>"
    }
  }
}
```

The `signingIdentity` is `null` in the file — the GH Actions runner reads it from `APPLE_SIGNING_IDENTITY` env var and overrides at build time.

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

## Release checklist (pre-publish)

Before clicking "Publish release" on the GitHub draft:

- [ ] `cargo test` passed in CI
- [ ] `npm test` passed in CI
- [ ] Playwright smoke suite passed
- [ ] DMG downloads, opens, drags to Applications without Gatekeeper dialog
- [ ] First-launch flow on a clean Mac (or fresh user account): Ollama model downloads, first translation works
- [ ] CHANGELOG.md updated for this version
- [ ] `tauri.conf.json` version matches the git tag
- [ ] Updater test: previous version's app sees the new release, downloads, restarts, runs correctly

## What this project does NOT have

To prevent confusion when patterns from other Johan projects bleed in:

- **No Docker, no Docker Compose, no Docker Swarm.**
- **No NFS mounts, no SQLite-on-NFS rules** (`.claude/rules/sqlite.md` is N/A here).
- **No Azure Spot resilience** (`.claude/rules/spot-resilience.md` is N/A here).
- **No Nginx Proxy Manager, no Let's Encrypt.**
- **No Linux servers of any kind.**
- **No database server.**

If you find yourself reading about any of the above for JuraDrop, you took a wrong turn.
