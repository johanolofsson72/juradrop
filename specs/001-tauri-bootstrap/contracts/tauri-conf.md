# Contract: `src-tauri/tauri.conf.json` shape

The Tauri 2.x configuration file MUST encode FR-015, FR-019, FR-020, FR-016 directly. Below is the canonical shape this spec requires. Field names and structure follow the Tauri 2.x schema (`https://schema.tauri.app/config/2.0.0`).

## Required content

```jsonc
{
  "$schema": "https://schema.tauri.app/config/2.0.0",
  "productName": "JuraDrop",
  "version": "0.1.0",
  "identifier": "se.noisycricket.juradrop",
  "build": {
    "beforeDevCommand": "npm run dev",
    "beforeBuildCommand": "npm run build",
    "devUrl": "http://localhost:1420",
    "frontendDist": "../dist"
  },
  "app": {
    "windows": [
      {
        "label": "main",
        "title": "JuraDrop",
        "width": 900,
        "height": 650,
        "minWidth": 700,
        "minHeight": 500,
        "resizable": true,
        "fullscreen": false,
        "visible": true
      }
    ],
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "targets": ["app"],
    "icon": ["icons/icon.png"],
    "macOS": {
      "minimumSystemVersion": "12.0"
    }
  }
}
```

## Contract assertions

The implementer MUST satisfy each of the following. The /speckit-tasks command derives test tasks from these.

| Assertion | FR | Test type |
|-----------|----|-----------|
| `productName = "JuraDrop"` | FR-015 | Static JSON inspection (vitest config test) |
| `identifier = "se.noisycricket.juradrop"` | FR-015 | Static JSON inspection |
| `app.windows[0].title = "JuraDrop"` | FR-015 | Static JSON inspection + Playwright window title assertion (FC-001) |
| `app.windows[0].width = 900` | FR-015 | Static JSON inspection + manual window check |
| `app.windows[0].height = 650` | FR-015 | Static JSON inspection + manual window check |
| `app.windows[0].minWidth = 700` | FR-015 | Static JSON inspection; destructive DT-004 also verifies |
| `app.windows[0].minHeight = 500` | FR-015 | Static JSON inspection; destructive DT-004 also verifies |
| `app.windows[0].resizable = true` | FR-015 | Static JSON inspection |
| `app.windows.length = 1` | FR-015 + invariant SingleWindowAtBootstrap | Static JSON inspection |
| `bundle.targets = ["app"]` only at this spec | FR-020 + spec scope. `.dmg` target arrives with spec 006 (signing-and-ci) — the unsigned DMG build fails on bundle_dmg.sh because notarization paths aren't wired yet | Static JSON inspection |
| `bundle.macOS.minimumSystemVersion = "12.0"` | Assumptions (macOS 12+) | Static JSON inspection |
| No `bundle.targets` mention of `x86_64` or universal | FR-020 | Static JSON inspection (the absence is the contract) |

## What is deliberately NOT in this file

- No `bundle.macOS.signingIdentity` — signing arrives in spec 006.
- No `plugins` block — no plugins are installed at this spec.
- No `bundle.updater` block — auto-updater arrives in spec 007.
- No `app.macOSPrivateApi: true` — not needed.
- No custom `csp` (it stays `null` — equivalent to Tauri's safe default for dev).
