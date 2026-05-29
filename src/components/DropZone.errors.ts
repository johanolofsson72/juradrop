// Spec 003 / T010 + spec 005 + spec 009 — Swedish copy for every ZoneFailure variant.
//
// This is the JS side of the cross-language Swedish-string contract.
// The Rust side lives in `src-tauri/src/zones/errors.rs` (the
// `#[error("…")]` attributes on `ZoneFailure`). A vitest test will
// assert these strings match byte-for-byte (T048 cross-language drift
// assertion). When updating either side, update both.

import type { ZoneFailure } from '@/lib/tauri-bridge';

export const SWEDISH_ZONE_ERROR = {
  invalid_format: 'Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt',
  multiple_files: 'Ett dokument i taget',
  zone_busy: 'Vänta tills föregående dokument är klart',
  zone_disabled: 'AI är inte redo ännu',
  parse_error: 'Kunde inte läsa dokumentet',
  password_protected: 'Dokumentet är lösenordsskyddat',
  empty_text: 'Dokumentet innehåller ingen text',
  model_error: 'AI-motorn svarade inte — försök igen',
  save_error: 'Kunde inte spara sammanfattningen',
  // Spec 005 — PDF image-only + text-encoding errors.
  no_extractable_text: 'Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än',
  unsupported_encoding: 'Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen',
  // Spec 009 — format-named long-tail variants.
  rtf_parse_error: 'Kunde inte läsa .rtf-filen',
  pages_parse_error: 'Kunde inte läsa .pages-filen',
  odt_parse_error: 'Kunde inte läsa .odt-filen',
  // Spec 024 — oversized-file guard.
  file_too_large: 'Filen är för stor — max 50 MB',
} as const satisfies Record<ZoneFailure, string>;

export type ZoneFailureCopy = (typeof SWEDISH_ZONE_ERROR)[ZoneFailure];
