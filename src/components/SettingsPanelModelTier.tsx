// Spec 010 / T022-T023 — three-row tier selector.
//
// Each row renders EITHER a selectable radio (when the tier's model
// is pulled) OR a `Ladda ned` button + size badge (when not pulled).
// Principle III alignment — the selectable set equals the pulled set
// (rule TierRadioIsOnlyEnabledIfModelPulled).

import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';
import { useSettingsStore } from '@/lib/settings-store';
import type { ModelTier } from '@/lib/settings-types';
import { MODEL_TIERS, tierRowMode } from '@/lib/settings-types';
import { triggerTierDownload } from '@/lib/tauri-bridge';

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
            onDownload={() => void triggerTierDownload(tier).catch(() => {})}
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
  onDownload: () => void;
}

function TierRow({ tier, mode, isSelected, onSelect, onDownload }: TierRowProps) {
  const label = TIER_LABELS[tier];
  const helper = TIER_HELPERS[tier];
  const size = TIER_SIZES[tier];

  if (mode === 'radio_selectable') {
    return (
      <li
        data-tier={tier}
        data-tier-mode="radio_selectable"
        className={[
          'rounded-md border p-3 transition-colors',
          isSelected
            ? 'border-accent bg-accent/5'
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

  // download_button mode
  return (
    <li
      data-tier={tier}
      data-tier-mode="download_button"
      className="rounded-md border border-border p-3 opacity-90"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex flex-col">
          <span className="text-sm font-medium text-foreground/80">{label}</span>
          <span className="text-xs text-foreground/60">{helper}</span>
          <span className="mt-1 text-xs text-foreground/50">
            {SETTINGS_PANEL_STRINGS.tier_not_downloaded_badge} — {size}
          </span>
        </div>
        <button
          type="button"
          onClick={onDownload}
          className="shrink-0 rounded-md border border-accent px-3 py-1 text-xs font-medium text-accent hover:bg-accent/10"
        >
          {SETTINGS_PANEL_STRINGS.tier_ladda_ned_button}
        </button>
      </div>
    </li>
  );
}
