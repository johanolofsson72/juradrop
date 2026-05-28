# Contract — On-disk settings file schema

**Path**: `${app_data_dir}/settings.json` — `app_data_dir` resolved via Tauri 2.x `app.path().app_data_dir()`.

**Encoding**: UTF-8, no BOM.

**Format**: One JSON object. No nested objects, no arrays.

## Strict schema

```json
{
  "schema_version": 1,
  "model_tier": "Smart"
}
```

### Allowed keys (exactly these two — no more, no less)

| Key              | Type    | Allowed values                  | Required |
|------------------|---------|---------------------------------|----------|
| `schema_version` | integer | `1`                             | yes      |
| `model_tier`     | string  | `"Snabb"`, `"Smart"`, `"Stor"`  | yes      |

### Forbidden anywhere in the file (BLOCKING — Principle I)

The following content categories MUST NOT appear in the file, NOR as values, NOR encoded inside any value:

- **Document content** — no extracted text, no document body bytes, no SHA hashes of user files.
- **Document paths** — no `~/Documents/...`, no `/Users/...`, no zone-specific recent-file list.
- **Tier-change history** — no list of past tier choices, no "last switched at" timestamp.
- **Zone history** — no record of which zones the user has used, when, or how often.
- **Analytics identifiers** — no UUID, no install-id, no session-id, no machine-id, no anonymous fingerprint.
- **Telemetry signals** — no event counts, no error counts, no model invocation counts.

### Enforcement (CI)

A Rust unit test in `src-tauri/tests/settings_invariants.rs` round-trips every reachable `SettingsSnapshot` and asserts:

1. The serialised JSON has **exactly** 2 top-level keys.
2. Those keys are **exactly** `schema_version` and `model_tier`.
3. Both values are present.
4. `schema_version` is the integer `1`.
5. `model_tier` is one of the three valid strings.

A second test parses every variant of `ModelTier` and asserts the round-trip is byte-identical.

## File-IO behaviours

### Load

```text
def load_or_default(path: Path) -> SettingsSnapshot:
    if not path.exists():
        return SettingsSnapshot::default()                       # FR-020: silent default
    text = path.read_text(encoding="utf-8")
    parsed = try_json_parse(text)
    if parsed is Err:
        debug_warn("settings.json malformed, falling back to default")
        return SettingsSnapshot::default()                       # FR-020: silent default + debug-only warning
    snapshot = try_deserialise(parsed)
    if snapshot is Err:
        debug_warn("settings.json schema invalid, falling back to default")
        return SettingsSnapshot::default()                       # forward-compat or hand-edited garbage
    return snapshot
```

### Save (atomic)

```text
def save(path: Path, snapshot: SettingsSnapshot) -> Result<(), WriteFailed>:
    json = serde_json::to_string_pretty(snapshot)                # ~50 bytes, pretty for hand-editability
    tmp_path = path.with_extension(".json.tmp")
    write_bytes(tmp_path, json.as_bytes())                       # full file, no append
    fsync(tmp_path)                                              # durability across crash
    rename(tmp_path, path)                                       # atomic on macOS APFS
```

Atomic rename is required: a torn write would leave the file half-empty, which the load path treats as malformed and resets to defaults. That would be a silent UX regression (user's tier choice silently reverts). The temp+rename pattern eliminates this.

## Example valid files

**First-run default** (after `RestoreSettingsOnLaunch` rule with no prior file, then a save):

```json
{
  "schema_version": 1,
  "model_tier": "Smart"
}
```

**User switched to Snabb**:

```json
{
  "schema_version": 1,
  "model_tier": "Snabb"
}
```

**User switched to Stor**:

```json
{
  "schema_version": 1,
  "model_tier": "Stor"
}
```

## Example invalid files (all → load default + debug warn)

```json
{}
```

```json
{"schema_version": 1}
```

```json
{"schema_version": 2, "model_tier": "Smart"}
```

```json
{"schema_version": 1, "model_tier": "smart"}
```

```json
{"schema_version": 1, "model_tier": "Smart", "telemetry_id": "abc"}
```

```text
this is not JSON at all
```

All of the above are treated identically: log debug warning, return default snapshot, overwrite the file on the next successful `set_model_tier` call.

## Forward-compat

If a future spec changes the schema:

1. Bump `SchemaVersion::V1` to `SchemaVersion::V2` in Rust.
2. Add a migration function `migrate_v1_to_v2(v1: V1Snapshot) -> V2Snapshot` in `settings::file_io`.
3. The load path's malformed-file branch becomes a "detect schema_version, migrate or fall back to default" branch.

Until that point, any `schema_version != 1` is treated as malformed (forward-compat-safe regression).
