// Spec 010 / T006 — TS mirror of the 22 Swedish settings-panel strings.
//
// Single source of truth lives in
// `src-tauri/tests/fixtures/settings-panel-strings.json`.
// The cross-language drift test (`SettingsPanel.strings.test.tsx`)
// asserts this const matches the JSON fixture byte-for-byte. When
// updating either side, update both.

export type SettingsPanelStringKey =
  | 'gear_label'
  | 'panel_title'
  | 'close_label'
  | 'section_model_tier_title'
  | 'section_appearance_title'
  | 'section_about_title'
  | 'tier_snabb_label'
  | 'tier_smart_label'
  | 'tier_stor_label'
  | 'tier_snabb_helper'
  | 'tier_smart_helper'
  | 'tier_stor_helper'
  | 'tier_snabb_size'
  | 'tier_smart_size'
  | 'tier_stor_size'
  | 'tier_ladda_ned_button'
  | 'tier_not_downloaded_badge'
  // Spec 027 — on-demand tier download UI.
  | 'tier_downloading_label'
  | 'tier_download_cancel'
  | 'tier_download_retry'
  | 'tier_download_err_network'
  | 'tier_download_err_disk_full'
  | 'tier_download_err_not_ready'
  | 'tier_download_err_not_found'
  | 'appearance_light'
  | 'appearance_dark'
  // Spec 026 — appearance picker option labels.
  | 'appearance_option_light'
  | 'appearance_option_dark'
  | 'appearance_option_system'
  | 'about_app_name'
  | 'about_license'
  | 'about_github_button'
  // Spec 025 — diagnostics opt-in section.
  | 'section_diagnostics_title'
  | 'diagnostics_toggle_label'
  | 'diagnostics_explanation'
  | 'diagnostics_path_label';

export const SETTINGS_PANEL_STRINGS: Record<SettingsPanelStringKey, string> = {
  gear_label: 'Inställningar',
  panel_title: 'Inställningar',
  close_label: 'Stäng',
  section_model_tier_title: 'Modell',
  section_appearance_title: 'Utseende',
  section_about_title: 'Om JuraDrop',
  tier_snabb_label: 'Snabb',
  tier_smart_label: 'Smart',
  tier_stor_label: 'Stor',
  tier_snabb_helper: 'Snabbast och minst. Bra för korta texter.',
  tier_smart_helper: 'Standardvalet. Bra balans mellan fart och kvalitet.',
  tier_stor_helper: 'Bästa kvaliteten. Tar längre tid och mer plats på disken.',
  tier_snabb_size: '~1.3 GB',
  tier_smart_size: '~3.3 GB',
  tier_stor_size: '~8.1 GB',
  tier_ladda_ned_button: 'Ladda ned',
  tier_not_downloaded_badge: 'Inte nedladdad',
  // Spec 027 — on-demand tier download UI (humanizer-reviewed).
  tier_downloading_label: 'Laddar ned…',
  tier_download_cancel: 'Avbryt',
  tier_download_retry: 'Försök igen',
  tier_download_err_network: 'Nedladdningen avbröts — kolla din uppkoppling.',
  tier_download_err_disk_full: 'Det finns inte plats på disken för modellen.',
  tier_download_err_not_ready: 'AI är inte redo ännu — vänta en stund.',
  tier_download_err_not_found: 'Modellen kunde inte hittas.',
  appearance_light: 'Ljust läge (följer systemet)',
  appearance_dark: 'Mörkt läge (följer systemet)',
  // Spec 026 — picker options (standard macOS Swedish terms).
  appearance_option_light: 'Ljust',
  appearance_option_dark: 'Mörkt',
  appearance_option_system: 'Följ systemet',
  about_app_name: 'JuraDrop',
  about_license: 'Öppen källkod, MIT-licens',
  about_github_button: 'Visa utgåvor på GitHub',
  // Spec 025 — diagnostics opt-in section.
  section_diagnostics_title: 'Felsökningslogg',
  diagnostics_toggle_label: 'Spara felsökningslogg lokalt',
  diagnostics_explanation:
    'Av som standard. Loggen sparas bara på din dator, innehåller aldrig dokumenttext och skickas aldrig någonstans. Slå på den om du vill hjälpa till att felsöka.',
  diagnostics_path_label: 'Loggfil:',
};

/** Pinned URL for the About section's GitHub Releases button (FR-017). */
export const GITHUB_RELEASES_URL =
  'https://github.com/johanolofsson72/juradrop/releases';
