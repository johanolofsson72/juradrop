// Spec 051 — the quiet card above the zones: one tip per launch, or, on
// the first launch after an update, what changed in this version.
// Design per design-system/MASTER.md: a row, not a hero — system font,
// CSS-variable colours, lucide icons only, no shadow/gradient/scale,
// 150 ms fade that prefers-reduced-motion switches off.

import { useEffect } from 'react';
import { Lightbulb, Sparkles, X } from 'lucide-react';
import { useStartupStore } from '@/lib/startup-store';
import { STARTUP_STRINGS, STARTUP_TIPS } from '@/lib/startup-strings';

export function StartupCard() {
  const card = useStartupStore((s) => s.card);
  const decided = useStartupStore((s) => s.decided);
  const dismissed = useStartupStore((s) => s.dismissed);
  const init = useStartupStore((s) => s.init);
  const nextTip = useStartupStore((s) => s.nextTip);
  const dismiss = useStartupStore((s) => s.dismiss);

  // Mounted only in the zone-grid path, i.e. once the app is ready.
  useEffect(() => {
    init();
  }, [init]);

  if (!decided || dismissed || card.kind === 'none') return null;

  const isTip = card.kind === 'tip';
  const Icon = isTip ? Lightbulb : Sparkles;
  const heading = isTip
    ? STARTUP_STRINGS.tip_heading
    : STARTUP_STRINGS.whats_new_heading(card.version);

  return (
    <section
      aria-label={STARTUP_STRINGS.card_region_label}
      data-startup-card={card.kind}
      className="flex w-full items-start gap-3 rounded-2xl border border-border bg-card/60 px-4 py-3
                 text-sm animate-in fade-in-0 duration-150 motion-reduce:animate-none"
    >
      <Icon aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
      <div className="min-w-0 flex-1">
        <h2 className="text-xs font-semibold uppercase tracking-wide text-foreground/60">
          {heading}
        </h2>
        {isTip ? (
          <p className="mt-1 leading-relaxed text-foreground/90">{STARTUP_TIPS[card.index]}</p>
        ) : (
          <ul className="mt-1 list-disc space-y-0.5 pl-4 leading-relaxed text-foreground/90">
            {card.notes.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        )}
        <button
          type="button"
          onClick={isTip ? nextTip : dismiss}
          className="mt-2 text-xs font-medium text-primary underline-offset-4 transition-colors
                     duration-150 hover:underline focus-visible:outline-none focus-visible:ring-2
                     focus-visible:ring-ring focus-visible:ring-offset-1"
        >
          {isTip ? STARTUP_STRINGS.tip_next : STARTUP_STRINGS.whats_new_ok}
        </button>
      </div>
      <button
        type="button"
        onClick={dismiss}
        aria-label={STARTUP_STRINGS.dismiss_label}
        className="rounded-md p-1 text-muted-foreground transition-colors duration-150
                   hover:bg-muted/60 hover:text-foreground focus-visible:outline-none
                   focus-visible:ring-2 focus-visible:ring-ring"
      >
        <X aria-hidden="true" className="h-4 w-4" />
      </button>
    </section>
  );
}
