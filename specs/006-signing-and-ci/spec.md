# Feature Specification: Signing, notarization & CI/CD release pipeline

**Feature Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`)

**Created**: 2026-05-27

**Status**: Draft

**Input**: User description: Set up automated signing + notarization + publishing for JuraDrop releases via GitHub Actions on tag push (v*.*.*). On `git tag vX.Y.Z && git push --tags`, a workflow on `macos-latest` runs the full regression sweep (vitest + cargo test + clippy strict + lint + typecheck), then invokes tauri-action to build the universal `.app`, sign it with the Developer ID Application certificate, build the DMG installer, submit to Apple notarytool, staple the ticket, and upload the signed + notarized DMG + Tauri updater manifest (`latest.json`) + `.sig` signature to a DRAFT GitHub Release. The developer publishes the draft manually after smoke-testing the DMG locally. Zero in-app code paths change — this spec is pure CI/CD infrastructure + Tauri configuration + a small local helper script.

## Clarifications

### Session 2026-05-27 (auto-picked recommendations per `.claude/settings.json`)

- Q: What happens when a tag is pushed and a draft release with the same name already exists from a previous run? → A: **Fail fast — the workflow aborts at the `tauri-action` step with an error message instructing the developer to delete the existing draft release manually.** Auto-overwriting a draft is risky (the developer may have intentionally kept it for forensic inspection of a prior failure); appending a suffix produces confusing release-name UX. Manual delete is a single-click action in the GitHub UI and preserves the auditable history of release attempts. Documented in the deployment runbook + the workflow's error message.
- Q: What is the v1 rollback procedure when a published release turns out to be broken (e.g. crashes on launch for a subset of users)? → A: **Fix forward only — no manifest-rewind.** v1 has no "yank" mechanism. If a release is broken, the developer cuts a new release (e.g. v0.2.0 → v0.2.1) that ships a fix. The broken v0.2.0 remains downloadable from the GitHub release page (auditable history), but the Tauri updater manifest at `releases/latest/download/latest.json` points to the latest published release (v0.2.1) so existing installs get the fix on next launch. Users who already installed the broken v0.2.0 stay on it until they relaunch and the updater offers v0.2.1. Pointing the manifest back to an older version is deferred — it would require either (a) hand-editing `latest.json` after publish, which is error-prone, or (b) a dedicated "yank-and-republish" workflow that's not worth building until a real incident demands it.
- Q: What GitHub Actions `permissions:` block does the release workflow need? → A: **`contents: write` at the workflow level, nothing else.** That's the minimum required to create a draft release + upload assets via the auto-provided `GITHUB_TOKEN`. No `pull-requests`, no `issues`, no `packages`, no `id-token`. The default at the repo level is read-only; declaring `contents: write` at the workflow level is the least-privilege escalation that still works. No PAT (personal access token) needed — the workflow uses the ephemeral `GITHUB_TOKEN` GitHub Actions injects for the run.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Cut the first signed release (Priority: P1)

The developer has finished spec 005, all 338 tests pass, the working tree is committed and pushed to main. They want to ship the first signed + notarized DMG so anyone with a Mac can install JuraDrop via double-click without the macOS "unidentified developer" warning. They run the local `scripts/release-prep.sh` to verify version pins, then push the tag `v0.1.0`. Within 25 minutes the GitHub Actions workflow finishes, a draft release appears at `github.com/johanolofsson72/juradrop/releases`, and the attached `JuraDrop_0.1.0_universal.dmg` opens cleanly on a fresh Mac without any Gatekeeper warning.

**Why this priority**: This is the entire spec — there is no second story here that delivers value without the release pipeline working. Without a signed + notarized DMG, end users cannot install JuraDrop without Terminal gymnastics (right-click → Open, or `xattr -d com.apple.quarantine`), which violates Principle II (Zero-CLI Install) and defeats the whole "law students with no CLI experience" target audience.

**Independent Test**: With the 8 GitHub Secrets configured (one-time user action documented in `.claude/docs/deployment.md`) and the Tauri updater pubkey pasted into `tauri.conf.json`, push a `v0.1.0` tag to a clean main. Confirm: (a) the workflow run completes successfully within 25 min on `macos-latest`; (b) a draft release named `v0.1.0` appears with `JuraDrop_0.1.0_universal.dmg`, `latest.json`, and `JuraDrop_0.1.0_universal.dmg.sig` attached; (c) the DMG opens via double-click without `xattr -d com.apple.quarantine`; (d) the inner `.app` passes `spctl --assess --type execute /Applications/JuraDrop.app` without errors; (e) the inner `.app` is notarized — `xcrun stapler validate /Applications/JuraDrop.app` returns "ready to be run".

**Acceptance Scenarios**:

1. **Given** a clean main with all spec 005 tests green, the developer has set the 8 GitHub Secrets, and the Tauri pubkey is pasted into `tauri.conf.json`, **When** the developer runs `git tag v0.1.0 && git push origin v0.1.0`, **Then** GitHub Actions starts the release workflow within 30 seconds, runs the full regression sweep, builds + signs + notarizes the DMG, and uploads it to a draft release named `v0.1.0` at `github.com/johanolofsson72/juradrop/releases` within 25 minutes.

2. **Given** the workflow uploaded the draft release, **When** the developer downloads `JuraDrop_0.1.0_universal.dmg` to a fresh test Mac and double-clicks it, **Then** the DMG mounts without Gatekeeper warning, `JuraDrop.app` can be dragged to Applications, and double-clicking the installed `.app` launches the app directly (no right-click → Open step required).

3. **Given** the release workflow ran successfully, **When** the developer inspects the draft release in the GitHub UI, **Then** the draft is NOT auto-published — it stays as a draft until the developer clicks "Publish release" manually. This gives the developer a chance to smoke-test the DMG before it goes live.

4. **Given** the developer has smoke-tested the DMG locally and is happy with the result, **When** they click "Publish release" in the GitHub UI, **Then** the release becomes public and the Tauri updater manifest at `github.com/johanolofsson72/juradrop/releases/latest/download/latest.json` resolves to the v0.1.0 manifest. Existing JuraDrop installs (when there are any) detect the update on next launch.

---

### User Story 2 — Bad tag gets caught locally (Priority: P2)

The developer is about to push `v0.2.0` but has forgotten to bump the version in `package.json` (it still says 0.1.0). Running `scripts/release-prep.sh` BEFORE the push catches the version mismatch and refuses to print the `git tag` command. No bad tag ever reaches origin. The developer fixes the version, commits, and re-runs `release-prep.sh` cleanly.

**Why this priority**: Pushing a tag that doesn't match the version pinned in three files (`Cargo.toml`, `tauri.conf.json`, `package.json`) produces a confusingly-named DMG (e.g. `JuraDrop_0.1.0_universal.dmg` for a `v0.2.0` tag). The Tauri updater would then never offer the new version. Catching this locally before push is cheap and prevents a publicly-broken release.

**Independent Test**: Set the version in any one of `Cargo.toml`, `tauri.conf.json`, or `package.json` to a value that doesn't match the others. Run `scripts/release-prep.sh v0.2.0`. Confirm: (a) the script exits with non-zero status; (b) the error message names the file that's out of sync + the value it has vs. the value expected; (c) no `git tag` command is printed.

**Acceptance Scenarios**:

1. **Given** the working tree has uncommitted changes, **When** the developer runs `scripts/release-prep.sh v0.2.0`, **Then** the script exits with non-zero status and the error message says "Working tree has uncommitted changes — commit or stash first."

2. **Given** the working tree is clean but the last commit hasn't been pushed to `origin/main`, **When** the developer runs `scripts/release-prep.sh v0.2.0`, **Then** the script exits with non-zero status and the error message says "Local main is ahead of origin/main by N commits — push first."

3. **Given** the version strings in `Cargo.toml`, `tauri.conf.json`, and `package.json` are not all equal to `0.2.0`, **When** the developer runs `scripts/release-prep.sh v0.2.0`, **Then** the script exits with non-zero status and the error message names the file that's out of sync with the target version.

4. **Given** all three version strings equal `0.2.0`, the working tree is clean, and local main is up-to-date with origin, **When** the developer runs `scripts/release-prep.sh v0.2.0`, **Then** the script prints the exact `git tag v0.2.0 && git push origin v0.2.0` command and exits with status 0.

---

### User Story 3 — Quality gates fail in CI before signing burns budget (Priority: P2)

The developer pushes `v0.3.0` but a flaky test slipped into main. The CI workflow runs vitest first; it fails on the flaky test. The workflow halts before invoking `tauri-action` — no Apple notarytool submission happens, no draft release is created, no CI minutes are spent on a build that would have been thrown away. The developer fixes the flaky test, deletes the broken tag, re-pushes.

**Why this priority**: Apple notarytool calls have a turnaround of ~5–10 min and the universal-binary build itself is ~12 min. Running tests first saves ~17 min per failed release attempt and avoids polluting the Apple notary submission history with broken DMGs.

**Independent Test**: Introduce a deliberate test failure in `src/__tests__/SammanfattaZone.test.tsx`. Push a fresh tag. Confirm: (a) the workflow reaches the vitest step and fails there; (b) no `tauri-action` step executes; (c) no draft release is created; (d) the GitHub Actions UI shows the failed test name in the workflow log.

**Acceptance Scenarios**:

1. **Given** a vitest test is failing on main, **When** the developer pushes a release tag, **Then** the workflow halts at the `npm test` step with a non-zero exit code; the `tauri-action` step does NOT execute; no draft release is created.

2. **Given** a `cargo test` is failing on main, **When** the developer pushes a release tag, **Then** the workflow halts at the `cargo test` step; the `tauri-action` step does NOT execute.

3. **Given** `cargo clippy -- -D warnings` produces a warning on main, **When** the developer pushes a release tag, **Then** the workflow halts at the clippy step with a clear annotation showing the offending line; the `tauri-action` step does NOT execute.

4. **Given** `npm run lint` or `npm run typecheck` fails, **When** the developer pushes a release tag, **Then** the workflow halts at the offending step; the `tauri-action` step does NOT execute.

---

### User Story 4 — Tauri updater wires into the released app (Priority: P3)

A user has JuraDrop 0.1.0 installed. The developer ships v0.2.0. The next time the user launches their installed app, Tauri's built-in updater dialog (English at v1) prompts: "An update is available — install now?" The user clicks "Install". The 0.2.0 DMG is downloaded over HTTPS from the GitHub release, the `.sig` signature is verified against the public key pinned in the running 0.1.0 binary, the new app replaces the old one in-place, and the app relaunches as 0.2.0.

**Why this priority**: Without this user story, every release after v0.1.0 requires the user to manually download a new DMG. With it, updates are one-click. Lower priority because it depends on the v0.1.0 release shipping with the updater plugin already configured — and at v0.1.0 there are by definition zero users to update.

**Independent Test**: Install a synthetic `0.1.0` build, set the bundled pubkey to match a test keypair, host a synthetic `latest.json` manifest pointing at a `0.2.0` DMG signed with the same test keypair, launch the 0.1.0 app. Confirm: (a) Tauri detects the update; (b) the built-in dialog appears in English; (c) accepting the dialog downloads the 0.2.0 DMG; (d) the signature verifies; (e) the app relaunches as 0.2.0.

**Acceptance Scenarios**:

1. **Given** JuraDrop 0.1.0 is installed on a Mac and a 0.2.0 draft release is published with `latest.json` + signed DMG, **When** the user launches the 0.1.0 app, **Then** within ~5 seconds of launch the Tauri updater dialog appears showing the new version + an "Install" button.

2. **Given** the user clicks "Install" in the updater dialog, **When** the download completes, **Then** the `.sig` signature is verified against the pubkey embedded in the running 0.1.0 binary, the new `.app` replaces the old one, and the app relaunches as 0.2.0.

3. **Given** the `.sig` signature does NOT verify (network MITM, corrupt download, or wrong pubkey), **When** the user clicks "Install", **Then** the install is REJECTED before any file write — Tauri's updater plugin enforces the signature check.

---

### Edge Cases

- **Apple notary outage**: Apple's notarytool API can be unavailable for hours. The workflow times out the notarytool wait at 60 minutes. On failure, the draft release is NOT created — the developer sees a CI failure and retries when Apple is back.
- **Signing certificate expired**: A Developer ID Application certificate has a 5-year lifetime. When it expires, every build fails at the codesign step. The workflow surfaces the codesign error in the GitHub Actions log; the developer re-issues the cert, re-exports the .p12, updates the GitHub Secret, and retries.
- **App-Specific Password revoked**: If the user revoked the notarytool app-specific password, the workflow fails at the notarytool submit step. Documented mitigation in `.claude/docs/deployment.md`.
- **Tauri pubkey lost**: If the developer loses the Tauri updater private key, no future release can be signed for the existing user base (the running app verifies against the pubkey it shipped with — a new pubkey is a different identity). Mitigation documented: keep the private key in a password manager + at least one offline backup. A pubkey rotation requires shipping a transitional release that accepts BOTH the old + new pubkeys, then a follow-up that drops the old one (out of v1 scope).
- **Tag pushed without bumping versions**: caught by `release-prep.sh` before the tag is even printed (US2).
- **Tag pushed with versions bumped but uncommitted**: caught by `release-prep.sh` (working tree check, US2).
- **CI runner runs out of disk during build**: rare but possible on `macos-latest`. The workflow fails with a disk-space error. Mitigation: re-run the workflow (Actions UI → "Re-run jobs"). No cleanup needed because each run uses a fresh runner.
- **Same tag pushed twice (or workflow re-run)**: per the 2026-05-27 clarification, the workflow's `tauri-action` step intentionally fails when a draft release with the same name already exists. The error message instructs the developer to delete the existing draft via the GitHub UI before re-running. No automatic overwrite — preserves the audit trail of release attempts and prevents accidental data loss from clobbering a draft the developer kept for forensics.
- **Release-prep.sh on a non-main branch**: the script bails out with "Refusing to prep a release from a non-main branch. Switch to main first." (the project's direct-push-to-main workflow per `.claude/rules/project-workflow.md`).
- **Workflow on a non-tag push**: the workflow's `on: push: tags: ['v*.*.*']` filter ensures it only triggers on tag pushes — branch pushes to main do NOT trigger a release build (that would burn budget on every commit).
- **Pre-release / beta tag** (e.g. `v0.1.0-beta.1`): the `v*.*.*` glob matches but the suffix is preserved in the tag name. The draft release is named `v0.1.0-beta.1`. The Tauri updater respects semver; users on `0.1.0` will see the beta as a newer version and install it. To avoid this in v1, do NOT push pre-release tags until the beta channel is supported (deferred). Documented as a known v1 trap.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a GitHub Actions workflow at `.github/workflows/release.yml` that triggers ONLY on pushes of tags matching the glob `v*.*.*`. Push to any branch (including main) MUST NOT trigger the workflow.
- **FR-002**: The workflow MUST run on `macos-latest` GitHub-hosted runners. Apple Silicon notarization can ONLY be performed on a Mac runner — Linux/Windows runners are excluded by Apple's notarytool design.
- **FR-003**: The workflow MUST run the full regression sweep BEFORE any signing or notarization step: `npm install`, `npm run lint`, `npm run typecheck`, `npm test`, `cd src-tauri && cargo fmt -- --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`. Any non-zero exit aborts the workflow before the build step.
- **FR-004**: The workflow MUST fetch the bundled Ollama sidecar binary via `bash scripts/fetch-ollama.sh` (existing script from spec 002) so the build includes the same `src-tauri/binaries/ollama-aarch64-apple-darwin` that local builds use.
- **FR-005**: The workflow MUST invoke `tauri-action/tauri-action@v0` (or its current pinned major) with the universal-darwin target set (`aarch64-apple-darwin` + `x86_64-apple-darwin`) so a single DMG runs on both Apple Silicon and Intel Macs.
- **FR-006**: The workflow MUST pass the eight signing-related GitHub Secrets to `tauri-action` via environment variables: `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD` (app-specific), `APPLE_TEAM_ID`, `TAURI_PRIVATE_KEY`, `TAURI_KEY_PASSWORD`.
- **FR-007**: After signing + notarization, the workflow MUST upload the resulting artifacts (`JuraDrop_<version>_universal.dmg`, `JuraDrop_<version>_universal.dmg.sig`, `latest.json`) to a DRAFT GitHub Release named `v<version>` with the tag's commit SHA. The release MUST NOT be auto-published.
- **FR-008**: `src-tauri/tauri.conf.json` MUST be updated so `bundle.targets` includes `"dmg"` (the DMG installer target). The previous `"app"` target stays so the `.app` is also built (tauri-action wraps both).
- **FR-009**: `src-tauri/tauri.conf.json` MUST declare a `plugins.updater` block with `active: true`, `dialog: true`, the GitHub Releases endpoint URL, and a `pubkey` field. The `pubkey` is a placeholder at spec-implementation time and is filled by the developer with the actual public key from `npm run tauri signer generate` before the first release.
- **FR-010**: `src-tauri/Cargo.toml` MUST add `tauri-plugin-updater = "2"`. `src-tauri/src/lib.rs` MUST register the plugin via `.plugin(tauri_plugin_updater::Builder::new().build())` in the Tauri builder chain.
- **FR-011**: System MUST provide a local helper script `scripts/release-prep.sh` that takes one argument (the target tag `vX.Y.Z`) and verifies four preconditions before printing the push command: (a) working tree clean (no untracked or modified files); (b) `Cargo.toml` version = `X.Y.Z`; (c) `src-tauri/tauri.conf.json` version = `X.Y.Z`; (d) `package.json` version = `X.Y.Z`; (e) local `main` branch is up-to-date with `origin/main`; (f) HEAD is on the `main` branch. Any failure exits non-zero with a clear English error message naming the offending file or condition.
- **FR-012**: `release-prep.sh` MUST NOT auto-push the tag. The script's success output is the literal copy-paste-ready command `git tag vX.Y.Z && git push origin vX.Y.Z` — the developer copies and runs it manually. This preserves a final human checkpoint.
- **FR-013**: System MUST update `.claude/docs/deployment.md` with the complete release procedure for the developer: prereqs (Apple Developer Program, certificate creation, .p12 export, app-specific password, Tauri keypair generation), the eight GitHub Secrets table with exact value sources, the first-release "paste the Tauri pubkey into `tauri.conf.json`" step, the `release-prep.sh` workflow, and the manual-publish step that follows the draft release.
- **FR-014**: System MUST update `README.md` to remove the "First signed + notarized DMG släpps under `Releases` när spec 006 är klar" placeholder. Replace with the real installation flow that points to `github.com/johanolofsson72/juradrop/releases/latest`.
- **FR-015**: The Tauri updater plugin MUST verify the `.sig` signature against the embedded pubkey before installing any downloaded update. If the signature does NOT verify, the install is REJECTED and the running app remains on its current version. This is built-in Tauri plugin behaviour — the spec asserts it is NOT disabled.
- **FR-016**: The CI workflow MUST NOT post, upload, or otherwise transmit any content from the repository's `src-tauri/tests/fixtures/` directory (which contains intentionally synthetic test documents but is part of the repo). It also MUST NOT transmit any document content from the developer's local filesystem — the workflow only sees the source tree, never user documents.
- **FR-017**: The CI workflow MUST cache Rust dependencies (`~/.cargo/registry`, `~/.cargo/git`, `src-tauri/target`) and Node dependencies (`~/.npm`, `node_modules`) keyed off `Cargo.lock` + `package-lock.json` hashes. Cold builds run ~30 min; cached builds target ~15 min.
- **FR-018**: The workflow MUST fail fast (`fail-fast: true` on the job-level strategy if a matrix is used) so a single failure doesn't waste budget on parallel jobs that can't succeed without it.
- **FR-018a**: The workflow MUST declare top-level `permissions: contents: write` and rely on the auto-provided `GITHUB_TOKEN` (not a personal access token) for draft release creation + asset upload. No other permissions are granted — least privilege.
- **FR-018b**: When a draft release with the same name as the current tag already exists, the workflow MUST fail at the `tauri-action` step with a clear error message: "A draft release named `vX.Y.Z` already exists. Delete it via the GitHub UI (Releases → Drafts → ⋯ → Delete) before re-running this workflow." No auto-overwrite, no auto-suffix.
- **FR-019**: The workflow log MUST surface the notarytool submission ID + the staple result on success. This gives the developer a paper trail when debugging end-user "JuraDrop can't be opened" reports.
- **FR-019a**: There is no v1 manifest-rewind / "yank" mechanism. When a published release turns out to be broken, the rollback procedure is: cut a new release with a bumped patch version that fixes the issue. The old broken DMG remains downloadable for audit but the Tauri updater manifest at `releases/latest/download/latest.json` always points to the latest *published* release. Users on the broken version receive the fix on next launch via the standard updater flow.
- **FR-020**: The release-prep.sh script MUST be POSIX-sh compatible (no bashisms like `[[`, no `local`, no associative arrays). The project's `scripts/fetch-ollama.sh` follows the same convention; the new script matches.

### Key Entities

- **ReleaseTag**: A git annotated tag matching the regex `^v\d+\.\d+\.\d+(-\w+(\.\d+)?)?$`. Drives both the workflow trigger and the draft release name. Pre-release suffixes (e.g. `-beta.1`) are allowed by the glob but discouraged at v1 (out of scope for beta-channel handling).
- **GitHubSecret**: One of the eight secrets `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`, `TAURI_PRIVATE_KEY`, `TAURI_KEY_PASSWORD`. Stored in GitHub repo settings, injected into the workflow as env vars. Not committed to the repo.
- **TauriUpdaterPubkey**: The Tauri minisign public key, generated via `npm run tauri signer generate`. Embedded in `tauri.conf.json` so it ships inside every installed `.app`. The matching private key is the `TAURI_PRIVATE_KEY` GitHub Secret.
- **DraftRelease**: A GitHub Release object that exists but is not yet visible to non-admins. Created by `tauri-action`. Becomes a public release when the developer clicks "Publish release".
- **NotarizationTicket**: Apple's response after notarytool processes the DMG. Stapled to the `.app` so Gatekeeper can verify it offline at first launch. The staple step happens automatically inside `tauri-action`.
- **UpdaterManifest**: The `latest.json` file describing the current version, download URL, and signature. Tauri's updater plugin fetches this on app launch.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Time from `git push --tags` to a draft release appearing in the GitHub Releases UI is ≤ 25 minutes for a cached build, ≤ 35 minutes for a cold build (no cargo / npm cache available).
- **SC-002**: A signed + notarized DMG produced by the workflow opens via double-click on a fresh macOS 12+ install without any Gatekeeper warning or "right-click → Open" workaround being needed. `spctl --assess --type execute /Applications/JuraDrop.app` returns "accepted".
- **SC-003**: When any quality gate (lint, typecheck, vitest, cargo test, clippy strict, cargo fmt --check) fails on a pushed tag, the workflow halts BEFORE the `tauri-action` step. Zero Apple notarytool submissions happen for failed-quality-gate builds.
- **SC-004**: `scripts/release-prep.sh` exits non-zero for every documented failure mode (dirty working tree, version mismatch, unpushed commits, non-main branch) and exits 0 only when all preconditions hold.
- **SC-005**: A user with JuraDrop 0.1.0 installed sees the Tauri updater dialog within 5 seconds of launching the app, IF a newer signed release is published. The dialog uses the Tauri built-in copy (English at v1; Swedish localisation is deferred).
- **SC-006**: Zero new outbound network surfaces are introduced by spec 006 in the running app. The release pipeline runs in GitHub Actions infrastructure, not in the user's installed app. The only new endpoint the installed app talks to is `github.com/johanolofsson72/juradrop/releases/latest/download/latest.json` for the updater check — already permitted by Principle I as one of the two allowed outbound surfaces.
- **SC-007**: The full release procedure (8 prereqs + release-prep.sh + tag push + workflow + manual publish) is documented in `.claude/docs/deployment.md` with enough specificity that a developer who has never released a Tauri app before can ship v0.1.0 by following the doc end-to-end.

## Assumptions

- The developer has a working Apple Developer Program account ($99/year) before this spec is invoked. The spec does NOT purchase the membership — that's a manual user action outside CI/CD.
- The developer has access to GitHub Actions on the `johanolofsson72/juradrop` repository. The repo is public per the project's MIT license; public repos get unlimited Actions minutes.
- The `macos-latest` GitHub-hosted runner provides a supported Xcode + macOS SDK combination. GitHub keeps `macos-latest` up to date; the workflow does not pin to a specific Xcode version at v1.
- Apple's notarytool API is reachable from `macos-latest` runners (it's a public Apple service, GitHub Actions runners are well-supported clients). Outages are rare and handled by retrying after the outage resolves.
- The Tauri minisign keypair generation produces a key fit for the Tauri updater plugin's verification. This is the standard `npm run tauri signer generate` flow; spec 006 does not invent a new key format.
- The developer pushes tags from `main` only (per `.claude/rules/project-workflow.md` direct-push workflow). The release-prep.sh script enforces this; the workflow does NOT enforce it (tag pushes from any branch would still trigger it).
- The first release (`v0.1.0`) is hand-cut after the developer has set the 8 secrets + pasted the Tauri pubkey + run release-prep.sh. Subsequent releases (`v0.1.1`, `v0.2.0`, ...) are easier because the one-time setup is already done.
- The Tauri updater plugin at v2.x is stable enough to ship at v1. We accept the built-in English dialog as a known v1 gap; Swedish localisation is a future spec.
- The pubkey field in `tauri.conf.json` is committed to git WITH the real key (not as a placeholder) at the moment the first release is cut. Public-key disclosure is the explicit intent — verifiers run on every user's machine, so the key must ship in the binary. Only the PRIVATE key is secret.
- The `release-prep.sh` script is run from the repo root. If the developer runs it from a subdirectory, the script bails out with a clear "must run from repo root" message.

## Out of Scope

- Swedish-localised Tauri updater dialog (future spec; English is v1).
- Differential / delta updates (Tauri 2.x supports full-replacement only at v1).
- Beta-channel + automatic pre-release tag handling (`-beta.1`, `-rc.1`). Pushing pre-release tags works mechanically but produces a confusing UX for stable-channel users.
- GitHub branch protection rules and required-reviews settings (deferred to spec 012's "polish-and-public-beta" pass).
- Crash reporting / telemetry on the released app — forbidden by Principle I.
- Code signing of the bundled Ollama sidecar binary as a separate identity. tauri-action handles inner-binary signing as part of the outer `.app` signing pass; no separate per-binary identity needed.
- Multi-architecture parallel jobs. A single universal-darwin job produces the universal `.app`; matrix builds are wasted complexity at this size.
- Self-hosted runners. The free GitHub-hosted `macos-latest` is sufficient at this volume.
- Hardware-token-backed signing (HSM, Yubikey). The .p12 + GitHub Secret approach is standard for indie Mac development and acceptable for the project's risk profile.
- Auto-bumping versions across the three files when the user types a tag. The developer bumps versions manually before tagging (and `release-prep.sh` catches mismatches).
- Slack / email release notifications. Future spec if user demand exists.
- Generating a CHANGELOG.md automatically from commits. Manual changelog is sufficient at this stage.
