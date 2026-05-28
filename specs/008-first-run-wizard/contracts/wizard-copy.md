# Wizard copy contract — Spec 008

Single source of truth: `src-tauri/tests/fixtures/wizard-strings.json` (created in `/implement`).

## The 12 keys

| Key | Purpose | Chars | Component |
|---|---|---|---|
| `welcome_title` | Top header on the welcome screen | 23 | WelcomeWizard |
| `welcome_paragraph` | Body paragraph; verb list doubles as feature preview | 199 | WelcomeWizard |
| `welcome_privacy_line` | Explicit privacy reassurance | 38 | WelcomeWizard |
| `welcome_download_note` | Sets expectation that a 2 GB download is coming | 102 | WelcomeWizard |
| `welcome_cta_primary` | Fortsätt button label | 8 | WelcomeWizard |
| `welcome_cta_secondary` | Avbryt button label | 6 | WelcomeWizard |
| `welcome_sidecar_helper` | Italic helper under buttons while sidecar boots | 21 | WelcomeWizard |
| `progress_label_downloading` | Active-download label | 17 | FirstRunProgress |
| `progress_label_waiting` | Network-drop label | 18 | FirstRunProgress |
| `progress_cancel_button` | Cancel button label | 18 | FirstRunProgress |
| `progress_eta_unknown` | ETA when bps=0 | 1 | FirstRunProgress |
| `progress_error_retry` | Retry button in error sub-state | 11 | FirstRunProgress |

## SwedishCopy invariants

Every string MUST satisfy (per spec 003 / FR-014, refined 2026-05-28 per /speckit.analyze C1):

1. **NonEmpty** — `length > 0`.
2. **NoEnglishPrefix** — does not start with `Error:`.
3. **NoEnglishWord** — does not contain the case-insensitive substring `error`.
4. **LengthBounded** — `welcome_paragraph` AND `welcome_download_note` ≤ 200 chars (both are long-form welcome content); every other key ≤ 80 chars.

These are checked by:
- `src-tauri/tests/wizard_strings.rs::every_wizard_string_satisfies_swedish_copy_invariants`
- `src/__tests__/WizardCopy.errors.test.tsx::wizard_strings_pass_swedish_copy_invariants`

Both tests read the fixture and assert the four properties for every key. The Rust test asserts the fixture matches the TS-side mirror in `src/lib/wizard-strings.ts`; the TS test does the reverse.

## Humanizer trail

The welcome paragraph was authored at spec time and ran through the `humanizer` skill. The early draft included AI-tinged phrases ("kraftfullt stöd", "intelligent processing") that were replaced with the literal verb list. The final paragraph is locked in clarification 1.

The other 11 strings are short enough that humanizer-review is a single-glance pass; they were modeled on the existing spec 002 `WelcomeCard` copy + spec 007 indicator vocabulary.

## Pattern-match with existing fixtures

Spec 003 / 004: `zone-error-strings.json` — 11 keys
Spec 003 / 004: `zone-identity.json` — 6 keys (one per zone)
Spec 007: `update-failure-strings.json` — 7 keys (6 variants + _comment)
**Spec 008: `wizard-strings.json` — 13 keys (12 strings + _comment)**

Each fixture is independently asserted from both Rust + TS sides; the cross-language drift test pattern is identical across all four specs. New strings ALWAYS go in a fixture, never embedded directly in component source.
