// Spec 007 / T008 — Swedish copy for every UpdateFailure variant.
//
// JS side of the cross-language Swedish-string contract for the
// auto-updater. The Rust side lives in `src-tauri/src/updater/errors.rs`
// (the `#[error("…")]` attributes on `UpdateFailure`). The single
// source of truth is `src-tauri/tests/fixtures/update-failure-strings.json`
// — both sides assert against that fixture, never against each other.

import type { UpdateFailureVariant } from '@/lib/tauri-bridge';

export const SWEDISH_UPDATE_FAILURE = {
  no_network: 'Kan inte nå GitHub — kontrollera nätverksanslutningen',
  manifest_malformed: 'Uppdateringsservern svarade med ogiltigt innehåll',
  signature_invalid: 'Säkerhetskontrollen misslyckades — uppdateringen installeras inte',
  download_interrupted: 'Nedladdningen avbröts — försök igen',
  install_failed: 'Kunde inte installera uppdateringen',
  unsupported_platform: 'Den nya versionen kräver en nyare macOS — uppdatera macOS först',
} as const satisfies Record<UpdateFailureVariant, string>;

export type UpdateFailureCopy = (typeof SWEDISH_UPDATE_FAILURE)[UpdateFailureVariant];
