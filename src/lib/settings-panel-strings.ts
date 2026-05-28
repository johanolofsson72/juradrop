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
  | 'appearance_light'
  | 'appearance_dark'
  | 'about_app_name'
  | 'about_license'
  | 'about_github_button';

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
  appearance_light: 'Ljust läge (följer systemet)',
  appearance_dark: 'Mörkt läge (följer systemet)',
  about_app_name: 'JuraDrop',
  about_license: 'Öppen källkod, MIT-licens',
  about_github_button: 'Visa utgåvor på GitHub',
};

/** Pinned URL for the About section's GitHub Releases button (FR-017). */
export const GITHUB_RELEASES_URL =
  'https://github.com/johanolofsson72/juradrop/releases';
