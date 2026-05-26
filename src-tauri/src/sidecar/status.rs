// User-visible status enums and derivation logic.
// Mirrors spec.allium SidecarStatus, ModelStatus, ConsentChoice,
// UserVisibleStatus, and AppStatus.

use serde::{Deserialize, Serialize};

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
}
