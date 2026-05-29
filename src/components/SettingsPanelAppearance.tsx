// Spec 026 — appearance picker: Ljust / Mörkt / Följ systemet.
//
// Was a read-only row (spec 010 FR-013/FR-014). Spec 026 makes it a real
// 3-way control at the user's request: the preference drives a `.dark` class
// on <html> (see src/lib/appearance.ts). "Följ systemet" mirrors the OS, so
// the default behaves exactly like the old prefers-color-scheme following.
// Styling mirrors the model-tier radiogroup for consistency (no new language).

import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';
import { useAppearanceStore } from '@/lib/appearance-store';
import type { Appearance } from '@/lib/appearance';

const OPTIONS: ReadonlyArray<{ value: Appearance; label: string }> = [
  { value: 'light', label: SETTINGS_PANEL_STRINGS.appearance_option_light },
  { value: 'dark', label: SETTINGS_PANEL_STRINGS.appearance_option_dark },
  { value: 'system', label: SETTINGS_PANEL_STRINGS.appearance_option_system },
];

export function AppearanceSection() {
  const appearance = useAppearanceStore((s) => s.appearance);
  const setAppearance = useAppearanceStore((s) => s.setAppearance);

  return (
    <section className="mb-6" aria-labelledby="settings-section-appearance">
      <h2
        id="settings-section-appearance"
        className="mb-3 text-xs font-semibold uppercase tracking-wide text-foreground/60"
      >
        {SETTINGS_PANEL_STRINGS.section_appearance_title}
      </h2>
      <ul
        className="flex flex-col gap-2"
        role="radiogroup"
        aria-labelledby="settings-section-appearance"
        data-settings-appearance
      >
        {OPTIONS.map((opt) => (
          <li key={opt.value}>
            <label
              className="flex cursor-pointer items-center gap-3 rounded-md border border-border p-3 text-sm transition-colors duration-150 hover:bg-accent/40"
              data-appearance-option={opt.value}
            >
              <input
                type="radio"
                name="appearance"
                value={opt.value}
                checked={appearance === opt.value}
                onChange={() => setAppearance(opt.value)}
                className="accent-[#007aff] dark:accent-[#0a84ff]"
              />
              <span className="text-foreground/90">{opt.label}</span>
            </label>
          </li>
        ))}
      </ul>
    </section>
  );
}
