# Quickstart: spec 002 Ollama Sidecar PoC

End-to-end developer walkthrough. Assumes spec 001 is already merged.

## One-time prep

```bash
# From the repo root, fetch the pinned Ollama binary (spec 002 only)
bash scripts/fetch-ollama.sh
# Produces src-tauri/binaries/ollama-aarch64-apple-darwin (~150 MB)
# The script verifies SHA-256 against the pinned hash — if it fails, do NOT proceed.
```

## Dev loop

```bash
npm install                # picks up new JS deps (shadcn dialog already there, zustand new)
npm run tauri dev          # launches the dev window
```

**First-launch happy path** (clean Mac, no prior JuraDrop install, no prior Ollama install):
1. Window opens. Welcome card shows "Startar AI..." then quickly "Begär samtycke" as the sidecar comes up.
2. The FR-019 consent modal appears — title "Ladda ner AI-modell", body about ollama.com, two buttons.
3. Click "Fortsätt". Modal dismisses. Welcome card shows "Laddar ner AI-modell ... 0%", then climbs to 100%.
4. Welcome card switches to "AI redo" when the pull completes.

**First-launch sad paths**:
- Click "Avbryt" → welcome card shows "AI-modell saknas. Starta om JuraDrop för att försöka igen." The modal does NOT re-appear in the same session. Quit + re-launch the app → modal shows again (file was written with `choice = "avbryt"` — see below).

**Subsequent launches** (model already present, consent already given):
- Welcome card shows "Startar AI..." for ≤ 2 s, then "AI redo".

## Verify zero non-loopback outbound (except `ollama.com`)

```bash
# Run during the round-trip test (model present + sidecar up):
lsof -p $(pgrep -f juradrop | head -1) -i -n -P 2>/dev/null | grep -E '(ESTABLISHED|LISTEN)'
# Expected: only 127.0.0.1:* (loopback). No remote IPs except during /api/pull, which targets ollama.com.

# Source-tree audit:
grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::|hyper::Client" src/ src-tauri/src/
# Expected matches: only reqwest:: in src-tauri/src/sidecar/client.rs, only loopback + ollama.com.
```

## Verify the round-trip (FC-008)

```bash
cd src-tauri
cargo test --test sidecar_roundtrip -- --ignored --nocapture
# Expected:
# - Sidecar spawns, reaches /api/tags within 10 s
# - Asserts gemma3:4b is present (or SKIPs with a clear message if not)
# - Sends POST /api/generate with prompt "Säg hej."
# - Asserts response is non-empty within 30 s (or 60 s on cold start)
# - Tears down sidecar
```

The test logs **never** include the prompt or response — only their lengths in TRACE-level dev output (research.md R-007).

## Reset consent (manual)

```bash
rm "$HOME/Library/Application Support/se.noisycricket.juradrop/consent.json"
# Next launch will show the FR-019 modal again.
```

## Verify the deny-by-default WebView posture survived

Open the dev window → DevTools (right-click → Inspect) → Console:
```js
await window.__TAURI__.core.invoke('plugin:fs|read_dir', { path: '/' })
// Expected: capability error — the fs plugin is not enabled.

await window.__TAURI__.event.listen('juradrop://status', e => console.log(e))
// Expected: succeeds (event:default permission granted).

await window.__TAURI__.core.invoke('get_status')
// Expected: succeeds (custom command, capability-allowed).
```

## Troubleshooting

- **"Porten är upptagen"**: Another process is bound to `127.0.0.1:11434`. Close any `ollama serve` running outside JuraDrop, or kill the process holding the port. JuraDrop fails fast by design (research.md spec-clarify Q1).
- **"AI-motorn kunde inte starta"**: `scripts/fetch-ollama.sh` was not run, or the binary lost its execute bit. Re-run the fetch script.
- **Consent modal never appears**: Check `~/Library/Application Support/se.noisycricket.juradrop/consent.json` exists — if so, the modal already ran. Delete the file to reset.
- **Round-trip test fails with "model not found"**: Run the app once, accept the consent, wait for the download to finish; THEN re-run the test.

## What's deliberately not here yet

- No drop zones — spec 003.
- No streaming inference — spec 003 (FR-021).
- No settings UI — spec 010.
- No first-run wizard polish — spec 008.
- No signed `.app` — spec 006.
