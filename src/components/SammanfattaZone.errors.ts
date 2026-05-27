// Spec 003 / T010 — Swedish copy for every ZoneFailure variant.
//
// This is the JS side of the cross-language Swedish-string contract.
// The Rust side lives in `src-tauri/src/zones/errors.rs` (the
// `#[error("…")]` attributes on `ZoneFailure`). A vitest test will
// assert these strings match byte-for-byte (T048 cross-language drift
// assertion). When updating either side, update both.

import type { ZoneFailure } from '@/lib/tauri-bridge';

export const SWEDISH_ZONE_ERROR = {
  invalid_format: 'Endast .docx i denna version',
  multiple_files: 'Ett dokument i taget',
  zone_busy: 'Vänta tills föregående dokument är klart',
  zone_disabled: 'AI är inte redo ännu',
  parse_error: 'Kunde inte läsa dokumentet',
  password_protected: 'Dokumentet är lösenordsskyddat',
  empty_text: 'Dokumentet innehåller ingen text',
  model_error: 'AI-motorn svarade inte — försök igen',
  save_error: 'Kunde inte spara sammanfattningen',
} as const satisfies Record<ZoneFailure, string>;

export type ZoneFailureCopy = (typeof SWEDISH_ZONE_ERROR)[ZoneFailure];
