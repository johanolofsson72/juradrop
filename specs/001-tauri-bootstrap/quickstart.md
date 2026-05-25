# Quickstart: clone to running window

This is the SC-001 verification path. From a fresh clone on a baseline modern Mac (Apple Silicon, macOS 12+, broadband internet) with the prerequisites already installed, the user should reach a running dev window in **under 5 minutes**.

## Prerequisites (one-time, NOT counted toward the 5-minute budget)

- macOS 12 (Monterey) or later, Apple Silicon
- Xcode Command Line Tools — `xcode-select --install`
- Node 20+ — `brew install node@20` or via `nvm`
- Rust toolchain — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- `aarch64-apple-darwin` target — `rustup target add aarch64-apple-darwin`

> The README documents these prerequisites. JuraDrop does not install them.

## Clone-to-window steps

```bash
git clone https://github.com/johanolofsson72/juradrop.git
cd juradrop
npm install              # ~60-90 s (cold cache, broadband)
npm run tauri dev        # First run: ~3-4 min (Rust cold build). Second run: ~10 s.
```

When the window opens you see:

- **Title bar**: "JuraDrop"
- **Body**: A centered welcome card containing:
  - Heading: **JuraDrop**
  - Subtitle: *Lokal AI för svenska juriststudenter*
  - One shadcn `Button` element (non-functional placeholder)
- **Appearance**: light or dark, matching the current macOS system appearance.

## Verifying the toolchain (SC-002)

In a second terminal:

```bash
npm test                 # vitest runs the smoke + DOM tests; expect green
npm run lint             # ESLint runs against src/; expect zero warnings
npm run typecheck        # tsc --noEmit; expect zero errors
cd src-tauri
cargo test               # Rust smoke test; expect green
cargo clippy -- -D warnings   # zero warnings
cargo fmt --check        # exits 0
```

All six exit 0 = SC-002 satisfied.

## Verifying the production build (US-3)

```bash
npm run tauri build      # ~5-8 min cold; produces src-tauri/target/release/bundle/macos/JuraDrop.app
```

Right-click `JuraDrop.app` → Open (unsigned at this spec, so Gatekeeper requires the right-click bypass). The window opens with the same welcome card.

## Troubleshooting (documented edge cases)

- *`npm install` fails with "EACCES"*: don't `sudo npm install`. Use `nvm` to control the Node install path. See README.
- *`cargo build` fails with linker errors*: missing Xcode Command Line Tools. Re-run `xcode-select --install`.
- *Window opens but is blank*: most likely the Vite dev server didn't start. Check that port 1420 is free (`lsof -i :1420`).
- *`tauri build` succeeds but `JuraDrop.app` won't launch*: it's unsigned; macOS Gatekeeper requires right-click → Open the first time. This is expected at this spec.
- *`prefers-color-scheme` change doesn't update window*: WKWebView caches the media query result in some macOS versions. Toggle the appearance once more, or restart `npm run tauri dev`. (This bug, if it exists, is a Tauri/WebKit issue — JuraDrop has no explicit dark-mode JS code per R-001.)
