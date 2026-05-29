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
  | 'unsupported_encoding'
  // Spec 009 — format-named long-tail variants. Spec 028 replaced the Pages
  // parse-error with an actionable "not supported" message.
  | 'rtf_parse_error'
  | 'pages_unsupported'
  | 'odt_parse_error'
  // Spec 024 — oversized-file guard.
  | 'file_too_large';

export interface ZoneSnapshot {
  state: ZoneState;
  disabled: boolean;
  failure: ZoneFailure | null;
  job_id: string | null;
  progress_hint: string | null;
}

// =====================================================================
// Spec 004 — six drop zones. Spec 013 — expanded to nine.
// =====================================================================

export type ZoneId =
  | 'sammanfatta'
  | 'tillengelska'
  | 'tillsvenska'
  | 'punktlista'
  | 'anonymisera'
  | 'forenkla'
  // Spec 013 — three new zones expanding from 2×3 to 3×3 grid.
  | 'kontakter'
  | 'generera'
  | 'kallor';

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

/** Spec 025 — opt-in local diagnostics status (consent + local log path). */
export interface DiagnosticsStatus {
  readonly enabled: boolean;
  readonly log_path: string | null;
}

/** Spec 025 — read the current diagnostics consent + log path. */
export async function getDiagnosticsStatus(): Promise<DiagnosticsStatus> {
  return invoke<DiagnosticsStatus>('get_diagnostics_status');
}

/** Spec 025 — flip + persist the local-diagnostics opt-in. */
export async function setDiagnosticsEnabled(enabled: boolean): Promise<DiagnosticsStatus> {
  return invoke<DiagnosticsStatus>('set_diagnostics_enabled', { enabled });
}

/** Spec 016 — accepted file extensions per zone, for the native picker
 *  filter. Generera takes only instruction files; every other zone takes
 *  the supported set. Mirrors the formats the hint copy advertises.
 *  Spec 028 removed `.pages` (modern Pages stores text in undecodable .iwa). */
export function formatFilterFor(zoneId: ZoneId): string[] {
  return zoneId === 'generera'
    ? ['txt', 'md']
    : ['docx', 'pdf', 'txt', 'md', 'rtf', 'odt'];
}

/** Spec 016 — open the native file picker filtered to the zone's accepted
 *  formats and dispatch the chosen file through the same path a drop uses.
 *  A cancelled picker (null) dispatches nothing. The accessible /
 *  keyboard-reachable alternative to OS drag-drop. */
export async function pickFileForZone(zoneId: ZoneId): Promise<void> {
  const { open } = await import('@tauri-apps/plugin-dialog');
  const selected = await open({
    multiple: false,
    directory: false,
    filters: [{ name: 'Dokument', extensions: formatFilterFor(zoneId) }],
  });
  if (typeof selected === 'string') {
    await dispatchToZone(zoneId, [selected]);
  }
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

/** Spec 026 — OS drag hover position (logical px) for lighting up the zone
 *  under the cursor. HTML5 `dragover` never fires in the WebView while
 *  Tauri's OS-level drag-drop is enabled, so the highlight rides this. */
export function subscribeFileDragOver(
  cb: (position: { x: number; y: number }) => void,
): Promise<UnlistenFn> {
  return listen<{ x: number; y: number }>('juradrop://file-dragover', (event) =>
    cb(event.payload),
  );
}

/** Spec 026 — the drag left the window without dropping; clear any highlight. */
export function subscribeFileDragLeave(cb: () => void): Promise<UnlistenFn> {
  return listen('juradrop://file-dragleave', () => cb());
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

// ============================================================
// Spec 010 — settings panel wrappers + event channel.
// ============================================================

import type {
  ModelTier,
  SettingsSnapshot,
  TierPullState,
} from './settings-types';

export async function getSettings(): Promise<SettingsSnapshot> {
  return invoke<SettingsSnapshot>('get_settings');
}

export async function setModelTier(tier: ModelTier): Promise<void> {
  await invoke<void>('set_model_tier', { tier });
}

export async function getTierPullState(): Promise<TierPullState> {
  return invoke<TierPullState>('get_tier_pull_state');
}

export async function triggerTierDownload(tier: ModelTier): Promise<void> {
  await invoke<void>('trigger_tier_download', { tier });
}

export async function getAppVersion(): Promise<string> {
  return invoke<string>('get_app_version');
}

export interface TierDownloadRequest {
  tier: ModelTier;
  model_id: string;
}

/** Subscribe to the `Ladda ned` intent channel. The spec 008 wizard
 *  picks this up and runs the existing model-pull flow. */
export function subscribeTierDownloadRequested(
  cb: (req: TierDownloadRequest) => void,
): Promise<UnlistenFn> {
  return listen<TierDownloadRequest>(
    'juradrop://settings/tier-download-requested',
    (event) => cb(event.payload),
  );
}
