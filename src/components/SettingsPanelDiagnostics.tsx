// Spec 025 / T006 — opt-in local diagnostics section.
//
// A sibling of the Model / Appearance / About sections. Off by default.
// A checkbox toggle flips the consent via the Tauri command; the Swedish
// explanation makes the privacy posture explicit (local-only, content-free,
// off by default), and the local log path is shown as monospace selectable
// text so the user can find + inspect the file. No "send" affordance — ever.

import { useCallback, useEffect, useState } from 'react';

import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';
import {
  getDiagnosticsStatus,
  setDiagnosticsEnabled,
  type DiagnosticsStatus,
} from '@/lib/tauri-bridge';

export function DiagnosticsSection() {
  const [status, setStatus] = useState<DiagnosticsStatus>({ enabled: false, log_path: null });

  useEffect(() => {
    const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
    if (!inTauri) return;
    void getDiagnosticsStatus()
      .then(setStatus)
      .catch(() => {
        /* leave default (off) — never surface a Swedish error for this */
      });
  }, []);

  const onToggle = useCallback((next: boolean) => {
    // Optimistic: reflect the intent immediately, then reconcile.
    setStatus((s) => ({ ...s, enabled: next }));
    void setDiagnosticsEnabled(next)
      .then(setStatus)
      .catch(() => setStatus((s) => ({ ...s, enabled: !next })));
  }, []);

  return (
    <section className="mb-6" aria-labelledby="settings-section-diagnostics">
      <h2
        id="settings-section-diagnostics"
        className="mb-3 text-xs font-semibold uppercase tracking-wide text-foreground/60"
      >
        {SETTINGS_PANEL_STRINGS.section_diagnostics_title}
      </h2>

      <div className="rounded-md border border-border p-3">
        <label className="flex cursor-pointer items-start gap-3">
          <input
            type="checkbox"
            checked={status.enabled}
            onChange={(e) => onToggle(e.target.checked)}
            data-diagnostics-toggle
            className="mt-0.5 h-4 w-4 shrink-0 accent-[#007aff] dark:accent-[#0a84ff]"
          />
          <span className="text-sm text-foreground/80">
            {SETTINGS_PANEL_STRINGS.diagnostics_toggle_label}
          </span>
        </label>

        <p className="mt-2 text-xs leading-relaxed text-foreground/60">
          {SETTINGS_PANEL_STRINGS.diagnostics_explanation}
        </p>

        {status.log_path && (
          <p className="mt-2 text-xs text-foreground/50">
            {SETTINGS_PANEL_STRINGS.diagnostics_path_label}{' '}
            <span className="select-all break-all font-mono" data-diagnostics-path>
              {status.log_path}
            </span>
          </p>
        )}
      </div>
    </section>
  );
}
