import { describe, expect, it, beforeEach, vi } from 'vitest';
import { statusMessage, useStatusStore } from '@/lib/status-store';
import * as bridge from '@/lib/tauri-bridge';
import type { AppStatus, UserVisibleStatus } from '@/lib/tauri-bridge';

vi.mock('@/lib/tauri-bridge', async () => {
  const actual = await vi.importActual<typeof import('@/lib/tauri-bridge')>(
    '@/lib/tauri-bridge',
  );
  return {
    ...actual,
    giveConsent: vi.fn().mockResolvedValue(undefined),
    cancelConsent: vi.fn().mockResolvedValue(undefined),
  };
});

const initial: AppStatus = {
  visible: 'startar',
  sidecar: 'not_started',
  model: 'not_present',
  progress_percent: null,
  consent: 'not_asked',
};

describe('useStatusStore', () => {
  beforeEach(() => {
    useStatusStore.setState({ status: { ...initial } });
    vi.clearAllMocks();
  });

  it('boots with the Startar / NotStarted / NotPresent / NotAsked tuple', () => {
    const s = useStatusStore.getState().status;
    expect(s).toEqual(initial);
  });

  it('setStatus replaces the full snapshot', () => {
    useStatusStore.getState().setStatus({
      visible: 'klar',
      sidecar: 'ready',
      model: 'ready',
      progress_percent: null,
      consent: 'fortsatt',
    });
    expect(useStatusStore.getState().status.visible).toBe('klar');
    expect(useStatusStore.getState().status.sidecar).toBe('ready');
  });

  it('setProgress mutates only progress_percent', () => {
    useStatusStore.getState().setProgress(37);
    const s = useStatusStore.getState().status;
    expect(s.progress_percent).toBe(37);
    expect(s.visible).toBe('startar'); // untouched
    expect(s.sidecar).toBe('not_started'); // untouched
  });

  it('giveConsent forwards to the tauri bridge', async () => {
    await useStatusStore.getState().giveConsent();
    expect(bridge.giveConsent).toHaveBeenCalledTimes(1);
  });

  it('cancelConsent forwards to the tauri bridge', async () => {
    await useStatusStore.getState().cancelConsent();
    expect(bridge.cancelConsent).toHaveBeenCalledTimes(1);
  });
});

describe('statusMessage()', () => {
  const baseline: AppStatus = { ...initial };

  // Exhaustive mapping coverage — every UserVisibleStatus value must produce
  // a Swedish string without leaking English or technical jargon to the UI.
  const cases: Array<{ visible: UserVisibleStatus; expected: string | RegExp }> = [
    { visible: 'startar', expected: 'Startar AI...' },
    { visible: 'klar', expected: 'AI är redo' },
    { visible: 'laddar_ner_modell', expected: 'Laddar ner AI-modell...' },
    { visible: 'begar_samtycke', expected: 'Väntar på att du godkänner nedladdningen.' },
    {
      visible: 'fel_kunde_inte_starta',
      expected: 'AI-motorn kunde inte starta. Starta om JuraDrop.',
    },
    {
      visible: 'fel_porten_upptagen',
      expected: 'Ett annat AI-program använder anslutningen. Stäng det och starta om JuraDrop.',
    },
    {
      visible: 'fel_disk_full',
      expected: 'Inte tillräckligt med diskutrymme. Frigör minst 4 GB.',
    },
    {
      visible: 'fel_modellnedladdning_avbroten',
      expected: 'Modellnedladdningen avbröts. Försök igen.',
    },
    { visible: 'fel_ovantat', expected: 'Något gick fel med AI-motorn. Starta om JuraDrop.' },
    {
      visible: 'modell_saknas_avbruten',
      expected: 'AI-modell saknas. Starta om JuraDrop för att försöka igen.',
    },
  ];

  for (const { visible, expected } of cases) {
    it(`maps ${visible} → its Swedish string`, () => {
      expect(statusMessage({ ...baseline, visible })).toBe(expected);
    });
  }

  it('renders the percent suffix when downloading with progress_percent set', () => {
    expect(
      statusMessage({ ...baseline, visible: 'laddar_ner_modell', progress_percent: 42 }),
    ).toBe('Laddar ner AI-modell... 42%');
  });

  it('omits the percent suffix when downloading with progress_percent null', () => {
    expect(
      statusMessage({ ...baseline, visible: 'laddar_ner_modell', progress_percent: null }),
    ).toBe('Laddar ner AI-modell...');
  });

  it('handles 0% as a real value, not a falsy fallback', () => {
    expect(
      statusMessage({ ...baseline, visible: 'laddar_ner_modell', progress_percent: 0 }),
    ).toBe('Laddar ner AI-modell... 0%');
  });

  it('produces strings with no English leakage', () => {
    const forbidden = /\b(loading|error|please|downloading|model|cancel)\b/i;
    for (const { visible } of cases) {
      const msg = statusMessage({ ...baseline, visible });
      expect(msg, `${visible} → "${msg}"`).not.toMatch(forbidden);
    }
  });

  it('produces strings with no "Error:" prefix or stack-trace markers', () => {
    for (const { visible } of cases) {
      const msg = statusMessage({ ...baseline, visible });
      expect(msg).not.toMatch(/^Error:|at [A-Za-z_]+\(|\bpanic\b/);
    }
  });
});
