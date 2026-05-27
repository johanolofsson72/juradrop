import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';

export type SidecarStatus =
  | 'not_started'
  | 'starting'
  | 'ready'
  | 'crashed'
  | 'stopping'
  | 'stopped';

export type ModelStatus = 'not_present' | 'downloading' | 'ready' | 'download_failed';

export type ConsentChoice = 'not_asked' | 'fortsatt' | 'avbryt';

export type UserVisibleStatus =
  | 'startar'
  | 'klar'
  | 'laddar_ner_modell'
  | 'begar_samtycke'
  | 'fel_kunde_inte_starta'
  | 'fel_porten_upptagen'
  | 'fel_disk_full'
  | 'fel_modellnedladdning_avbroten'
  | 'fel_ovantat'
  | 'modell_saknas_avbruten';

export interface AppStatus {
  visible: UserVisibleStatus;
  sidecar: SidecarStatus;
  model: ModelStatus;
  progress_percent: number | null;
  consent: ConsentChoice;
}

export async function getStatus(): Promise<AppStatus> {
  return invoke<AppStatus>('get_status');
}

export async function giveConsent(): Promise<void> {
  await invoke<void>('give_consent');
}

export async function cancelConsent(): Promise<void> {
  await invoke<void>('cancel_consent');
}

export async function runRoundtripDev(): Promise<number> {
  return invoke<number>('run_roundtrip_dev');
}

export function subscribeStatus(cb: (s: AppStatus) => void): Promise<UnlistenFn> {
  return listen<AppStatus>('juradrop://status', (event) => cb(event.payload));
}

export function subscribeProgress(cb: (percent: number) => void): Promise<UnlistenFn> {
  return listen<{ percent: number }>('juradrop://progress', (event) => cb(event.payload.percent));
}

// =====================================================================
// Spec 003 — first drop zone (Sammanfatta).
// =====================================================================

export type ZoneState = 'idle' | 'dragover' | 'processing' | 'success' | 'error';

export type JobOutcome = 'in_flight' | 'success' | 'failure' | 'cancelled';

export type ZoneFailure =
  | 'invalid_format'
  | 'multiple_files'
  | 'zone_busy'
  | 'zone_disabled'
  | 'parse_error'
  | 'password_protected'
  | 'empty_text'
  | 'model_error'
  | 'save_error';

export interface ZoneSnapshot {
  state: ZoneState;
  disabled: boolean;
  failure: ZoneFailure | null;
  job_id: string | null;
  progress_hint: string | null;
}

/** Cancel an in-flight summarization. Idempotent — silent no-op when the
 *  passed `jobId` doesn't match the current in-flight job. */
export async function cancelSummary(jobId: string): Promise<void> {
  await invoke<void>('cancel_summary', { jobId });
}

/** Subscribe to drop-zone state-machine snapshots emitted on
 *  `juradrop://sammanfatta`. Returns the unlisten function. */
export function subscribeZone(cb: (snap: ZoneSnapshot) => void): Promise<UnlistenFn> {
  return listen<ZoneSnapshot>('juradrop://sammanfatta', (event) => cb(event.payload));
}
