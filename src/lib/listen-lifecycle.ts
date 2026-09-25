// Spec 050 FR-010 — Tauri's `listen()` resolves its unlisten function
// asynchronously. A React cleanup that runs before the promise resolves
// (StrictMode's mount → unmount → mount, or a fast unmount) used to find
// `undefined` and leak the listener — in dev, one OS drop dispatched twice.
//
// `disposable(pending)` returns a synchronous stop function that is safe
// to call at any time: before resolution it marks the subscription dead
// and the unlisten runs the moment it arrives; after, it unlistens now.
// Calling it twice is a no-op. A rejected subscription is swallowed here
// (the caller has nothing to unlisten) — callers that care about the
// failure attach their own handler to `pending` before passing it in.
export function disposable(pending: Promise<() => void>): () => void {
  let disposed = false;
  let unlisten: (() => void) | undefined;
  pending.then(
    (fn) => {
      if (disposed) fn();
      else unlisten = fn;
    },
    () => {},
  );
  return () => {
    if (disposed) return;
    disposed = true;
    unlisten?.();
    unlisten = undefined;
  };
}
