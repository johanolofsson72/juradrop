# Plan — 051 startup-tips-whats-new

## Files

| File | Role |
|---|---|
| `src/lib/startup-strings.ts` | All Swedish copy: 14 tips, card labels, the settings section, and `RELEASE_NOTES` keyed by version |
| `src/lib/startup-prefs.ts` | Pure: `sanitizePrefs(unknown)`, `loadPrefs()`, `savePrefs()`, `decideCard({...})`. No React. |
| `src/lib/startup-store.ts` | Zustand store: prefs, current card, session-dismissed, `init(version = package.json version)`, `nextTip()`, `dismiss()`, `setTipsEnabled()` |
| `src/components/StartupCard.tsx` | The card (tip / what's new); renders nothing until `init` has run |
| `src/components/SettingsPanelStartup.tsx` | The "Start" section with the "Visa tips vid start" checkbox |
| `src/App.tsx` | Mounts `<StartupCard/>` in the zone-grid path; calls `init` when the status first becomes klar |
| `src/lib/status-store.ts` | `consentGivenThisSession` set on a successful give_consent (the first-run signal) |

## Design (MASTER.md)

The card is a row, not a hero: `rounded-2xl border border-border bg-card/60 px-4 py-3`, `text-sm`, with a lucide icon in `text-muted-foreground`. "Nästa tips" is a text button in the accent colour. × is a 24 px ghost icon button. It matches the InstructionField width (`w-full`). No shadow, no gradient, no scale transforms, and a 150 ms opacity fade that is disabled by reduced-motion.

## Tests

- Unit: `sanitizePrefs` (PBT over arbitrary JSON via fast-check-style generators written with plain loops, since fast-check is not a dep), and the `decideCard` truth table.
- Store: init rotates and persists; nextTip; dismiss; the toggle.
- Component: the card renders the tip, whats_new, and nothing (loading), plus button behaviour. The Settings checkbox.
- Integration: App klar path shows the card; the wizard path does not.
- Destructive: the storage getter/setter throws, corrupt JSON, a huge index, a negative/NaN index, a non-string version, rapid Nästa tips ×50 (stays in range), dismiss then Nästa tips (no-op), a toggle flip-flop.
