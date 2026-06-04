# Data Model: Kontakter grouped per person (spec 040)

No persisted entities change. The model below describes the in-memory shape of the combine step and the output format. Mirrors `spec.allium`.

## MergedSection (in-memory, one combine invocation)

| Field | Type | Rules |
|---|---|---|
| heading | String | Exact trimmed heading text (`## David Dahl`). Key for cross-part merging. |
| kind | `person \| ovriga` | `ovriga` iff heading == `## Övriga uppgifter` (exact trimmed match, shared const). |
| first_seen | usize | Order key. Person sections render by first-seen; the ovriga section renders LAST regardless. |
| lines | Vec\<String\> | Trimmed detail lines, first-seen order, exact-trim dedup **within this section only**. |

### Ordering rules

1. Person sections: first-seen order across the part sequence.
2. `## Övriga uppgifter`: always last when non-empty or when it collected headingless lines.
3. No canonical category order exists anymore (spec-013 CANONICAL array removed).

### Membership rules

- A line before any heading in a part → ovriga section (covers whole heading-less parts).
- A section with zero lines → rendered as bare heading (person found, no details). Exception: an EMPTY ovriga section is omitted (nothing unattributed → no section).
- Cross-section duplicates preserved (dedup never crosses a heading boundary).

## Output format (model-facing contract, single + multi part)

```markdown
## <Person name>

- Adress: <street, postal code, city>
- Personnummer: <ÅÅÅÅMMDD-XXXX>
- Telefon: <number>
- E-post: <address>

## <Next person>

- Telefon: <number>

## Övriga uppgifter

- Telefon: <orphan number>
```

- Detail labels: exactly `Adress` / `Personnummer` / `Telefon` / `E-post` (extraction scope unchanged from spec 013).
- Bare person heading (no bullets) is valid output.
- `## Övriga uppgifter` omitted when everything is attributed.
- No greeting/meta-text before the first heading (FR-021 guardrail).

## State transitions

None — the combine step is a pure function `&[String] -> String` (unchanged signature `merge_kontakter(parts: &[String]) -> String`).
