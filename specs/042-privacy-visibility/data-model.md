# Data Model: Privacy Visibility (spec 042)

No state machines, no persistence, no lifecycle. Two static shapes.

## 1. Fact base (`src/lib/privacy-facts.ts`)

```ts
export const PRIVACY_BADGE_TEXT: string;        // the one-line badge claim (humanizer-gated)
export const PRIVACY_NEVER_LEAVES: readonly string[];  // ['dokument', 'instruktioner', 'resultat'] — the scope
export const PRIVACY_NETWORK_USES: readonly string[];  // the two honest exceptions, one sentence each
```

Constraints (pinned by tests):
- Every machine reference: "din dator" (no "din Mac" in app strings).
- No string claims app-level "never uses the internet".
- `PRIVACY_NETWORK_USES.length === 2` — exactly the model download and the update check; adding a third would mean Principle I changed, and this test failing is the alarm.

## 2. Rendered surfaces

| Surface | Source | Size | Names network uses? |
|---|---|---|---|
| Badge (`PrivacyBadge.tsx`) | `PRIVACY_BADGE_TEXT` | 1 line | no |
| Wizard welcome (`wizard-strings` pair) | amended `welcome_paragraph`, `welcome_privacy_line` | 2 short lines | no (download note covers the model) |
| Wizard download note | existing `welcome_download_note` (verbatim) | 1 line | model only (in context) |
| Help entry (`_privacy_help` ×3 mirrors) | `PRIVACY_HELP_TITLE/_BODY` | short paragraph | **yes — both** |
| README "Privacy guarantees" | manual section | section | **yes — both** |

## 3. PrivacyBadge component

- Props: none. State: none. Interaction: none (no link, no tabIndex, no handlers).
- Render: a `<p data-privacy-badge>` with `PRIVACY_BADGE_TEXT`, exposed to assistive tech as content.
- Visibility: rendered exactly where the grid is rendered (same conditional branch in App.tsx) — `BadgeAlwaysWithGrid` falls out of co-location, not synchronization.

## Relationships

```
privacy-facts.ts ──→ PrivacyBadge.tsx (verbatim)
                ──→ help PRIVACY_HELP body (quotes the facts)   ←─ 3-way mirror pins Rust/JSON/TS
vocabulary tests ──→ pin wizard-strings + facts + help body to the same rules
```
