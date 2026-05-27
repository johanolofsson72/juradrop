# Design notes: Six-zone grid (spec 004)

The main window switches from a single column (spec 003 — WelcomeCard above
a single SammanfattaZone) to a 2×3 CSS grid of six DropZone instances. The
WelcomeCard stays where it is (status row above the grid). References
`../MASTER.md` for color, typography, and motion rules.

## Anatomy

```
┌──────────────────────────────────────────┐
│            JuraDrop  (welcome card)      │   ← unchanged from spec 003
└──────────────────────────────────────────┘

┌──────────────┬──────────────┬──────────────┐
│  Sammanfatta │ Till engelska│ Till svenska │   ← row 1
│  [ docx ]    │  [ docx ]    │  [ docx ]    │
│  Släpp …     │  Släpp …     │  Släpp …     │
├──────────────┼──────────────┼──────────────┤
│  Punktlista  │ Anonymisera  │   Förenkla   │   ← row 2
│  [ docx ]    │  [ docx ]    │  [ docx ]    │
│  Släpp …     │  Släpp …     │  Släpp …     │
└──────────────┴──────────────┴──────────────┘
```

Each zone reuses the spec 003 visual treatment (dashed border, mono `[ docx ]`
label, title, hint, status announcer, optional `Avbryt` link during
processing). The only per-zone variation is the title text + hint text +
sidecar suffix.

## Layout

- Container: `mx-auto w-full max-w-5xl` (was `max-w-md` for the single zone).
- Grid: `grid grid-cols-3 grid-rows-2 gap-4`.
- Each zone cell: same `min-height: 18rem` from spec 003.

### Responsive collapse

Three breakpoints, declarative via Tailwind:

- ≥ 920 px: `grid-cols-3 grid-rows-2` (the canonical 2×3)
- 520–919 px: `grid-cols-2 grid-rows-3`
- < 520 px: `grid-cols-1 grid-rows-6` (rare on desktop; preserved for completeness)

Reading order across breakpoints stays left-to-right, top-to-bottom: Sammanfatta → TillEngelska → TillSvenska → Punktlista → Anonymisera → Förenkla.

## Typography (per zone)

Identical to spec 003 — `text-2xl font-semibold tracking-tight text-foreground` for the title, `text-sm text-muted-foreground` for the hint and the live region. The `[ docx ]` signature label stays at `text-[11px] font-mono uppercase tracking-[0.32em] text-muted-foreground`.

## Color

All six zones share the same color palette from spec 003:
- Idle: `border-border` dashed.
- Dragover: `border-[#007aff]` (macOS system blue) + `animate-pulse`.
- Processing: same accent border, no pulse.
- Success: `border-emerald-500` solid + `bg-emerald-500/[0.08]`.
- Error: `border-destructive` solid + `bg-destructive/[0.08]`.

No per-zone color differentiation. The Swedish title carries the action identity; color is reserved for state.

## Motion

Unchanged from spec 003:
- Border-color + background-color transitions: 150 ms ease-out.
- Dragover pulse: `animate-pulse` only on the zone the cursor is over.
- Spinner: `animate-spin` only during processing.
- No bouncing, no shake-on-error, no per-zone differentiation (Principle VI).

## Disclaimer paragraphs (Anonymisera + Förenkla only)

These two zones include a Swedish disclaimer paragraph in their **output .docx files** (FR-013 + FR-014), italic, between the FR-009 header and the model body. The disclaimer text:

- Anonymisera: `AI-anonymisering är inte hundra procent — granska resultatet innan du delar.`
- Förenkla: `Förenklad version — granska att inga juridiska poänger gick förlorade.`

The UI does NOT show these disclaimers in the React component; they only appear when the user opens the sidecar in Word. The zone tile itself is identical to the other four.

## Drop routing

The OS-level drop arrives as a `WindowEvent::DragDrop::Drop` carrying a single CSS-pixel position. The Rust handler emits `juradrop://file-dropped { paths, position }`; the React layer calls `document.elementFromPoint(position.x, position.y)` and walks up to the nearest `[data-zone-id]` ancestor (set on each DropZone's root `<section>`). A drop outside any zone is silently ignored — no error flash.

## Accessibility

Each zone independently honors the spec 003 accessibility contract — `role="status"`, `aria-live="polite"`, `aria-atomic="true"` on the live region; `aria-label`, `aria-disabled`, `data-state` on the container. Six independent live regions means a screen reader announces the right zone's state.

When all six zones are disabled (sidecar not Ready), the disabled hint is the same Swedish welcome-card copy (per FR-012). VoiceOver will read the same hint six times if the user tabs through all zones — acceptable, since the disabled-state usually has all zones inactive simultaneously and the user wouldn't tab through more than once.
