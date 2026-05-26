# Contract: `consent.json` schema

The on-disk persistence of `FirstLaunchConsent` from `spec.allium`. Stored in the macOS app-support directory.

## Path

`{app_data_dir}/consent.json`

On macOS resolves to: `~/Library/Application Support/se.noisycricket.juradrop/consent.json`

## Schema (v1)

```json
{
  "schemaVersion": 1,
  "choice": "fortsatt",
  "askedAt": "2026-05-26T12:34:56.789Z"
}
```

### Field semantics

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `schemaVersion` | integer | yes | Pinned to `1` at this spec. Spec 010 (settings panel) may extend. |
| `choice` | string enum | yes | One of `"fortsatt"` or `"avbryt"`. Absence of file or absence of field = `"not_asked"`. |
| `askedAt` | ISO-8601 UTC timestamp | yes when `choice ∈ {fortsatt, avbryt}` | Records when the modal was answered. Useful for spec 011 telemetry-free debugging (was the consent fresh enough?). |

## Lifecycle

1. **First launch on a clean Mac**: file absent → `consent.choice = NotAsked` → modal shows.
2. **User clicks "Fortsätt"**: write file with `choice = "fortsatt"`. Pull starts.
3. **User clicks "Avbryt"**: write file with `choice = "avbryt"`. Welcome card shows `modell_saknas_avbruten`. Modal MUST NOT re-appear (FR-019: shown exactly once).
4. **User deletes the file manually**: next launch treats as `NotAsked` and shows the modal again. This is intentional — the user can revoke consent by clearing the file.
5. **Schema-version mismatch**: if `schemaVersion > 1` is encountered (e.g., spec 010 extended it), spec-002 code refuses to start and surfaces a Swedish error "Inställningsfilen är skapad av en nyare version av JuraDrop." This is forward-compat guardrail.

## Atomic write contract

1. Serialize to `consent.json.tmp` in the same directory.
2. Call `sync_all()` on the file handle.
3. Rename `consent.json.tmp` → `consent.json` (atomic on macOS APFS).
4. Discard the temp file if rename fails.

Guarantees no partial-write state on power loss.

## What is NOT in this file

- No model tag (`gemma3:4b`) — that's compile-time config, not user state.
- No user identity — there is none.
- No telemetry, no install ID, no UUID. Anything that could be used to fingerprint the user is forbidden by Principle I.
