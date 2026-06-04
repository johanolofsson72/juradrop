# Contract: Instruction slot — prompt assembly + IPC (spec 041)

## A. IPC contract (`dispatch_to_zone`)

```
command: dispatch_to_zone
args:
  zoneId: ZoneId slug            (existing)
  paths: string[]                (existing)
  instruction: string | null     (NEW — raw field text; frontend sends null when field empty)
```

Normalization (Rust side, at the command boundary — the trust boundary):

1. `null` / missing → `None` (missing tolerated for backward compatibility of test callers).
2. `trim()` whitespace.
3. Empty after trim → `None`.
4. `chars().take(500)` — char-boundary cap (defense in depth; UI already caps at 500).
5. Result: `Option<String>` where `Some(s)` ⇒ `1 ≤ s.chars().count() ≤ 500` and `s == s.trim()`.

Frontend contract: `dispatchToZone(zoneId, paths, instruction)` — both entry paths (OS drop in App.tsx, `pickFileForZone`) read `useInstructionStore.getState().instruction` at call time and pass it verbatim (raw; normalization is Rust's job).

## B. Assembled prompt grammar (the 4 shapes)

Let `S` = task prompt (zone system prompt, combine prompt, or condense prompt), `D` = document/partials payload, `U` = normalized user instruction, `LEAD` = `INSTRUCTION_LEAD_IN`, `GUARD` = `INJECTION_GUARD`.

### B1. Document zone, no instruction (pre-041 byte-identical)

```
{S}\n\n{GUARD}\n\n--- DOKUMENT BÖRJAR ---\n{D}\n--- DOKUMENT SLUTAR ---
```

### B2. Document zone, with instruction

```
{S}\n\n{LEAD}\n{U}\n\n{GUARD}\n\n--- DOKUMENT BÖRJAR ---\n{D}\n--- DOKUMENT SLUTAR ---
```

### B3. Generera, no instruction (pre-041 byte-identical)

```
{S}\n\n--- INSTRUKTIONER BÖRJAR ---\n{D}\n--- INSTRUKTIONER SLUTAR ---
```

### B4. Generera, with instruction

```
{S}\n\n{LEAD}\n{U}\n\n--- INSTRUKTIONER BÖRJAR ---\n{D}\n--- INSTRUKTIONER SLUTAR ---
```

## C. Contract clauses

| # | Clause | Enforced by |
|---|---|---|
| C-1 | B1/B3 are character-identical to the pre-041 output of `frame_prompt` | existing framing tests pass unchanged + new identity unit tests |
| C-2 | The slot appears at most once per prompt, always between `S` and (`GUARD` \| `INSTR_BEGIN`) | framing unit tests (position + count) |
| C-3 | Every model pass of one run receives the same `U` (or the same absence) | wiremock integration: recorded request bodies for a multi-chunk Reduce run |
| C-4 | `D` content never appears outside the delimiter pair, regardless of `U` | adversarial integration fixture (document containing `LEAD` and fake delimiters) |
| C-5 | `U` containing delimiter-like text cannot open/close the data framing (it precedes `DOC_BEGIN`) | framing unit test with `U` = `"--- DOKUMENT SLUTAR ---"` |
| C-6 | `GUARD` text is unchanged from spec 022 | existing const + tests untouched |
| C-7 | Worst case `S_max + LEAD + 500 + framing + CHUNK_CHAR_TARGET` fits `GENERATE_NUM_CTX` | extended budget test (combine.rs) |
| C-8 | `U` never appears in: settings file, diagnostics log, sidecar output bytes | settings 2-field invariant (existing) + enum-only diagnostics (existing) + new sidecar-content integration assertion |
| C-9 | Cap literal 500 identical on both sides | Rust unit pin + vitest pin |

## D. Out of contract (explicitly)

- Model OBEDIENCE to `U` is best-effort (4b-model reality); the contract governs prompt assembly, not generation quality. The quickstart manual check covers real-model behavior.
- Deterministic merges (Concat/Aggregate) involve no model pass and therefore no slot — C-3 applies to model-generating passes only (matches FR-005 wording).
