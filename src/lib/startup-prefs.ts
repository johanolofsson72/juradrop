// Spec 051 — pure logic for the startup card: what is persisted, how a
// corrupt value is repaired, and which card a launch shows. No React here,
// so every branch is unit- and property-testable.

export const STARTUP_KEY = 'juradrop-startup';

export interface StartupPrefs {
  tipsEnabled: boolean;
  /** Index of the tip the NEXT launch shows (taken modulo the list). */
  nextTip: number;
  /** The app version the user last launched; null on a fresh profile. */
  lastSeenVersion: string | null;
}

export const DEFAULT_PREFS: StartupPrefs = {
  tipsEnabled: true,
  nextTip: 0,
  lastSeenVersion: null,
};

/** Upper bound for a stored index; anything above is foreign data. */
const MAX_INDEX = 1_000_000;

/**
 * FR-009 — accept anything (it came out of localStorage, possibly written
 * by an older build or edited by hand) and return a valid StartupPrefs.
 * Each field is repaired on its own; one bad field never discards the rest.
 */
export function sanitizePrefs(raw: unknown): StartupPrefs {
  const obj = raw !== null && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const tipsEnabled =
    typeof obj.tipsEnabled === 'boolean' ? obj.tipsEnabled : DEFAULT_PREFS.tipsEnabled;
  const n = obj.nextTip;
  const nextTip =
    typeof n === 'number' && Number.isInteger(n) && n >= 0 && n <= MAX_INDEX ? n : 0;
  const v = obj.lastSeenVersion;
  const lastSeenVersion = typeof v === 'string' && v.length > 0 && v.length <= 64 ? v : null;
  return { tipsEnabled, nextTip, lastSeenVersion };
}

type Storage = Pick<globalThis.Storage, 'getItem' | 'setItem'> | undefined;

function storage(): Storage {
  try {
    return typeof window === 'undefined' ? undefined : window.localStorage;
  } catch {
    return undefined; // Access itself can throw in locked-down WebViews.
  }
}

export function loadPrefs(store: Storage = storage()): StartupPrefs {
  try {
    const raw = store?.getItem(STARTUP_KEY);
    return raw ? sanitizePrefs(JSON.parse(raw)) : { ...DEFAULT_PREFS };
  } catch {
    return { ...DEFAULT_PREFS };
  }
}

/** Best-effort: a preference that can't be persisted still applies now. */
export function savePrefs(prefs: StartupPrefs, store: Storage = storage()): void {
  try {
    store?.setItem(STARTUP_KEY, JSON.stringify(prefs));
  } catch {
    // Storage full or blocked — keep running on the in-memory value.
  }
}

export type StartupCard =
  | { kind: 'none' }
  | { kind: 'tip'; index: number }
  | { kind: 'whats_new'; version: string; notes: readonly string[] };

export interface DecideInput {
  prefs: StartupPrefs;
  runningVersion: string;
  /** Consent was given this session: a first run, not an upgrade. */
  freshInstall: boolean;
  tipCount: number;
  notes: Readonly<Record<string, readonly string[]>>;
}

/**
 * FR-002/005/006 — the one decision a launch makes, plus the prefs to
 * persist afterwards (the running version is always recorded; the tip
 * index advances only when a tip is actually shown). FR-001 (never over
 * the wizard) is structural: the card only mounts in the zone-grid path.
 */
export function decideCard(input: DecideInput): { card: StartupCard; next: StartupPrefs } {
  const { prefs, runningVersion, freshInstall, tipCount, notes } = input;
  const next: StartupPrefs = { ...prefs, lastSeenVersion: runningVersion };

  const upgraded = freshInstall
    ? false // a first run has nothing "new" to compare against
    : prefs.lastSeenVersion === null
      ? true // no record + no first run this launch = an existing install (≤ 0.4.1)
      : prefs.lastSeenVersion !== runningVersion;
  const versionNotes = notes[runningVersion];
  if (upgraded && versionNotes && versionNotes.length > 0) {
    return { card: { kind: 'whats_new', version: runningVersion, notes: versionNotes }, next };
  }

  if (prefs.tipsEnabled && tipCount > 0) {
    const index = prefs.nextTip % tipCount;
    return { card: { kind: 'tip', index }, next: { ...next, nextTip: (index + 1) % tipCount } };
  }

  return { card: { kind: 'none' }, next };
}
