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

/** Spec 008 / FR-013 — cancel the in-flight model pull. Silent no-op
 *  if no pull is in flight; idempotent across all non-downloading
 *  states. Never touches the consent record. */
export async function cancelModelPull(): Promise<void> {
  await invoke<void>('cancel_model_pull');
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
  | 'save_error'
  // Spec 005 — two new variants for the four-format input matrix.
  | 'no_extractable_text'
  | 'unsupported_encoding';

export interface ZoneSnapshot {
  state: ZoneState;
  disabled: boolean;
  failure: ZoneFailure | null;
  job_id: string | null;
  progress_hint: string | null;
}

// =====================================================================
// Spec 004 — six drop zones.
// =====================================================================

export type ZoneId =
  | 'sammanfatta'
  | 'tillengelska'
  | 'tillsvenska'
  | 'punktlista'
  | 'anonymisera'
  | 'forenkla';

export interface FileDroppedPayload {
  paths: string[];
  position: { x: number; y: number };
}

/** Cancel an in-flight summarization on a specific zone. Idempotent —
 *  silent no-op when (zoneId, jobId) doesn't match the current
 *  in-flight job for that zone. */
export async function cancelSummary(zoneId: ZoneId, jobId: string): Promise<void> {
  await invoke<void>('cancel_summary', { zoneId, jobId });
}

/** Dispatch a file drop to a specific zone. The WebView resolves the
 *  zone via `document.elementFromPoint` after the
 *  `juradrop://file-dropped` event and invokes this command. */
export async function dispatchToZone(zoneId: ZoneId, paths: string[]): Promise<void> {
  await invoke<void>('dispatch_to_zone', { zoneId, paths });
}

/** Subscribe to per-zone state-machine snapshots on
 *  `juradrop://zone/<slug>`. Returns the unlisten function. */
export function subscribeZone(
  zoneId: ZoneId,
  cb: (snap: ZoneSnapshot) => void,
): Promise<UnlistenFn> {
  return listen<ZoneSnapshot>(`juradrop://zone/${zoneId}`, (event) => cb(event.payload));
}

/** Subscribe to the OS-level drag-drop event with CSS-pixel position.
 *  The WebView uses this to look up which `[data-zone-id]` element
 *  was under the cursor at drop time. */
export function subscribeFileDropped(
  cb: (payload: FileDroppedPayload) => void,
): Promise<UnlistenFn> {
  return listen<FileDroppedPayload>('juradrop://file-dropped', (event) => cb(event.payload));
}

// =====================================================================
// Spec 007 — auto-updater types + commands + subscription.
// =====================================================================

export type UpdateFailureVariant =
  | 'no_network'
  | 'manifest_malformed'
  | 'signature_invalid'
  | 'download_interrupted'
  | 'install_failed'
  | 'unsupported_platform';

export type UpdateStatus =
  | { state: 'unknown' }
  | { state: 'checking' }
  | { state: 'up_to_date'; version: string; checked_at: string }
  | {
      state: 'available';
      version: string;
      notes: string;
      download_url: string;
      dismissed: boolean;
    }
  | { state: 'downloading'; version: string; progress_pct: number }
  | {
      state: 'ready_to_install';
      version: string;
      deferred: boolean;
      dismissed: boolean;
    }
  | { state: 'restarting'; version: string }
  | {
      state: 'failed';
      failure: UpdateFailureVariant;
      message: string;
      checked_at: string;
    };

export async function checkForUpdatesNow(): Promise<void> {
  await invoke<void>('check_for_updates_now');
}

export async function installUpdateNow(): Promise<void> {
  await invoke<void>('install_update_now');
}

export async function confirmRestartInstall(): Promise<void> {
  await invoke<void>('confirm_restart_install');
}

export async function cancelDeferredRestart(): Promise<void> {
  await invoke<void>('cancel_deferred_restart');
}

export async function dismissUpdateIndicator(): Promise<void> {
  await invoke<void>('dismiss_update_indicator');
}

/** Subscribe to the update-lifecycle event channel.
 *  SC-007: `juradrop://update-status` is unique — no collision with
 *  `juradrop://status`, `juradrop://progress`, `juradrop://file-dropped`,
 *  or any `juradrop://zone/<slug>` channel. */
export function subscribeUpdateStatus(
  cb: (status: UpdateStatus) => void,
): Promise<UnlistenFn> {
  return listen<UpdateStatus>('juradrop://update-status', (event) => cb(event.payload));
}
