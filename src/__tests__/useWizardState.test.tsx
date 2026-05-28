// Spec 008 / T007 — truth table for the useWizardState derivation.
//
// Asserts every row of R-001's table maps to the expected phase. The
// hook is a pure function of AppStatus; no React state, no useEffect.

import { describe, expect, it } from 'vitest';

import { deriveWizardPhase } from '@/lib/use-wizard-state';

describe('deriveWizardPhase — R-001 truth table', () => {
  it('fresh install (consent=not_asked) → welcome', () => {
    expect(
      deriveWizardPhase({
        consent: 'not_asked',
        model: 'not_present',
        visible: 'startar',
      }),
    ).toBe('welcome');
  });

  it('user previously cancelled consent (consent=avbryt) → welcome', () => {
    expect(
      deriveWizardPhase({
        consent: 'avbryt',
        model: 'not_present',
        visible: 'startar',
      }),
    ).toBe('welcome');
  });

  it('consent=fortsatt but model missing → welcome', () => {
    expect(
      deriveWizardPhase({
        consent: 'fortsatt',
        model: 'not_present',
        visible: 'startar',
      }),
    ).toBe('welcome');
  });

  it('consent=fortsatt + previous Cancel left model_missing_aborted → welcome', () => {
    expect(
      deriveWizardPhase({
        consent: 'fortsatt',
        model: 'not_present',
        visible: 'modell_saknas_avbruten',
      }),
    ).toBe('welcome');
  });

  it('consent=fortsatt + model download_failed → error', () => {
    expect(
      deriveWizardPhase({
        consent: 'fortsatt',
        model: 'download_failed',
        visible: 'fel_modellnedladdning_avbroten',
      }),
    ).toBe('error');
  });

  it('consent=fortsatt + fel_disk_full → error', () => {
    expect(
      deriveWizardPhase({
        consent: 'fortsatt',
        model: 'downloading',
        visible: 'fel_disk_full',
      }),
    ).toBe('error');
  });

  it('consent=fortsatt + model downloading → progress', () => {
    expect(
      deriveWizardPhase({
        consent: 'fortsatt',
        model: 'downloading',
        visible: 'laddar_ner_modell',
      }),
    ).toBe('progress');
  });

  it('consent=fortsatt + model ready + visible=klar → hidden (SC-002)', () => {
    expect(
      deriveWizardPhase({
        consent: 'fortsatt',
        model: 'ready',
        visible: 'klar',
      }),
    ).toBe('hidden');
  });

  it('error states map to error regardless of model status', () => {
    for (const visible of [
      'fel_kunde_inte_starta',
      'fel_porten_upptagen',
      'fel_ovantat',
      'fel_modellnedladdning_avbroten',
    ] as const) {
      expect(
        deriveWizardPhase({
          consent: 'fortsatt',
          model: 'downloading',
          visible,
        }),
      ).toBe('error');
    }
  });

  it('clarification 4 — sidecar boot does not flip phase; phase stays welcome', () => {
    // While the sidecar boots, consent is still not_asked → welcome.
    // The sidecar status gates the Fortsätt button inside WelcomeWizard,
    // but the phase derivation doesn't read sidecar.status.
    expect(
      deriveWizardPhase({
        consent: 'not_asked',
        model: 'not_present',
        visible: 'startar',
      }),
    ).toBe('welcome');
  });
});
