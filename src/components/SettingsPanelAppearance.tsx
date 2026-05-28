// Spec 010 / T037 — read-only appearance row.
//
// FR-013 — displays the current OS appearance as one of two Swedish
// strings. FR-014 — NO interactive controls; this section has zero
// inputs, buttons, selects, or role="switch" descendants.

import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';
import { useSystemAppearance } from '@/lib/use-system-appearance';

export function AppearanceSection() {
  const appearance = useSystemAppearance();
  const text =
    appearance === 'dark'
      ? SETTINGS_PANEL_STRINGS.appearance_dark
      : SETTINGS_PANEL_STRINGS.appearance_light;
  return (
    <section className="mb-6" aria-labelledby="settings-section-appearance">
      <h2
        id="settings-section-appearance"
        className="mb-3 text-xs font-semibold uppercase tracking-wide text-foreground/60"
      >
        {SETTINGS_PANEL_STRINGS.section_appearance_title}
      </h2>
      <p
        className="rounded-md border border-border p-3 text-sm text-foreground/80"
        data-settings-appearance
      >
        {text}
      </p>
    </section>
  );
}
