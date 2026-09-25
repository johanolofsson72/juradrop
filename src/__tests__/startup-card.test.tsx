// Spec 051 — startup tips + "Nytt i versionen".
//
// ===== FUNCTIONAL COVERAGE INVENTORY =====
// 1. Tip shown on launch (SC-157)
// 2. Next launch shows the next tip; the list cycles (SC-158)
// 3. "Nästa tips" steps forward and is remembered (SC-159)
// 4. × hides the card for the session (SC-160)
// 5. Settings "Visa tips vid start" off → no tip (SC-161)
// 6. What's-new once after an update, then tips again (SC-162)
// 7. Fresh install → tip, never what's-new (SC-163)
// 8. Corrupt / blocked storage → defaults, no crash (SC-164)
// 9. Nothing renders before the decision (SC-165)
// 10. Card only in the zone-grid path, never over the wizard (FR-001)
// =========================================

import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { StartupCard } from '@/components/StartupCard';
import { StartupSection } from '@/components/SettingsPanelStartup';
import {
  DEFAULT_PREFS,
  STARTUP_KEY,
  decideCard,
  loadPrefs,
  sanitizePrefs,
  savePrefs,
  type StartupPrefs,
} from '@/lib/startup-prefs';
import { useStartupStore } from '@/lib/startup-store';
import { RELEASE_NOTES, STARTUP_STRINGS, STARTUP_TIPS } from '@/lib/startup-strings';
import { useStatusStore } from '@/lib/status-store';
import { App } from '../App';
import { version as APP_VERSION } from '../../package.json';

const N = STARTUP_TIPS.length;
/** A version that has bundled notes — decouples these tests from package.json. */
const NOTED = Object.keys(RELEASE_NOTES)[0]!;

/** Decide this launch as if running `version`, before the card mounts. */
function launchAs(version: string) {
  act(() => useStartupStore.getState().init(version));
}

function stored(): StartupPrefs {
  return JSON.parse(localStorage.getItem(STARTUP_KEY) ?? 'null');
}

function store(prefs: Partial<StartupPrefs>) {
  localStorage.setItem(STARTUP_KEY, JSON.stringify({ ...DEFAULT_PREFS, ...prefs }));
}

/** A new "launch": fresh session state, prefs re-read from storage. */
function relaunch({ fresh = false } = {}) {
  useStartupStore.setState({
    prefs: loadPrefs(),
    card: { kind: 'none' },
    decided: false,
    dismissed: false,
  });
  useStatusStore.setState({ consentGivenThisSession: fresh });
}

beforeEach(() => {
  localStorage.clear();
  relaunch();
});

afterEach(() => cleanup());

// ─── Unit: sanitizePrefs (+ property-based) ─────────────────────────────
describe('sanitizePrefs (FR-009)', () => {
  it('returns defaults for non-objects', () => {
    for (const raw of [null, undefined, 42, 'x', true, [], () => 1]) {
      expect(sanitizePrefs(raw)).toEqual(DEFAULT_PREFS);
    }
  });

  it('keeps valid fields', () => {
    expect(sanitizePrefs({ tipsEnabled: false, nextTip: 3, lastSeenVersion: '0.4.1' })).toEqual({
      tipsEnabled: false,
      nextTip: 3,
      lastSeenVersion: '0.4.1',
    });
  });

  it('repairs each bad field independently', () => {
    expect(sanitizePrefs({ tipsEnabled: 'yes', nextTip: 2, lastSeenVersion: 7 })).toEqual({
      tipsEnabled: true,
      nextTip: 2,
      lastSeenVersion: null,
    });
  });

  it.each([-1, 1.5, NaN, Infinity, 1_000_001, '3'])('rejects index %s', (n) => {
    expect(sanitizePrefs({ nextTip: n }).nextTip).toBe(0);
  });

  it('accepts the index boundaries 0 and 1 000 000', () => {
    expect(sanitizePrefs({ nextTip: 0 }).nextTip).toBe(0);
    expect(sanitizePrefs({ nextTip: 1_000_000 }).nextTip).toBe(1_000_000);
  });

  it('rejects an empty or oversized version string', () => {
    expect(sanitizePrefs({ lastSeenVersion: '' }).lastSeenVersion).toBeNull();
    expect(sanitizePrefs({ lastSeenVersion: 'v'.repeat(65) }).lastSeenVersion).toBeNull();
    expect(sanitizePrefs({ lastSeenVersion: 'v'.repeat(64) }).lastSeenVersion).toBe('v'.repeat(64));
  });

  it('PBT: any JSON value sanitizes to a well-typed prefs object', () => {
    // Deterministic pseudo-random generator — no fast-check dependency.
    let seed = 0x2f6b;
    const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
    const atoms = [null, true, false, 0, -3, 2.5, 1e9, '', '0.5.0', 'x'.repeat(100), [], {}];
    const pick = () => atoms[Math.floor(rnd() * atoms.length)];
    for (let i = 0; i < 2000; i += 1) {
      const raw = rnd() < 0.2 ? pick() : { tipsEnabled: pick(), nextTip: pick(), lastSeenVersion: pick(), extra: pick() };
      const p = sanitizePrefs(JSON.parse(JSON.stringify(raw ?? null)));
      expect(typeof p.tipsEnabled).toBe('boolean');
      expect(Number.isInteger(p.nextTip) && p.nextTip >= 0).toBe(true);
      expect(p.lastSeenVersion === null || typeof p.lastSeenVersion === 'string').toBe(true);
      expect(Object.keys(p).sort()).toEqual(['lastSeenVersion', 'nextTip', 'tipsEnabled']);
    }
  });
});

describe('loadPrefs / savePrefs (FR-009)', () => {
  it('round-trips', () => {
    savePrefs({ tipsEnabled: false, nextTip: 4, lastSeenVersion: '1.0.0' });
    expect(loadPrefs()).toEqual({ tipsEnabled: false, nextTip: 4, lastSeenVersion: '1.0.0' });
  });

  it('corrupt JSON → defaults', () => {
    localStorage.setItem(STARTUP_KEY, '{not json');
    expect(loadPrefs()).toEqual(DEFAULT_PREFS);
  });

  it('a throwing getItem → defaults', () => {
    const throwing = { getItem: () => { throw new Error('blocked'); }, setItem: () => {} };
    expect(loadPrefs(throwing)).toEqual(DEFAULT_PREFS);
  });

  it('a throwing setItem is swallowed', () => {
    const throwing = { getItem: () => null, setItem: () => { throw new Error('quota'); } };
    expect(() => savePrefs(DEFAULT_PREFS, throwing)).not.toThrow();
  });

  it('no storage at all → defaults, save is a no-op', () => {
    expect(loadPrefs(undefined)).toEqual(DEFAULT_PREFS);
    expect(() => savePrefs(DEFAULT_PREFS, undefined)).not.toThrow();
  });
});

// ─── Unit: decideCard truth table ───────────────────────────────────────
describe('decideCard (FR-002/005/006)', () => {
  const notes = { '2.0.0': ['Nyhet'] };
  const base = { runningVersion: '2.0.0', freshInstall: false, tipCount: 5, notes };

  it('upgrade with notes → whats_new, version recorded, index untouched', () => {
    const r = decideCard({ ...base, prefs: { ...DEFAULT_PREFS, nextTip: 2, lastSeenVersion: '1.0.0' } });
    expect(r.card).toEqual({ kind: 'whats_new', version: '2.0.0', notes: ['Nyhet'] });
    expect(r.next).toEqual({ tipsEnabled: true, nextTip: 2, lastSeenVersion: '2.0.0' });
  });

  it('no record + not a first run (upgrade from ≤ 0.4.1) → whats_new', () => {
    expect(decideCard({ ...base, prefs: DEFAULT_PREFS }).card.kind).toBe('whats_new');
  });

  it('fresh install → tip, never whats_new', () => {
    const r = decideCard({ ...base, freshInstall: true, prefs: DEFAULT_PREFS });
    expect(r.card).toEqual({ kind: 'tip', index: 0 });
  });

  it('same version → tip at the stored index, index advances', () => {
    const r = decideCard({ ...base, prefs: { ...DEFAULT_PREFS, nextTip: 3, lastSeenVersion: '2.0.0' } });
    expect(r.card).toEqual({ kind: 'tip', index: 3 });
    expect(r.next.nextTip).toBe(4);
  });

  it('wraps the index at the end of the list', () => {
    const r = decideCard({ ...base, prefs: { ...DEFAULT_PREFS, nextTip: 4, lastSeenVersion: '2.0.0' } });
    expect(r.card).toEqual({ kind: 'tip', index: 4 });
    expect(r.next.nextTip).toBe(0);
  });

  it('a stored index beyond the list is taken modulo', () => {
    const r = decideCard({ ...base, prefs: { ...DEFAULT_PREFS, nextTip: 12, lastSeenVersion: '2.0.0' } });
    expect(r.card).toEqual({ kind: 'tip', index: 2 });
  });

  it('upgrade to a version WITHOUT notes → tip', () => {
    const r = decideCard({ ...base, runningVersion: '3.0.0', prefs: { ...DEFAULT_PREFS, lastSeenVersion: '2.0.0' } });
    expect(r.card.kind).toBe('tip');
    expect(r.next.lastSeenVersion).toBe('3.0.0');
  });

  it('upgrade to a version with an EMPTY notes list → tip', () => {
    const r = decideCard({ ...base, notes: { '2.0.0': [] }, prefs: { ...DEFAULT_PREFS, lastSeenVersion: '1.0.0' } });
    expect(r.card.kind).toBe('tip');
  });

  it('tips off → none, but whats_new still shows on upgrade', () => {
    const off = { ...DEFAULT_PREFS, tipsEnabled: false };
    expect(decideCard({ ...base, prefs: { ...off, lastSeenVersion: '2.0.0' } }).card.kind).toBe('none');
    expect(decideCard({ ...base, prefs: { ...off, lastSeenVersion: '1.0.0' } }).card.kind).toBe('whats_new');
  });

  it('tips off never advances the index', () => {
    const r = decideCard({ ...base, prefs: { ...DEFAULT_PREFS, tipsEnabled: false, nextTip: 3, lastSeenVersion: '2.0.0' } });
    expect(r.next.nextTip).toBe(3);
  });

  it('an empty tip list → none', () => {
    expect(decideCard({ ...base, tipCount: 0, prefs: { ...DEFAULT_PREFS, lastSeenVersion: '2.0.0' } }).card.kind).toBe('none');
  });
});

// ─── Content ────────────────────────────────────────────────────────────
describe('bundled copy (FR-008)', () => {
  it('has at least 12 tips, all distinct and non-empty', () => {
    expect(N).toBeGreaterThanOrEqual(12);
    expect(new Set(STARTUP_TIPS).size).toBe(N);
    STARTUP_TIPS.forEach((t) => expect(t.trim().length).toBeGreaterThan(20));
  });

  it('has no exclamation marks and no emoji (MASTER.md tone)', () => {
    const all = [...STARTUP_TIPS, ...Object.values(RELEASE_NOTES).flat()];
    for (const line of all) {
      expect(line).not.toMatch(/!/);
      expect(line).not.toMatch(/\p{Extended_Pictographic}/u);
    }
  });

});

// ─── Component + store: functional ──────────────────────────────────────
describe('StartupCard — functional', () => {
  it('SC-157: shows a tip on launch', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    render(<StartupCard />);
    expect(screen.getByRole('region', { name: STARTUP_STRINGS.card_region_label })).toBeInTheDocument();
    expect(screen.getByText(STARTUP_TIPS[0]!)).toBeInTheDocument();
  });

  it('SC-158: the next launch shows the next tip, and the list cycles', () => {
    store({ lastSeenVersion: APP_VERSION });
    const seen: string[] = [];
    for (let i = 0; i < N + 1; i += 1) {
      relaunch();
      const { unmount } = render(<StartupCard />);
      seen.push(screen.getByRole('region').querySelector('p')!.textContent!);
      unmount();
    }
    expect(new Set(seen.slice(0, N)).size).toBe(N);
    expect(seen[N]).toBe(seen[0]);
  });

  it('SC-159: Nästa tips steps forward and is remembered for next launch', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    render(<StartupCard />);
    fireEvent.click(screen.getByText(STARTUP_STRINGS.tip_next));
    expect(screen.getByText(STARTUP_TIPS[1]!)).toBeInTheDocument();
    expect(stored().nextTip).toBe(2);
  });

  it('SC-160: × hides the card for this session only', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    const { unmount } = render(<StartupCard />);
    fireEvent.click(screen.getByRole('button', { name: STARTUP_STRINGS.dismiss_label }));
    expect(screen.queryByRole('region')).toBeNull();
    unmount();
    relaunch();
    render(<StartupCard />);
    expect(screen.getByRole('region')).toBeInTheDocument();
  });

  it('SC-161: the settings toggle turns tips off (and persists)', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    render(<StartupSection />);
    const box = screen.getByRole('checkbox', { name: new RegExp(STARTUP_STRINGS.tips_toggle_label) });
    expect(box).toBeChecked();
    fireEvent.click(box);
    expect(box).not.toBeChecked();
    expect(stored().tipsEnabled).toBe(false);
    cleanup();
    relaunch();
    render(<StartupCard />);
    expect(screen.queryByRole('region')).toBeNull();
  });

  it('SC-162: what’s-new shows once after an update, then tips resume', () => {
    store({ lastSeenVersion: '0.0.1' });
    relaunch();
    launchAs(NOTED);
    const { unmount } = render(<StartupCard />);
    expect(screen.getByText(STARTUP_STRINGS.whats_new_heading(NOTED))).toBeInTheDocument();
    for (const line of RELEASE_NOTES[NOTED]!) expect(screen.getByText(line)).toBeInTheDocument();
    fireEvent.click(screen.getByText(STARTUP_STRINGS.whats_new_ok));
    expect(screen.queryByRole('region')).toBeNull();
    unmount();
    relaunch();
    launchAs(NOTED);
    render(<StartupCard />);
    expect(screen.getByText(STARTUP_STRINGS.tip_heading)).toBeInTheDocument();
  });

  it('SC-162b: an upgrade from ≤ 0.4.1 (nothing stored) also shows what’s-new', () => {
    relaunch();
    launchAs(NOTED);
    render(<StartupCard />);
    expect(screen.getByText(STARTUP_STRINGS.whats_new_heading(NOTED))).toBeInTheDocument();
  });

  it('SC-163: a fresh install gets a tip, not what’s-new', () => {
    relaunch({ fresh: true });
    render(<StartupCard />);
    expect(screen.getByText(STARTUP_STRINGS.tip_heading)).toBeInTheDocument();
    expect(stored().lastSeenVersion).toBe(APP_VERSION);
  });

  it('SC-165: renders nothing before the decision', () => {
    useStartupStore.setState({ init: () => {} });
    const { container } = render(<StartupCard />);
    expect(container).toBeEmptyDOMElement();
    // restore the real init for later tests
    useStartupStore.setState({ init: useStartupStore.getInitialState().init });
  });

  it('decides once per session even if mounted twice', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    const a = render(<StartupCard />);
    a.unmount();
    render(<StartupCard />);
    expect(screen.getByText(STARTUP_TIPS[0]!)).toBeInTheDocument();
    expect(stored().nextTip).toBe(1);
  });
});

// ─── Destructive ────────────────────────────────────────────────────────
describe('StartupCard — destructive', () => {
  it('SC-164: corrupt storage → defaults, still renders', () => {
    localStorage.setItem(STARTUP_KEY, '][');
    relaunch();
    expect(() => render(<StartupCard />)).not.toThrow();
    expect(screen.getByRole('region')).toBeInTheDocument();
  });

  it('foreign index 999 999 lands inside the list', () => {
    store({ nextTip: 999_999, lastSeenVersion: APP_VERSION });
    relaunch();
    render(<StartupCard />);
    expect(screen.getByText(STARTUP_TIPS[999_999 % N]!)).toBeInTheDocument();
  });

  it('50 rapid Nästa tips clicks stay in range and cycle correctly', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    render(<StartupCard />);
    const next = screen.getByText(STARTUP_STRINGS.tip_next);
    for (let i = 0; i < 50; i += 1) fireEvent.click(next);
    expect(screen.getByText(STARTUP_TIPS[50 % N]!)).toBeInTheDocument();
    expect(stored().nextTip).toBe((50 % N + 1) % N);
  });

  it('Nästa tips after dismiss is a no-op', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    render(<StartupCard />);
    act(() => useStartupStore.getState().dismiss());
    const before = stored().nextTip;
    act(() => useStartupStore.getState().nextTip());
    expect(stored().nextTip).toBe(before);
  });

  it('Nästa tips on the what’s-new card is a no-op', () => {
    store({ lastSeenVersion: '0.0.1' });
    relaunch();
    launchAs(NOTED);
    render(<StartupCard />);
    act(() => useStartupStore.getState().nextTip());
    expect(useStartupStore.getState().card.kind).toBe('whats_new');
  });

  it('toggle flip-flop ends in the last state', () => {
    relaunch();
    render(<StartupSection />);
    const box = screen.getByRole('checkbox');
    for (let i = 0; i < 7; i += 1) fireEvent.click(box);
    expect(box).not.toBeChecked();
    expect(stored().tipsEnabled).toBe(false);
  });

  it('turning tips off mid-session does not yank the visible card', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    render(<StartupCard />);
    act(() => useStartupStore.getState().setTipsEnabled(false));
    expect(screen.getByRole('region')).toBeInTheDocument();
  });

  it('keyboard: both buttons are reachable and labelled', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    render(<StartupCard />);
    const buttons = screen.getAllByRole('button');
    expect(buttons.map((b) => b.textContent || b.getAttribute('aria-label'))).toEqual([
      STARTUP_STRINGS.tip_next,
      STARTUP_STRINGS.dismiss_label,
    ]);
  });
});

// ─── Integration: App paths (FR-001) ────────────────────────────────────
describe('App integration (FR-001)', () => {
  it('shows the card in the ready zone-grid path', () => {
    store({ lastSeenVersion: APP_VERSION });
    relaunch();
    useStatusStore.setState((s) => ({
      status: { ...s.status, visible: 'klar', sidecar: 'ready', model: 'ready', consent: 'fortsatt' },
    }));
    render(<App />);
    expect(screen.getByRole('region', { name: STARTUP_STRINGS.card_region_label })).toBeInTheDocument();
  });

  it('never shows the card over the first-run wizard', () => {
    relaunch();
    useStatusStore.setState((s) => ({
      status: { ...s.status, visible: 'begar_samtycke', sidecar: 'ready', model: 'not_present', consent: 'not_asked' },
    }));
    render(<App />);
    expect(screen.queryByRole('region', { name: STARTUP_STRINGS.card_region_label })).toBeNull();
    expect(useStartupStore.getState().decided).toBe(false);
  });
});
