# Contract: `package.json` `scripts` section

FR-002 requires these six scripts and they MUST work on a fresh checkout. This contract pins the exact command each script runs.

## Required content

```jsonc
{
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview",
    "tauri": "tauri",
    "tauri:dev": "tauri dev",
    "tauri:build": "tauri build --target aarch64-apple-darwin",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:e2e": "playwright test",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit"
  }
}
```

> **Note on script names**: `CLAUDE.md` uses `npm run tauri dev` and `npm run tauri build` (space-separated). With the `"tauri": "tauri"` passthrough, both `npm run tauri dev` and the alias `npm run tauri:dev` work. Both forms MUST resolve to the same Tauri CLI command. The alias forms (`tauri:dev`, `tauri:build`) are added for convenience and tab-completion in zsh.

## Contract assertions

| Assertion | FR | Test type |
|-----------|----|-----------|
| `npm run tauri dev` (or `npm run tauri:dev`) opens a window | FR-002 + FC-001 | Manual / Playwright smoke |
| `npm run tauri build` (or `npm run tauri:build`) produces a `.app` | FR-002 + US-3 acceptance | Manual filesystem check |
| `npm test` runs vitest, exits 0, ≥ 1 test passes | FR-002, FR-011, FC-007 | CI / local |
| `npm run lint` runs ESLint over `src/`, exits 0, zero warnings | FR-002, FR-004, FC-010 | CI / local |
| `npm run typecheck` runs `tsc --noEmit`, exits 0 | FR-002, FR-003, FC-009 | CI / local |
| `npm run test:e2e` runs Playwright stub, exits 0 | FR-002 + R-006 | CI / local |
| `tauri:build` target is `aarch64-apple-darwin` only | FR-020 | Static script inspection |

## Cargo / Rust side (not in package.json but contracted)

Per CLAUDE.md, these MUST also work from the repo root:

| Command | FR | Test type |
|---------|----|-----------|
| `cd src-tauri && cargo test` | FR-012, FC-008 | CI / local |
| `cd src-tauri && cargo clippy -- -D warnings` | FR-013, FC-011 | CI / local |
| `cd src-tauri && cargo fmt --check` | FR-014, FC-012 | CI / local |

## What is deliberately NOT in this file

- No `"start"` script — desktop apps don't have one.
- No `"deploy"` script — distribution is GitHub Releases (spec 006).
- No `"ci"` aggregator script — CI workflow is spec 006.
- No `"format"` script — Prettier is invoked via editor or `npx prettier`; we don't want a script that silently modifies files outside the contract.
