# Contract: Ollama API usage

The entire JuraDrop→Ollama HTTP surface at this spec. Every other Ollama endpoint is OUT OF SCOPE.

## Base URL

`http://127.0.0.1:11434` — loopback only, enforced by `OLLAMA_HOST` env var passed to the sidecar (research.md R-004).

## Endpoints used

### `GET /api/tags`

**Purpose**: list locally-present models (presence check).

**Request**: no body, no auth.

**Response (200)**:
```json
{
  "models": [
    { "name": "gemma3:4b", "modified_at": "...", "size": 3300000000, "digest": "..." }
  ]
}
```

**Logic**: model present iff `models[].name` contains `"gemma3:4b"`.

**Timeout**: 5 s per attempt; up to 10 s of polling during sidecar startup.

### `POST /api/pull`

**Purpose**: download the default model. Called only after `FirstLaunchConsent.choice = Fortsatt`.

**Request body**:
```json
{ "name": "gemma3:4b", "stream": true }
```

**Response**: NDJSON stream, one event per line:
```json
{ "status": "pulling manifest" }
{ "status": "downloading", "digest": "...", "total": 3300000000, "completed": 100000000 }
...
{ "status": "success" }
```

**Logic**: compute `percent = floor((completed / total) * 100)`, emit `juradrop://progress`. Terminate on `{ "status": "success" }` (set `ModelStatus = Ready`) or on stream error (set `ModelStatus = DownloadFailed`).

**Timeout**: 5 minutes total (FR + SC-002). Per-line read timeout: 30 s (catches stalled connections).

**Outbound destination**: `ollama.com` (Ollama's default registry). This is the only non-loopback host introduced by this spec. Audited at impl time via the grep audit from spec 001 (T039b) with `ollama.com` whitelisted.

### `POST /api/generate`

**Purpose**: one inference round-trip (FC-008 dev-only test + future spec 003 drop zones).

**Request body**:
```json
{ "model": "gemma3:4b", "prompt": "<prompt>", "stream": false }
```

**Response (200)**:
```json
{ "model": "gemma3:4b", "response": "<text>", "done": true, ... }
```

**Logic**: extract `response` field as `Redacted<String>` immediately at the deserializer boundary; never let it pass through a `Debug`/`Display`-able plain string. Assert non-empty.

**Timeout**: 30 s (SC-004). For dev cold-start, the first call may take up to 60 s as the model loads into memory — the test allows for this.

**`stream: false`**: per FR-021, this spec uses blocking inference. Streaming inference arrives in spec 003.

## Endpoints explicitly NOT used at this spec

- `/api/chat` — multi-turn conversation; spec 003+.
- `/api/embeddings` — embeddings; no use case yet.
- `/api/show` — model metadata; presence check via `/api/tags` is sufficient.
- `/api/copy`, `/api/delete`, `/api/create`, `/api/push` — out of scope (JuraDrop never modifies the user's model library).
- `/api/version` — not load-bearing.
- `/api/ps`, `/api/list` — not load-bearing.

## Outbound destination summary

| Destination | Endpoint | When | Frequency |
|-------------|----------|------|-----------|
| `127.0.0.1:11434` | `/api/tags`, `/api/pull`, `/api/generate` | Always (sidecar) | High |
| `ollama.com` (and CDNs Ollama redirects to) | `/api/pull` via the sidecar's outbound | First launch only, after explicit consent | Once per fresh install |

No other outbound destinations. Verified at impl time by the grep audit + by a `lsof -p <pid> -i -P -n` snapshot in the destructive test plan.
