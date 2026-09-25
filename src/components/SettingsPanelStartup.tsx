// Spec 051 FR-005 — "Start" section: switch the launch tip on/off.
// Styling mirrors the appearance radiogroup rows (no new design language).

import { useStartupStore } from '@/lib/startup-store';
import { STARTUP_STRINGS } from '@/lib/startup-strings';

export function StartupSection() {
  const enabled = useStartupStore((s) => s.prefs.tipsEnabled);
  const setTipsEnabled = useStartupStore((s) => s.setTipsEnabled);

  return (
    <section className="mb-6" aria-labelledby="settings-section-startup">
      <h2
        id="settings-section-startup"
        className="mb-3 text-xs font-semibold uppercase tracking-wide text-foreground/60"
      >
        {STARTUP_STRINGS.section_title}
      </h2>
      <label
        className="flex cursor-pointer items-start gap-3 rounded-md border border-border p-3 text-sm transition-colors duration-150 hover:bg-accent/40"
        data-settings-startup-tips
      >
        <input
          type="checkbox"
          checked={enabled}
          onChange={(e) => setTipsEnabled(e.target.checked)}
          className="mt-0.5 accent-[#007aff] dark:accent-[#0a84ff]"
        />
        <span>
          <span className="block text-foreground/90">{STARTUP_STRINGS.tips_toggle_label}</span>
          <span className="mt-0.5 block text-xs text-muted-foreground">
            {STARTUP_STRINGS.tips_toggle_helper}
          </span>
        </span>
      </label>
    </section>
  );
}
