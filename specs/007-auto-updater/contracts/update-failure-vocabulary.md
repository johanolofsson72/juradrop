# UpdateFailure vocabulary contract — Spec 007

Six Swedish failure variants. Each maps to a specific cause; no generic fallback per Principle VIII.

| Variant | Swedish copy | Chars | Triggered by | Recovery |
|---|---|---:|---|---|
| `NoNetwork` | `Kan inte nå GitHub — kontrollera nätverksanslutningen` | 53 | `reqwest::Error::is_connect()` / `is_timeout()` / DNS failure | User connects to network + clicks "Sök efter uppdateringar igen" |
| `ManifestMalformed` | `Uppdateringsservern svarade med ogiltigt innehåll` | 49 | 4xx/5xx HTTP status, malformed JSON, missing required manifest fields | Wait for upstream fix (the developer publishes a correct manifest) |
| `SignatureInvalid` | `Säkerhetskontrollen misslyckades — uppdateringen installeras inte` | 65 | minisign verification failure on the downloaded DMG | Wait for upstream fix; meanwhile the running version stays untouched |
| `DownloadInterrupted` | `Nedladdningen avbröts — försök igen` | 35 | Network drop mid-download, OS sleep too long, plugin's `Io(reqwest)` | User clicks "Sök efter uppdateringar igen" — the partial download is discarded |
| `InstallFailed` | `Kunde inte installera uppdateringen` | 33 | Tauri's `Update::install` returns an Io error (disk full, permission denied, etc.) | User re-attempts; if persistent, manually download + install from the GitHub release page |
| `UnsupportedPlatform` | `Den nya versionen kräver en nyare macOS — uppdatera macOS först` | 60 | Manifest's `minimumSystemVersion` is greater than the running macOS version | User upgrades macOS (out of JuraDrop's control) |

All variants satisfy the SwedishCopy invariant from spec 003:
- Length ≤ 80 chars ✓
- No English `Error:` prefix ✓
- Non-empty ✓

## UI mapping

`UpdateFailure` variants are NEVER shown via a modal dialog (Tauri's built-in dialog is disabled per FR-001). Instead:

- **Indicator badge** in the top-right of the main window: hidden when state is `Failed` (FR-010). Failures are silent — the user is NOT nagged.
- **"Senast kollat" footnote** in the bottom-right of the main window: clickable. When state is `Failed`, expanding the footnote shows the variant's Swedish copy + a "Sök efter uppdateringar igen" button.

Rationale per FR-010: showing a red error banner on every offline launch would train users to ignore all update notifications. Silent failure with on-demand recovery preserves trust.

## Plugin error → UpdateFailure mapping (Rust)

```rust
// src-tauri/src/updater/errors.rs
impl From<tauri_plugin_updater::Error> for UpdateFailure {
    fn from(e: tauri_plugin_updater::Error) -> Self {
        use tauri_plugin_updater::Error as E;
        match e {
            E::Reqwest(re) if re.is_connect() || re.is_timeout() => Self::NoNetwork,
            E::Reqwest(_) => Self::ManifestMalformed,
            E::Serialization(_) => Self::ManifestMalformed,
            E::Minisign(_) => Self::SignatureInvalid,
            E::Io(io) if io.kind() == std::io::ErrorKind::Other => Self::InstallFailed,
            E::Io(_) => Self::DownloadInterrupted,
            // The plugin's minimum-system-version variant; name may
            // shift between plugin minor versions, hence the catch-all
            // string check on the Display impl.
            other if format!("{}", other).contains("minimumSystemVersion") => Self::UnsupportedPlatform,
            _ => Self::ManifestMalformed,  // conservative — unknown errors look like bad manifest
        }
    }
}
```

The final catch-all to `ManifestMalformed` is the only place a generic mapping occurs, and even that is documented + tested: any genuinely unknown plugin error degrades to "the server gave us something we couldn't parse", which is the most user-friendly framing for an unrecognised plugin error.

## Cross-language drift fixture

`src-tauri/tests/fixtures/update-failure-strings.json` (per data-model.md). Asserted in Rust by the same pattern as spec 003's `zone-error-strings.json` integration test. Asserted in TS by `src/__tests__/UpdateIndicator.errors.test.tsx`.
