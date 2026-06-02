# Data Model: Strict Content-Security-Policy (spec 030)

This feature introduces no runtime entities or persisted data. The only
"data" is a static configuration value. Documented here for completeness and
to anchor the pinning test.

## Entity: ContentSecurityPolicy (build-time config)

A single declared value in `src-tauri/tauri.conf.json` under
`app.security`. Two fields:

| Field | Type | Applies to | Constraint |
|---|---|---|---|
| `csp` | string | release builds | Strict (see below). MUST NOT be `null`. |
| `devCsp` | string | dev builds only | Strict + Vite dev origin + HMR ws. Never ships. |

### Directive set (production `csp`)

| Directive | Allowed origins | Invariant source |
|---|---|---|
| `default-src` | `'self'` | ResourcesAreLocalOnly |
| `script-src` | `'self'` (+ Tauri-injected hashes/nonce at build) | NoRemoteOrUnsafeScript / FR-012 |
| `style-src` | `'self' 'unsafe-inline'` | NoRemoteStyleOrigin / FR-012 |
| `img-src` | `'self' data:` | ResourcesAreLocalOnly |
| `font-src` | `'self' data:` | ResourcesAreLocalOnly |
| `connect-src` | `'self' ipc: http://ipc.localhost http://127.0.0.1:11434 http://localhost:11434` | LocalhostOnlyEgress / FR-002,003 |
| `object-src` | `'none'` | DefenseInDepthLocked / FR-014 |
| `base-uri` | `'self'` | DefenseInDepthLocked / FR-014 |
| `frame-ancestors` | `'none'` | DefenseInDepthLocked / FR-014 |
| `form-action` | `'self'` | DefenseInDepthLocked / FR-014 |
| `report-uri`/`report-to` | (absent) | NoReportEndpoint / FR-013 |

### Invariants (must always hold — asserted by the pinning test)

1. `csp != null` (PolicyIsDeclared / FR-001).
2. `connect-src` contains zero non-localhost hosts (LocalhostOnlyEgress / SC-005).
3. `script-src` == exactly `'self'` (+ build-injected hashes); no `'unsafe-inline'`/`'unsafe-eval'` (NoRemoteOrUnsafeScript / FR-012).
4. No `report-uri`/`report-to` token anywhere (NoReportEndpoint / FR-013).
5. `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`, `form-action 'self'` all present (DefenseInDepthLocked / FR-014).
6. `style-src`/`img-src`/`font-src` contain no remote origin (ResourcesAreLocalOnly).

No state transitions. No lifecycle. The triviality of this model is why TLA+ hits its gate.
