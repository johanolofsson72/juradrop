# Contract — Swedish error copy fixture

**Fixture path**: `src-tauri/tests/fixtures/crash-recovery-strings.json`

## Schema

```json
{
  "_comment": "(string — explanatory)",
  "fel_ovantat": "(string — pinned Swedish copy)",
  "model_error": "(string — pinned Swedish copy)"
}
```

Exactly 3 keys. No additional fields.

## Pinned values

| Key | Pinned value | Length (chars) |
|---|---|---|
| `fel_ovantat` | `AI-motorn svarar inte. Starta om JuraDrop.` | 42 |
| `model_error` | `AI-motorn svarade inte — försök igen` | 36 |

Both ≤ 80 chars.

## Cross-language drift contract

Enforced by `src/__tests__/crash-recovery-strings-drift.test.ts`:

1. Both fixture values are loaded from disk via `import fixture from '...crash-recovery-strings.json'`.
2. The TS test asserts the fixture's `fel_ovantat` matches a hard-coded constant.
3. The TS test asserts the fixture's `model_error` matches a hard-coded constant.
4. Both ≤ 80 chars (UTF-8 char count via spread).
5. Neither contains any of the 14 English-leakage denylist substrings (defense in depth — the dedicated denylist test catches this too).

## Rust-side correspondence

The Rust code referencing these strings MUST stay in sync with the fixture. Specifically:

- `UserVisibleStatus::FelOvantat`'s render path (currently in `src/components/WelcomeCard.tsx` consuming the status enum) must surface the `fel_ovantat` string. The TS-side display lookup is the single source of truth at the UI layer.
- `ZoneFailure::ModelError`'s Display impl (in `src-tauri/src/zones/errors.rs`) must return the `model_error` string. The fixture is the source of truth at the cross-language drift boundary.

If the Rust Display impl drifts from the fixture, the existing `zone-error-strings.json` drift test from spec 003 catches it (because `ZoneFailure::ModelError` is already in that fixture under the `model_error` key). Spec 011 adds `model_error` to the new `crash-recovery-strings.json` fixture as well — both fixtures must agree.

## Why duplicate `model_error` across two fixtures?

The cross-spec coupling is intentional:
- `zone-error-strings.json` (spec 003) owns all per-zone failure copy. `model_error` is one of 14 keys there.
- `crash-recovery-strings.json` (spec 011) owns the crash-recovery-specific copy. `model_error` appears here because crash-during-dispatch routes through this variant.

The drift test for spec 011 asserts both files have the SAME value for `model_error`. If they ever disagree, the test fails and forces a deliberate update of both.
