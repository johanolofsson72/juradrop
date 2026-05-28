# Contract: Help system (FR-018 – FR-024)

## Per-zone popover (FR-018)

- Each `DropZone` card renders a `(?)` button at top-right corner (absolute, no portal).
- Button: `aria-label="Hjälp om <zone-title>"`, `type="button"`.
- Click toggles a popover with `role="tooltip"` containing `ZONE_HELP_STRINGS[zone].short` (≤ 80 chars).
- Dismiss: re-click the icon, Esc, or click outside the popover.
- The popover MUST NOT trigger a drop dispatch when clicked (stopPropagation; the `(?)` is not part of the drop surface).

## Chrome-bar help icon (FR-019, FR-022)

- Position: `fixed right-24 top-3 z-40` — LEFT of GearIcon (`right-14`), which is left of UpdateIndicator (`right-3`). Canonical order L→R: **help, gear, update**.
- `aria-label` Swedish (e.g. "Hjälp"). `data-help-icon` test hook.
- Disabled (`aria-disabled` + `disabled` + opacity-40 + no-op click) when `wizardUp || restartUp` — same predicate as `gearIconEnabled`.

## HelpPanel slide-in (FR-019, FR-020, FR-023)

- Mirrors `SettingsPanel`: `role="dialog"`, `aria-modal="false"`, fixed inset-0 z-50, scrim `bg-black/30`, `aside` 380px from right edge, 200ms ease-out slide.
- Dismiss: Esc, close-X, scrim/outside-click.
- Body lists all 9 zones in canonical order. Each row: title (large), `short` (helper line), `long` (≤ 300 chars), and a format-badge row reusing the `[DOCX]` convention (Generera shows `[TXT] [MD]`; others show the 7-format set).
- `data-help-panel` + `data-help-visibility` test hooks.

## Mutual exclusion (FR-023)

- Opening HelpPanel calls `settingsPanel.closePanel()` synchronously before/with `helpPanel.openPanel()`.
- Opening SettingsPanel calls `helpPanel.closePanel()` synchronously.
- Invariant: `!(HelpPanel.visibility ∈ {open,opening} && SettingsPanel.visibility ∈ {open,opening})`.

## Strings (FR-021, FR-024)

- 9 short + 9 long = 18 strings in `zone-help-strings.json`, Rust `ZONE_HELP_STRINGS`, TS `ZONE_HELP_STRINGS`.
- Byte-for-byte drift parity enforced by the existing T035-lineage drift test (extended to discover the new fixture).
- All copy passes the `humanizer` skill before commit. Swedish, no AI-tells, within char budgets.

## Test surface

- vitest: popover open/close/Esc/outside; panel open/close/Esc/X/scrim; mutual exclusion; modal-gating (disabled during wizard/restart); 18-string render; `data-settings-gear` still present + clickable in 9-zone layout (FR-017 / SC-010).
- Rust: `zone-help-strings.json` drift test (Rust const == fixture); char-budget assertions (short ≤ 80, long ≤ 300).
