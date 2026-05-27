// Spec 007 / T004 — UpdateFailure Swedish vocabulary + plugin error mapping.
//
// Six-variant enum carrying the Swedish copy. Independent of
// `ZoneFailure` because update failures are app-global, not per-zone.

use serde::{Deserialize, Serialize};

/// FR-013 — six Swedish-localised failure variants. Each Swedish copy
/// satisfies the SwedishCopy invariants from spec 003: ≤ 80 chars,
/// no English `Error:` prefix, non-empty.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum UpdateFailure {
    #[error("Kan inte nå GitHub — kontrollera nätverksanslutningen")]
    NoNetwork,

    #[error("Uppdateringsservern svarade med ogiltigt innehåll")]
    ManifestMalformed,

    #[error("Säkerhetskontrollen misslyckades — uppdateringen installeras inte")]
    SignatureInvalid,

    #[error("Nedladdningen avbröts — försök igen")]
    DownloadInterrupted,

    #[error("Kunde inte installera uppdateringen")]
    InstallFailed,

    #[error("Den nya versionen kräver en nyare macOS — uppdatera macOS först")]
    UnsupportedPlatform,
}

impl UpdateFailure {
    pub const ALL: [Self; 6] = [
        Self::NoNetwork,
        Self::ManifestMalformed,
        Self::SignatureInvalid,
        Self::DownloadInterrupted,
        Self::InstallFailed,
        Self::UnsupportedPlatform,
    ];

    pub fn snake_case_key(self) -> &'static str {
        match self {
            Self::NoNetwork => "no_network",
            Self::ManifestMalformed => "manifest_malformed",
            Self::SignatureInvalid => "signature_invalid",
            Self::DownloadInterrupted => "download_interrupted",
            Self::InstallFailed => "install_failed",
            Self::UnsupportedPlatform => "unsupported_platform",
        }
    }
}

// T009 — plugin error → UpdateFailure mapping. The plugin's `Error`
// shape may shift between minor versions; we match conservatively.
// Note: tauri-plugin-updater's Error enum is not pub-exposed in
// a stable shape across versions, so we map via the Display string.
impl UpdateFailure {
    pub fn from_plugin_error(e: &dyn std::fmt::Display) -> Self {
        let s = format!("{e}").to_lowercase();
        if s.contains("connect")
            || s.contains("timed out")
            || s.contains("timeout")
            || s.contains("dns")
            || s.contains("unreachable")
        {
            Self::NoNetwork
        } else if s.contains("minisign") || s.contains("signature") {
            Self::SignatureInvalid
        } else if s.contains("minimum") && s.contains("version") {
            Self::UnsupportedPlatform
        } else if s.contains("json") || s.contains("parse") || s.contains("malformed") {
            Self::ManifestMalformed
        } else if s.contains("install") || s.contains("write") || s.contains("rename") {
            Self::InstallFailed
        } else if s.contains("io") || s.contains("disconnect") || s.contains("broken pipe") {
            Self::DownloadInterrupted
        } else {
            // Conservative fallback — unknown plugin errors look like
            // bad manifest content from the user's POV.
            Self::ManifestMalformed
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_variant_starts_with_english_error_prefix() {
        for v in UpdateFailure::ALL {
            let s = v.to_string();
            assert!(
                !s.starts_with("Error:"),
                "UpdateFailure::{v:?} has English `Error:` prefix"
            );
            assert!(
                !s.to_lowercase().contains("error"),
                "UpdateFailure::{v:?} contains the English word 'error'"
            );
        }
    }

    #[test]
    fn every_variant_at_most_80_chars() {
        for v in UpdateFailure::ALL {
            let len = v.to_string().chars().count();
            assert!(len <= 80, "{v:?} is {len} chars; spec FR-014 caps at 80");
        }
    }

    #[test]
    fn every_variant_non_empty() {
        for v in UpdateFailure::ALL {
            assert!(!v.to_string().is_empty());
        }
    }

    #[test]
    fn snake_case_serialization_matches_key() {
        for v in UpdateFailure::ALL {
            let json = serde_json::to_string(&v).unwrap();
            assert_eq!(json, format!("\"{}\"", v.snake_case_key()));
        }
    }

    #[test]
    fn round_trips_through_serde() {
        for v in UpdateFailure::ALL {
            let json = serde_json::to_string(&v).unwrap();
            let back: UpdateFailure = serde_json::from_str(&json).unwrap();
            assert_eq!(v, back);
        }
    }

    #[test]
    fn connection_error_string_maps_to_no_network() {
        struct StubErr(&'static str);
        impl std::fmt::Display for StubErr {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str(self.0)
            }
        }
        assert_eq!(
            UpdateFailure::from_plugin_error(&StubErr("connect refused")),
            UpdateFailure::NoNetwork
        );
        assert_eq!(
            UpdateFailure::from_plugin_error(&StubErr("dns lookup failed")),
            UpdateFailure::NoNetwork
        );
        assert_eq!(
            UpdateFailure::from_plugin_error(&StubErr("timeout after 30s")),
            UpdateFailure::NoNetwork
        );
    }

    #[test]
    fn signature_error_string_maps_to_signature_invalid() {
        struct StubErr;
        impl std::fmt::Display for StubErr {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("minisign verification failure")
            }
        }
        assert_eq!(
            UpdateFailure::from_plugin_error(&StubErr),
            UpdateFailure::SignatureInvalid
        );
    }

    #[test]
    fn unknown_error_falls_back_to_manifest_malformed() {
        struct StubErr;
        impl std::fmt::Display for StubErr {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("something completely unexpected")
            }
        }
        assert_eq!(
            UpdateFailure::from_plugin_error(&StubErr),
            UpdateFailure::ManifestMalformed
        );
    }
}
