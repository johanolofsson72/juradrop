import { describe, expect, it, beforeEach } from 'vitest';
import {
  resolveDark,
  getStoredAppearance,
  persistAppearance,
  applyAppearance,
} from '@/lib/appearance';

// Spec 026 — appearance preference logic (Ljust / Mörkt / Följ systemet).

describe('appearance preference', () => {
  beforeEach(() => {
    window.localStorage.clear();
    document.documentElement.classList.remove('dark');
  });

  it('defaults to "system" when nothing is stored', () => {
    expect(getStoredAppearance()).toBe('system');
  });

  it('reads a persisted preference back', () => {
    window.localStorage.setItem('juradrop-appearance', 'dark');
    expect(getStoredAppearance()).toBe('dark');
  });

  it('ignores a junk stored value and falls back to "system"', () => {
    window.localStorage.setItem('juradrop-appearance', 'neon');
    expect(getStoredAppearance()).toBe('system');
  });

  it('resolveDark is deterministic for explicit light/dark (independent of OS)', () => {
    expect(resolveDark('light')).toBe(false);
    expect(resolveDark('dark')).toBe(true);
  });

  it('applyAppearance toggles the .dark class on <html>', () => {
    applyAppearance('dark');
    expect(document.documentElement.classList.contains('dark')).toBe(true);
    applyAppearance('light');
    expect(document.documentElement.classList.contains('dark')).toBe(false);
  });

  it('persistAppearance both stores and applies', () => {
    persistAppearance('dark');
    expect(window.localStorage.getItem('juradrop-appearance')).toBe('dark');
    expect(document.documentElement.classList.contains('dark')).toBe(true);
  });
});
