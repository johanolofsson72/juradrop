# Design notes: Sammanfatta drop zone (spec 003)

Visual treatment for the single drop zone introduced in spec 003. References
`../MASTER.md` for color, typography, spacing rules. **This page is a
planning document**; the React implementation in `src/components/SammanfattaZone.tsx`
is the load-bearing source.

## Anatomy

```
┌────────────────────────────────────────┐ ← dashed border, 2 px
│                                        │   (idle: border-muted;
│                                        │    dragover: border-primary, pulse)
│           [icon: arrow-down]           │ ← lucide-react `ArrowDownToLine`
│                                        │
│              Sammanfatta               │ ← title, text-lg, font-semibold
│                                        │
│   Släpp ett .docx-dokument här         │ ← hint, text-sm, text-muted-foreground
│                                        │
└────────────────────────────────────────┘
```

## State treatments

| State | Border | Background | Hint copy | Extras |
|---|---|---|---|---|
| `idle` | `border-muted` dashed | transparent | "Släpp ett .docx-dokument här" | — |
| `dragover` | `border-primary` dashed + soft pulse | `bg-primary/5` | "Släpp för att sammanfatta" | subtle scale-105 |
| `processing` | `border-primary` solid | `bg-primary/5` | "Sammanfattar…" | spinner (lucide `Loader2` + `animate-spin`), "Avbryt" button below |
| `success` | `border-emerald-500` solid | `bg-emerald-500/10` | "Klar — öppnar fil…" | check icon, brief flash |
| `error` | `border-destructive` solid | `bg-destructive/10` | `SWEDISH_ZONE_ERROR[failure]` | warning icon |
| `disabled` | `border-muted` dashed, opacity-60 | transparent | matches `statusMessage(status)` from welcome card | cursor-not-allowed, no drop handler |

Pulse animation: 1.2 s loop, `box-shadow` ramp 0 → 0 0 8px primary/40 → 0. Subtle, not bouncy (Principle VI — no scroll-jacking, no confetti).

## Avbryt (cancel) button

- Visible only when `state === 'processing'`.
- Style: `<Button variant="ghost" size="sm">` from shadcn primitives.
- Position: below the spinner, centred.
- Keyboard: focusable, activates on `Enter` and `Space`.
- Label: literal Swedish "Avbryt".

## Typography

- Title `Sammanfatta`: `text-lg font-semibold tracking-tight` (matches WelcomeCard `CardTitle`).
- Hint: `text-sm text-muted-foreground`.
- Error in zone: `text-sm text-destructive`.
- Success: `text-sm text-emerald-600 dark:text-emerald-400`.

All copy uses SF Pro via the existing Tailwind config. No external fonts.

## Accessibility

- The zone has `role="button"` and `tabIndex={0}` so it is keyboard-focusable.
- A nested `<p role="status" aria-live="polite" aria-atomic="true">` carries the current Swedish progress hint / error string.
- The disabled state announces the reason via `aria-disabled="true"` + the hint text.
- Spinner is wrapped in `<span aria-hidden="true">` — VoiceOver reads the progress hint, not the spinner.

## Motion

Strictly per Principle VI: subtle micro-interactions only.

- Dragover: border pulse + soft scale (1.0 → 1.02). 1.2 s loop.
- Drop accepted: instant spinner fade-in (150 ms).
- Success flash: 800 ms — green border + soft glow → fade to idle.
- Error flash: 500 ms — red border solid → 4.5 s muted → fade to idle.

No bouncing, no shake-on-error, no confetti.
