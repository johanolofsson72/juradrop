// Spec 010 / T043 — About section: app name, version, license, GitHub.
//
// FR-016 / FR-017 — version comes from the Rust `get_app_version`
// command (semver from package_info). GitHub link goes through
// Tauri's `shell.open` — no embedded webview, no app navigation.

import { open as shellOpen } from '@tauri-apps/plugin-shell';
import { useEffect, useState } from 'react';

import {
  GITHUB_RELEASES_URL,
  SETTINGS_PANEL_STRINGS,
} from '@/lib/settings-panel-strings';
import { getAppVersion } from '@/lib/tauri-bridge';

export function AboutSection() {
  const [version, setVersion] = useState<string | null>(null);

  useEffect(() => {
    const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
    if (!inTauri) return;
    void getAppVersion()
      .then(setVersion)
      .catch(() => setVersion(null));
  }, []);

  const handleGitHubClick = () => {
    void shellOpen(GITHUB_RELEASES_URL).catch(() => {
      // FR-017 edge case — silent no-op in release, debug-only warn.
      // The user did not lose data; the click just didn't navigate.
    });
  };

  return (
    <section className="mb-2" aria-labelledby="settings-section-about">
      <h2
        id="settings-section-about"
        className="mb-3 text-xs font-semibold uppercase tracking-wide text-foreground/60"
      >
        {SETTINGS_PANEL_STRINGS.section_about_title}
      </h2>
      <div className="flex flex-col gap-2 rounded-md border border-border p-3">
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-foreground">
            {SETTINGS_PANEL_STRINGS.about_app_name}
          </span>
          <span className="text-xs text-foreground/60" data-settings-version>
            {version ?? '—'}
          </span>
        </div>
        <span className="text-xs text-foreground/60">
          {SETTINGS_PANEL_STRINGS.about_license}
        </span>
        <button
          type="button"
          onClick={handleGitHubClick}
          className="mt-1 self-start rounded-md border border-accent px-3 py-1 text-xs font-medium text-accent hover:bg-accent/10"
          data-settings-github
        >
          {SETTINGS_PANEL_STRINGS.about_github_button}
        </button>
      </div>
    </section>
  );
}
