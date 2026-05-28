// Spec 010 / T036 — subscribes to `(prefers-color-scheme: dark)`
// via React 18's `useSyncExternalStore`. Returns `'light' | 'dark'`.
// FR-015 / SC-004 — the change event re-renders within 500 ms, well
// inside the budget (the MediaQueryList event fires synchronously).

import { useSyncExternalStore } from 'react';

export type SystemAppearance = 'light' | 'dark';

function getSnapshot(): SystemAppearance {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
    return 'light';
  }
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function getServerSnapshot(): SystemAppearance {
  return 'light';
}

function subscribe(onChange: () => void): () => void {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
    return () => {};
  }
  const mql = window.matchMedia('(prefers-color-scheme: dark)');
  const handler = () => onChange();
  if (typeof mql.addEventListener === 'function') {
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }
  // Older Safari / WebKit fallback.
  mql.addListener(handler);
  return () => mql.removeListener(handler);
}

export function useSystemAppearance(): SystemAppearance {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
