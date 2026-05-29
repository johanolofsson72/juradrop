// Spec 010 / T022-T023 + spec 027 — three-row tier selector.
//
// Each row renders ONE of:
//   - a selectable radio (when the tier's model is pulled), or
//   - a `Ladda ned` button + size badge (not pulled, idle), or
//   - a live download progress sub-state (downloading), or
//   - an honest error sub-state with `Försök igen` (failed).
// Spec 027 wires `Ladda ned` to a real streaming pull via the
// tier-download store; at most one tier downloads at a time (FR-009),
// so the other unpulled tier's button is disabled while one runs.

import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';
import { useSettingsStore } from '@/lib/settings-store';
import type { ModelTier } from '@/lib/settings-types';
import { MODEL_TIERS, tierRowMode } from '@/lib/settings-types';
import { useTierDownloadStore } from '@/lib/tier-download-store';
import type { TierDownloadEvent, TierDownloadFailure } from '@/lib/tauri-bridge';

const TIER_LABELS: Record<ModelTier, string> = {
  Snabb: SETTINGS_PANEL_STRINGS.tier_snabb_label,
  Smart: SETTINGS_PANEL_STRINGS.tier_smart_label,
  Stor: SETTINGS_PANEL_STRINGS.tier_stor_label,
};
const TIER_HELPERS: Record<ModelTier, string> = {
  Snabb: SETTINGS_PANEL_STRINGS.tier_snabb_helper,
  Smart: SETTINGS_PANEL_STRINGS.tier_smart_helper,
  Stor: SETTINGS_PANEL_STRINGS.tier_stor_helper,
};
const TIER_SIZES: Record<ModelTier, string> = {
  Snabb: SETTINGS_PANEL_STRINGS.tier_snabb_size,
  Smart: SETTINGS_PANEL_STRINGS.tier_smart_size,
  Stor: SETTINGS_PANEL_STRINGS.tier_stor_size,
};

const FAILURE_STRINGS: Record<TierDownloadFailure, string> = {
  network: SETTINGS_PANEL_STRINGS.tier_download_err_network,
  disk_full: SETTINGS_PANEL_STRINGS.tier_download_err_disk_full,
  not_ready: SETTINGS_PANEL_STRINGS.tier_download_err_not_ready,
  not_found: SETTINGS_PANEL_STRINGS.tier_download_err_not_found,
};

/** Bytes → "5,0 GB" with a Swedish decimal comma (FR-003 / R-010). */
function formatGB(bytes: number): string {
  return `${(bytes / 1e9).toFixed(1).replace('.', ',')} GB`;
}

/** "62 % · 5,0 / 8,1 GB", or the indeterminate label when total is unknown. */
function progressText(ev: TierDownloadEvent): string {
  if (ev.total <= 0) return SETTINGS_PANEL_STRINGS.tier_downloading_label;
  return `${ev.percent} % · ${formatGB(ev.completed)} / ${formatGB(ev.total)}`;
}

export function ModelTierSection() {
  const snapshot = useSettingsStore((s) => s.snapshot);
  const pullState = useSettingsStore((s) => s.pullState);
  const selectTier = useSettingsStore((s) => s.selectTier);
  const active = snapshot?.model_tier ?? 'Smart';

  return (
    <section className="mb-6" aria-labelledby="settings-section-model">
      <h2
        id="settings-section-model"
        className="mb-3 text-xs font-semibold uppercase tracking-wide text-foreground/60"
      >
        {SETTINGS_PANEL_STRINGS.section_model_tier_title}
      </h2>
      <ul className="flex flex-col gap-2" role="radiogroup">
        {MODEL_TIERS.map((tier) => (
          <TierRow
            key={tier}
            tier={tier}
            mode={tierRowMode(pullState, tier)}
            isSelected={active === tier}
            onSelect={() => void selectTier(tier).catch(() => {})}
          />
        ))}
      </ul>
    </section>
  );
}

interface TierRowProps {
  tier: ModelTier;
  mode: 'radio_selectable' | 'download_button';
  isSelected: boolean;
  onSelect: () => void;
}

function TierRow({ tier, mode, isSelected, onSelect }: TierRowProps) {
  const label = TIER_LABELS[tier];
  const helper = TIER_HELPERS[tier];
  const size = TIER_SIZES[tier];

  // Spec 027 — download state for THIS tier + the global "is any downloading".
  const current = useTierDownloadStore((s) => s.current);
  const refusal = useTierDownloadStore((s) => s.refusal);
  const start = useTierDownloadStore((s) => s.start);
  const cancel = useTierDownloadStore((s) => s.cancel);
  const retry = useTierDownloadStore((s) => s.retry);

  if (mode === 'radio_selectable') {
    return (
      <li
        data-tier={tier}
        data-tier-mode="radio_selectable"
        className={[
          'rounded-md border p-3 transition-colors',
          isSelected
            ? 'border-[#007aff] bg-[#007aff]/5 dark:border-[#0a84ff] dark:bg-[#0a84ff]/5'
            : 'border-border hover:bg-muted/30',
        ].join(' ')}
      >
        <label className="flex cursor-pointer items-start gap-3">
          <input
            type="radio"
            name="settings-model-tier"
            value={tier}
            checked={isSelected}
            onChange={onSelect}
            className="mt-1"
            aria-label={label}
          />
          <div className="flex flex-col">
            <span className="text-sm font-medium text-foreground">{label}</span>
            <span className="text-xs text-foreground/60">{helper}</span>
          </div>
        </label>
      </li>
    );
  }

  // ===== download_button mode — four sub-states (spec 027) =====
  const isDownloadingThis = current?.tier === tier && current.phase === 'downloading';
  const isErrorThis = current?.tier === tier && current.phase === 'error';
  const anyDownloading = current?.phase === 'downloading';
  const otherDownloading = anyDownloading && current?.tier !== tier;
  const startRefusal = refusal?.tier === tier ? refusal : null;

  return (
    <li
      data-tier={tier}
      data-tier-mode="download_button"
      className="rounded-md border border-border p-3 opacity-90"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 flex-col">
          <span className="text-sm font-medium text-foreground/80">{label}</span>
          <span className="text-xs text-foreground/60">{helper}</span>

          {isDownloadingThis ? (
            <div className="mt-2" data-tier-download-progress={tier}>
              <div
                role="progressbar"
                aria-valuemin={0}
                aria-valuemax={100}
                aria-valuenow={current.total > 0 ? current.percent : undefined}
                aria-label={SETTINGS_PANEL_STRINGS.tier_downloading_label}
                className="h-1.5 w-full overflow-hidden rounded-full bg-muted"
              >
                <div
                  className="h-full rounded-full bg-[#007aff] transition-all duration-500 ease-out dark:bg-[#0a84ff]"
                  style={{
                    width: current.total > 0 ? `${Math.min(100, current.percent)}%` : '100%',
                  }}
                />
              </div>
              <span className="mt-1 block text-xs text-foreground/60">
                {progressText(current)}
              </span>
            </div>
          ) : startRefusal?.reason === 'not_ready' ? (
            // Spec 027 /tla GAP-3: a fresh "not ready" refusal (e.g. from a
            // retry while the AI is still starting) takes priority over a
            // stale failure message left in the slot.
            <span className="mt-1 text-xs text-destructive" role="alert">
              {SETTINGS_PANEL_STRINGS.tier_download_err_not_ready}
            </span>
          ) : isErrorThis && current.failure ? (
            <span className="mt-1 text-xs text-destructive" role="alert">
              {FAILURE_STRINGS[current.failure]}
            </span>
          ) : (
            <span className="mt-1 text-xs text-foreground/50">
              {SETTINGS_PANEL_STRINGS.tier_not_downloaded_badge} — {size}
            </span>
          )}
        </div>

        {/* Right-hand control: Avbryt while downloading, Försök igen on error, else Ladda ned. */}
        {isDownloadingThis ? (
          <button
            type="button"
            onClick={() => void cancel(tier)}
            className="shrink-0 rounded-md border border-border px-3 py-1 text-xs font-medium text-foreground/80 transition-colors duration-150 hover:bg-muted/60"
            data-tier-cancel={tier}
          >
            {SETTINGS_PANEL_STRINGS.tier_download_cancel}
          </button>
        ) : isErrorThis ? (
          <button
            type="button"
            onClick={() => void retry(tier)}
            className="shrink-0 rounded-md border border-[#007aff] px-3 py-1 text-xs font-medium text-[#007aff] transition-colors duration-150 hover:bg-[#007aff]/10 dark:border-[#0a84ff] dark:text-[#0a84ff] dark:hover:bg-[#0a84ff]/10"
            data-tier-retry={tier}
          >
            {SETTINGS_PANEL_STRINGS.tier_download_retry}
          </button>
        ) : (
          <button
            type="button"
            onClick={() => void start(tier)}
            disabled={otherDownloading}
            className="shrink-0 rounded-md border border-[#007aff] px-3 py-1 text-xs font-medium text-[#007aff] transition-colors duration-150 hover:bg-[#007aff]/10 disabled:cursor-not-allowed disabled:opacity-40 dark:border-[#0a84ff] dark:text-[#0a84ff] dark:hover:bg-[#0a84ff]/10"
            data-zone-pick-tier={tier}
            data-tier-download-button={tier}
          >
            {SETTINGS_PANEL_STRINGS.tier_ladda_ned_button}
          </button>
        )}
      </div>
    </li>
  );
}
