# Feature Specification: Tier-download idle timeout (stalled pull self-recovery)

**Feature Branch**: `034-tier-download-pull-timeout` (direct-push to `main`, no feature branch per project workflow)

**Created**: 2026-06-03

**Status**: Draft

**Input**: User description: "Add a read/idle timeout to the tier-download path so a silently-stalled model pull cannot hang in the `downloading` state forever (spec 027 /tla GAP-1)."

## Clarifications

### Session 2026-06-03

- Q: How long of total stream silence (no bytes received) before the pull is abandoned as a network failure? → A: **90 seconds**. Above any realistic inter-chunk gap or registry-side verify pause (seconds), below "the user has given up"; same order of magnitude as the bundled path's 300 s *total* cap but governs silence, not total duration, so it cannot fire during a slow-but-progressing large-model download.
- Q: Where does the idle guard live — only the on-demand tier pull (spec 027), or the shared pull method used by both the tier pull and the bundled first-run pull (spec 008)? → A: **The shared `OllamaClient::pull` method**. Both callers benefit from a single guard; the bundled path keeps its existing 300 s total-duration cap AND gains the idle guard (strictly safer, never weaker). No duplicated timeout logic.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A stalled download stops lying and offers a retry (Priority: P1)

A law student opens Settings and taps **Ladda ned** on a model tier (e.g. "Stor"). The download starts and the row shows progress. Partway through, their network silently drops in a way that never closes the connection cleanly — the café Wi-Fi captive portal kicks in, the VPN flaps, or the registry stalls. No more bytes arrive, but no error arrives either. Today the row sits at, say, "62 %" forever; the only way out is to notice it is frozen and tap **Avbryt**. After this feature, the app notices the silence on its own: within a bounded idle window the row flips to the existing network-error state with the existing **Försök igen** button, and the student can retry (or walk away) without having had to diagnose the freeze themselves.

**Why this priority**: This is the entire feature. It is the liveness guarantee — the system must make progress (reach a terminal state) on its own rather than depending on the user to recognise and break a deadlock. Without it the download state machine has a reachable forever-stuck state, which is the GAP-1 finding from spec 027's formal verification.

**Independent Test**: Drive `OllamaClient::pull` against a mock registry that accepts the request, opens the NDJSON stream, then goes permanently silent. Assert that `pull` returns an error (not a hang) within roughly the idle-timeout window, that the error categorises to the network failure bucket, and that the tier-download state settles to `error` with no cancel and no other caller intervention.

**Acceptance Scenarios**:

1. **Given** a tier download is in progress and progress lines are flowing, **When** the registry connection goes permanently silent mid-stream, **Then** within the bounded idle window the download settles into the `error` state showing the existing network-failure message and the **Försök igen** retry affordance — with no user action taken.
2. **Given** a download that has just settled into `error` because of an idle timeout, **When** the user taps **Försök igen**, **Then** the existing retry path starts a fresh pull (the row returns to `downloading`), reusing the same machinery as any other network-category failure — no new code path.
3. **Given** a healthy download where bytes keep arriving (even slowly, with multi-second gaps between progress lines on a large 8–12 GB model over a slow link), **When** the download runs for many minutes, **Then** the idle timeout never fires — because each received chunk resets the idle clock, and only *total silence* longer than the threshold triggers it.

### Edge Cases

- **Silence right after the stream opens, before any progress line**: the idle clock starts when the read begins; if the first byte never arrives within the idle window, the pull settles to `error` (network) the same way. No special-casing.
- **Brief network hiccup shorter than the idle window**: bytes resume before the threshold elapses; the idle clock resets and the download continues uninterrupted. The timeout must be generous enough that ordinary jitter, registry-side "verifying sha256 digest" pauses, and slow-disk flushes never trip it.
- **Stall during the final verifying/writing phase** (Ollama emits non-numeric status markers like "verifying sha256 digest", "writing manifest" with no byte counts): these still arrive as stream bytes, so they reset the idle clock; a stall *here* with no bytes at all for the full window is still a legitimate timeout.
- **The bundled first-run model pull** (spec 008) has its own separate 300-second *total* timeout. This feature must not regress that path. If the idle timeout lives in the shared pull method, the bundled path simply gains an additional, stricter-on-silence guard on top of its existing total cap (strictly safer; never weaker).
- **Cancel racing the timeout**: if the user taps **Avbryt** at almost the same moment the idle timeout fires, the outcome must still be a single clean terminal state (cancelled OR error), never a double-terminal or a stuck row. The existing cancel-vs-completion select already arbitrates this; the timeout error is just another way the pull future can resolve.
- **`already_pulled` TOCTOU**: a separate, already-benign observation from the same spec-027 verification — the at-most-one-download lock is re-checked under the lock, so two near-simultaneous start requests cannot both enter `downloading`. This feature documents that invariant in a clarifying comment; it does not change the behaviour.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The model-pull network path MUST enforce a bounded **idle** timeout: if no response bytes are received for longer than a fixed idle threshold, the pull MUST terminate with an error rather than continue waiting indefinitely.
- **FR-002**: The idle timeout MUST be a *per-read / inter-chunk* timeout that resets on every received chunk — it MUST NOT impose a fixed cap on the total download duration. A healthy download that keeps producing bytes MUST be able to run arbitrarily long.
- **FR-003**: An idle-timeout termination MUST be classified into the existing **network** failure category, so the tier-download row presents the existing network-failure Swedish message and the existing **Försök igen** retry affordance. No new failure category, no new user-facing string, no new UI state.
- **FR-004**: When a tier download stalls and the idle timeout fires, the tier-download state MUST transition from `downloading` to `error` **without any user action** (this is the liveness property). The `error` state MUST carry the network failure reason.
- **FR-005**: From the resulting `error` state, the existing retry transition (**Försök igen** → start a new pull) MUST work unchanged — the idle-timeout error is indistinguishable, to the retry path, from any other network failure.
- **FR-006**: The idle timeout MUST NOT introduce any new outbound network destination. It strengthens an existing localhost-only registry-pull call and contacts no new endpoint (Principle I).
- **FR-007**: The idle-timeout threshold MUST be a single named, documented constant set to **90 seconds** of stream silence, with a justification that it cannot fire during a healthy-but-slow download (well above the largest realistic inter-chunk gap, well below "the user has given up"). The constant MUST be expressed so an automated test can exercise the timeout path without waiting the full 90 s in real time (e.g. an injectable / parameterised idle duration on the pull call, defaulting to the 90 s constant in production).
- **FR-008**: The idle guard MUST live in the shared pull method used by both the on-demand tier pull (spec 027) and the bundled first-run pull (spec 008). The change MUST NOT regress the bundled path's existing separate total-duration timeout: the bundled path retains its 300 s total cap AND gains the idle guard (strictly safer, never weaker).
- **FR-009**: The cancel-vs-timeout interaction MUST resolve to exactly one terminal outcome (cancelled OR error), never a stuck row and never two terminal transitions.
- **FR-010**: A clarifying code comment MUST document that the `already_pulled` / start-download lock re-check holds the at-most-one-download invariant (benign TOCTOU), so a future reader does not mistake the re-check for a race.
- **FR-011**: Spec 027's `spec.allium` MUST be amended to record the previously-missing liveness assumption: the `downloading` state has a bounded idle timeout, so it always eventually leaves `downloading` (to `pulled`, `error`, or `not_pulled` via cancel) — `downloading` is not a terminal sink.

### Key Entities *(include if feature involves data)*

- **Idle-timeout threshold**: a single duration constant governing the maximum tolerated *silence* (no bytes received) on the pull stream before the pull is abandoned as a network failure. Distinct from the bundled path's total-duration cap.
- **Pull failure (network category)**: the existing failure bucket that an idle timeout maps into; drives the existing Swedish network-error copy and the **Försök igen** retry button. Unchanged by this feature except that one more upstream condition now reaches it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A pull whose stream goes permanently silent settles into a terminal `error` (network) state on its own, with zero user actions, within a bounded time of roughly the idle threshold (verified by an automated test driving a stalled mock registry — the test asserts the pull resolves to an error within a small multiple of the configured threshold, not "eventually/never").
- **SC-002**: A pull whose stream keeps delivering bytes with realistic multi-second inter-chunk gaps does NOT time out, even when total runtime greatly exceeds the idle threshold (verified by an automated test that drips chunks slower than a naive total-timeout would tolerate but faster than the idle threshold).
- **SC-003**: After an idle-timeout error, exercising the existing retry transition starts a fresh download — demonstrating the failure reuses the existing network-error → retry path with no new state (verified by the existing tier-download retry test continuing to pass against an idle-timeout-induced error).
- **SC-004**: The bundled first-run pull path retains a working timeout (no regression): its existing total-timeout test stays green, and because the idle guard is shared, a bundled-path stall also settles via the idle guard (in addition to its 300 s total cap).
- **SC-005**: Zero new outbound network endpoints introduced (verified by the existing Principle-I no-outbound grep/audit tests staying green and by code review of the diff touching only timeout configuration on an existing localhost call).
- **SC-006**: Zero new user-facing Swedish strings and zero new UI states introduced (verified by the existing cross-language string-drift tests staying green with no new keys, and by the diff adding no entries to the failure-message fixtures).

## Assumptions

- A real Ollama `/api/pull` against a reachable registry emits stream activity continuously while bytes flow; multi-second gaps between NDJSON progress lines are normal, but multi-minute *total silence* indicates a dead/half-open connection, not slow-but-healthy progress. The idle threshold is locked at **90 s** of silence (Clarifications Q1) — in the same order of magnitude as the bundled path's 300 s total cap but governing silence rather than total duration.
- The HTTP client library in use supports a per-read idle timeout primitive (it does — `reqwest 0.12.28`'s `read_timeout`), so the idle guard can be configured declaratively on the existing client rather than hand-rolled around each chunk read. The plan will confirm the precise mapping from that library's timeout error to the existing network failure category.
- The existing `error` → **Försök igen** retry path (spec 027) is correct and complete; this feature only adds one more way to reach `error`, it does not modify retry behaviour.
- The bundled first-run pull (spec 008) and the on-demand tier pull (spec 027) share the same underlying pull method (`OllamaClient::pull`), so the idle guard is placed there (Clarifications Q2) and benefits both; this is strictly safer for the bundled path, which keeps its total-duration cap as well.
- This is a hardening/liveness fix with no new entities and no new user-visible states; it is on the **light** track, but `/tla` is in scope because it encodes a liveness invariant and amends spec 027's `.allium`.
