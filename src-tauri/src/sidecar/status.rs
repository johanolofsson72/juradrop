// User-visible status enums and derivation logic.
// Mirrors spec.allium SidecarStatus, ModelStatus, ConsentChoice,
// UserVisibleStatus, and AppStatus.

use serde::{Deserialize, Serialize};

use super::client::ClientError;
use super::manager::SidecarError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SidecarStatus {
    NotStarted,
    Starting,
    Ready,
    Crashed,
    Stopping,
    Stopped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelStatus {
    NotPresent,
    Downloading,
    Ready,
    DownloadFailed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ConsentChoice {
    #[default]
    NotAsked,
    Fortsatt,
    Avbryt,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UserVisibleStatus {
    Startar,
    Klar,
    LaddarNerModell,
    BegarSamtycke,
    FelKundeInteStarta,
    FelPortenUpptagen,
    FelDiskFull,
    FelModellnedladdningAvbroten,
    FelOvantat,
    ModellSaknasAvbruten,
}

#[derive(Debug, Clone, Serialize)]
pub struct AppStatus {
    pub visible: UserVisibleStatus,
    pub sidecar: SidecarStatus,
    pub model: ModelStatus,
    pub progress_percent: Option<u8>,
    pub consent: ConsentChoice,
}

// T046: exhaustive mapping from each sidecar/client error variant to its
// user-visible Swedish status. The match arms must NOT use a wildcard `_`
// — adding a new error variant should fail the build until it's mapped.
impl From<&SidecarError> for UserVisibleStatus {
    fn from(e: &SidecarError) -> Self {
        match e {
            SidecarError::BundledBinaryMissing => UserVisibleStatus::FelKundeInteStarta,
            SidecarError::PortBusy => UserVisibleStatus::FelPortenUpptagen,
            SidecarError::StartupTimeout => UserVisibleStatus::FelKundeInteStarta,
            SidecarError::Crashed(_) => UserVisibleStatus::FelOvantat,
            SidecarError::Plugin(_) => UserVisibleStatus::FelKundeInteStarta,
        }
    }
}

impl From<&ClientError> for UserVisibleStatus {
    fn from(e: &ClientError) -> Self {
        match e {
            ClientError::Http(_) => UserVisibleStatus::FelModellnedladdningAvbroten,
            ClientError::Json(_) => UserVisibleStatus::FelModellnedladdningAvbroten,
            ClientError::Timeout => UserVisibleStatus::FelModellnedladdningAvbroten,
            ClientError::EmptyResponse => UserVisibleStatus::FelModellnedladdningAvbroten,
            ClientError::DiskFull => UserVisibleStatus::FelDiskFull,
        }
    }
}

impl AppStatus {
    pub fn derive(
        sidecar: SidecarStatus,
        model: ModelStatus,
        progress_percent: Option<u8>,
        consent: ConsentChoice,
    ) -> Self {
        let visible = match (sidecar, model, consent) {
            (SidecarStatus::NotStarted | SidecarStatus::Starting, _, _) => {
                UserVisibleStatus::Startar
            }
            (SidecarStatus::Ready, ModelStatus::Ready, _) => UserVisibleStatus::Klar,
            (SidecarStatus::Ready, ModelStatus::Downloading, _) => {
                UserVisibleStatus::LaddarNerModell
            }
            (SidecarStatus::Ready, ModelStatus::NotPresent, ConsentChoice::NotAsked) => {
                UserVisibleStatus::BegarSamtycke
            }
            (SidecarStatus::Ready, ModelStatus::NotPresent, ConsentChoice::Avbryt) => {
                UserVisibleStatus::ModellSaknasAvbruten
            }
            (SidecarStatus::Ready, ModelStatus::NotPresent, ConsentChoice::Fortsatt) => {
                UserVisibleStatus::LaddarNerModell
            }
            (SidecarStatus::Ready, ModelStatus::DownloadFailed, _) => {
                UserVisibleStatus::FelModellnedladdningAvbroten
            }
            (SidecarStatus::Crashed, _, _) => UserVisibleStatus::FelOvantat,
            (SidecarStatus::Stopping | SidecarStatus::Stopped, _, _) => UserVisibleStatus::Startar,
        };
        Self {
            visible,
            sidecar,
            model,
            progress_percent,
            consent,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_ready_when_sidecar_and_model_ready() {
        let s = AppStatus::derive(
            SidecarStatus::Ready,
            ModelStatus::Ready,
            None,
            ConsentChoice::Fortsatt,
        );
        assert_eq!(s.visible, UserVisibleStatus::Klar);
    }

    #[test]
    fn derive_begar_samtycke_when_consent_not_asked_and_model_missing() {
        let s = AppStatus::derive(
            SidecarStatus::Ready,
            ModelStatus::NotPresent,
            None,
            ConsentChoice::NotAsked,
        );
        assert_eq!(s.visible, UserVisibleStatus::BegarSamtycke);
    }

    #[test]
    fn derive_modell_saknas_avbruten_when_user_cancelled() {
        let s = AppStatus::derive(
            SidecarStatus::Ready,
            ModelStatus::NotPresent,
            None,
            ConsentChoice::Avbryt,
        );
        assert_eq!(s.visible, UserVisibleStatus::ModellSaknasAvbruten);
    }

    #[test]
    fn derive_laddar_when_downloading() {
        let s = AppStatus::derive(
            SidecarStatus::Ready,
            ModelStatus::Downloading,
            Some(42),
            ConsentChoice::Fortsatt,
        );
        assert_eq!(s.visible, UserVisibleStatus::LaddarNerModell);
        assert_eq!(s.progress_percent, Some(42));
    }

    #[test]
    fn derive_fel_ovantat_when_crashed() {
        let s = AppStatus::derive(
            SidecarStatus::Crashed,
            ModelStatus::Ready,
            None,
            ConsentChoice::Fortsatt,
        );
        assert_eq!(s.visible, UserVisibleStatus::FelOvantat);
    }

    #[test]
    fn derive_startar_when_sidecar_not_yet_ready() {
        let s = AppStatus::derive(
            SidecarStatus::Starting,
            ModelStatus::NotPresent,
            None,
            ConsentChoice::NotAsked,
        );
        assert_eq!(s.visible, UserVisibleStatus::Startar);
    }

    // T046 — exhaustive SidecarError → UserVisibleStatus mapping coverage.
    #[test]
    fn sidecar_error_port_busy_maps_to_fel_porten_upptagen() {
        let e = SidecarError::PortBusy;
        assert_eq!(
            UserVisibleStatus::from(&e),
            UserVisibleStatus::FelPortenUpptagen
        );
    }

    #[test]
    fn sidecar_error_bundled_binary_missing_maps_to_fel_kunde_inte_starta() {
        let e = SidecarError::BundledBinaryMissing;
        assert_eq!(
            UserVisibleStatus::from(&e),
            UserVisibleStatus::FelKundeInteStarta
        );
    }

    #[test]
    fn sidecar_error_startup_timeout_maps_to_fel_kunde_inte_starta() {
        let e = SidecarError::StartupTimeout;
        assert_eq!(
            UserVisibleStatus::from(&e),
            UserVisibleStatus::FelKundeInteStarta
        );
    }

    #[test]
    fn sidecar_error_crashed_maps_to_fel_ovantat() {
        let e = SidecarError::Crashed(Some(137));
        assert_eq!(UserVisibleStatus::from(&e), UserVisibleStatus::FelOvantat);
    }

    #[test]
    fn sidecar_error_plugin_maps_to_fel_kunde_inte_starta() {
        let e = SidecarError::Plugin("dyld error".into());
        assert_eq!(
            UserVisibleStatus::from(&e),
            UserVisibleStatus::FelKundeInteStarta
        );
    }

    // T046 — exhaustive ClientError → UserVisibleStatus mapping coverage.
    #[test]
    fn client_error_disk_full_maps_to_fel_disk_full() {
        let e = ClientError::DiskFull;
        assert_eq!(UserVisibleStatus::from(&e), UserVisibleStatus::FelDiskFull);
    }

    #[test]
    fn client_error_network_variants_map_to_fel_modellnedladdning_avbroten() {
        for e in [
            ClientError::Http("offline".into()),
            ClientError::Json("bad".into()),
            ClientError::Timeout,
            ClientError::EmptyResponse,
        ] {
            assert_eq!(
                UserVisibleStatus::from(&e),
                UserVisibleStatus::FelModellnedladdningAvbroten,
                "{e:?}"
            );
        }
    }
}
