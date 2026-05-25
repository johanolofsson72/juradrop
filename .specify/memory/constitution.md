<!--
  Sync Impact Report
  Version change: 0.0.0 → 1.0.0 (initial ratification)
  Added principles:
    - I. Privacy by Architecture (NON-NEGOTIABLE)
    - II. Zero-CLI Install (Granny-Grade)
    - III. Local-Only Inference
    - IV. Single-User Desktop App, Not a Service
    - V. Swedish-First UI, English-First Code
    - VI. Native macOS Feel
    - VII. Bundled Sidecar — Ollama Is Internal Plumbing
    - VIII. Honest Failure States
    - IX. Open Source, Free, No Lock-In
  Added sections:
    - Technology Stack
    - Distribution Strategy
    - Development Workflow
    - Governance
  Templates requiring updates:
    - .specify/templates/plan-template.md — ✅ no changes needed (generic)
    - .specify/templates/spec-template.md — ✅ no changes needed (generic)
    - .specify/templates/tasks-template.md — ✅ no changes needed (generic)
  Follow-up TODOs: none
-->

# JuraDrop Constitution

JuraDrop is a macOS desktop application that lets Swedish law students drop confidential legal documents onto themed drop zones in a native window, and have Ollama running locally translate, summarize, anonymize, or rewrite them — **without any document content ever leaving the user's machine**. This constitution governs every architectural decision in the repository.

## Core Principles

### I. Privacy by Architecture (NON-NEGOTIABLE)

User document content MUST NEVER leave the user's Mac. This is privacy-by-architecture, not privacy-by-policy.

Forbidden, with no exceptions:
- Cloud LLM calls (OpenAI, Anthropic, Cohere, Mistral hosted, etc.).
- Telemetry or analytics that capture any portion of document content, prompts, or responses.
- Crash reports that include document text, file paths from user folders, or model output.
- Automatic uploads of files, prompts, results, or derived artifacts.

The only acceptable outbound network traffic:
1. Tauri auto-updater pulling a signed update manifest and DMG from GitHub Releases.
2. Initial Ollama model download from `ollama.com` (or the configured Ollama registry) on first launch or model change.

Both contain ZERO user content. Any proposal to add another outbound call (Sentry, Plausible, "anonymous usage stats", model-side cloud fallback, etc.) requires a constitutional amendment with a recorded rationale and version bump — not a code-review approval.

### II. Zero-CLI Install (Granny-Grade)

The target user is a 19-year-old Swedish law student who has never opened Terminal. Installing JuraDrop MUST require zero command-line interaction.

- Distribution is a single signed + notarized `.dmg`. User double-clicks, drags `JuraDrop.app` to `/Applications`, launches it. Done.
- The app MUST NOT instruct users to run `brew install`, `pip install`, `ollama pull`, `chmod +x`, or anything resembling a shell command in its UI, README, or first-run flow.
- All dependencies (Ollama binary, model download, file format parsers) MUST be handled inside the app process.
- Error states MUST be expressed in plain Swedish, never as a stack trace or exit code.

### III. Local-Only Inference

All LLM inference MUST run against a local Ollama process bundled as a Tauri sidecar.

- The Ollama binary is bundled inside `JuraDrop.app/Contents/MacOS/` and started/stopped as a sidecar process by the Tauri Rust core.
- The default model is a small instruct model (`gemma3:4b` or `llama3.2:3b`, ~2–3 GB), pulled on first launch with a progress UI.
- Network access for inference is bound to `127.0.0.1:11434` (Ollama's default). The app MUST NOT accept a remote Ollama host via configuration — that would re-open the privacy hole this app is built to close.
- Model selection MAY be exposed in settings, but only between locally-pulled models.

### IV. Single-User Desktop App, Not a Service

JuraDrop is a per-user desktop utility. It is NOT multi-tenant, NOT a server, NOT a SaaS, and does not have user accounts.

- No backend. No database servers. No login. No password reset flow.
- All state (settings, recent files, model selection) is stored under the user's macOS app-support directory using Tauri's storage APIs.
- No background daemon, no `launchd` agent, no menu-bar tray. The window IS the app — close the window, the app quits.

### V. Swedish-First UI, English-First Code

User-facing strings MUST be in Swedish (sv-SE). Code, identifiers, comments, commit messages, PR descriptions, and internal documentation MUST be in English.

- Drop zone labels, error messages, settings copy, first-run wizard: Swedish.
- React component names, Rust function names, Tauri command names, file names, comments, git history: English.
- Filesystem-visible names (e.g. output sidecar suffix `.tillengelska.docx`) are Swedish — they ARE user-facing strings.
- A single i18n layer in the frontend (e.g. `i18next` with one locale) is preferred over hardcoded Swedish strings so future translations remain possible, but the only shipped locale at v1.0 is Swedish.

### VI. Native macOS Feel

JuraDrop MUST look and feel like a native macOS application, not a cross-platform afterthought.

- Typography: SF Pro (system font), no web font downloads.
- Appearance: auto-follow the macOS appearance preference via `prefers-color-scheme`; dark and light themes both supported.
- Window chrome: standard macOS title bar (red/yellow/green), no custom-painted chrome.
- File picker: native macOS open-file dialog via Tauri's `dialog` API, never an HTML `<input type=file>`.
- Visual reference: the dark, minimal, dashed-border drop-zone aesthetic of the "Resize Images" macOS utility. See `design-system/MASTER.md`.
- Animations: subtle micro-interactions only — dragover border pulse, in-zone progress spinner, soft success checkmark. No bouncing, no confetti, no scroll-jacking.

### VII. Bundled Sidecar — Ollama Is Internal Plumbing

Ollama is an implementation detail. The user MUST NOT need to know what Ollama is, that it exists, or how to manage it.

- The app starts the bundled Ollama sidecar on launch and stops it on quit.
- The model registry, the `ollama serve` lifecycle, the port binding — all invisible.
- If Ollama crashes mid-job, the app MUST detect the failure, restart the sidecar, and either retry or surface a plain-Swedish "Något gick fel — försök igen" message. The user MUST NEVER see "connection refused", "EADDRINUSE", or a Rust panic trace.
- The Settings panel MAY expose model selection ("Snabb / Smart / Stor") but never raw model tags like `llama3.2:3b-instruct-q4_K_M`.

### VIII. Honest Failure States

The app MUST be honest about what went wrong without leaking internals.

- Unsupported file: "Det här filformatet stöds inte än." — name the format if known, suggest a workaround.
- Document parse failed: "Kunde inte läsa filen — den kan vara skadad eller låst." — don't dump the parser exception.
- Model not yet downloaded: show the download progress UI, not a silent failure.
- Sidecar dead: try once to restart automatically; if that fails too, "AI-motorn svarar inte. Starta om JuraDrop."
- No silent fallbacks. No "success" that didn't actually succeed.

### IX. Open Source, Free, No Lock-In

JuraDrop is released under the MIT license, sourced publicly at `https://github.com/johanolofsson72/juradrop`, and free to use.

- No paywalls, no license keys, no nag screens, no "Pro" tier.
- No vendor lock-in: output files are standard formats (`.docx`, `.pdf`, `.txt`, `.md`) — never a proprietary JuraDrop-only format.
- Contributions are welcomed but must respect every principle above, especially Principle I.

## Technology Stack

- **Application framework**: Tauri 2.x (Rust core + WKWebView UI).
- **Frontend**: React 18+ with TypeScript, Tailwind CSS, shadcn/ui components.
- **State**: TanStack Query for sidecar communication, Zustand for local UI state. Keep it boring.
- **LLM runtime**: Ollama, bundled as a Tauri sidecar. Default model `gemma3:4b` or `llama3.2:3b` (decided pre-MVP after quality testing on Swedish legal text).
- **Document parsing (Rust)**:
  - `.docx` — `docx-rs` or custom zip+xml walker.
  - `.pdf` — `pdf-extract` (text-only; OCR is out of scope for v1).
  - `.txt`, `.md` — stdlib `fs::read_to_string`.
  - `.rtf` — `rtf-parser` (best-effort).
  - `.pages`, `.odt` — best-effort; may degrade to plaintext-only or "format not supported in this version".
- **Document writing (Rust)**: `docx-rs` for `.docx` output, stdlib for `.txt`/`.md`. PDF output for v1 is out of scope — `.pdf` input becomes `.docx` output.
- **Hosting**: N/A. This is a desktop app. The only server-side surface is GitHub Releases hosting the signed DMG and update manifest.
- **Repository**: https://github.com/johanolofsson72/juradrop

## Distribution Strategy

- **Apple Developer Program**: required. Annual €99 cost is part of the project budget.
- **Signing**: Developer ID Application certificate, applied to the outer `.app` and to the inner Ollama sidecar binary.
- **Notarization**: every release is notarized via `notarytool`. Pre-notarization builds are dev-only and never shared with end users.
- **Distribution channel**: GitHub Releases. The signed DMG plus the Tauri updater JSON manifest are both attached to each tagged release.
- **Updates**: Tauri's built-in updater. On launch the app fetches the manifest from GitHub, compares versions, prompts the user before downloading. Update binaries are signed with the project's Tauri updater key (separate from the Apple Developer ID).
- **Mac App Store**: explicitly out of scope. App Store sandboxing rules conflict with the bundled-Ollama-sidecar architecture, and the 30% take is not worth the review pain for a free open-source app.

## Development Workflow

- Features specified via speckit: `spec.md` → `clarify` (recommended) → `plan.md` → `tasks.md` → implementation → tests → `/tla` formal verification → done.
- Branch naming: `NNN-feature-name` matching the speckit spec ID.
- Commit messages: Conventional Commits in English (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `style:`, `chore:`).
- Verification: every implementation MUST pass `cargo test` (Rust), `npm test` (vitest for React), and the Playwright smoke suite (drag-a-file-on-each-zone) before merge.
- For UI changes: invoke the `frontend-design` skill BEFORE writing UI code. Reference `design-system/MASTER.md` for color, typography, and motion rules.
- For user-facing copy: invoke the `humanizer` skill before shipping. Swedish copy must read like a Swedish person wrote it, not like a translated English template.
- No PRs required (solo project — see `.claude/rules/project-workflow.md`); commit straight to `main` after local verification passes.

## Governance

This constitution governs all feature development in the JuraDrop project. Amendments require:
1. Description of the change and rationale (especially for Principle I — privacy amendments need an extraordinary justification).
2. Update to this file with a semantic version increment.
3. Review of dependent templates and `CLAUDE.md` for consistency.

Versioning follows semantic versioning:
- MAJOR: principle removal or incompatible redefinition (e.g. weakening Principle I).
- MINOR: new principle or material expansion.
- PATCH: clarification or wording fix.

All implementation plans MUST include a Constitution Check section verifying compliance with these principles. Plans that violate Principle I MUST be rejected, not negotiated.

**Version**: 1.0.0 | **Ratified**: 2026-05-25 | **Last Amended**: 2026-05-25
