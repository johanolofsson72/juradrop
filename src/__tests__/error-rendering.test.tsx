import { render, screen } from '@testing-library/react';
import { describe, expect, it, beforeEach } from 'vitest';
import { WelcomeCard } from '../components/WelcomeCard';
import { useStatusStore } from '@/lib/status-store';
import type { AppStatus, UserVisibleStatus } from '@/lib/tauri-bridge';

// T051 — verifies that every error/failure UserVisibleStatus variant renders
// a Swedish string in the welcome card, with no English leakage, no `Error:`
// prefix, and no stack-trace fragments. FR-017 + Principle V.

const baseStatus: AppStatus = {
  visible: 'startar',
  sidecar: 'crashed',
  model: 'not_present',
  progress_percent: null,
  consent: 'not_asked',
};

const setStore = (overrides: Partial<AppStatus>) => {
  useStatusStore.setState((s) => ({ status: { ...s.status, ...overrides } }));
};

interface ErrorCase {
  visible: UserVisibleStatus;
  expected: string;
}

// All status variants that signal a failure or "user must act" state.
const errorCases: ErrorCase[] = [
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
  {
    visible: 'fel_ovantat',
    expected: 'Något gick fel med AI-motorn. Starta om JuraDrop.',
  },
  {
    visible: 'modell_saknas_avbruten',
    expected: 'AI-modell saknas. Starta om JuraDrop för att försöka igen.',
  },
];

// Words that should NEVER appear in user-facing failure copy — common English
// leakage patterns from copy-pasted error strings, plus diagnostic markers
// that belong in logs not in the UI.
const englishLeakage =
  /\b(error|please|loading|downloading|failed|cancel|model|sorry|oops|something)\b/i;
const diagnosticPrefix = /^(Error:|TypeError|RangeError|panic|panicked at)/i;
const stackFragment = /\bat [A-Za-z_$][A-Za-z_$0-9.]*\(|\bsrc-tauri\b|\.rs:\d+/;

describe('WelcomeCard error rendering (T051)', () => {
  beforeEach(() => {
    useStatusStore.setState({ status: { ...baseStatus } });
  });

  for (const { visible, expected } of errorCases) {
    it(`renders the correct Swedish string for ${visible}`, () => {
      setStore({ visible });
      render(<WelcomeCard />);
      expect(screen.getByText(expected)).toBeInTheDocument();
    });

    it(`leaks no English words for ${visible}`, () => {
      setStore({ visible });
      render(<WelcomeCard />);
      const text = screen.getByText(expected).textContent ?? '';
      expect(text, `${visible} → "${text}"`).not.toMatch(englishLeakage);
    });

    it(`shows no diagnostic prefix (Error:, panicked) for ${visible}`, () => {
      setStore({ visible });
      render(<WelcomeCard />);
      const text = screen.getByText(expected).textContent ?? '';
      expect(text).not.toMatch(diagnosticPrefix);
    });

    it(`shows no stack-trace fragments for ${visible}`, () => {
      setStore({ visible });
      render(<WelcomeCard />);
      const text = screen.getByText(expected).textContent ?? '';
      expect(text).not.toMatch(stackFragment);
    });

    it(`applies the destructive color class for ${visible}`, () => {
      setStore({ visible });
      const { container } = render(<WelcomeCard />);
      const live = container.querySelector('[aria-live="polite"]');
      expect(live).not.toBeNull();
      expect(live?.className).toMatch(/text-destructive/);
    });
  }

  it('uses the muted-foreground class (not destructive) for the non-error klar state', () => {
    setStore({ visible: 'klar', sidecar: 'ready', model: 'ready', consent: 'fortsatt' });
    const { container } = render(<WelcomeCard />);
    const live = container.querySelector('[aria-live="polite"]');
    expect(live?.className).toMatch(/text-muted-foreground/);
    expect(live?.className).not.toMatch(/text-destructive/);
  });

  it('uses the muted-foreground class for the downloading state', () => {
    setStore({
      visible: 'laddar_ner_modell',
      sidecar: 'ready',
      model: 'downloading',
      progress_percent: 50,
      consent: 'fortsatt',
    });
    const { container } = render(<WelcomeCard />);
    const live = container.querySelector('[aria-live="polite"]');
    expect(live?.className).toMatch(/text-muted-foreground/);
    expect(live?.className).not.toMatch(/text-destructive/);
  });
});
