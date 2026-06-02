# Contract: CSP policy value (spec 030)

The "interface" this feature exposes is the declared policy value the
WKWebView enforces. The contract is the exact production policy string and
the guarantees a test pins it to.

## Production `csp` (the shipped contract)

```
default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' ipc: http://ipc.localhost http://127.0.0.1:11434 http://localhost:11434; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'
```

## Development `devCsp` (never ships)

```
default-src 'self' http://localhost:1420; script-src 'self' 'unsafe-inline' http://localhost:1420; style-src 'self' 'unsafe-inline' http://localhost:1420; img-src 'self' data: http://localhost:1420; font-src 'self' data: http://localhost:1420; connect-src 'self' ipc: http://ipc.localhost http://127.0.0.1:11434 http://localhost:11434 http://localhost:1420 ws://localhost:1420; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'
```

## Pinned guarantees (test contract)

A test reading the bundled `tauri.conf.json` MUST assert, on the **production** `csp`:

| ID | Assertion |
|---|---|
| C-1 | `app.security.csp` is a non-null, non-empty string (FR-001). |
| C-2 | `connect-src` host tokens ⊆ { `'self'`, `ipc:`, `http://ipc.localhost`, `http://127.0.0.1:11434`, `http://localhost:11434` } — zero other hosts (FR-002/003, SC-005). |
| C-3 | `script-src` contains `'self'` and NOT `'unsafe-inline'` and NOT `'unsafe-eval'` and no `http(s)://` host (FR-004/012). |
| C-4 | The string contains neither `report-uri` nor `report-to` (FR-013). |
| C-5 | The string contains `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`, `form-action 'self'` (FR-014). |
| C-6 | `style-src`, `img-src`, `font-src` contain no `http(s)://` remote host (FR-005); `data:` permitted on img/font only. |
| C-7 | The production `csp` differs from `devCsp` only by added dev-origin/ws tokens; `devCsp` still satisfies C-4 and C-5 (FR-015 — dev never relaxes report/defense-in-depth). |

## Non-contract (verified manually, not by the pinning test)

- SC-001 live egress block (a renderer `fetch('https://example.com')` is blocked) — manual `tauri dev` devtools probe per quickstart.
- SC-003 Ollama round-trip under CSP — manual `tauri dev` document drop.
- FR-007 GitHub shell.open, FR-008 updater — covered by their existing tests staying green + manual smoke.
