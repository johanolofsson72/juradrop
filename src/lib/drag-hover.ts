// Spec 026 — OS drag-hover highlight tracker.
//
// Tauri's OS-level drag-drop (dragDropEnabled defaults to true) suppresses
// the WebView's HTML5 drag events, so the per-zone hover highlight cannot be
// driven by React onDragOver. Instead the Rust side forwards the native
// `Over` / `Leave` events (see lib.rs handle_drag_drop_event) and this
// tracker flips the zone under the cursor between `idle` and `dragover`.
//
// The DOM/store lookups are injected so the routing logic is unit-testable
// without a real WebView (App.tsx wires the live implementations).

import type { ZoneId, ZoneSnapshot } from './tauri-bridge';

export interface DragHoverDeps {
  /** Resolve the zone id under a logical-pixel point, or null if none. */
  zoneAtPoint: (x: number, y: number) => ZoneId | null;
  /** Current snapshot for a zone (undefined if unknown). */
  getZone: (id: ZoneId) => ZoneSnapshot | undefined;
  /** Persist a zone snapshot. */
  setZone: (id: ZoneId, snap: ZoneSnapshot) => void;
}

export interface DragHoverTracker {
  /** Cursor moved to (x, y) during a drag — light up the zone under it. */
  over: (x: number, y: number) => void;
  /** Drag left the window / a drop happened — clear any highlight. */
  clear: () => void;
  /** The currently-highlighted zone, or null. (Exposed for tests.) */
  readonly hovered: ZoneId | null;
}

export function createDragHoverTracker(deps: DragHoverDeps): DragHoverTracker {
  let hovered: ZoneId | null = null;

  const clear = () => {
    if (!hovered) return;
    const snap = deps.getZone(hovered);
    // Only revert OUR transient highlight; never clobber a zone that has
    // since moved to processing/success/error.
    if (snap?.state === 'dragover') {
      deps.setZone(hovered, { ...snap, state: 'idle' });
    }
    hovered = null;
  };

  const over = (x: number, y: number) => {
    const zoneId = deps.zoneAtPoint(x, y);
    if (zoneId === hovered) return; // still over the same zone — no-op
    clear();
    if (!zoneId) return; // over empty space
    const snap = deps.getZone(zoneId);
    // Mirrors DropZone's interactivity gate: only an idle, enabled zone
    // lights up. A processing/disabled zone is never hijacked.
    if (snap && snap.state === 'idle' && !snap.disabled) {
      deps.setZone(zoneId, { ...snap, state: 'dragover' });
      hovered = zoneId;
    }
  };

  return {
    over,
    clear,
    get hovered() {
      return hovered;
    },
  };
}
