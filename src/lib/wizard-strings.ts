// Spec 008 / T003 — TS mirror of the 12 Swedish wizard strings.
//
// Single source of truth lives in `src-tauri/tests/fixtures/wizard-strings.json`.
// The cross-language drift test (`WizardCopy.errors.test.tsx`) asserts this
// const matches the JSON fixture byte-for-byte. When updating either side,
// update both.

export type WizardStringKey =
  | 'welcome_title'
  | 'welcome_paragraph'
  | 'welcome_privacy_line'
  | 'welcome_download_note'
  | 'welcome_cta_primary'
  | 'welcome_cta_secondary'
  | 'welcome_sidecar_helper'
  | 'progress_label_downloading'
  | 'progress_label_waiting'
  | 'progress_cancel_button'
  | 'progress_eta_unknown'
  | 'progress_error_retry';

export const WIZARD_STRINGS: Record<WizardStringKey, string> = {
  welcome_title: 'Välkommen till JuraDrop',
  welcome_paragraph:
    'JuraDrop läser dokument lokalt på din Mac och hjälper dig sammanfatta, översätta, anonymisera, punktlista och förenkla juridisk text — utan att något skickas till någon molntjänst.',
  welcome_privacy_line: 'Inget dokumentinnehåll lämnar din Mac.',
  welcome_download_note:
    'En AI-modell på cirka 2 GB laddas ner första gången du startar appen — efter det fungerar allt utan nät.',
  welcome_cta_primary: 'Fortsätt',
  welcome_cta_secondary: 'Avbryt',
  welcome_sidecar_helper: 'Förbereder AI-motorn…',
  progress_label_downloading: 'Hämtar AI-modell…',
  progress_label_waiting: 'Väntar på nätverk…',
  progress_cancel_button: 'Avbryt nedladdning',
  progress_eta_unknown: '—',
  progress_error_retry: 'Försök igen',
};
