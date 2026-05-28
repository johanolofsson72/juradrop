// Spec 010 / T025 — global Cmd+, listener mounted once at App.tsx.
// Calls the supplied `onToggle` when the user presses Cmd+,
// (the macOS-standard preferences shortcut). `preventDefault()` is
// called so the keystroke does not propagate.

import { useEffect } from 'react';

export function useCmdComma(onToggle: () => void): void {
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (event.metaKey && event.key === ',') {
        event.preventDefault();
        onToggle();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onToggle]);
}
